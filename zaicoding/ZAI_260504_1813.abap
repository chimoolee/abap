REPORT ZAI_260504_1813.

SELECT-OPTIONS s_budat FOR mkpf-budat OBLIGATORY.
SELECT-OPTIONS s_werks FOR mseg-werks OBLIGATORY.

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

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    DATA lt_mov_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_stk_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_sel_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_only  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lt_result1   TYPE ty_t_result.
    DATA lt_result2   TYPE ty_t_result.

    DATA lo_alv TYPE REF TO cl_salv_table.

    " 1) Materials with movement history (MSEG/MKPF) in date/plant
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

    " 2) Materials with current stock <> 0 in selected plants
    SELECT
      matnr,
      SUM( labst ) AS qty
      FROM mard
      WHERE werks IN @s_werks
      GROUP BY matnr
      HAVING SUM( labst ) <> 0
      INTO TABLE @lt_stock.

    " Extract stock material numbers
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      APPEND <ls_stk>-matnr TO lt_stk_matnr.
    ENDLOOP.

    " 3) Union set: movement OR stock
    INSERT LINES OF lt_mov_matnr INTO TABLE lt_sel_matnr.
    INSERT LINES OF lt_stk_matnr INTO TABLE lt_sel_matnr.

    " 4) Fetch material master + text for union set
    IF lt_sel_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_result1
        WHERE mara~matnr IN @lt_sel_matnr.
    ENDIF.

    " 5) Set status: movement vs stock-only
    LOOP AT lt_result1 ASSIGNING FIELD-SYMBOL(<ls_res1>).
      IF line_exists( lt_mov_matnr[ table_line = <ls_res1>-matnr ] ).
        <ls_res1>-status = '입출고 있음'.
      ELSEIF line_exists( lt_stk_matnr[ table_line = <ls_res1>-matnr ] ).
        <ls_res1>-status = '재고만 있음'.
      ENDIF.
    ENDLOOP.

    " 6) Materials with BOM (for FG/HALB) in selected plants, not yet shown
    SELECT DISTINCT
           mast~matnr
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      INTO TABLE @lt_bom_matnr
      WHERE mast~werks IN @s_werks
        AND mara~mtart IN ( 'FERT', 'HALB' )
        AND mast~matnr <> ''.

    " Subtract already selected materials
    LOOP AT lt_bom_matnr ASSIGNING FIELD-SYMBOL(<lv_bom_matnr>).
      IF NOT line_exists( lt_sel_matnr[ table_line = <lv_bom_matnr> ] ).
        APPEND <lv_bom_matnr> TO lt_bom_only.
      ENDIF.
    ENDLOOP.

    " 7) Fetch FG/HALB BOM-only materials and mark status
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
        INTO TABLE @lt_result2
        WHERE mara~matnr IN @lt_bom_only.
      LOOP AT lt_result2 ASSIGNING FIELD-SYMBOL(<ls_res2>).
        <ls_res2>-status = 'BOM 에 만 있음'.
      ENDLOOP.
    ENDIF.

    " 8) Display ALV page 1: movement/stock materials
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result1
    ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).

    " 9) Display ALV page 2: BOM-only FG/HALB
    IF lt_result2 IS NOT INITIAL.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_result2
      ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->display( ).
    ENDIF.

  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).