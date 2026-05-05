REPORT ZAI_260505_0928.

TABLES mara.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR mseg-werks.
SELECT-OPTIONS s_matnr FOR mara-matnr.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        has_mov TYPE abap_bool,
        stock_qty TYPE mard-labst,
      END OF ty_key,
      ty_t_key TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.

    TYPES:
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE HASHED TABLE OF ty_attr WITH UNIQUE KEY matnr.

    TYPES:
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        werks TYPE mseg-werks,
        stock_qty TYPE mard-labst,
        status_text TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_keys TYPE ty_t_key.
    DATA ls_key TYPE ty_key.

    DATA lt_mov TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.
    DATA lt_stock TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    DATA lt_attr TYPE ty_t_attr.
    DATA ls_attr TYPE ty_attr.

    DATA lt_result TYPE ty_t_result.
    DATA ls_result TYPE ty_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with movement (MKPF/MSEG) per plant/date
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @DATA(lt_mov_raw)
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr IN @s_matnr.

    LOOP AT lt_mov_raw INTO DATA(ls_mov_raw).
      CLEAR ls_key.
      ls_key-matnr = ls_mov_raw-matnr.
      ls_key-werks = ls_mov_raw-werks.
      ls_key-has_mov = abap_true.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    " 2) Materials with current stock > 0 per plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS stock_qty
      FROM mard
      WHERE mard~werks IN @s_werks
        AND mard~matnr IN @s_matnr
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @DATA(lt_stock_agg).

    LOOP AT lt_stock_agg INTO DATA(ls_stock_agg).
      READ TABLE lt_keys INTO ls_key
        WITH TABLE KEY matnr = ls_stock_agg-matnr werks = ls_stock_agg-werks.
      IF sy-subrc <> 0.
        CLEAR ls_key.
        ls_key-matnr = ls_stock_agg-matnr.
        ls_key-werks = ls_stock_agg-werks.
        ls_key-has_mov = abap_false.
        ls_key-stock_qty = ls_stock_agg-stock_qty.
        INSERT ls_key INTO TABLE lt_keys.
      ELSE.
        ls_key-stock_qty = ls_stock_agg-stock_qty.
        DELETE lt_keys FROM TABLE VALUE ty_t_key( ( ls_key ) ).
        INSERT ls_key INTO TABLE lt_keys.
      ENDIF.
    ENDLOOP.

    " If nothing found, show empty ALV
    IF lt_keys IS INITIAL.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = DATA(lo_alv_empty)
        CHANGING  t_table      = lt_result ).
      lo_alv_empty->display( ).
      RETURN.
    ENDIF.

    " Build material list for attribute fetch
    LOOP AT lt_keys INTO ls_key.
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 3) Fetch material attributes and text
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @DATA(lt_attr_raw)
      WHERE mara~matnr IN @lt_matnr.

    " Map to hashed by matnr
    LOOP AT lt_attr_raw INTO ls_attr.
      INSERT ls_attr INTO TABLE lt_attr.
    ENDLOOP.

    " 4) Build final result
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_result.
      READ TABLE lt_attr INTO ls_attr WITH TABLE KEY matnr = ls_key-matnr.
      ls_result-matnr = ls_key-matnr.
      ls_result-werks = ls_key