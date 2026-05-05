REPORT ZAI_260505_2256.

SELECT-OPTIONS s_budat FOR mkpf~budat.
SELECT-OPTIONS s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_mv_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_mv_key,
      ty_t_mv_key TYPE STANDARD TABLE OF ty_mv_key WITH EMPTY KEY,

      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,

      BEGIN OF ty_matinfo,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_matinfo,
      ty_t_matinfo TYPE STANDARD TABLE OF ty_matinfo WITH EMPTY KEY,

      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        qty    TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mv_keys TYPE ty_t_mv_key.
    DATA lt_stock   TYPE ty_t_stock.
    DATA lt_keys    TYPE ty_t_mv_key.
    DATA lt_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matinfo TYPE ty_t_matinfo.
    DATA lt_result  TYPE ty_t_result.

    SELECT mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
      GROUP BY mseg~matnr, mseg~werks
      INTO TABLE @lt_mv_keys.

    SELECT mard~matnr,
           mard~werks,
           SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    lt_keys = lt_mv_keys.
    LOOP AT lt_stock INTO DATA(ls_stock).
      APPEND VALUE ty_mv_key( matnr = ls_stock-matnr
                              werks = ls_stock-werks ) TO lt_keys.
    ENDLOOP.
    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    LOOP AT lt_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

    IF lt_matnr IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_matinfo
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    SORT lt_matinfo BY matnr.
    SORT lt_mv_keys BY matnr werks.
    SORT lt_stock   BY matnr werks.

    LOOP AT lt_keys INTO ls_key.
      DATA(lv_has_mv) = abap_false.
      DATA(lv_qty)    = CONV mard-labst( 0 ).
      READ TABLE lt_mv_keys WITH KEY matnr = ls_key-matnr
                                     werks = ls_key-werks
                                     BINARY SEARCH TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mv = abap_true.
      ENDIF.

      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_key-matnr
                                               werks = ls_key-werks
                                               BINARY SEARCH.
      IF sy-subrc = 0.
        lv_qty = ls_stock-qty.
      ENDIF.

      READ TABLE lt_matinfo INTO DATA(ls_info)
           WITH KEY matnr = ls_key-matnr BINARY SEARCH.

      APPEND VALUE ty_result(
        matnr  = ls_key-matnr
        werks  = ls_key-werks
        mtart  = COND #( WHEN sy-subrc = 0 THEN ls_info-mtart ELSE '' )
        matkl  = COND #( WHEN sy-subrc = 0 THEN ls_info-matkl ELSE '' )
        maktx  = COND #( WHEN sy-subrc = 0 THEN ls_info-maktx ELSE '' )
        qty    = lv_qty
        status = COND #( WHEN lv_has_mv = abap_true THEN '입출고 실적'
                         ELSE '재고만 있음' ) ) TO lt_result.
    ENDLOOP.

    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        WRITE: / 'ALV error: ', lx->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).