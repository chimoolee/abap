REPORT ZAI_260505_2223.

TABLES mara.

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

    DATA lt_result       TYPE ty_t_result.
    DATA lo_alv          TYPE REF TO cl_salv_table.

    DATA lt_mov_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr_all    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with movements in date/plant
    SELECT DISTINCT
           mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Materials with current stock <> 0 in selected plants
    SELECT DISTINCT
           mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    " 3) Union of materials
    lt_matnr_all = lt_mov_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_matnr_all.
    SORT lt_matnr_all.
    DELETE ADJACENT DUPLICATES FROM lt_matnr_all.

    " 4) Read master data/texts for union set
    IF lt_matnr_all IS NOT INITIAL.
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
        WHERE mara~matnr IN @lt_matnr_all.
    ENDIF.

    " Prepare lookup: sort movement/stock sets for fast READ
    SORT lt_mov_matnr.
    SORT lt_stock_matnr.

    " 5) Derive status text
    DATA lv_matnr TYPE mara-matnr.
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
      lv_matnr = <ls_res>-matnr.
      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.

      READ TABLE lt_mov_matnr WITH KEY table_line = lv_matnr
           TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_matnr WITH KEY table_line = lv_matnr
           TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        <ls_res>-status = |입출고 있음|.
      ELSEIF lv_has_stk = abap_true.
        <ls_res>-status = |재고만 있음|.
      ELSE.
        " Should not occur because of union; keep safe default
        <ls_res>-status = |해당 없음|.
      ENDIF.
    ENDLOOP.

    " 6) Show ALV
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        WRITE: / 'ALV 오류: ', lx->get_text( ).
    ENDTRY.

    IF lt_result IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
      WRITE: / '조건: 전기일, 플랜트. 입출고 또는 현재 재고<>0 자재 표시.'.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).