REPORT ZAI_260504_1606.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_date_f TYPE sy-datum.
PARAMETERS p_date_t TYPE sy-datum.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES ty_t_stock  TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mara,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             matkl TYPE mara-matkl,
             meins TYPE mara-meins,
           END OF ty_mara.
    TYPES ty_t_mara TYPE STANDARD TABLE OF ty_mara WITH EMPTY KEY.

    TYPES: BEGIN OF ty_makt,
             matnr TYPE makt-matnr,
             maktx TYPE makt-maktx,
           END OF ty_makt.
    TYPES ty_t_makt TYPE STANDARD TABLE OF ty_makt WITH EMPTY KEY.

    TYPES: BEGIN OF ty_out,
             section   TYPE char10,
             matnr     TYPE mara-matnr,
             maktx     TYPE makt-maktx,
             mtart     TYPE mara-mtart,
             matkl     TYPE mara-matkl,
             meins     TYPE mara-meins,
             werks     TYPE mseg-werks,
             stock_qty TYPE mard-labst,
             moved     TYPE abap_bool,
             status    TYPE char20,
           END OF ty_out.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    DATA lt_mov_mats  TYPE ty_t_matnr.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_stock_mats TYPE ty_t_matnr.
    DATA lt_bom_fert  TYPE ty_t_matnr.
    DATA lt_bom_comp  TYPE ty_t_matnr.
    DATA lt_main      TYPE ty_t_matnr.
    DATA lt_exist     TYPE ty_t_matnr.
    DATA lt_all       TYPE ty_t_matnr.
    DATA lt_mara      TYPE ty_t_mara.
    DATA lt_makt      TYPE ty_t_makt.
    DATA lt_out       TYPE ty_t_out.

    DATA ls_stock TYPE ty_stock.
    DATA lv_matnr TYPE mara-matnr.
    DATA ls_mara  TYPE ty_mara.
    DATA ls_makt  TYPE ty_makt.
    DATA ls_out   TYPE ty_out.

    " Movements in date range
    IF p_date_f IS INITIAL OR p_date_t IS INITIAL.
      " If dates not provided, no date restriction -> no movement selection
    ELSE.
      SELECT DISTINCT mseg~matnr
        FROM mkpf AS mkpf
        INNER JOIN mseg AS mseg
          ON mseg~mblnr = mkpf~mblnr
         AND mseg~mjahr = mkpf~mjahr
        WHERE mseg~werks = @p_werks
          AND mkpf~budat BETWEEN @p_date_f AND @p_date_t
        INTO TABLE @lt_mov_mats.
    ENDIF.

    " Current stock not zero by material in plant
    SELECT mard~matnr, SUM( mard~labst ) AS qty
      FROM mard AS mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " Extract stock material list
    LOOP AT lt_stock INTO ls_stock.
      APPEND ls_stock-matnr TO lt_stock_mats.
    ENDLOOP.

    " BOM: finished goods having BOM in plant
    SELECT DISTINCT mast~matnr
      FROM mast AS mast
      INNER JOIN mara AS mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_bom_fert.

    " BOM components in plant
    SELECT DISTINCT stpo~idnrk
      FROM mast AS mast
      INNER JOIN stpo AS stpo
        ON stpo~stlnr = mast~stlnr
      WHERE mast~werks = @p_werks
      INTO TABLE @lt_bom_comp.

    " Main set: union of movement and stock, excluding BOM-finished
    lt_main = lt_mov_mats.
    APPEND LINES OF lt_stock_mats TO lt_main.
    SORT lt_main.
    DELETE ADJACENT DUPLICATES FROM lt_main.
    SORT lt_bom_fert.
    DELETE ADJACENT DUPLICATES FROM lt_bom_fert.
    DELETE lt_main WHERE table_line IN lt_bom_fert.

    " Existing set (movement or stock)
    lt_exist = lt_mov_mats.
    APPEND LINES OF lt_stock_mats TO lt_exist.
    SORT lt_exist.
    DELETE ADJACENT DUPLICATES FROM lt_exist.

    " Components only: remove any that have stock or movement
    SORT lt_bom_comp.
    DELETE ADJACENT DUPLICATES FROM lt_bom_comp.
    DELETE lt_bom_comp WHERE table_line IN lt_exist.

    " All materials to fetch details/texts
    lt_all = lt_main.
    APPEND LINES OF lt_bom_fert TO lt_all.
    APPEND LINES OF lt_bom_comp TO lt_all.
    SORT lt_all.
    DELETE ADJACENT DUPLICATES FROM lt_all.

    IF lt_all IS INITIAL.
      " Nothing to display, still show empty ALV with columns
    ELSE.
      " Material details
      SELECT mara~matnr, mara~mtart, mara~matkl, mara~meins
        FROM mara AS mara
        WHERE mara~matnr IN @lt_all
        INTO TABLE @lt_mara.

      " Material texts
      SELECT makt~matnr, makt~maktx
        FROM makt AS makt
        WHERE makt~matnr IN @lt_all
          AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.
    ENDIF.

    " Prepare lookups
    SORT lt_mara BY matnr.
    SORT lt_makt BY matnr.
    SORT lt_stock BY matnr.
    SORT lt_mov_mats.

    " Build MAIN section rows
    LOOP AT lt_main INTO lv_matnr.
      CLEAR: ls_mara, ls_makt, ls_stock, ls_out.
      READ TABLE lt_mara INTO ls_mara WITH KEY matnr = lv_matnr BINARY SEARCH.
      READ TABLE lt_makt INTO ls_makt WITH KEY matnr = lv_matnr BINARY SEARCH.
      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = lv_matnr BINARY SEARCH.

      ls_out-section   = '메인'.
      ls_out-matnr     = lv_matnr.
      ls_out-maktx     = ls_makt-maktx.
      ls_out-mtart     = ls_mara-mtart.
      ls_out-matkl     = ls_mara-matkl.
      ls_out-meins     = ls_mara-meins.
      ls_out-werks     = p_werks.
      ls_out-stock_qty = ls_stock-qty.

      READ TABLE lt_mov_mats WITH KEY table_line = lv_matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls_out-moved = abap_true.
      ELSE.
        ls_out-moved = abap_false.
      ENDIF.

      IF ls_out-moved = abap_true AND ls_out-stock_qty IS NOT INITIAL.
        ls_out-status = '입출고+재고'.
      ELSEIF ls_out-moved = abap_true AND ls_out-stock_qty IS INITIAL.
        ls_out-status = '입출고 있음'.
      ELSE.
        ls_out-status = '재고만 있음'.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    " Build BOM-FG section rows
    LOOP AT lt_bom_fert INTO lv_matnr.
      CLEAR: ls_mara, ls_makt, ls_stock, ls_out.
      READ TABLE lt_mara INTO ls_mara WITH KEY matnr = lv_matnr BINARY SEARCH.
      READ TABLE lt_makt INTO ls_makt WITH KEY matnr = lv_matnr BINARY SEARCH.
      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = lv_matnr BINARY SEARCH.

      ls_out-section   = 'BOM-완제품'.
      ls_out-matnr     = lv_matnr.
      ls_out-maktx     = ls_makt-maktx.
      ls_out-mtart     = ls_mara-mtart.
      ls_out-matkl     = ls_mara-matkl.
      ls_out-meins     = ls_mara-meins.
      ls_out-werks     = p_werks.
      ls_out-stock_qty = ls_stock-qty.

      READ TABLE lt_mov