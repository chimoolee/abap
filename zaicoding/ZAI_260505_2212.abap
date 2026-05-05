REPORT ZAI_260505_2212.

TABLES mara.

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
        matnr     TYPE mara-matnr,
        mtart     TYPE mara-mtart,
        matkl     TYPE mara-matkl,
        maktx     TYPE makt-maktx,
        stock_qty TYPE mard-labst,
        last_budat TYPE mkpf-budat,
        status    TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.

    DATA lt_move_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock_sum,
        matnr TYPE mara-matnr,
        qty   TYPE mard-labst,
      END OF ty_stock_sum,
      ty_t_stock_sum TYPE STANDARD TABLE OF ty_stock_sum WITH EMPTY KEY.

    DATA lt_stock_sum TYPE ty_t_stock_sum.

    TYPES:
      BEGIN OF ty_last_move,
        matnr TYPE mara-matnr,
        budat TYPE mkpf-budat,
      END OF ty_last_move,
      ty_t_last_move TYPE STANDARD TABLE OF ty_last_move WITH EMPTY KEY.

    DATA lt_last_move TYPE ty_t_last_move.

    " 1) Materials with movements in date/plant
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Current stock by material in selected plants (non-zero)
    SELECT matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE werks IN @s_werks
        AND labst <> 0.

    " 3) Union of materials
    IF lt_move_matnr IS NOT INITIAL.
      APPEND LINES OF lt_move_matnr TO lt_all_matnr.
    ENDIF.
    IF lt_stock_matnr IS NOT INITIAL.
      APPEND LINES OF lt_stock_matnr TO lt_all_matnr.
    ENDIF.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    IF lt_all_matnr IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Stock sum per material for selected plants
    SELECT matnr,
           SUM( labst ) AS qty
      FROM mard
      INTO TABLE @lt_stock_sum
      WHERE werks IN @s_werks
      GROUP BY matnr
      HAVING SUM( labst ) <> 0.

    " 5) Last movement date per material in range
    SELECT mseg~matnr,
           MAX( mkpf~budat ) AS budat
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_last_move
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
      GROUP BY mseg~matnr.

    " 6) Basic material info + text for union list
    SELECT mara~matnr,
           mara~mtart,
           mara~matkl,
           makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_result
      WHERE mara~matnr IN @lt_all_matnr.

    " 7) Enrich with stock, last date, status
    DATA ls_res TYPE ty_result.
    LOOP AT lt_result INTO ls_res.
      DATA(lv_stock) = CONV mard-labst( 0 ).
      READ TABLE lt_stock_sum ASSIGNING FIELD-SYMBOL(<ls_stock>)
        WITH KEY matnr = ls_res-matnr.
      IF sy-subrc = 0.
        lv_stock = <ls_stock>-qty.
      ENDIF.

      DATA(lv_has_move) = abap_false.
      DATA(lv_last) = CONV mkpf-budat( '00000000' ).
      READ TABLE lt_last_move ASSIGNING FIELD-SYMBOL(<ls_last>)
        WITH KEY matnr = ls_res-matnr.
      IF sy-subrc = 0.
        lv_has_move = abap_true.
        lv_last = <ls_last>-budat.
      ENDIF.

      ls_res-stock_qty = lv_stock.
      ls_res-last_budat = lv_last.

      IF lv_has_move = abap_true AND lv_stock <> 0.
        ls_res-status = '입출고+재고'.
      ELSEIF lv_has_move = abap_true.
        ls_res-status = '입출고 실적 있음'.
      ELSEIF lv_stock <> 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = '해당없음'.
      ENDIF.

      MODIFY lt_result FROM ls_res.
    ENDLOOP.

    " 8) Display with SALV
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