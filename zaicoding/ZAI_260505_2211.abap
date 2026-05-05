REPORT ZAI_260505_2211.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,         " 전기일
  s_werks FOR mseg~werks.         " 플랜트

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

    " 자재 집합: 입출고 실적 보유
    DATA lt_mov_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    " 자재 집합: 현재 재고 > 0
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    " 최종 조회용 자재 리스트
    DATA lt_sel_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 입출고 실적이 있는 자재 (자재문서 + 플랜트 + 전기일)
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mseg~werks IN @s_werks
        AND mkpf~budat IN @s_budat
        AND mseg~matnr <> ''.

    " 현재 시점 재고가 0이 아닌 자재 (플랜트 기준)
    SELECT DISTINCT mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst > 0
        AND mard~matnr <> ''.

    " 최종 자재 목록 = 실적 자재 U 재고 자재
    APPEND LINES OF lt_mov_matnr   TO lt_sel_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_sel_matnr.
    SORT lt_sel_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_sel_matnr.

    IF lt_sel_matnr IS INITIAL.
      WRITE: / '선택된 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 자재 기본정보 + 텍스트
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
      WHERE mara~matnr IN @lt_sel_matnr.

    " 상태 플래그 세팅
    DATA(lv_has_move) = abap_false.
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
      lv_has_move = xsdbool( line_exists( lt_mov_matnr[
        table_line = <ls_res>-matnr ] ) ).
      IF lv_has_move = abap_true.
        <ls_res>-status = '입출고 있음'.
      ELSE.
        <ls_res>-status = '재고만 있음'.
      ENDIF.
    ENDLOOP.

    " ALV 표시
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