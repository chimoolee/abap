REPORT ZAI_260504_2034.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock_agg,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
      END OF ty_stock_agg,
      ty_t_stock_agg TYPE STANDARD TABLE OF ty_stock_agg WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr     TYPE mara-matnr,
        werks     TYPE werks_d,
        mtart     TYPE mara-mtart,
        matkl     TYPE mara-matkl,
        maktx     TYPE makt-maktx,
        stock_qty TYPE mard-labst,
        status    TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov_keys   TYPE ty_t_key.
    DATA lt_stock_agg  TYPE ty_t_stock_agg.
    DATA lt_all_keys   TYPE ty_t_key.
    DATA lt_attr       TYPE ty_t_attr.
    DATA lt_result     TYPE ty_t_result.
    DATA lt_matnr      TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Movement keys by MKPF/MSEG with posting date and plant filter
    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_keys
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " Current stock aggregated by MATNR/WERKS
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard
      INTO TABLE @lt_stock_agg
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks.

    " Remove zero-qty entries from stock
    DELETE lt_stock_agg WHERE qty = 0.

    " Build union of keys: movements and non-zero stock
    lt_all_keys = lt_mov_keys.
    LOOP AT lt_stock_agg INTO DATA(ls_sa).
      APPEND VALUE ty_key( matnr = ls_sa-matnr werks = ls_sa-werks ) TO lt_all_keys.
    ENDLOOP.
    SORT lt_all_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_all_keys COMPARING matnr werks.

    " Prepare material list for attribute fetch
    LOOP AT lt_all_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " Fetch attributes from MARA/MAKT
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
        INTO TABLE @lt_attr
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    SORT lt_attr BY matnr.
    SORT lt_mov_keys BY matnr werks.
    SORT lt_stock_agg BY matnr werks.

    " Build result with status and stock quantity
    LOOP AT lt_all_keys INTO ls_key.
      DATA(ls_res) = VALUE ty_result(
        matnr = ls_key