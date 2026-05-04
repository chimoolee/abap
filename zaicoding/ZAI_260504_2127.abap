REPORT ZAI_260504_2127.

TABLES mara.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

TYPES:
  BEGIN OF ty_move,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
  END OF ty_move,
  ty_t_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_stock,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
    labst TYPE mard-labst,
  END OF ty_stock,
  ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_attr,
    matnr TYPE mara-matnr,
    mtart TYPE mara-mtart,
    matkl TYPE mara-matkl,
    maktx TYPE makt-maktx,
  END OF ty_attr,
  ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_pair,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
  END OF ty_pair,
  ty_t_pair TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY.

TYPES:
  BEGIN OF ty_result,
    matnr     TYPE mara-matnr,
    werks     TYPE mseg-werks,
    mtart     TYPE mara-mtart,
    matkl     TYPE mara-matkl,
    maktx     TYPE makt-maktx,
    stock_qty TYPE mard-labst,
    status    TYPE char20,
  END OF ty_result,
  ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_move      TYPE ty_t_move.
    DATA lt_stock_raw TYPE ty_t_stock.
    DATA lt_stock_sum TYPE ty_t_stock.
    DATA lt_union     TYPE ty_t_pair.
    DATA lt_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_attr      TYPE ty_t_attr.
    DATA lt_result    TYPE ty_t_result.

    DATA ls_move      TYPE ty_move.
    DATA ls_stock_r   TYPE ty_stock.
    DATA ls_stock_s   TYPE ty_stock.
    DATA ls_pair      TYPE ty_pair.
    DATA ls_attr      TYPE ty_attr.
    DATA ls_result    TYPE ty_result.

    DATA lo_alv TYPE REF TO cl_salv_table.

* Materials with goods movements in selected period and plant
    SELECT DISTINCT
      m~matnr,
      m~werks
      FROM mseg AS m
      INNER JOIN mkpf AS k
        ON k~mblnr = m~mblnr
       AND k~mjahr = m~mjahr
      INTO TABLE @lt_move
      WHERE k~budat IN @s_budat
        AND m~werks IN @s_werks
        AND m~matnr IS NOT INITIAL.

* Current stock (> 0) by MATNR+WERKS
    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @lt_stock_raw
      WHERE mard~werks IN @s_werks
        AND mard~labst > 0
        AND mard~matnr IS NOT INITIAL.

* Aggregate stock by MATNR+WERKS
    SORT lt_stock_raw BY matnr werks.
    CLEAR ls_stock_s.
    LOOP AT lt_stock_raw INTO ls_stock_r.
      IF ls_stock_s-matnr IS INITIAL
         OR ls_stock_s-matnr <> ls_stock_r-matnr
         OR ls_stock_s-werks <> ls_stock_r-werks.
        IF ls_stock_s-matnr IS NOT INITIAL.
          APPEND ls_stock_s TO lt_stock_sum.
        ENDIF.
        MOVE-CORRESPONDING ls_stock_r TO ls_stock_s.
      ELSE.
        ls_stock_s-labst = ls_stock_s-labst + ls_stock_r-labst.
      ENDIF.
    ENDLOOP.
    IF ls_stock_s-matnr IS NOT INITIAL.
      APPEND ls_stock_s TO lt_stock_sum.
    ENDIF.

* Build union of pairs (movement + stock)
    LOOP AT lt_move INTO ls_move.
      ls_pair-matnr = ls_move-matnr.
      ls_pair-werks = ls_move-werks.
      APPEND ls_pair TO lt_union.
    ENDLOOP.
    LOOP AT lt_stock_sum INTO ls_stock_s.
      ls_pair-matnr = ls_stock_s-matnr.
      ls_pair-werks = ls_stock_s-werks.
      APPEND ls_pair TO lt_union.
    ENDLOOP.
    SORT lt_union BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_union COMPARING matnr werks.

* Prepare material list for attribute/text read
    DATA lv_matnr TYPE mara-matnr.
    LOOP AT lt_union INTO ls_pair.
      lv_matnr = ls_pair-matnr.
      APPEND lv_matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

* Read material attributes and text
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_attr
      WHERE mara~matnr IN @lt_matnr.

    SORT lt_attr BY matnr.
    SORT lt_move BY matnr werks.
    SORT lt_stock_sum BY matnr werks.

* Compose result
    LOOP AT lt_union INTO ls_pair.
      CLEAR ls_result.
      ls_result-matnr = ls_pair-matnr.
      ls_result-werks = ls_pair-werks.

      READ TABLE lt_attr INTO ls_attr WITH KEY matnr = ls_pair-matnr
           BINARY SEARCH.
      IF sy-subrc = 0.
        ls_result-mtart = ls_attr-mtart.
        ls_result-matkl = ls_attr-matkl.
        ls_result-maktx = ls_attr-maktx.
      ENDIF.

      DATA(lv_has_move) = abap_false.
      READ TABLE lt_move WITH KEY matnr = ls_pair-matnr
                                   werks = ls_pair-werks
                                   TRANSPORTING NO FIELDS
                                   BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_move = abap_true.
      ENDIF.

      DATA(lv_stock_qty) = CONV mard-labst( 0 ).
      READ TABLE lt_stock_sum INTO ls_stock_s
           WITH KEY matnr = ls_pair-matnr
                    werks = ls_pair-werks
           BINARY SEARCH.
      IF sy-subrc = 0.
        lv_stock_qty = ls_stock_s-labst.
      ENDIF.

      ls_result-stock_qty = lv_stock_qty.

      IF lv_stock_qty > 0 AND lv_has_move = abap_false.
        ls_result-status = '재고만 있음'.
      ELSEIF lv_has_move = abap_true.
        ls_result-status = '입출고 있음'.
      ELSE.
        ls_result-status = ''.
      ENDIF.

      APPEND ls_result TO lt_result.
    ENDLOOP.

* Display ALV
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result
    ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).