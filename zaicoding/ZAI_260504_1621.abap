REPORT ZAI_260504_1621.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_row,
             category  TYPE char20,
             matnr     TYPE mara-matnr,
             maktx     TYPE makt-maktx,
             werks     TYPE werks_d,
             stock_qty TYPE mard-labst,
             fg_bom    TYPE abap_bool,
           END OF ty_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    DATA lt_mov_mat     TYPE ty_t_matnr.
    DATA lt_stock       TYPE ty_t_stock.
    DATA lt_stock_mat   TYPE ty_t_matnr.
    DATA lt_bom_fg      TYPE ty_t_matnr.
    DATA lt_bom_comp    TYPE ty_t_matnr.
    DATA lt_all_mat     TYPE ty_t_matnr.
    DATA lt_result      TYPE ty_t_row.

    DATA lo_alv TYPE REF TO cl_salv_table.

*   1) Materials with movements in period for plant
    SELECT DISTINCT mseg~matnr
      FROM mseg AS mseg
      INNER JOIN mkpf AS mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
     WHERE mseg~werks = @p_werks
       AND mkpf~budat IN @s_budat
      INTO TABLE @lt_mov_mat.

*   2) Materials with current stock <> 0 in plant
    SELECT mard~matnr, mard~labst
      FROM mard AS mard
     WHERE mard~werks = @p_werks
       AND mard~labst <> 0
      INTO TABLE @lt_stock.

*   Derive stock material list
    DATA ls_stock LIKE LINE OF lt_stock.
    LOOP AT lt_stock INTO ls_stock.
      APPEND ls_stock-matnr TO lt_stock_mat.
    ENDLOOP.

*   3) Finished goods with BOM in plant
    SELECT DISTINCT mast~matnr
      FROM mast AS mast
      INNER JOIN mara AS mara
        ON mara~matnr = mast~matnr
     WHERE mast~werks = @p_werks
       AND mara~mtart = 'FERT'
      INTO TABLE @lt_bom_fg.

*   4) BOM component materials for BOMs assigned in plant
    SELECT DISTINCT stpo~idnrk
      FROM mast AS mast
      INNER JOIN stpo AS stpo
        ON stpo~stlnr = mast~stlnr
     WHERE mast~werks = @p_werks
       AND stpo~idnrk IS NOT NULL
       AND stpo~idnrk <> ''
      INTO TABLE @lt_bom_comp.

*   Build sets for fast lookup
    DATA lt_mov_set     TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_stock_set   TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_bom_fg_set  TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_bom_cmp_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.

    lt_mov_set     = lt_mov_mat.
    lt_stock_set   = lt_stock_mat.
    lt_bom_fg_set  = lt_bom_fg.
    lt_bom_cmp_set = lt_bom_comp.

*   Result: 1) Movement exists
    DATA ls_row TYPE ty_row.
    DATA lv_stock_qty TYPE mard-labst.
    DATA lv_matnr TYPE mara-matnr.

    LOOP AT lt_mov_mat INTO lv_matnr.
      CLEAR: ls_row, lv_stock_qty.
      ls_row-matnr = lv_matnr.
      ls_row-werks = p_werks.
      ls_row-category = '입출고실적있음'.
      READ TABLE lt_bom_fg_set WITH TABLE KEY table_line = lv_matnr
           TRANSPORTING NO FIELDS.
      ls_row-fg_bom = xsdbool( sy-subrc = 0 ).
      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        lv_stock_qty = ls_stock-labst.
      ENDIF.
      ls_row-stock_qty = lv_stock_qty.
      APPEND ls_row TO lt_result.
    ENDLOOP.

*   2) Stock only (no movement)
    LOOP AT lt_stock INTO ls_stock.
      READ TABLE lt_mov_set WITH TABLE KEY table_line = ls_stock-matnr
           TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        CLEAR ls_row.
        ls_row-matnr = ls_stock-matnr.
        ls_row-werks = p_werks.
        ls_row-category = '재고만있음'.
        ls_row-stock_qty = ls_stock-labst.
        READ TABLE lt_bom_fg_set WITH TABLE KEY table_line = ls_stock-matnr
             TRANSPORTING NO FIELDS.
        ls_row-fg_bom = xsdbool( sy-subrc = 0 ).
        APPEND ls_row TO lt_result.
      ENDIF.
    ENDLOOP.

*   3) BOM only components (no movement, no stock)
    LOOP AT lt_bom_comp INTO lv_matnr.
      READ TABLE lt_mov_set WITH TABLE KEY table_line = lv_matnr
           TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      READ TABLE lt_stock_set WITH TABLE KEY table_line = lv_matnr
           TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      CLEAR ls_row.
      ls_row-matnr = lv_matnr.
      ls_row-werks = p_werks.
      ls_row-category = 'BOM에만있음'.
      ls_row-stock_qty = 0.
      ls_row-fg_bom = abap_false.
      APPEND ls_row TO lt_result.
    ENDLOOP.

*   Collect all materials for text fetch
    LOOP AT lt_result INTO ls_row.
      APPEND ls_row-matnr TO lt_all_mat.
    ENDLOOP.
    SORT lt_all_mat.
    DELETE ADJACENT DUPLICATES FROM lt_all_mat.

*   Build range for MATNR to avoid IN row type issues
    DATA lr_matnr TYPE RANGE OF mara-matnr.
    DATA ls_r TYPE LINE OF lr_matnr.
    LOOP AT lt_all_mat INTO lv_matnr.
      CLEAR ls_r.
      ls_r-sign = 'I'.
      ls_r-option = 'EQ'.
      ls_r-low = lv_matnr.
      APPEND ls_r TO lr_matnr.
    ENDLOOP.

*   Fetch material descriptions
    TYPES: BEGIN OF ty_makt,
             matnr TYPE mara-matnr,
             maktx TYPE makt-maktx,
           END OF ty_makt.
    DATA lt_makt TYPE STANDARD TABLE OF ty_makt WITH EMPTY KEY.
    DATA ls_makt TYPE ty_makt.

    IF lr_matnr IS NOT INITIAL.
      SELECT makt~matnr, makt~maktx
        FROM makt AS makt
       WHERE makt~matnr IN @lr_matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.
    ENDIF.

*   Map texts
    SORT lt_makt BY matnr.
    LOOP AT lt_result INTO ls_row.
      READ TABLE lt_makt INTO ls_makt WITH KEY matnr = ls_row-matnr
           BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-maktx = ls_makt-maktx.
      ENDIF.
      MODIFY lt_result FROM ls_row.
    ENDLOOP.

*   Display with SALV
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      '자재 현황: 입출고실적/재고/BOM 구분 - 플랜트 ' && p_werks ).

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).