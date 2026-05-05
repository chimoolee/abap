REPORT ZAI_260505_2041.

TABLES mara.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat OBLIGATORY,
  s_werks FOR t001w-werks OBLIGATORY.

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
    DATA lt_union       TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with movements in selected date/plant
    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Materials with current non-zero stock in plant
    SELECT DISTINCT
      mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    " 3) Union
    APPEND LINES OF lt_mov_matnr   TO lt_union.
    APPEND LINES OF lt_stock_matnr TO lt_union.
    SORT lt_union.
    DELETE ADJACENT DUPLICATES FROM lt_union.

    IF lt_union IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Read master/text for union materials
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
      WHERE mara~matnr IN @lt_union.

    " 5) Derive status
    SORT lt_mov_matnr.
    SORT lt_stock_matnr.

    DATA lv_in_mov   TYPE abap_bool.
    DATA lv_in_stock TYPE abap_bool.
    DATA ls_res      TYPE ty_result.

    LOOP AT lt_result INTO ls_res.
      CLEAR: lv_in_mov, lv_in_stock.

      READ TABLE lt_mov_matnr WITH KEY table_line = ls_res-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_in_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_matnr WITH KEY table_line = ls_res-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_in_stock = abap_true.
      ENDIF.

      IF lv_in_mov = abap_true AND lv_in_stock = abap_true.
        ls_res-status = '입출고+재고'.
      ELSEIF lv_in_mov = abap_true.
        ls_res-status = '입출고 있음'.
      ELSEIF lv_in_stock = abap_true.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = '미정'.
      ENDIF.

      MODIFY lt_result FROM ls_res.
    ENDLOOP.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_sAlv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        WRITE: / 'ALV 표시 중 오류: ', lx_msg->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).