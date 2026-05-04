REPORT ZAI_260504_1556.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR mkpf-budat NO INTERVALS OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES ty_t_kv TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    TYPES: BEGIN OF ty_row,
             matnr    TYPE mara-matnr,
             mtart    TYPE mara-mtart,
             matkl    TYPE mara-matkl,
             meins    TYPE mara-meins,
             maktx    TYPE makt-maktx,
             stock    TYPE mard-labst,
             category TYPE char20,
           END OF ty_row.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    DATA lt_mov          TYPE ty_t_matnr.
    DATA lt_stock_agg    TYPE ty_t_stock.
    DATA lt_stock_mats   TYPE ty_t_matnr.
    DATA lt_all_mats     TYPE ty_t_matnr.
    DATA lt_bom_comp     TYPE ty_t_matnr.
    DATA lt_fert_bom     TYPE ty_t_matnr.
    DATA lt_out          TYPE ty_t_out.
    DATA ls_out          TYPE ty_row.
    DATA lv_fert         TYPE mara-mtart VALUE 'FERT'.

    " 1) Materials with movements in plant/date
    SELECT DISTINCT mseg~matnr
      FROM mseg AS mseg
      INNER JOIN mkpf AS mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mseg~werks = @p_werks
        AND mkpf~budat IN @s_budat
      INTO TABLE @lt_mov.

    " 2) Current stock > 0 by plant
    SELECT mard~matnr,
           SUM( mard~labst ) AS labst
      FROM mard AS mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @lt_stock_agg.

    lt_stock_mats = VALUE #( FOR s IN lt_stock_agg ( s-matnr ) ).

    " 3) Finished goods with BOM in plant
    SELECT DISTINCT mara~matnr
      FROM mast AS mast
      INNER JOIN mara AS mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND mara~mtart = @lv_fert
      INTO TABLE @lt_fert_bom.

    " 4) BOM component materials in plant
    SELECT DISTINCT stpo~idnrk
      FROM mast AS mast
      INNER JOIN stpo AS stpo
        ON stpo~stlnr = mast~stlnr
      WHERE mast~werks = @p_werks
      INTO TABLE @lt_bom_comp.

    " 5) Union of movement and stock materials
    lt_all_mats = lt_mov.
    LOOP AT lt_stock_mats INTO DATA(lv_matnr1).
      IF line_exists( lt_all_mats[ table_line = lv_matnr1 ] ) = abap_false.
        APPEND lv_matnr1 TO lt_all_mats.
      ENDIF.
    ENDLOOP.

    " 6) Add BOM-only components (no stock, no movement)
    LOOP AT lt_bom_comp INTO DATA(lv_bcomp).
      IF line_exists( lt_all_mats[ table_line = lv_bcomp ] ) = abap_false.
        APPEND lv_bcomp TO lt_all_mats.
      ENDIF.
    ENDLOOP.

    " 7) Fetch MARA/MM and MAKT for all materials
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    IF lt_all_mats IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             mara~meins
        FROM mara AS mara
        FOR ALL ENTRIES IN @lt_all_mats
        WHERE mara~matnr = @lt_all_mats-table_line
        INTO TABLE @lt_mara.

      SORT lt_mara BY matnr.
    ENDIF.

    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    IF lt_all_mats IS NOT INITIAL.
      SELECT makt~matnr,
             makt~maktx
        FROM makt AS makt
        FOR ALL ENTRIES IN @lt_all_mats
        WHERE makt~matnr = @lt_all_mats-table_line
          AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.
      SORT lt_makt BY matnr.
    ENDIF.

    " 8) Build output
    LOOP AT lt_all_mats INTO DATA(lv_matnr2).
      CLEAR ls_out.
      ls_out-matnr = lv_matnr2.

      READ TABLE lt_mara WITH KEY matnr = lv_matnr2 INTO DATA(ls_mara) BINARY SEARCH.
      IF sy-subrc = 0.
        ls_out-mtart = ls_mara-mtart.
        ls_out-matkl = ls_mara-matkl.
        ls_out-meins = ls_mara-meins.
      ENDIF.

      READ TABLE lt_makt WITH KEY matnr = lv_matnr2 INTO DATA(ls_makt) BINARY SEARCH.
      IF sy-subrc = 0.
        ls_out-maktx = ls_makt-maktx.
      ENDIF.

      READ TABLE lt_stock_agg WITH KEY matnr = lv_matnr2 INTO DATA(ls_stk).
      IF sy-subrc = 0.
        ls_out-stock = ls_stk-labst.
      ELSE.
        ls_out-stock = 0.
      ENDIF.

      DATA(lv_in_mov) = xsdbool( line_exists( lt_mov[ table_line = lv_matnr2 ] ) ).
      DATA(lv_in_stock) = xsdbool( ls_out-stock > 0 ).
      DATA(lv_in_fert_bom) = xsdbool( line_exists( lt_fert_bom[ table_line = lv_matnr2 ] ) ).
      DATA(lv_in_bom_comp) = xsdbool( line_exists( lt_bom_comp[ table_line = lv_matnr2 ] ) ).

      IF lv_in_fert_bom = abap_true.
        ls_out-category = 'FERT BOM'.
      ELSEIF lv_in_mov = abap_true AND lv_in_stock = abap_true.
        ls_out-category = '입출고/재고 있음'.
      ELSEIF lv_in_mov = abap_true.
        ls_out-category = '입출고 있음'.
      ELSEIF lv_in_stock = abap_true.
        ls_out-category = '재고만 있음'.
      ELSEIF lv_in_bom_comp = abap_true.
        ls_out-category = 'BOM만 있음'.
      ELSE.
        ls_out-category = '기타'.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    SORT lt_out BY category matnr.

    IF lt_out IS INITIAL.
      WRITE: / '조회 결과가 없습니다.'.
      RETURN.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).