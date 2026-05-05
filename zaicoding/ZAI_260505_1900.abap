REPORT ZAI_260505_1900.

SELECT-OPTIONS s_budat FOR mkpf~budat.
SELECT-OPTIONS s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_key,
      ty_t_key_h TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks,
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock_h TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks,
      BEGIN OF ty_info,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_info,
      ty_t_info_h TYPE HASHED TABLE OF ty_info WITH UNIQUE KEY matnr,
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        qty   TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CLASS-METHODS get_movements
      IMPORTING
        it_budat TYPE RANGE OF mkpf-budat
        it_werks TYPE RANGE OF mseg-werks
      RETURNING
        VALUE(rt_mov) TYPE ty_t_key_h.

    CLASS-METHODS get_stocks
      IMPORTING
        it_werks TYPE RANGE OF mard-werks
      RETURNING
        VALUE(rt_stock) TYPE ty_t_stock_h.

    CLASS-METHODS get_material_info
      IMPORTING
        it_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY
      RETURNING
        VALUE(rt_info) TYPE ty_t_info_h.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mov    TYPE ty_t_key_h.
    DATA lt_stock  TYPE ty_t_stock_h.
    DATA lt_keys   TYPE ty_t_key_h.
    DATA lt_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_info   TYPE ty_t_info_h.
    DATA lt_result TYPE ty_t_result.
    DATA ls_key    TYPE ty_key.
    DATA ls_res    TYPE ty_result.
    DATA ls_info   TYPE ty_info.
    DATA ls_stock  TYPE ty_stock.
    DATA lo_alv    TYPE REF TO cl_salv_table.

    lt_mov   = get_movements( it_budat = s_budat it_werks = s_werks ).
    lt_stock = get_stocks( it_werks = s_werks ).

    " Union of keys: movements
    LOOP AT lt_mov INTO ls_key.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.
    " Union of keys: stocks
    LOOP AT lt_stock INTO ls_stock.
      ls_key-matnr = ls_stock-matnr.
      ls_key-werks = ls_stock-werks.
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    " Build material list
    LOOP AT lt_keys INTO ls_key.
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    lt_info = get_material_info( it_matnr = lt_matnr ).

    " Build result
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_res.
      ls_res-matnr = ls_key-matnr.
      ls_res-werks = ls_key-werks.

      READ TABLE lt_info WITH TABLE KEY matnr = ls_key-matnr INTO ls_info.
      IF sy-subrc = 0.
        ls_res-mtart = ls_info-mtart.
        ls_res-matkl = ls_info-matkl.
        ls_res-maktx = ls_info-maktx.
      ENDIF.

      READ TABLE lt_stock WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks INTO ls_stock.
      IF sy-subrc = 0.
        ls_res-qty = ls_stock-qty.
      ELSE.
        ls_res-qty = 0.
      ENDIF.

      READ TABLE lt_mov WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks INTO ls_key.
      IF sy-subrc <> 0 AND ls_res-qty <> 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = '입출고 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
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
    DATA lt_mov TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~