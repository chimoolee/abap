REPORT ZAI_260505_2256.

TABLES mara.
TABLES t001w.

SELECT-OPTIONS s_budat FOR sy-datum.
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
        status TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mv_keys TYPE ty_t_mv_key.
    DATA lt_stock   TYPE ty_t_stock.
    DATA lt_keys    TYPE ty_t_mv_key.
    DATA lt_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matinfo TYPE ty_t_matinfo.
    DATA lt_result  TYPE ty_t_result.

    DATA lo_alv TYPE REF TO cl_salv_table.

*   1) Materials with goods movement based on selection
    IF s_budat[] IS INITIAL AND s_werks[] IS INITIAL.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mv_keys.
    ELSEIF s_budat[] IS INITIAL AND s_werks[] IS NOT INITIAL.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mseg~werks IN @s_werks
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mv_keys.
    ELSEIF s_budat[] IS NOT INITIAL AND s_werks[] IS INITIAL.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mv_keys.
    ELSE.
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
    ENDIF.

*   2) Materials with current non-zero stock by plant
    IF s_werks[] IS INITIAL.
      SELECT mard~matnr,
             mard~werks,
             SUM( mard~labst ) AS qty
        FROM mard
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) <> 0
        INTO TABLE @lt_stock.
    ELSE.
      SELECT mard~matnr,
             mard~werks,
             SUM( mard~labst ) AS qty
        FROM mard
        WHERE mard~werks IN @s_werks
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) <> 0
        INTO TABLE @lt_stock.
    ENDIF.

*   3) Union keys (movement OR stock)
    lt_keys = lt_mv_keys.
    LOOP AT lt_stock INTO DATA(ls_stock).
      APPEND VALUE ty_mv_key(
        matnr = ls_stock-matnr
        werks = ls_stock-werks ) TO lt_keys.
    ENDLOOP.
    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

*   4) Collect material numbers for text/master data
    LOOP AT lt_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

*   5) Get material master and text
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

*   6) Build result
    LOOP AT lt_keys INTO ls_key.
      DATA(lv_has_mv) = abap_false.
      DATA(lv_qty)    TYPE mard-labst VALUE 0.
      DATA(ls_info)   TYPE ty_matinfo.

      READ TABLE lt_mv_keys WITH KEY matnr = ls_key-matnr
                                     werks = ls_key-werks
                                     TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mv = abap_true.
      ENDIF.

      READ TABLE lt_stock INTO ls_stock
           WITH KEY matnr = ls_key-matnr
                    werks = ls_key-werks.
      IF sy-subrc = 0.
        lv_qty = ls_stock-qty.
      ENDIF.

      READ TABLE lt_matinfo INTO ls_info
           WITH KEY matnr = ls_key-matnr.

      DATA(lv_status) = COND string(
                          WHEN lv_has_mv = abap_true THEN '입출고 실적'
                          WHEN lv_qty    <> 0        THEN '재고만 있음'
                          ELSE                           '해당없음' ).

      APPEND VALUE ty_result(
        matnr  = ls_key-matnr
        werks  = ls_key-werks
        mtart  = ls_info-mtart
        matkl  = ls_info-matkl
        maktx  = ls_info-maktx
        qty    = lv_qty
        status = lv_status ) TO lt_result.
    ENDLOOP.

*   7) Display ALV
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        WRITE: / 'ALV Error: ', lx->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).