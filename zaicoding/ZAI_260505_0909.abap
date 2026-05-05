REPORT ZAI_260505_0909.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_mov,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_mov,
      ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY,

      BEGIN OF ty_stock,
        matnr TYPE mard-matnr,
        werks TYPE mard-werks,
        labst TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,

      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY,

      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_key,
      ty_t_key TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks,

      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CLASS-METHODS get_movements
      IMPORTING
        it_budat TYPE RANGE OF mkpf-budat
        it_werks TYPE RANGE OF mseg-werks
      RETURNING
        VALUE(rt_mov) TYPE ty_t_mov.

    CLASS-METHODS get_stocks
      IMPORTING
        it_werks TYPE RANGE OF mard-werks
      RETURNING
        VALUE(rt_stock) TYPE ty_t_stock.

    CLASS-METHODS get_attrs
      IMPORTING
        it_matnr TYPE STANDARD TABLE OF mara-matnr
      RETURNING
        VALUE(rt_attr) TYPE ty_t_attr.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mov    TYPE ty_t_mov.
    DATA lt_stock  TYPE ty_t_stock.
    DATA lt_keys   TYPE ty_t_key.
    DATA ls_key    TYPE ty_key.
    DATA lt_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_attr   TYPE ty_t_attr.
    DATA ls_attr   TYPE ty_attr.
    DATA lt_result TYPE ty_t_result.
    DATA ls_result TYPE ty_result.
    DATA lo_alv    TYPE REF TO cl_salv_table.

    lt_mov   = get_movements( it_budat = s_budat it_werks = s_werks ).
    lt_stock = get_stocks( it_werks = s_werks ).

    LOOP AT lt_mov INTO DATA(ls_mov).
      ls_key-matnr = ls_mov-matnr.
      ls_key-werks = ls_mov-werks.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    LOOP AT lt_stock INTO DATA(ls_stock).
      ls_key-matnr = ls_stock-matnr.
      ls_key-werks = ls_stock-werks.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    LOOP AT lt_keys INTO ls_key.
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS NOT INITIAL.
      lt_attr = get_attrs( it_matnr = lt_matnr ).
    ENDIF.

    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_result.
      ls_result-matnr = ls_key-matnr.
      ls_result-werks = ls_key-werks.

      READ TABLE lt_attr INTO ls_attr WITH KEY matnr = ls_key-matnr.
      IF sy-subrc = 0.
        ls_result-mtart = ls_attr-mtart.
        ls_result-matkl = ls_attr-matkl.
        ls_result-maktx = ls_attr-maktx.
      ENDIF.

      DATA(lv_has_mov) = abap_false.
      READ TABLE lt_mov TRANSPORTING NO FIELDS
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      DATA(lv_has_stock) = abap_false.
      READ TABLE lt_stock INTO ls_stock
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0 AND ls_stock-labst <> 0.
        lv_has_stock = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_result-status = '입출고 있음'.
      ELSEIF lv_has_stock = abap_true.
        ls_result-status = '재고만 있음'.
      ELSE.
        CONTINUE.
      ENDIF.

      APPEND ls_result TO lt_result.
    ENDLOOP.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result
    ).
    lo_alv->display( ).
  ENDMETHOD.

  METHOD get_movements.
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @rt_mov
      WHERE mkpf~budat IN @it_budat
        AND mseg~werks IN @it_werks.
  ENDMETHOD.

  METHOD get_stocks.
    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @rt_stock
      WHERE mard~werks IN @it_werks
        AND mard~labst <> 0.
  ENDMETHOD.

  METHOD get_attrs.
    DATA lt_matnr_local TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    lt_matnr_local = it_matnr.

    IF lt_matnr_local IS INITIAL.
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
      INTO TABLE @rt_attr
      WHERE mara~matnr IN @lt_matnr_local.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).