REPORT ZAI_260505_1854.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR mkpf~budat NO INTERVALS.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY,
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        werks  TYPE werks_d,
        qty    TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.
    DATA lt_stock TYPE ty_t_stock.
    DATA lt_attr TYPE ty_t_attr.

    DATA lt_move TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Movements for plant/date
    SELECT DISTINCT
           mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move
      WHERE mseg~werks = @p_werks
        AND mkpf~budat IN @s_budat.

    " Current stock aggregated at plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr, mard~werks
      INTO TABLE @lt_stock.

    " Build full material list: movements + stock>0 without movements
    DATA lv_matnr TYPE mara-matnr.
    LOOP AT lt_move INTO lv_matnr.
      APPEND lv_matnr TO lt_matnr.
    ENDLOOP.

    LOOP AT lt_stock INTO DATA(ls_stock).
      IF ls_stock-qty > 0.
        " Add if not already in list
        READ TABLE lt_matnr WITH KEY table_line = ls_stock-matnr TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND ls_stock-matnr TO lt_matnr.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " If nothing to show, just display empty ALV
    IF lt_matnr IS INITIAL.
      DATA lo_alv TYPE REF TO cl_salv_table.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_result ).
      lo_alv->display( ).
      RETURN.
    ENDIF.

    " Fetch attributes/texts
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

    " Build result
    LOOP AT lt_matnr INTO lv_matnr.
      DATA(ls_res) = VALUE ty_result( ).
      ls_res-matnr = lv_matnr.
      ls_res-werks = p_werks.
      READ TABLE lt_attr INTO DATA(ls_attr) WITH KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        ls_res-mtart = ls_attr-mtart.
        ls_res-matkl = ls_attr-matkl.
        ls_res-maktx = ls_attr-maktx.
      ENDIF.

      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = lv_matnr werks = p_werks.
      IF sy-subrc = 0.
        ls_res-qty = ls_stock-qty.
      ELSE.
        CLEAR ls_res-qty.
      ENDIF.

      READ TABLE lt_move WITH KEY table_line = lv_matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls_res-status = '입출고 있음'.
      ELSEIF ls_res-qty > 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        CONTINUE.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).