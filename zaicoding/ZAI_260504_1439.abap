REPORT ZAI_260504_1439.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_from  TYPE sy-datum DEFAULT sy-datum OBLIGATORY.
PARAMETERS p_to    TYPE sy-datum DEFAULT sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mara,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             meins TYPE mara-meins,
           END OF ty_mara.
    TYPES ty_t_mara TYPE STANDARD TABLE OF ty_mara WITH EMPTY KEY.

    TYPES: BEGIN OF ty_out,
             section   TYPE char10,
             matnr     TYPE mara-matnr,
             werks     TYPE werks_d,
             mtart     TYPE mara-mtart,
             meins     TYPE mara-meins,
             stock_qty TYPE mard-labst,
             has_mvmt  TYPE abap_bool,
             status    TYPE char20,
           END OF ty_out.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    DATA lt_mv_matnr  TYPE ty_t_matnr.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_all_matnr TYPE ty_t_matnr.
    DATA lt_mara      TYPE ty_t_mara.
    DATA lt_bom_fert  TYPE ty_t_matnr.
    DATA lt_bom_comp  TYPE ty_t_matnr.
    DATA lt_out       TYPE ty_t_out.

    DATA ls_out   TYPE ty_out.
    DATA ls_stock TYPE ty_stock.
    DATA ls_mara  TYPE ty_mara.

    DATA lv_from TYPE sy-datum.
    DATA lv_to   TYPE sy-datum.
    lv_from = p_from.
    lv_to   = p_to.
    IF lv_from > lv_to.
      DATA(lv_tmp) = lv_from.
      lv_from = lv_to.
      lv_to   = lv_tmp.
    ENDIF.

    " 1) Materials with movement in period at plant (MATDOC)
    SELECT DISTINCT matdoc~matnr
      FROM matdoc
      WHERE matdoc~werks = @p_werks
        AND matdoc~budat_mkpf BETWEEN @lv_from AND @lv_to
      INTO TABLE @lt_mv_matnr.

    " 2) Materials with non-zero current stock at plant (MARD)
    SELECT mard~matnr, SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " 3) Union of movement list and stock list
    lt_all_matnr = lt_mv_matnr.
    LOOP AT lt_stock INTO ls_stock.
      APPEND ls_stock-matnr TO lt_all_matnr.
    ENDLOOP.
    SORT lt_all_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr COMPARING table_line.

    " 4) Basic material data for candidates
    IF lt_all_matnr IS NOT INITIAL.
      SELECT mara~matnr, mara~mtart, mara~meins
        FROM mara
        WHERE mara~matnr IN @lt_all_matnr
        INTO TABLE @lt_mara.
      SORT lt_mara BY matnr.
    ENDIF.

    " 5) Build MAIN section rows
    LOOP AT lt_all_matnr INTO DATA(lv_matnr).
      CLEAR ls_out.
      ls_out-section = 'MAIN'.
      ls_out-matnr   = lv_matnr.
      ls_out-werks   = p_werks.

      READ TABLE lt_mara INTO ls_mara WITH KEY matnr = lv_matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_out-mtart = ls_mara-mtart.
        ls_out-meins = ls_mara-meins.
      ENDIF.

      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        ls_out-stock_qty = ls_stock-qty.
      ELSE.
        ls_out-stock_qty = 0.
      ENDIF.

      READ TABLE lt_mv_matnr WITH KEY table_line = lv_matnr TRANSPORTING NO FIELDS.
      ls_out-has_mvmt = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      IF ls_out-has_mvmt = abap_true AND ls_out-stock_qty <> 0.
        ls_out-status = '입출고/재고'.
      ELSEIF ls_out-has_mvmt = abap_true AND ls_out-stock_qty = 0.
        ls_out-status = '입출고만 있음'.
      ELSEIF ls_out-has_mvmt = abap_false AND ls_out-stock_qty <> 0.
        ls_out-status = '재고만 있음'.
      ELSE.
        CONTINUE.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    " 6) BOM: Finished products with BOM at plant
    SELECT DISTINCT mast~matnr
      FROM mast
      INNER JOIN mara ON mara~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_bom_fert.
    SORT lt_bom_fert BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_bom_fert COMPARING table_line.

    " 7) BOM components used at plant (distinct component materials)
    SELECT DISTINCT stpo~idnrk
      FROM mast
      INNER JOIN stpo ON stpo~stlnr = mast~stlnr
      WHERE mast~werks = @p_werks
        AND stpo~idnrk <> ''
      INTO TABLE @lt_bom_comp.
    SORT lt_bom_comp BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_bom_comp COMPARING table_line.

    " Enrich MARA for BOM headers/components if missing
    DATA lt_bom_all TYPE ty_t_matnr.
    lt_bom_all = lt_bom_fert.
    APPEND LINES OF lt_bom_comp TO lt_bom_all.
    SORT lt_bom_all BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_bom_all COMPARING table_line.

    DATA lt_mara_bom TYPE ty_t_mara.
    IF lt_bom_all IS NOT INITIAL.
      SELECT mara~matnr, mara~mtart, mara~meins
        FROM mara
        WHERE mara~matnr IN @lt_bom_all
        INTO TABLE @lt_mara_bom.
      SORT lt_mara_bom BY matnr.
    ENDIF.

    " 8) Add BOM section rows for FERT with BOM
    LOOP AT lt_bom_fert INTO lv_matnr.
      CLEAR ls_out.
      ls_out-section = 'BOM'.
      ls_out-matnr   = lv_matnr.
      ls_out-werks   = p_werks.

      READ TABLE lt_mara_bom INTO ls_mara WITH KEY matnr = lv_matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_out-mtart = ls_mara-mtart.
        ls_out-meins = ls_mara-meins.
      ENDIF.

      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        ls_out-stock_qty = ls_stock-qty.
      ELSE.
        ls_out-stock_qty = 0.
      ENDIF.

      READ TABLE lt_mv_matnr WITH KEY table_line = lv_matnr TRANSPORTING NO FIELDS.
      ls_out-has_mvmt = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      IF ls_out-has_mvmt = abap_true OR ls_out-stock_qty <> 0.
        ls_out-status = 'BOM 보유'.
      ELSE.
        ls_out-status = 'BOM 보유'.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    " 9) Add BOM-only component rows: no movement and no stock
    LOOP AT lt_bom_comp INTO lv_matnr.
      READ TABLE lt_stock WITH KEY matnr = lv_matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      READ TABLE lt_mv_matnr WITH KEY table_line = lv_matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      CLEAR ls_out.
      ls_out-section   = 'BOM'.
      ls_out-matnr     = lv_matnr.
      ls_out-werks     = p_werks.
      ls_out-stock_qty = 0.
      ls_out-has_mvmt  = abap_false.
      ls_out-status    = 'BOM 만 있음'.

      READ TABLE lt_mara_bom INTO ls_mara WITH KEY matnr = lv_matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_out-mtart = ls_mara-mtart.
        ls_out-meins = ls_mara-meins.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    " 10) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).