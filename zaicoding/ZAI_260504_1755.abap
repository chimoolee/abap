REPORT ZAI_260504_1755.

SELECT-OPTIONS s_budat FOR mkpf-budat NO-EXTENSION.
SELECT-OPTIONS s_werks FOR mseg-werks NO-EXTENSION.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr       TYPE mara-matnr,
        mtart       TYPE mara-mtart,
        matkl       TYPE mara-matkl,
        maktx       TYPE makt-maktx,
        status_text TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result       TYPE ty_t_result.
    DATA lt_result_bom   TYPE ty_t_result.

    DATA lt_mov_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_only     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lt_details      TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.
    DATA lt_details_bom  TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    " 1) Materials with movements (MKPF/MSEG) in selected date and plant
    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr <> ''.

    " 2) Materials with current stock (MARD) not zero for selected plant
    SELECT
      mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~matnr <> ''
        AND mard~labst <> 0.

    " Union: all materials to display on first page (movements or non-zero stock)
    APPEND LINES OF lt_mov_matnr   TO lt_all_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_all_matnr.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    " Read master/texts for first page materials
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
        INTO TABLE @lt_details
        WHERE mara~matnr IN @lt_all_matnr.
    ENDIF.

    " Prepare lookup by sorting lists
    SORT lt_mov_matnr.
    SORT lt_stock_matnr.

    " Build first page result with status
    DATA ls_det TYPE ty_result.
    LOOP AT lt_details INTO ls_det.
      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.

      READ TABLE lt_mov_matnr WITH KEY table_line = ls_det-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_matnr WITH KEY table_line = ls_det-matnr
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_det-status_text = '입출고 실적 있음'.
      ELSEIF lv_has_stk = abap_true.
        ls_det-status_text = '재고만 있음'.
      ELSE.
        ls_det-status_text = ''.
      ENDIF.

      APPEND ls_det TO lt_result.
    ENDLOOP.

    " 3) BOM-only materials (FERT/HALB) for selected plants not in first page
    SELECT DISTINCT
      mara~matnr
      FROM stko
      INNER JOIN stpo
        ON stpo~stlnr = stko~stlnr
      INNER JOIN mara
        ON mara~matnr = stko~matnr
      INTO TABLE @lt_bom_matnr
      WHERE stko~werks IN @s_werks
        AND mara~mtart IN ('FERT','HALB')
        AND mara~matnr <> ''.

    SORT lt_bom_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_bom_matnr.

    " Exclude materials already in first page list
    SORT lt_all_matnr.
    DATA lv_mat TYPE mara-matnr.
    LOOP AT lt_bom_matnr INTO lv_mat.
      READ TABLE lt_all_matnr WITH KEY table_line = lv_mat
        TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc <> 0.
        APPEND lv_mat TO lt_bom_only.
      ENDIF.
    ENDLOOP.

    " Read master/texts for BOM-only materials
    IF lt_bom_only IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_details_bom
        WHERE mara~matnr IN @lt_bom_only.
    ENDIF.

    LOOP AT lt_details_bom INTO ls_det.
      ls_det-status_text = 'BOM 에 만 있음'.
      APPEND ls_det TO lt_result_bom.
    ENDLOOP.

    " Display ALV: first page (movements/stock)
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->display( ).

    " Display ALV: second page (BOM-only)
    IF lt_result_bom IS NOT INITIAL.
      NEW-PAGE.
      CLEAR lo_alv.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_result_bom ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).