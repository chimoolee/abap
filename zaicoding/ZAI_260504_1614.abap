REPORT ZAI_260504_1614.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR mkpf-budat NO INTERVALS OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: ty_row TYPE STRUCTURE OF (
             matnr TYPE mara-matnr
             werks TYPE werks_d
             mtart TYPE mara-mtart
             maktx TYPE makt-maktx
             labst TYPE mard-labst
             category TYPE char20
             parent TYPE mara-matnr
           ).
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mast,
             matnr TYPE mara-matnr,
             stlnr TYPE stpo-stlnr,
             stlal TYPE stpo-stlal,
           END OF ty_mast.
    TYPES ty_t_mast TYPE STANDARD TABLE OF ty_mast WITH EMPTY KEY.

    TYPES: BEGIN OF ty_comp,
             parent TYPE mara-matnr,
             idnrk  TYPE mara-matnr,
           END OF ty_comp.
    TYPES ty_t_comp TYPE STANDARD TABLE OF ty_comp WITH EMPTY KEY.

    DATA lt_rows TYPE ty_t_row.
    DATA ls_row  TYPE ty_row.

    DATA lt_mov TYPE ty_t_matnr.
    DATA lt_stock TYPE ty_t_stock.
    DATA lt_bom_mast TYPE ty_t_mast.
    DATA lt_comp_raw TYPE STANDARD TABLE OF stpo WITH EMPTY KEY.
    DATA lt_comp TYPE ty_t_comp.

    DATA lt_all_matnr TYPE ty_t_matnr.
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.

    DATA ls_stock TYPE ty_stock.
    DATA lv_found TYPE abap_bool.

    DATA lo_alv TYPE REF TO cl_salv_table.

    " 1) Materials with movements in period at plant
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mseg~werks = @p_werks
        AND mkpf~budat IN @s_budat
      INTO TABLE @lt_mov.

    " 2) Materials with current stock <> 0 at plant
    SELECT mard~matnr,
           mard~labst
      FROM mard
      WHERE mard~werks = @p_werks
        AND mard~labst <> 0
      INTO TABLE @lt_stock.

    " 3) BOM Finished goods (FERT) and their components for plant
    SELECT mast~matnr,
           mast~stlnr,
           mast~stlal
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_bom_mast.

    IF lt_bom_mast IS NOT INITIAL.
      SELECT stpo~stlnr,
             stpo~stlal,
             stpo~idnrk
        FROM stpo
        FOR ALL ENTRIES IN @lt_bom_mast
        WHERE stpo~stlnr = @lt_bom_mast-stlnr
          AND stpo~stlal = @lt_bom_mast-stlal
        INTO TABLE @lt_comp_raw.
      IF sy-subrc = 0.
        SORT lt_comp_raw BY stlnr stlal idnrk.
      ENDIF.
    ENDIF.

    " Map components to parents
    LOOP AT lt_bom_mast INTO DATA(ls_mast).
      READ TABLE lt_comp_raw ASSIGNING FIELD-SYMBOL(<ls_cr>)
           WITH KEY stlnr = ls_mast-stlnr
                    stlal = ls_mast-stlal
           BINARY SEARCH.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(lv_tabix) = sy-tabix.
      WHILE lv_tabix <= lines( lt_comp_raw ).
        READ TABLE lt_comp_raw INDEX lv_tabix ASSIGNING <ls_cr>.
        IF sy-subrc <> 0.
          EXIT.
        ENDIF.
        IF <ls_cr>-stlnr <> ls_mast-stlnr OR <ls_cr>-stlal <> ls_mast-stlal.
          EXIT.
        ENDIF.
        APPEND VALUE ty_comp( parent = ls_mast-matnr idnrk = <ls_cr>-idnrk ) TO lt_comp.
        lv_tabix = lv_tabix + 1.
      ENDWHILE.
    ENDLOOP.

    " Collect all material numbers involved
    lt_all_matnr = lt_mov.
    LOOP AT lt_stock INTO ls_stock.
      APPEND ls_stock-matnr TO lt_all_matnr.
    ENDLOOP.
    LOOP AT lt_bom_mast INTO ls_mast.
      APPEND ls_mast-matnr TO lt_all_matnr.
    ENDLOOP.
    LOOP AT lt_comp INTO DATA(ls_comp).
      APPEND ls_comp-idnrk TO lt_all_matnr.
    ENDLOOP.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    " Get material types
    IF lt_all_matnr IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart
        FROM mara
        FOR ALL ENTRIES IN @lt_all_matnr
        WHERE mara~matnr = @lt_all_matnr-table_line
        INTO TABLE @lt_mara.
      SORT lt_mara BY matnr.
      " Get texts
      SELECT makt~matnr,
             makt~maktx
        FROM makt
        FOR ALL ENTRIES IN @lt_all_matnr
        WHERE makt~matnr = @lt_all_matnr-table_line
          AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.
      SORT lt_makt BY matnr.
    ENDIF.

    " Helper forms as inline READs
    " A) Movement rows
    LOOP AT lt_mov INTO DATA(lv_matnr_mov).
      CLEAR ls_row.
      ls_row-matnr = lv_matnr_mov.
      ls_row-werks = p_werks.
      ls_row-category = '입출고있음'.
      READ TABLE lt_mara INTO DATA(ls_mara) WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-mtart = ls_mara-mtart.
      ENDIF.
      READ TABLE lt_makt INTO DATA(ls_maktx) WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-maktx = ls_maktx-maktx.
      ENDIF.
      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_row-matnr.
      IF sy-subrc = 0.
        ls_row-labst = ls_stock-labst.
      ENDIF.
      APPEND ls_row TO lt_rows.
    ENDLOOP.

    " B) Stock-only rows
    LOOP AT lt_stock INTO ls_stock.
      READ TABLE lt_mov WITH KEY table_line = ls_stock-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      CLEAR ls_row.
      ls_row-matnr = ls_stock-matnr.
      ls_row-werks = p_werks.
      ls_row-category = '재고만있음'.
      ls_row-labst = ls_stock-labst.
      READ TABLE lt_mara INTO ls_mara WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-mtart = ls_mara-mtart.
      ENDIF.
      READ TABLE lt_makt INTO ls_maktx WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-maktx = ls_maktx-maktx.
      ENDIF.
      APPEND ls_row TO lt_rows.
    ENDLOOP.

    " C) BOM Finished goods section
    LOOP AT lt_bom_mast INTO ls_mast.
      CLEAR ls_row.
      ls_row-matnr = ls_mast-matnr.
      ls_row-werks = p_werks.
      ls_row-category = 'BOM-완제품'.
      READ TABLE lt_mara INTO ls_mara WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-mtart = ls_mara-mtart.
      ENDIF.
      READ TABLE lt_makt INTO ls_maktx WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-maktx = ls_maktx-maktx.
      ENDIF.
      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_row-matnr.
      IF sy-subrc = 0.
        ls_row-labst = ls_stock-labst.
      ENDIF.
      APPEND ls_row TO lt_rows.
    ENDLOOP.

    " D) BOM Components section
    LOOP AT lt_comp INTO ls_comp.
      CLEAR ls_row.
      ls_row-matnr = ls_comp-idnrk.
      ls_row-parent = ls_comp-parent.
      ls_row-werks = p_werks.
      READ TABLE lt_mov WITH KEY table_line = ls_row-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls_row-category = 'BOM-요소'.
      ELSE.
        READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_row-matnr.
        IF sy-subrc = 0 AND ls_stock-labst <> 0.
          ls_row-category = 'BOM-요소'.
          ls_row-labst = ls_stock-labst.
        ELSE.
          ls_row-category = 'BOM에만있음'.
        ENDIF.
      ENDIF.
      IF ls_row-category = 'BOM-요소' AND ls_row-labst IS INITIAL.
        READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_row-matnr.
        IF sy-subrc = 0.
          ls_row-labst = ls_stock-labst.
        ENDIF.
      ENDIF.
      READ TABLE lt_mara INTO ls_mara WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-mtart = ls_mara-mtart.
      ENDIF.
      READ TABLE lt_makt INTO ls_maktx WITH KEY matnr = ls_row-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_row-maktx = ls_maktx-maktx.
      ENDIF.
      APPEND ls_row TO lt_rows.
    ENDLOOP.

    " Display ALV
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_rows ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).