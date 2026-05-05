REPORT ZAI_260505_2221.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,
  s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr     TYPE mara-matnr,
        mtart     TYPE mara-mtart,
        matkl     TYPE mara-matkl,
        maktx     TYPE makt-maktx,
        has_mov   TYPE abap_bool,
        has_stock TYPE abap_bool,
        remark    TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result        TYPE ty_t_result.
    DATA lo_alv           TYPE REF TO cl_salv_table.

    DATA lt_mov_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_union_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Materials with material documents in period/plant
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " Materials with current stock not zero in selected plants
    SELECT DISTINCT mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    " Union of both material sets
    lt_union_matnr = lt_mov_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_union_matnr.
    SORT lt_union_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_union_matnr.

    IF lt_union_matnr IS NOT INITIAL.
      " Read master data and text for the union list
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
    ENDIF.

    " Mark flags and remarks
    SORT lt_mov_matnr.
    SORT lt_stock_matnr.

    LOOP AT lt_result INTO DATA(ls_res).
      IF line_exists( lt_mov_matnr[ table_line = ls_res-matnr ] ).
        ls_res-has_mov = abap_true.
      ENDIF.
      IF line_exists( lt_stock_matnr[ table_line = ls_res-matnr ] ).
        ls_res-has_stock = abap_true.
      ENDIF.
      IF ls_res-has_stock = abap_true AND ls_res-has_mov IS INITIAL.
        ls_res-remark = '재고만 있음'.
      ENDIF.
      MODIFY lt_result FROM ls_res.
    ENDLOOP.

    " Show ALV
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        WRITE: / 'ALV error:', lx->get_text( ).
    ENDTRY.

    IF lt_result IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).