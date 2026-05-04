REPORT ZAI_260504_1515.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_from  TYPE sy-datum OBLIGATORY.
PARAMETERS p_to    TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lv_from TYPE sy-datum.
    DATA lv_to   TYPE sy-datum.
    lv_from = p_from.
    lv_to   = p_to.

    IF lv_from > lv_to.
      DATA lv_tmp TYPE sy-datum.
      lv_tmp = lv_from.
      lv_from = lv_to.
      lv_to = lv_tmp.
    ENDIF.

    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Movements in period for plant
    DATA lt_move_matnr TYPE ty_t_matnr.
    SELECT DISTINCT matdoc~matnr
      FROM matdoc AS matdoc
      WHERE matdoc~werks = @p_werks
        AND matdoc~budat BETWEEN @lv_from AND @lv_to
      INTO TABLE @lt_move_matnr.

    " Current stock <> 0 by material at plant
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    DATA lt_stock TYPE ty_t_stock.

    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard AS mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " Build union of movement and stock materials for main list
    DATA lt_union TYPE ty_t_matnr.
    lt_union = lt_move_matnr.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      READ TABLE lt_union WITH KEY table_line = <ls_stk>-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND <ls_stk>-matnr TO lt_union.
      ENDIF.
    ENDLOOP.
    SORT lt_union.
    DELETE ADJACENT DUPLICATES FROM lt_union.

    " Range for union list
    DATA lr_union TYPE RANGE OF mara-matnr.
    CLEAR lr_union.
    LOOP AT lt_union ASSIGNING FIELD-SYMBOL(<lv_um>).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = <lv_um> ) TO lr_union.
    ENDLOOP.

    " Material master and text for main list
    TYPES: BEGIN OF ty_mat,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             maktx TYPE makt-maktx,
           END OF ty_mat.
    TYPES ty_t_mat TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.
    DATA lt_mat TYPE ty_t_mat.

    IF lr_union IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             makt~maktx
        FROM mara AS mara
        INNER JOIN makt AS makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        WHERE mara~matnr IN @lr_union
        INTO TABLE @lt_mat.
    ENDIF.

    " Prepare for lookups
    SORT lt_stock BY matnr.
    SORT lt_move_matnr.

    " Result rows
    TYPES: BEGIN OF ty_row,
             section TYPE c LENGTH 10,
             matnr   TYPE mara-matnr,
             mtart   TYPE mara-mtart,
             maktx   TYPE makt-maktx,
             qty     TYPE mard-labst,
             note    TYPE c LENGTH 20,
           END OF ty_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    DATA lt_main TYPE ty_t_row.

    " Build main list rows
    LOOP AT lt_mat ASSIGNING FIELD-SYMBOL(<ls_mat>).
      DATA(ls_row) = VALUE ty_row(
        section = 'MAIN'
        matnr   = <ls_mat>-matnr
        mtart   = <ls_mat>-mtart
        maktx   = <ls_mat>-maktx
        qty     = 0
        note    = '' ).

      DATA ls_stk TYPE ty_stock.
      READ TABLE lt_stock INTO ls_stk WITH KEY matnr = <ls_mat>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-qty = ls_stk-qty.
      ENDIF.

      DATA(lv_moved) = abap_false.
      READ TABLE lt_move_matnr WITH KEY table_line = <ls_mat>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        lv_moved = abap_true.
      ENDIF.

      IF lv_moved = abap_true.
        ls_row-note = '입출고 있음'.
      ELSE.
        ls_row-note = '재고만 있음'.
      ENDIF.

      APPEND ls_row TO lt_main.
    ENDLOOP.

    " BOM section: headers (FERT) with BOM in plant
    DATA lt_hdr TYPE ty_t_matnr.
    SELECT DISTINCT mara~matnr
      FROM mara AS mara
      INNER JOIN mast AS mast
        ON mast~matnr = mara~matnr
      WHERE mara~mtart = 'FERT'
        AND mast~werks = @p_werks
      INTO TABLE @lt_hdr.
    SORT lt_hdr.
    DELETE ADJACENT DUPLICATES FROM lt_hdr.

    " Range for headers
    DATA lr_hdr TYPE RANGE OF mara-matnr.
    CLEAR lr_hdr.
    LOOP AT lt_hdr ASSIGNING FIELD-SYMBOL(<lv_hm>).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = <lv_hm> ) TO lr_hdr.
    ENDLOOP.

    " BOM components for headers in plant
    DATA lt_comp TYPE ty_t_matnr.
    IF lr_hdr IS NOT INITIAL.
      SELECT DISTINCT stpo~idnrk
        FROM mast AS mast
        INNER JOIN stpo AS stpo
          ON stpo~stlnr = mast~stlnr
        WHERE mast~matnr IN @lr_hdr
          AND mast~werks = @p_werks
        INTO TABLE @lt_comp.
      SORT lt_comp.
      DELETE ADJACENT DUPLICATES FROM lt_comp.
    ENDIF.

    " Components with only BOM (no move, no stock)
    DATA lt_comp_only TYPE ty_t_matnr.
    LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<lv_cmat>).
      READ TABLE lt_union WITH KEY table_line = <lv_cmat> BINARY SEARCH.
      IF sy-subrc <> 0.
        APPEND <lv_cmat> TO lt_comp_only.
      ENDIF.
    ENDLOOP.
    SORT lt_comp_only.
    DELETE ADJACENT DUPLICATES FROM lt_comp_only.

    " Collect BOM section materials: headers + components-only
    DATA lt_bom_all TYPE ty_t_matnr.
    lt_bom_all = lt_hdr.
    LOOP AT lt_comp_only ASSIGNING FIELD-SYMBOL(<lv_co>).
      READ TABLE lt_bom_all WITH KEY table_line = <lv_co> BINARY SEARCH.
      IF sy-subrc <> 0.
        APPEND <lv_co> TO lt_bom_all.
      ENDIF.
    ENDLOOP.
    SORT lt_bom_all.
    DELETE ADJACENT DUPLICATES FROM lt_bom_all.

    " Range for BOM all
    DATA lr_bom TYPE RANGE OF mara-matnr.
    CLEAR lr_bom.
    LOOP AT lt_bom_all ASSIGNING FIELD-SYMBOL(<lv_bm>).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = <lv_bm> ) TO lr_bom.
    ENDLOOP.

    DATA lt_bom_mat TYPE ty_t_mat.
    IF lr_bom IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             makt~maktx
        FROM mara AS mara
        INNER JOIN makt AS makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        WHERE mara~matnr IN @lr_bom
        INTO TABLE @lt_bom_mat.
    ENDIF.

    DATA lt_bom TYPE ty_t_row.

    LOOP AT lt_bom_mat ASSIGNING <ls_mat>.
      DATA(ls_bom_row) = VALUE ty_row(
        section = 'BOM'
        matnr   = <ls_mat>-matnr
        mtart   = <ls_mat>-mtart
        maktx   = <ls_mat>-maktx
        qty     = 0
        note    = '' ).

      READ TABLE lt_stock INTO ls_stk WITH KEY matnr = <ls_mat>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_bom_row-qty = ls_stk-qty.
      ENDIF.

      DATA(lv_is_hdr) = abap_false.
      READ TABLE lt_hdr WITH KEY table_line = <ls_mat>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        lv_is_hdr = abap_true.
      ENDIF.

      IF lv_is_hdr = abap_true.
        ls_bom_row-note = 'FERT BOM'.
      ELSE.
        ls_bom_row-note = 'BOM 만 있음'.
      ENDIF.

      APPEND ls_bom_row TO lt_bom.
    ENDLOOP.

    " Display MAIN
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_main ).
    lo_alv->get_display_settings(
      )->set_list_header(
      value = '자재 리스트 - 메인(입출고 또는 재고 보유) - 플랜트 ' && p_werks ).
    lo_alv->display( ).

    " Display BOM section
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_bom ).
    lo_alv->get_display_settings(
      )->set_list_header(
      value = '자재 리스트 - BOM 섹션(FERT 및 BOM 전용) - 플랜트 ' && p_werks ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).