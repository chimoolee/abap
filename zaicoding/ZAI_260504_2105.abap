REPORT ZAI_260504_2105.

TABLES mara.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

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
        status TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.

    DATA lt_mov TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stk TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 자재문서 기준 입출고 실적 자재
    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 현재 시점 재고가 0이 아닌 자재
    SELECT DISTINCT
      mard~matnr
      FROM mard
      INTO TABLE @lt_stk
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    " 합집합 자재 리스트
    lt_matnr = lt_mov.
    APPEND LINES OF lt_stk TO lt_matnr.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS NOT INITIAL.
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
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    " 상태 판별을 위한 해시 테이블
    DATA lt_mov_h TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_stk_h TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_mov_h = lt_mov.
    lt_stk_h = lt_stk.

    " 상태 세팅: 입출고 있음 / 재고만 있음
    DATA ls_res TYPE ty_result.
    LOOP AT lt_result INTO ls_res.
      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.

      READ TABLE lt_mov_h WITH TABLE KEY table_line = ls_res-matnr
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stk_h WITH TABLE KEY table_line = ls_res-matnr
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_res-status = '입출고 있음'.
      ELSEIF lv_has_stk = abap_true.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = ''.
      ENDIF.

      MODIFY lt_result FROM ls_res.
    ENDLOOP.

    " ALV 출력
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