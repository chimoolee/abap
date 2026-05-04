REPORT ZAI_260504_1957.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

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
      ty_t_key     TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
      ty_t_key_h   TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks,
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr_h  TYPE HASHED TABLE OF ty_attr WITH UNIQUE KEY matnr,
      ty_status    TYPE c LENGTH 20,
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        status TYPE ty_status,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_post        TYPE ty_t_key.
    DATA lt_stock_keys  TYPE ty_t_key.
    DATA lt_union_hash  TYPE ty_t_key_h.
    DATA lt_post_hash   TYPE ty_t_key_h.
    DATA lt_stock_hash  TYPE ty_t_key_h.
    DATA lt_result      TYPE ty_t_result.
    DATA lt_attr        TYPE ty_t_attr_h.
    DATA lt_matnr       TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with postings in date range per plant (optional filters)
    SELECT DISTINCT
      s~matnr,
      s~werks
      FROM mseg AS s
      INNER JOIN mkpf AS k
        ON k~mblnr = s~mblnr
       AND k~mjahr = s~mjahr
      INTO TABLE @lt_post
      WHERE ( k~budat IN @s_budat OR @s_budat IS INITIAL )
        AND ( s~werks IN @s_werks OR @s_werks IS INITIAL ).

    lt_post_hash = CORRESPONDING ty_t_key_h( lt_post ).

    " 2) Materials with current non-zero stock per plant (optional plant filter)
    SELECT DISTINCT
      mard~matnr,
      mard~werks
      FROM mard
      INTO TABLE @lt_stock_keys
      WHERE ( mard~werks IN @s_werks OR @s_werks IS INITIAL )
        AND mard~labst <> 0.

    lt_stock_hash = CORRESPONDING ty_t_key_h( lt_stock_keys ).

    " 3) Union of keys
    lt_union_hash = lt_post_hash.
    LOOP AT lt_stock_keys INTO DATA(ls_skey).
      INSERT ls_skey INTO TABLE lt_union_hash.
    ENDLOOP.

    " 4) Collect material list
    LOOP AT lt_union_hash INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

    " 5) Read attributes and text
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
        INTO TABLE @DATA(lt_attr_std)
        WHERE mara~matnr IN @lt_matnr.
      lt_attr = CORRESPONDING ty_t_attr_h( lt_attr_std ).
    ENDIF.

    " 6) Build result with status
    LOOP AT lt_union_hash INTO ls_key.
      DATA(lv_has_post) = xsdbool(
        line_exists( lt_post_hash[ matnr = ls_key-matnr werks = ls_key-werks ] ) ).
      DATA(lv_has_stock) = xsdbool(
        line_exists( lt_stock_hash[ matnr = ls_key-matnr werks = ls_key-werks ] ) ).
      DATA(ls_attr) = VALUE ty_attr( ).
      READ TABLE lt_attr WITH KEY matnr = ls_key-matnr INTO ls_attr.

      DATA(lv_status) = COND ty_status(
        WHEN lv_has_post = abap_true AND lv_has_stock = abap_true THEN '입출고+재고'
        WHEN lv_has_post = abap_true THEN '입출고 있음'
        WHEN lv_has_stock = abap_true THEN '재고만 있음'
        ELSE ' ' ).

      APPEND VALUE ty_result(
        matnr  = ls_key-matnr
        werks  = ls_key-werks
        mtart  = ls_attr-mtart
        matkl  = ls_attr-matkl
        maktx  = ls_attr-maktx
        status = lv_status ) TO lt_result.
    ENDLOOP.

    " 7) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).