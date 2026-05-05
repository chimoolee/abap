REPORT ZAI_260505_2013.

TABLES mara.

SELECT-OPTIONS: s_budat FOR mkpf~budat,
                 s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        labst TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mm,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mm,
      ty_t_mm TYPE STANDARD TABLE OF ty_mm WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        werks  TYPE werks_d,
        labst  TYPE mard-labst,
        status TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CLASS-METHODS get_move_keys
      IMPORTING
        it_budat TYPE RANGE OF mkpf-budat
        it_werks TYPE RANGE OF t001w-werks
      RETURNING
        VALUE(rt_keys) TYPE ty_t_key.

    CLASS-METHODS get_stock
      IMPORTING
        it_werks TYPE RANGE OF t001w-werks
      RETURNING
        VALUE(rt_stock) TYPE ty_t_stock.

    CLASS-METHODS get_mm_data
      IMPORTING
        it_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY
      RETURNING
        VALUE(rt_mm) TYPE ty_t_mm.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_move_keys TYPE ty_t_key.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_all_keys  TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.
    DATA ls_key       TYPE ty_key.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lv_matnr TYPE mara-matnr.

    DATA lt_mm     TYPE ty_t_mm.
    DATA ls_mm     TYPE ty_mm.

    DATA lt_result TYPE ty_t_result.
    DATA ls_result TYPE ty_result.

    DATA lo_alv TYPE REF TO cl_salv_table.

    lt_move_keys = get_move_keys( it_budat = s_budat it_werks = s_werks ).
    lt_stock     = get_stock( it_werks = s_werks ).

    LOOP AT lt_move_keys INTO ls_key.
      INSERT ls_key INTO TABLE lt_all_keys.
    ENDLOOP.

    LOOP AT lt_stock INTO DATA(ls_stock).
      ls_key-matnr = ls_stock-matnr.
      ls_key-werks = ls_stock-werks.
      INSERT ls_key INTO TABLE lt_all_keys.
    ENDLOOP.

    LOOP AT lt_all_keys INTO ls_key.
      lv_matnr = ls_key-matnr.
      APPEND lv_matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

    lt_mm = get_mm_data( lt_matnr ).

    DATA lt_mm_hash TYPE HASHED TABLE OF ty_mm WITH UNIQUE KEY matnr.
    lt_mm_hash = lt_mm.

    DATA lt_stock_hash TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.
    lt_stock_hash = lt_stock.

    DATA lt_move_hash TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.
    lt_move_hash = lt_move_keys.

    LOOP AT lt_all_keys INTO ls_key.
      CLEAR ls_result.
      READ TABLE lt_mm_hash INTO ls_mm WITH KEY matnr = ls_key-matnr.
      ls_result-matnr = ls_key-matnr.
      ls_result-werks = ls_key-werks.
      IF sy-subrc = 0.
        ls_result-mtart = ls_mm-mtart.
        ls_result-matkl = ls_mm-matkl.
        ls_result-maktx = ls_mm-maktx.
      ENDIF.

      READ TABLE lt_stock_hash INTO DATA(ls_s)
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        ls_result-labst = ls_s-labst.
      ELSE.
        ls_result-labst = 0.
      ENDIF.

      READ TABLE lt_move_hash WITH KEY matnr = ls_key-matnr werks = ls_key-werks
           TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls_result-status = '입출고 있음'.
      ELSE.
        ls_result-status = '재고만 있음'.
      ENDIF.

      APPEND ls_result TO lt_result.
    ENDLOOP.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->display( ).
  ENDMETHOD.

  METHOD get_move_keys.
    DATA lt_keys TYPE ty_t_key.
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_keys
      WHERE mkpf~budat IN @it_budat
        AND mseg~werks IN @it_werks.
    rt_keys = lt_keys.
  ENDMETHOD.

  METHOD get_stock.
    DATA lt_stock TYPE ty_t_stock.
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS labst
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @it_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0.
    rt_stock = lt_stock.
  ENDMETHOD.

  METHOD get_mm_data.
    DATA lt_mm TYPE ty_t_mm.
    IF it_matnr IS INITIAL.
      rt_mm = lt_mm.
      RETURN.
    ENDIF.

    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_mm
      WHERE mara~matnr IN @it_matnr.
    rt_mm = lt_mm.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).