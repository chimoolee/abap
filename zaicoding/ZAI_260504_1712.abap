REPORT ZAI_260504_1712.

TABLES mara.

PARAMETERS p_begda TYPE sy-datum DEFAULT sy-datum.
PARAMETERS p_endda TYPE sy-datum DEFAULT sy-datum.
SELECT-OPTIONS s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lv_begda TYPE sy-datum VALUE p_begda.
    DATA lv_endda TYPE sy-datum VALUE p_endda.

    IF lv_begda IS INITIAL OR lv_endda IS INITIAL OR lv_begda > lv_endda.
      MESSAGE '유효한 기간을 입력하세요.' TYPE 'E'.
      RETURN.
    ENDIF.

    TYPES: BEGIN OF ty_mov,
             matnr TYPE mseg-matnr,
             werks TYPE mseg-werks,
           END OF ty_mov,
           ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mard-matnr,
             werks TYPE mard-werks,
             labst TYPE mard-labst,
           END OF ty_stock,
           ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_pair,
             matnr TYPE mara-matnr,
             werks TYPE werks_d,
           END OF ty_pair,
           ty_t_pair TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY.

    TYPES: BEGIN OF ty_desc,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             matkl TYPE mara-matkl,
             maktx TYPE makt-maktx,
           END OF ty_desc,
           ty_t_desc TYPE STANDARD TABLE OF ty_desc WITH EMPTY KEY.

    TYPES: BEGIN OF ty_result,
             section  TYPE char10,
             category TYPE char20,
             matnr    TYPE mara-matnr,
             werks    TYPE werks_d,
             mtart    TYPE mara-mtart,
             matkl    TYPE mara-matkl,
             maktx    TYPE makt-maktx,
             labst    TYPE mard-labst,
             has_mov  TYPE abap_bool,
           END OF ty_result,
           ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov        TYPE ty_t_mov.
    DATA lt_stock      TYPE ty_t_stock.
    DATA lt_bom_fert   TYPE ty_t_pair.
    DATA lt_bom_comp   TYPE ty_t_pair.
    DATA lt_union_keys TYPE ty_t_pair.
    DATA lt_result     TYPE ty_t_result.
    DATA lt_desc       TYPE ty_t_desc.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~budat BETWEEN @lv_begda AND @lv_endda
        AND mseg~werks IN @s_werks.

    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    SELECT DISTINCT
      mast~matnr,
      mast~werks
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      INTO TABLE @lt_bom_fert
      WHERE mast~werks IN @s_werks
        AND mara~mtart = 'FERT'.

    SELECT DISTINCT
      stpo~idnrk AS matnr,
      mast~werks AS werks
      FROM mast
      INNER JOIN mara AS mh
        ON mh~matnr = mast~matnr
      INNER JOIN stpo
        ON stpo~stlnr = mast~stlnr
      INTO TABLE @lt_bom_comp
      WHERE mast~werks IN @s_werks
        AND mh~mtart = 'FERT'.

    DATA lt_key_mov   TYPE ty_t_pair.
    DATA lt_key_stock TYPE ty_t_pair.

    lt_key_mov   = CORRESPONDING ty_t_pair( lt_mov ).
    lt_key_stock = CORRESPONDING ty_t_pair( lt_stock ).

    lt_union_keys = lt_key_mov.
    APPEND LINES OF lt_key_stock TO lt_union_keys.
    SORT lt_union_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_union_keys COMPARING matnr werks.

    TYPES: BEGIN OF ty_hash,
             matnr TYPE mara-matnr,
             werks TYPE werks_d,
           END OF ty_hash.
    DATA lt_h_mov   TYPE HASHED TABLE OF ty_hash WITH UNIQUE KEY matnr werks.
    DATA lt_h_stock TYPE HASHED TABLE OF ty_hash WITH UNIQUE KEY matnr werks.

    lt_h_mov   = CORRESPONDING #( lt_key_mov ).
    lt_h_stock = CORRESPONDING #( lt_key_stock ).

    DATA lt_h_stock_val TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.
    lt_h_stock_val = lt_stock.

    LOOP AT lt_union_keys INTO DATA(ls_key).
      DATA(ls_res) = VALUE ty_result(
        section = 'MAIN'
        matnr   = ls_key-matnr
        werks   = ls_key-werks
        has_mov = COND #( WHEN line_exists(
                              lt_h_mov[ matnr = ls_key-matnr
                                        werks = ls_key-werks ] )
                          THEN abap_true ELSE abap_false )
        labst   = 0 ).

      READ TABLE lt_h_stock_val INTO DATA(ls_stock_v)
        WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        ls_res-labst = ls_stock_v-labst.
      ENDIF.

      IF ls_res-has_mov = abap_true AND ls_res-labst <> 0.
        ls_res-category = '입출고/재고'.
      ELSEIF ls_res-has_mov = abap_true.
        ls_res-category = '입출고 실적'.
      ELSE.
        ls_res-category = '재고만 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    LOOP AT lt_bom_fert INTO DATA(ls_fert).
      DATA(ls_res_f) = VALUE ty_result(
        section  = 'BOM'
        category = '완제품(BOM있음)'
        matnr    = ls_fert-matnr
        werks    = ls_fert-werks
        has_mov  = COND #( WHEN line_exists(
                               lt_h_mov[ matnr = ls_fert-matnr
                                         werks = ls_fert-werks ] )
                           THEN abap_true ELSE abap_false )
        labst    = 0 ).
      READ TABLE lt_h_stock_val INTO ls_stock_v
        WITH TABLE KEY matnr = ls_fert-matnr werks = ls_fert-werks.
      IF sy-subrc = 0.
        ls_res_f-labst = ls_stock_v-labst.
      ENDIF.
      APPEND ls_res_f TO lt_result.
    ENDLOOP.

    LOOP AT lt_bom_comp INTO DATA(ls_comp).
      IF line_exists( lt_h_mov[ matnr = ls_comp-matnr werks = ls_comp-werks ] ).
        CONTINUE.
      ENDIF.
      IF line_exists( lt_h_stock[ matnr = ls_comp-matnr werks = ls_comp-werks ] ).
        CONTINUE.
      ENDIF.

      DATA(ls_res_c) = VALUE ty_result(
        section  = 'BOM'
        category = 'BOM 에 만 있음'
        matnr    = ls_comp-matnr
        werks    = ls_comp-werks
        has_mov  = abap_false
        labst    = 0 ).
      APPEND ls_res_c TO lt_result.
    ENDLOOP.

    DELETE ADJACENT DUPLICATES FROM lt_result COMPARING matnr werks section category.

    LOOP AT lt_result INTO DATA(ls_r2).
      APPEND ls_r2-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_desc
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    DATA lt_h_desc TYPE HASHED TABLE OF ty_desc WITH UNIQUE KEY matnr.
    lt_h_desc = lt_desc.

    LOOP AT lt_result INTO ls_r2.
      READ TABLE lt_h_desc INTO DATA(ls_d)
        WITH TABLE KEY matnr = ls_r2-matnr.
      IF sy-subrc = 0.
        ls_r2-mtart = ls_d-mtart.
        ls_r2-matkl = ls_d-matkl.
        ls_r2-maktx = ls_d-maktx.
      ENDIF.
      MODIFY lt_result FROM ls_r2.
    ENDLOOP.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).