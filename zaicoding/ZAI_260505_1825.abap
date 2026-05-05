REPORT ZAI_260505_1825.

TABLES mara.

SELECT-OPTIONS s_budat FOR mkpf-budat NO-EXTENSION.
SELECT-OPTIONS s_werks FOR mseg-werks NO-EXTENSION.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    CONSTANTS:
      c_stat_mov   TYPE char20 VALUE '입출고 실적 있음',
      c_stat_stock TYPE char20 VALUE '재고만 있음'.

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

    DATA lt_mov_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stk_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    SELECT DISTINCT
      mard~matnr
      FROM mard
      INTO TABLE @lt_stk_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    APPEND LINES OF lt_mov_matnr TO lt_matnr.
    APPEND LINES OF lt_stk_matnr TO lt_matnr.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    TYPES:
      BEGIN OF ty_sel,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_sel,
      ty_t_sel TYPE STANDARD TABLE OF ty_sel WITH EMPTY KEY.

    DATA lt_sel TYPE ty_t_sel.

    IF lt_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_sel
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    SORT lt_mov_matnr.

    DATA ls_result TYPE ty_result.
    LOOP AT lt_sel INTO DATA(ls_sel).
      CLEAR ls_result.
      ls_result-matnr = ls_sel-matnr.
      ls_result-mtart = ls_sel-mtart.
      ls_result-matkl = ls_sel-matkl.
      ls_result-maktx = ls_sel-maktx.

      DATA(l_has_mov) = abap_false.
      READ TABLE lt_mov_matnr WITH KEY table_line = ls_sel-matnr
           TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        l_has_mov = abap_true.
      ENDIF.

      IF l_has_mov = abap_true.
        ls_result-status = c_stat_mov.
      ELSE.
        ls_result-status = c_stat_stock.
      ENDIF.

      APPEND ls_result TO lt_result.
    ENDLOOP.

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