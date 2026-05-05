REPORT ZAI_260505_2318.

TABLES mara.

SELECT-OPTIONS s_matnr FOR mara~matnr.
SELECT-OPTIONS s_budat FOR mkpf~budat.
SELECT-OPTIONS s_werks FOR mseg~werks.

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

    DATA lt_result     TYPE ty_t_result.
    DATA lt_mv_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stk_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 자재문서가 있는 자재 수집 (MKPF~BUDAT, MSEG~WERKS, 선택적 MATNR)
    IF s_matnr[] IS INITIAL.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mv_matnr
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks.
    ELSE.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mv_matnr
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks
          AND mseg~matnr IN @s_matnr.
    ENDIF.

    " 현재 시점 재고 보유 자재 수집 (MARD, 어느 저장위치라도 재고 <> 0)
    IF s_matnr[] IS INITIAL.
      SELECT DISTINCT mard~matnr
        FROM mard
        INTO TABLE @lt_stk_matnr
        WHERE mard~werks IN @s_werks
          AND mard~labst <> 0.
    ELSE.
      SELECT DISTINCT mard~matnr
        FROM mard
        INTO TABLE @lt_stk_matnr
        WHERE mard~werks IN @s_werks
          AND mard~labst <> 0
          AND mard~matnr IN @s_matnr.
    ENDIF.

    " 두 집합 합집합
    APPEND LINES OF lt_mv_matnr TO lt_all_matnr.
    APPEND LINES OF lt_stk_matnr TO lt_all_matnr.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    " 자재 기본정보 + 텍스트 조회
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

    " 상태 결정: 입출고가 있으면 '입출고 있음', 없고 재고만 있으면 '재고만 있음'
    IF lt_result IS NOT INITIAL.
      SORT lt_mv_matnr.
      SORT lt_stk_matnr.
      DATA lv_has_mv  TYPE abap_bool.
      DATA lv_has_stk TYPE abap_bool.
      LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
        READ TABLE lt_mv_matnr WITH KEY table_line = <ls_res>-matnr
          TRANSPORTING NO FIELDS BINARY SEARCH.
        lv_has_mv = xsdbool( sy-subrc = 0 ).
        READ TABLE lt_stk_matnr WITH KEY table_line = <ls_res>-matnr
          TRANSPORTING NO FIELDS BINARY SEARCH.
        lv_has_stk = xsdbool( sy-subrc = 0 ).
        IF lv_has_mv = abap_true.
          <ls_res>-status = '입출고 있음'.
        ELSEIF lv_has_stk = abap_true.
          <ls_res>-status = '재고만 있음'.
        ELSE.
          <ls_res>-status = ''.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 표시
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).