REPORT ZAI_260504_2052.

TABLES mara.

SELECT-OPTIONS s_budat FOR sy-datum.
SELECT-OPTIONS s_werks FOR mseg-werks.

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

    DATA lt_result      TYPE ty_t_result.
    DATA lt_mov_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Materials with movements by date/plant
    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mseg~werks IN @s_werks
        AND mkpf~budat IN @s_budat.

    " Materials with current non-zero stock by plant
    SELECT
      matnr
      FROM mard
      WHERE werks IN @s_werks
      GROUP BY matnr
      HAVING SUM( labst ) <> 0
      INTO TABLE @lt_stock_matnr.

    " Union of both sets
    lt_all_matnr = lt_mov_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_all_matnr.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    " Read master data and text for the union set
    IF lt_all_matnr IS NOT INITIAL.
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
        WHERE mara~matnr IN @lt_all_matnr.
    ENDIF.

    SORT lt_mov_matnr.
    SORT lt_stock_matnr.

    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
      DATA(lv_in_mov) = abap_false.
      DATA(lv_in_stk) = abap_false.

      READ TABLE lt_mov_matnr WITH KEY table_line = <ls_res>-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_in_mov = abap_true.
      ENDIF.

      IF lv_in_mov = abap_false.
        READ TABLE lt_stock_matnr WITH KEY table_line = <ls_res>-matnr
          TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc = 0.
          lv_in_stk = abap_true.
        ENDIF.
      ENDIF.

      IF lv_in_mov = abap_true.
        <ls_res>-status = '입출고 실적 있음'.
      ELSEIF lv_in_stk = abap_true.
        <ls_res>-status = '재고만 있음'.
      ELSE.
        <ls_res>-status = '해당 없음'.
      ENDIF.
    ENDLOOP.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_display_settings( )->set_list_header(
      value = '자재 리스트 - 전기일/플랜트 기준, 실적 또는 재고 보유 자재 표시' ).

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).