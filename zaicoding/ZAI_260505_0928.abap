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
        matnr     TYPE mara-matnr,
        werks     TYPE mseg-werks,
        has_mov   TYPE abap_bool,
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
        matnr      TYPE mara-matnr,
        mtart      TYPE mara-mtart,
        matkl      TYPE mara-matkl,
        maktx      TYPE makt-maktx,
        werks      TYPE mseg-werks,
        stock_qty  TYPE mard-labst,
        status_txt TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mov_raw,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_mov_raw,
      ty_t_mov_raw TYPE STANDARD TABLE OF ty_mov_raw WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock_agg,
        matnr     TYPE mard-matnr,
        werks     TYPE mard-werks,
        stock_qty TYPE mard-labst,
      END OF ty_stock_agg,
      ty_t_stock_agg TYPE STANDARD TABLE OF ty_stock_agg WITH EMPTY KEY.

    DATA lt_keys       TYPE ty_t_key.
    DATA ls_key        TYPE ty_key.
    DATA lt_attr       TYPE ty_t_attr.
    DATA ls_attr       TYPE ty_attr.
    DATA lt_result     TYPE ty_t_result.
    DATA ls_result     TYPE ty_result.
    DATA lt_matnr      TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_mov_raw    TYPE ty_t_mov_raw.
    DATA lt_stock_agg  TYPE ty_t_stock_agg.
    DATA lo_alv        TYPE REF TO cl_salv_table.

    " 1) Materials with movement per plant/date
    IF s_matnr[] IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mov_raw
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks.
    ELSE.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mov_raw
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks
          AND mseg~matnr IN @s_matnr.
    ENDIF.

    LOOP AT lt_mov_raw INTO DATA(ls_mov_raw).
      READ TABLE lt_keys INTO ls_key
        WITH TABLE KEY matnr = ls_mov_raw-matnr werks = ls_mov_raw-werks.
      IF sy-subrc <> 0.
        CLEAR ls_key.
        ls_key-matnr = ls_mov_raw-matnr.
        ls_key-werks = ls_mov_raw-werks.
      ENDIF.
      ls_key-has_mov = abap_true.
      DELETE TABLE lt_keys FROM ls_key.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    " 2) Materials with current stock > 0 per plant
    IF s_matnr[] IS INITIAL.
      SELECT
        mard~matnr,
        mard~werks,
        SUM( mard~labst ) AS stock_qty
        FROM mard
        INTO TABLE @lt_stock_agg
        WHERE mard~werks IN @s_werks
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) > 0.
    ELSE.
      SELECT
        mard~matnr,
        mard~werks,
        SUM( mard~labst ) AS stock_qty
        FROM mard
        INTO TABLE @lt_stock_agg
        WHERE mard~werks IN @s_werks
          AND mard~matnr IN @s_matnr
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) > 0.
    ENDIF.

    LOOP AT lt_stock_agg INTO DATA(ls_stock_agg).
      READ TABLE lt_keys INTO ls_key
        WITH TABLE KEY matnr = ls_stock_agg-matnr werks = ls_stock_agg-werks.
      IF sy-subrc <> 0.
        CLEAR ls_key.
        ls_key-matnr = ls_stock_agg-matnr.
        ls_key-werks = ls_stock_agg-werks.
        ls_key-has_mov = abap_false.
      ENDIF.
      ls_key-stock_qty = ls_stock_agg-stock_qty.
      DELETE TABLE lt_keys FROM ls_key.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    IF lt_keys IS INITIAL.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_result ).
      lo_alv->display( ).
      RETURN.
    ENDIF.

    " Build material list for attribute fetch
    LOOP AT lt_keys INTO ls_key.
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 3) Fetch material attributes and text
    DATA lt_attr_raw TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_attr_raw
      WHERE mara~matnr IN @lt_matnr.

    LOOP AT lt_attr_raw INTO ls_attr.
      INSERT ls_attr INTO TABLE lt_attr.
    ENDLOOP.

    " 4) Build final result
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_result.
      READ TABLE lt_attr INTO ls_attr
        WITH TABLE KEY matnr = ls_key-matnr.
      ls_result-matnr = ls_key-matnr.
      ls_result-werks = ls_key-werks.
      ls_result-mtart = ls_attr-mtart.
      ls_result-matkl = ls_attr-matkl.
      ls_result-maktx = ls_attr-maktx.
      ls_result-stock_qty = ls_key-stock_qty.
      IF ls_key-has_mov = abap_true.
        ls_result-status_txt = '입출고 있음'.
      ELSE.
        ls_result-status_txt = '재고만 있음'.
      ENDIF.
      APPEND ls_result TO lt_result.
    ENDLOOP.

    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_result ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).