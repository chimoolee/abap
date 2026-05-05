REPORT ZAI_260505_2151.

SELECT-OPTIONS s_budat FOR mkpf~budat NO-EXTENSION.
SELECT-OPTIONS s_werks FOR mseg~werks NO-EXTENSION.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr   TYPE mara-matnr,
        mtart   TYPE mara-mtart,
        matkl   TYPE mara-matkl,
        maktx   TYPE makt-maktx,
        status  TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.

    DATA lt_mov_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stk_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_union_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with material document postings (by date/plant)
    IF s_budat[] IS INITIAL AND s_werks[] IS INITIAL.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        INTO TABLE @lt_mov_matnr.
    ELSEIF s_budat[] IS INITIAL AND s_werks[] IS NOT INITIAL.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        WHERE mseg~werks IN @s_werks
        INTO TABLE @lt_mov_matnr.
    ELSEIF s_budat[] IS NOT INITIAL AND s_werks[] IS INITIAL.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
        INTO TABLE @lt_mov_matnr.
    ELSE.
      SELECT DISTINCT mseg~matnr
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks
        INTO TABLE @lt_mov_matnr.
    ENDIF.

    SORT lt_mov_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_mov_matnr.

    " 2) Materials with current stock not zero (by plant)
    IF s_werks[] IS INITIAL.
      SELECT DISTINCT mard~matnr
        FROM mard
        WHERE mard~labst <> 0
        INTO TABLE @lt_stk_matnr.
    ELSE.
      SELECT DISTINCT mard~matnr
        FROM mard
        WHERE mard~werks IN @s_werks
          AND mard~labst <> 0
        INTO TABLE @lt_stk_matnr.
    ENDIF.

    SORT lt_stk_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_stk_matnr.

    " 3) Union of both material lists
    lt_union_matnr = lt_mov_matnr.
    APPEND LINES OF lt_stk_matnr TO lt_union_matnr.
    SORT lt_union_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_union_matnr.

    IF lt_union_matnr IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Select master data and text for union set
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

    IF lt_result IS INITIAL.
      WRITE: / '자재 마스터에서 해당 자재를 찾을 수 없습니다.'.
      RETURN.
    ENDIF.

    " 5) Mark status: '재고만 있음' if no movement but has stock, else '입출고 있음'
    SORT lt_mov_matnr.
    SORT lt_stk_matnr.

    DATA ls_res TYPE ty_result.
    LOOP AT lt_result INTO ls_res.
      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.

      READ TABLE lt_mov_matnr WITH KEY table_line = ls_res-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stk_matnr WITH KEY table_line = ls_res-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_res-status = '입출고 있음'.
      ELSEIF lv_has_stk = abap_true.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = '입출고 있음'.
      ENDIF.

      MODIFY lt_result FROM ls_res TRANSPORTING status.
    ENDLOOP.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).