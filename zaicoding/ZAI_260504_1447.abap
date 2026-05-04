REPORT ZAI_260504_1447.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE sy-datum OBLIGATORY.
PARAMETERS p_endda TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lt_mov TYPE ty_t_matnr.
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf AS mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
     WHERE mseg~werks = @p_werks
       AND mkpf~budat BETWEEN @p_begda AND @p_endda
      INTO TABLE @lt_mov.

    DATA lt_stock TYPE ty_t_matnr.
    SELECT mard~matnr
      FROM mard
     WHERE mard~werks = @p_werks
       AND mard~labst <> 0
      INTO TABLE @lt_stock.

    DATA lt_all TYPE ty_t_matnr.
    lt_all = lt_mov.
    APPEND LINES OF lt_stock TO lt_all.
    SORT lt_all.
    DELETE ADJACENT DUPLICATES FROM lt_all.

    DATA lt_mov_s   TYPE SORTED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_stock_s TYPE SORTED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_mov_s   = lt_mov.
    lt_stock_s = lt_stock.

    TYPES: BEGIN OF ty_attr,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             maktx TYPE makt-maktx,
           END OF ty_attr.
    TYPES ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.
    DATA lt_attr TYPE ty_t_attr.

    IF lt_all IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             makt~maktx
        FROM mara
        LEFT OUTER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
       WHERE mara~matnr IN @lt_all
        INTO TABLE @lt_attr.
    ENDIF.

    TYPES: BEGIN OF ty_main,
             matnr    TYPE mara-matnr,
             mtart    TYPE mara-mtart,
             maktx    TYPE makt-maktx,
             has_mov  TYPE abap_bool,
             has_stk  TYPE abap_bool,
             status   TYPE char20,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.
    DATA lt_main TYPE ty_t_main.

    LOOP AT lt_attr ASSIGNING FIELD-SYMBOL(<ls_attr>).
      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.

      READ TABLE lt_mov_s WITH TABLE KEY table_line = <ls_attr>-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_s WITH TABLE KEY table_line = <ls_attr>-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      DATA(ls_main) = VALUE ty_main(
        matnr   = <ls_attr>-matnr
        mtart   = <ls_attr>-mtart
        maktx   = <ls_attr>-maktx
        has_mov = lv_has_mov
        has_stk = lv_has_stk ).

      IF lv_has_mov = abap_true AND lv_has_stk = abap_true.
        ls_main-status = |입출고+재고|.
      ELSEIF lv_has_mov = abap_true.
        ls_main-status = |입출고 있음|.
      ELSEIF lv_has_stk = abap_true.
        ls_main-status = |재고만 있음|.
      ELSE.
        CONTINUE.
      ENDIF.

      APPEND ls_main TO lt_main.
    ENDLOOP.

    TYPES: BEGIN OF ty_fert,
             matnr TYPE mara-matnr,
             stlnr TYPE mast-stlnr,
           END OF ty_fert.
    TYPES ty_t_fert TYPE STANDARD TABLE OF ty_fert WITH EMPTY KEY.
    DATA lt_fert TYPE ty_t_fert.

    SELECT DISTINCT mast~matnr,
                    mast~stlnr
      FROM mast
      INNER JOIN mara AS ma
        ON ma~matnr = mast~matnr
     WHERE mast~werks = @p_werks
       AND ma~mtart  = 'FERT'
      INTO TABLE @lt_fert.

    TYPES ty_t_stlnr TYPE STANDARD TABLE OF stpo-stlnr WITH EMPTY KEY.
    DATA lt_stlnr TYPE ty_t_stlnr.
    LOOP AT lt_fert ASSIGNING FIELD-SYMBOL(<ls_fert>).
      APPEND <ls_fert>-stlnr TO lt_stlnr.
    ENDLOOP.
    SORT lt_stlnr.
    DELETE ADJACENT DUPLICATES FROM lt_stlnr.

    TYPES: BEGIN OF ty_comp,
             stlnr TYPE stpo-stlnr,
             matnr TYPE mara-matnr,
           END OF ty_comp.
    TYPES ty_t_comp TYPE STANDARD TABLE OF ty_comp WITH EMPTY KEY.
    DATA lt_comp TYPE ty_t_comp.

    IF lt_stlnr IS NOT INITIAL.
      SELECT DISTINCT stpo~stlnr,
                      stpo~idnrk
        FROM stpo
       WHERE stpo~stlnr IN @lt_stlnr
        INTO TABLE @lt_comp.
    ENDIF.

    TYPES: BEGIN OF ty_map,
             stlnr TYPE mast-stlnr,
             matnr TYPE mara-matnr,
           END OF ty_map.
    TYPES ty_t_map TYPE SORTED TABLE OF ty_map WITH UNIQUE KEY stlnr.
    DATA lt_map TYPE ty_t_map.
    LOOP AT lt_fert ASSIGNING <ls_fert>.
      INSERT VALUE ty_map( stlnr = <ls_fert>-stlnr matnr = <ls_fert>-matnr ) INTO TABLE lt_map.
    ENDLOOP.

    DATA lt_comp_mat TYPE ty_t_matnr.
    LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<ls_comp>).
      APPEND <ls_comp>-matnr TO lt_comp_mat.
    ENDLOOP.
    SORT lt_comp_mat.
    DELETE ADJACENT DUPLICATES FROM lt_comp_mat.

    DATA lt_cmov TYPE ty_t_matnr.
    IF lt_comp_mat IS NOT INITIAL.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        INNER JOIN mkpf AS mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
       WHERE mseg~werks = @p_werks
         AND mkpf~budat BETWEEN @p_begda AND @p_endda
         AND mseg~matnr IN @lt_comp_mat
        INTO TABLE @lt_cmov.
    ENDIF.

    DATA lt_cstk TYPE ty_t_matnr.
    IF lt_comp_mat IS NOT INITIAL.
      SELECT mard~matnr
        FROM mard
       WHERE mard~werks = @p_werks
         AND mard~labst <> 0
         AND mard~matnr IN @lt_comp_mat
        INTO TABLE @lt_cstk.
    ENDIF.

    DATA lt_cmov_s TYPE SORTED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_cstk_s TYPE SORTED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_cmov_s = lt_cmov.
    lt_cstk_s = lt_cstk.

    DATA lt_bom_mats TYPE ty_t_matnr.
    APPEND LINES OF lt_comp_mat TO lt_bom_mats.
    LOOP AT lt_fert ASSIGNING <ls_fert>.
      APPEND <ls_fert>-matnr TO lt_bom_mats.
    ENDLOOP.
    SORT lt_bom_mats.
    DELETE ADJACENT DUPLICATES FROM lt_bom_mats.

    TYPES: BEGIN OF ty_txt,
             matnr TYPE mara-matnr,
             maktx TYPE makt-maktx,
           END OF ty_txt.
    TYPES ty_t_txt TYPE STANDARD TABLE OF ty_txt WITH EMPTY KEY.
    DATA lt_txt TYPE ty_t_txt.

    IF lt_bom_mats IS NOT INITIAL.
      SELECT makt~matnr,
             makt~maktx
        FROM makt
       WHERE makt~spras = @sy-langu
         AND makt~matnr IN @lt_bom_mats
        INTO TABLE @lt_txt.
    ENDIF.

    TYPES: BEGIN OF ty_bom,
             parent    TYPE mara-matnr,
             parenttx  TYPE makt-maktx,
             comp      TYPE mara-matnr,
             comptx    TYPE makt-maktx,
             status    TYPE char20,
           END OF ty_bom.
    TYPES ty_t_bom TYPE STANDARD TABLE OF ty_bom WITH EMPTY KEY.
    DATA lt_bom_only TYPE ty_t_bom.

    FIELD-SYMBOLS <ls_txt> TYPE ty_txt.

    LOOP AT lt_comp ASSIGNING <ls_comp>.
      READ TABLE lt_cmov_s WITH TABLE KEY table_line = <ls_comp>-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      READ TABLE lt_cstk_s WITH TABLE KEY table_line = <ls_comp>-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      DATA(lv_parent) = VALUE mara-matnr( ).
      READ TABLE lt_map WITH KEY stlnr = <ls_comp>-stlnr ASSIGNING FIELD-SYMBOL(<ls_map>).
      IF sy-subrc = 0.
        lv_parent = <ls_map>-matnr.
      ENDIF.

      DATA(lv_parenttx) = VALUE makt-maktx( ).
      READ TABLE lt_txt ASSIGNING <ls_txt> WITH KEY matnr = lv_parent.
      IF sy-subrc = 0.
        lv_parenttx = <ls_txt>-maktx.
      ENDIF.

      DATA(lv_comptx) = VALUE makt-maktx( ).
      READ TABLE lt_txt ASSIGNING <ls_txt> WITH KEY matnr = <ls_comp>-matnr.
      IF sy-subrc = 0.
        lv_comptx = <ls_txt>-maktx.
      ENDIF.

      APPEND VALUE ty_bom(
        parent   = lv_parent
        parenttx = lv_parenttx
        comp     = <ls_comp>-matnr
        comptx   = lv_comptx
        status   = |BOM 만 있음| ) TO lt_bom_only.
    ENDLOOP.

    TYPES: BEGIN OF ty_out,
             category TYPE char10,
             matnr    TYPE mara-matnr,
             maktx    TYPE makt-maktx,
             mtart    TYPE mara-mtart,
             parent   TYPE mara-matnr,
             parenttx TYPE makt-maktx,
             has_mov  TYPE abap_bool,
             has_stk  TYPE abap_bool,
             status   TYPE char20,
           END OF ty_out.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.
    DATA lt_out TYPE ty_t_out.

    LOOP AT lt_main ASSIGNING FIELD-SYMBOL(<ls_main>).
      APPEND VALUE ty_out(
        category = |MAIN|
        matnr    = <ls_main>-matnr
        maktx    = <ls_main>-maktx
        mtart    = <ls_main>-mtart
        has_mov  = <ls_main>-has_mov
        has_stk  = <ls_main>-has_stk
        status   = <ls_main>-status ) TO lt_out.
    ENDLOOP.

    LOOP AT lt_bom_only ASSIGNING FIELD-SYMBOL(<ls_bom>).
      APPEND VALUE ty_out(
        category = |BOM_ONLY|
        matnr    = <ls_bom>-comp
        maktx    = <ls_bom>-comptx
        parent   = <ls_bom>-parent
        parenttx = <ls_bom>-parenttx
        status   = <ls_bom>-status ) TO lt_out.
    ENDLOOP.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      |플랜트 { p_werks } 기간 { p_begda } ~ { p_endda } 자재/재고/입출고/BOM 요약| ).
    lo_alv->get_columns( )->get_column( 'CATEGORY' )->set_short_text( '섹션' ).
    lo_alv->get_columns( )->get_column( 'MATNR' )->set_short_text( '자재' ).
    lo_alv->get_columns( )->get_column( 'MAKTX' )->set_short_text( '자재명' ).
    lo_alv->get_columns( )->get_column( 'MTART' )->set_short_text( '유형' ).
    lo_alv->get_columns( )->get_column( 'PARENT' )->set_short_text( '상위FERT' ).
    lo_alv->get_columns( )->get_column( 'PARENTTX' )->set_short_text( '상위명' ).
    lo_alv->get_columns( )->get_column( 'HAS_MOV' )->set_short_text( '입출고' ).
    lo_alv->get_columns( )->get_column( 'HAS_STK' )->set_short_text( '재고' ).
    lo_alv->get_columns( )->get_column( 'STATUS' )->set_short_text( '상태' ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).