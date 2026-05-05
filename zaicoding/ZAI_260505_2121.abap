REPORT ZAI_260505_2121.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,
  s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mov_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with material documents (movements) in selection
    SELECT DISTINCT
           ms~matnr
      FROM mseg AS ms
      INNER JOIN mkpf AS mk
        ON mk~mblnr = ms~mblnr
       AND mk~mjahr = ms~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mk~budat IN @s_budat
        AND ms~werks IN @s_werks.

    " 2) Materials with current stock not zero in selected plants
    SELECT DISTINCT
           md~matnr
      FROM mard AS md
      INTO TABLE @lt_stock_matnr
      WHERE md~werks IN @s_werks
        AND md~labst > 0.

    " 3) Union lists into lt_all_matnr
    IF lt_mov_matnr IS NOT INITIAL.
      APPEND LINES OF lt_mov_matnr TO lt_all_matnr.
    ENDIF.
    IF lt_stock_matnr IS NOT INITIAL.
      APPEND LINES OF lt_stock_matnr TO lt_all_matnr.
    ENDIF.

    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    TYPES:
      BEGIN OF ty_result,
        matnr       TYPE mara-matnr,
        mtart       TYPE mara-mtart,
        matkl       TYPE mara-matkl,
        maktx       TYPE makt-maktx,
        status_text TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.

    IF lt_all_matnr IS INITIAL.
      " No data meets criteria
      DATA(ls_empty) = VALUE ty_result(
        matnr       = ''
        mtart       = ''
        matkl       = ''
        maktx       = ''
        status_text = '선택 조건에 해당 없음' ).
      APPEND ls_empty TO lt_result.
    ELSE.
      " 4) Read material master/texts for the union set
      SELECT
        ma~matnr,
        ma~mtart,
        ma~matkl,
        tx~maktx
        FROM mara AS ma
        LEFT JOIN makt AS tx
          ON tx~matnr = ma~matnr
         AND tx~spras = @sy-langu
        INTO TABLE @lt_result
        FOR ALL ENTRIES IN @lt_all_matnr
        WHERE ma~matnr = @lt_all_matnr-table_line.

      " Prepare for membership checks
      SORT lt_mov_matnr.
      SORT lt_stock_matnr.

      " 5) Derive status text
      LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
        DATA(lv_has_mov) = abap_false.
        DATA(lv_has_stk) = abap_false.

        READ TABLE lt_mov_matnr WITH KEY table_line = <ls_res>-matnr
             TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc = 0.
          lv_has_mov = abap_true.
        ENDIF.

        READ TABLE lt_stock_matnr WITH KEY table_line = <ls_res>-matnr
             TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc = 0.
          lv_has_stk = abap_true.
        ENDIF.

        IF lv_has_mov = abap_true.
          <ls_res>-status_text = '입출고 있음'.
        ELSEIF lv_has_stk = abap_true.
          <ls_res>-status_text = '재고만 있음'.
        ELSE.
          " Should not happen due to union, but keep safe
          <ls_res>-status_text = '상태 불명'.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        WRITE: / 'ALV 표시 중 오류: ', lx_msg->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).