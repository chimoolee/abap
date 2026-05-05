REPORT ZAI_260505_2008.

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
      BEGIN OF ty_stock,
        matnr     TYPE mara-matnr,
        werks     TYPE werks_d,
        stock_qty TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_text,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_text,
      ty_t_text TYPE STANDARD TABLE OF ty_text WITH EMPTY KEY.

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

    DATA lt_move   TYPE ty_t_key.
    DATA lt_stock  TYPE ty_t_stock.
    DATA lt_key    TYPE ty_t_key.
    DATA lt_text   TYPE ty_t_text.
    DATA lt_result TYPE ty_t_result.

    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move
      WHERE ( @s_budat[] IS INITIAL OR mkpf~budat IN @s_budat )
        AND ( @s_werks[] IS INITIAL OR mseg~werks IN @s_werks )
        AND mseg~matnr <> ''.

    SORT lt_move BY matnr werks.

    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS stock_qty
      FROM mard
      WHERE ( @s_werks[] IS INITIAL OR mard~werks IN @s_werks )
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @lt_stock.

    SORT lt_stock BY matnr werks.

    lt_key = lt_move.
    LOOP AT lt_stock INTO DATA(ls_stk).
      APPEND VALUE ty_key( matnr = ls_stk-matnr werks = ls_stk-werks ) TO lt_key.
    ENDLOOP.
    SORT lt_key BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_key COMPARING matnr werks.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lv_prev TYPE mara-matnr.
    LOOP AT lt_key INTO DATA(ls_key).
      IF ls_key-matnr <> lv_prev.
        APPEND ls_key-matnr TO lt_matnr.
        lv_prev = ls_key-matnr.
      ENDIF.
    ENDLOOP.

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
        INTO TABLE @lt_text
        WHERE mara~matnr IN @lt_matnr.
      SORT lt_text BY matnr.
    ENDIF.

    LOOP AT lt_key INTO ls_key.
      DATA(ls_res) = VALUE ty_result(
        matnr = ls_key-matnr
        werks = ls_key-werks ).

      READ TABLE lt_text INTO DATA(ls_text)
        WITH KEY matnr = ls_key-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = ls_text-mtart.
        ls_res-matkl = ls_text-matkl.
        ls_res-maktx = ls_text-maktx.
      ENDIF.

      READ TABLE lt_stock INTO ls_stk
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-stock_qty = ls_stk-stock_qty.
      ELSE.
        ls_res-stock_qty = 0.
      ENDIF.

      READ TABLE lt_move WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-status = '입출고 실적'.
      ELSEIF ls_res-stock_qty > 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = ''.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).