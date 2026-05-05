REPORT ZAI_260505_2141.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,
  s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.

    DATA lt_mov_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_union_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with material documents in date/plant range
    SELECT DISTINCT
           mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Materials with current stock <> 0 in the selected plants
    SELECT DISTINCT
           mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst > 0.

    " 3) Union of movement and stock materials
    lt_union_matnr = lt_mov_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_union_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_union_matnr.

    IF lt_union_matnr IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Read master data and text for all union materials
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_result
      WHERE mara~matnr IN @lt_union_matnr.

    " 5) Determine status text
    DATA lv_status TYPE char20.
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
      DATA(lv_matnr) = <ls_res>-matnr.
      DATA(lv_in_mov) = abap_false.
      DATA(lv_in_stk) = abap_false.

      READ TABLE lt_mov_matnr WITH KEY table_line = lv_matnr
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_in_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_matnr WITH KEY table_line = lv_matnr
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_in_stk = abap_true.
      ENDIF.

      IF lv_in_mov = abap_false AND lv_in_stk = abap_true.
        lv_status = '재고만 있음'.
      ELSE.
        lv_status = '입출고 있음'.
      ENDIF.

      <ls_res>-status = lv_status.
    ENDLOOP.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).