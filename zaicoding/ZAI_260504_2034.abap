REPORT ZAI_260504_2034.

TABLES mara.

SELECT-OPTIONS s_budat FOR sy-datum.
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
        status    TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov_keys  TYPE ty_t_key.
    DATA lt_stock_agg TYPE ty_t_stock_agg.
    DATA lt_all_keys  TYPE ty_t_key.
    DATA lt_attr      TYPE ty_t_attr.
    DATA lt_result    TYPE ty_t_result.
    DATA lt_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

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

    " Keep only non-zero stock
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

    " Fetch attributes from MARA/MAKT (language-dependent text)
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
        matnr = ls_key-matnr
        werks = ls_key-werks
        mtart = VALUE mara-mtart( )
        matkl = VALUE mara-matkl( )
        maktx = VALUE makt-maktx( )
        stock_qty = 0
        status = '' ).

      READ TABLE lt_attr INTO DATA(ls_attr)
        WITH KEY matnr = ls_key-matnr
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = ls_attr-mtart.
        ls_res-matkl = ls_attr-matkl.
        ls_res-maktx = ls_attr-maktx.
      ENDIF.

      DATA(lv_has_mov) = abap_false.
      READ TABLE lt_mov_keys TRANSPORTING NO FIELDS
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_agg INTO DATA(ls_stk)
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-stock_qty = ls_stk-qty.
      ENDIF.

      IF lv_has_mov = abap_true AND ls_res-stock_qty > 0.
        ls_res-status = '입출고/재고있음'.
      ELSEIF lv_has_mov = abap_true AND ls_res-stock_qty = 0.
        ls_res-status = '입출고만 있음'.
      ELSEIF lv_has_mov = abap_false AND ls_res-stock_qty > 0.
        ls_res-status = '재고만 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

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