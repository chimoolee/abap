REPORT ZAI_260504_1445.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_md,
             matnr TYPE mara-matnr,
             meins TYPE mara-meins,
             maktx TYPE makt-maktx,
           END OF ty_md.
    TYPES ty_t_md TYPE STANDARD TABLE OF ty_md WITH EMPTY KEY.

    TYPES: BEGIN OF ty_row,
             section    TYPE char20,
             matnr      TYPE mara-matnr,
             maktx      TYPE makt-maktx,
             meins      TYPE mara-meins,
             stock_qty  TYPE mard-labst,
             has_move   TYPE abap_bool,
             has_stock  TYPE abap_bool,
             status     TYPE char20,
           END OF ty_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    DATA lt_mov         TYPE ty_t_matnr.
    DATA lt_stock_agg   TYPE ty_t_stock.
    DATA lt_stock       TYPE ty_t_matnr.
    DATA lt_union       TYPE ty_t_matnr.
    DATA lt_md          TYPE ty_t_md.
    DATA lt_fert        TYPE ty_t_matnr.
    DATA lt_comp        TYPE ty_t_matnr.
    DATA lt_bom_all     TYPE ty_t_matnr.
    DATA lt_result      TYPE ty_t_row.

    DATA lo_alv TYPE REF TO cl_salv_table.

    " 1) Materials with movements in period/plant
    SELECT DISTINCT matdoc~matnr
      FROM matdoc
      INTO TABLE @lt_mov
      WHERE matdoc~werks = @p_werks
        AND matdoc~budat_mkpf IN @s_budat
        AND matdoc~matnr <> ''.

    " 2) Materials with current non-zero stock in plant (sum across SLoc)
    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
      INTO TABLE @lt_stock_agg
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0.

    " Build simple MATNR list from stock aggregation
    LOOP AT lt_stock_agg ASSIGNING FIELD-SYMBOL(<s>).
      APPEND <s>-matnr TO lt_stock.
    ENDLOOP.

    " 3) Union of materials (movements or stock)
    lt_union = lt_mov.
    APPEND LINES OF lt_stock TO lt_union.
    SORT lt_union BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_union COMPARING table_line.

    " 4) Master data texts for union set
    IF lt_union IS NOT INITIAL.
      SELECT mara~matnr,
             mara~meins,
             makt~maktx
        FROM mara
        INNER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_md
        WHERE mara~matnr IN @lt_union.
    ENDIF.

    " Helper hashed tables for quick lookup
    DATA lt_mov_h TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    DATA lt_stock_h TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_mov_h = lt_mov.
    lt_stock_h = lt_stock.

    DATA lt_stock_qty_h TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr.
    lt_stock_qty_h = lt_stock_agg.

    " 5) Build main section rows
    LOOP AT lt_md ASSIGNING FIELD-SYMBOL(<md>).
      DATA(lv_has_move) = COND abap_bool( WHEN line_exists( lt_mov_h[ table_line = <md>-matnr ] )
                                          THEN abap_true ELSE abap_false ).
      DATA(lv_has_stock) = COND abap_bool( WHEN line_exists( lt_stock_h[ table_line = <md>-matnr ] )
                                           THEN abap_true ELSE abap_false ).
      DATA(lv_qty) = VALUE mard-labst( ).
      READ TABLE lt_stock_qty_h ASSIGNING FIELD-SYMBOL(<q>) WITH KEY matnr = <md>-matnr.
      IF sy-subrc = 0.
        lv_qty = <q>-qty.
      ENDIF.

      DATA(lv_status) = VALUE char20(
         WHEN lv_has_move = abap_true AND lv_has_stock = abap_true THEN '입출고+재고'
         WHEN lv_has_move = abap_true AND lv_has_stock = abap_false THEN '입출고만 있음'
         WHEN lv_has_move = abap_false AND lv_has_stock = abap_true THEN '재고만 있음'
         ELSE '' ).

      APPEND VALUE ty_row(
        section   = '일반 자재'
        matnr     = <md>-matnr
        maktx     = <md>-maktx
        meins     = <md>-meins
        stock_qty = lv_qty
        has_move  = lv_has_move
        has_stock = lv_has_stock
        status    = lv_status ) TO lt_result.
    ENDLOOP.

    " 6) Finished goods with BOM (headers)
    SELECT DISTINCT mara~matnr
      FROM mara
      INNER JOIN mast
        ON mast~matnr = mara~matnr
       AND mast~werks = @p_werks
      INTO TABLE @lt_fert
      WHERE mara~mtart = 'FERT'.

    " 7) BOM components for those headers
    IF lt_fert IS NOT INITIAL.
      SELECT DISTINCT stpo~idnrk
        FROM stpo
        INNER JOIN mast
          ON mast~stlnr = stpo~stlnr
       INTO TABLE @lt_comp
       WHERE mast~matnr IN @lt_fert
         AND mast~werks = @p_werks.
    ENDIF.

    " 8) Build unified set for BOM section: headers + BOM-only components
    lt_bom_all = lt_fert.

    " Components that have neither movement nor stock
    LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<c_mat>).
      IF NOT line_exists( lt_union[ table_line = <c_mat> ] ).
        APPEND <c_mat> TO lt_bom_all.
      ENDIF.
    ENDLOOP.

    SORT lt_bom_all BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_bom_all COMPARING table_line.

    " 9) Read master data for BOM section
    DATA lt_bom_md TYPE ty_t_md.
    IF lt_bom_all IS NOT INITIAL.
      SELECT mara~matnr,
             mara~meins,
             makt~maktx
        FROM mara
        INNER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_bom_md
        WHERE mara~matnr IN @lt_bom_all.
    ENDIF.

    " 10) Append BOM section rows
    LOOP AT lt_bom_md ASSIGNING FIELD-SYMBOL(<bmd>).
      DATA(lv_b_has_move) = COND abap_bool( WHEN line_exists( lt_mov_h[ table_line = <bmd>-matnr ] )
                                            THEN abap_true ELSE abap_false ).
      DATA(lv_b_has_stock) = COND abap_bool( WHEN line_exists( lt_stock_h[ table_line = <bmd>-matnr ] )
                                             THEN abap_true ELSE abap_false ).
      DATA(lv_b_qty) = VALUE mard-labst( ).
      READ TABLE lt_stock_qty_h ASSIGNING FIELD-SYMBOL(<bq>) WITH KEY matnr = <bmd>-matnr.
      IF sy-subrc = 0.
        lv_b_qty = <bq>-qty.
      ENDIF.

      DATA(lv_b_status) = VALUE char20(
         WHEN lv_b_has_move = abap_true OR lv_b_has_stock = abap_true THEN ''
         ELSE 'BOM 만 있음' ).

      APPEND VALUE ty_row(
        section   = 'BOM/완제품'
        matnr     = <bmd>-matnr
        maktx     = <bmd>-maktx
        meins     = <bmd>-meins
        stock_qty = lv_b_qty
        has_move  = lv_b_has_move
        has_stock = lv_b_has_stock
        status    = lv_b_status ) TO lt_result.
    ENDLOOP.

    " 11) Display ALV
    IF lt_result IS INITIAL.
      " Ensure at least an empty row to open ALV
      APPEND VALUE ty_row( section = '일반 자재' ) TO lt_result.
    ENDIF.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
        " Fallback simple list if SALV fails
        LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<r>).
          WRITE: / <r>-section, <r>-matnr, <r>-maktx, <r>-meins, <r>-stock_qty,
                 <r>-has_move, <r>-has_stock, <r>-status.
        ENDLOOP.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).