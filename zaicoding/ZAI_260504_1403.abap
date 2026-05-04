REPORT ZAI_260504_1403.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE sy-datum OBLIGATORY.
PARAMETERS p_endda TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    IF p_begda > p_endda.
      MESSAGE '시작일이 종료일보다 늦습니다.' TYPE 'E'.
    ENDIF.

    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock_agg,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock_agg.
    TYPES ty_t_stock_agg TYPE STANDARD TABLE OF ty_stock_agg WITH EMPTY KEY.

    TYPES: BEGIN OF ty_main,
             matnr  TYPE mara-matnr,
             maktx  TYPE makt-maktx,
             mtart  TYPE mara-mtart,
             werks  TYPE werks_d,
             stock  TYPE mard-labst,
             status TYPE char20,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    TYPES: BEGIN OF ty_bom,
             kind      TYPE char4,        "FERT or COMP
             matnr     TYPE mara-matnr,
             maktx     TYPE makt-maktx,
             werks     TYPE werks_d,
             stock     TYPE mard-labst,
             status    TYPE char20,       "입출고 있음/재고만 있음/BOM 만 있음
           END OF ty_bom.
    TYPES ty_t_bom TYPE STANDARD TABLE OF ty_bom WITH EMPTY KEY.

    DATA lt_move_matnr TYPE ty_t_matnr.
    DATA lt_stock_matnr TYPE ty_t_matnr.
    DATA lt_union_matnr TYPE ty_t_matnr.
    DATA lt_stock_agg   TYPE ty_t_stock_agg.
    DATA lt_main        TYPE ty_t_main.
    DATA lt_bom         TYPE ty_t_bom.

    " 1) Materials with movements in period for plant
    SELECT DISTINCT ms~matnr
      FROM mseg AS ms
      INNER JOIN mkpf AS mk
        ON mk~mblnr = ms~mblnr
       AND mk~mjahr = ms~mjahr
      WHERE ms~werks = @p_werks
        AND mk~budat BETWEEN @p_begda AND @p_endda
      INTO TABLE @lt_move_matnr.

    " 2) Materials with current stock > 0 for plant
    SELECT DISTINCT mard~matnr
      FROM mard
      WHERE mard~werks = @p_werks
        AND mard~labst > 0
      INTO TABLE @lt_stock_matnr.

    " 3) Aggregate stock by material for plant
    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      INTO TABLE @lt_stock_agg.

    " 4) Union of movement or stock materials
    lt_union_matnr = lt_move_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_union_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_union_matnr.

    " 5) Read basic data (MARA, MAKT)
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    IF lt_union_matnr IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart
        FROM mara
        WHERE mara~matnr IN @lt_union_matnr
        INTO TABLE @lt_mara.

      DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
      SELECT makt~matnr,
             makt~maktx
        FROM makt
        WHERE makt~matnr IN @lt_union_matnr
          AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.

      " Build main list
      DATA ls_main TYPE ty_main.
      LOOP AT lt_union_matnr ASSIGNING FIELD-SYMBOL(<l_matnr>).
        CLEAR ls_main.
        ls_main-matnr = <l_matnr>.
        ls_main-werks = p_werks.

        READ TABLE lt_mara ASSIGNING FIELD-SYMBOL(<l_mara>) WITH KEY matnr = <l_matnr>.
        IF sy-subrc = 0.
          ls_main-mtart = <l_mara>-mtart.
        ENDIF.

        READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<l_makt>) WITH KEY matnr = <l_matnr>.
        IF sy-subrc = 0.
          ls_main-maktx = <l_makt>-maktx.
        ENDIF.

        READ TABLE lt_stock_agg ASSIGNING FIELD-SYMBOL(<l_stk>) WITH KEY matnr = <l_matnr>.
        IF sy-subrc = 0.
          ls_main-stock = <l_stk>-qty.
        ENDIF.

        DATA(l_has_move) = abap_false.
        READ TABLE lt_move_matnr WITH KEY table_line = <l_matnr> TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          l_has_move = abap_true.
        ENDIF.

        IF l_has_move = abap_true.
          ls_main-status = '입출고 있음'.
        ELSE.
          ls_main-status = '재고만 있음'.
        ENDIF.

        APPEND ls_main TO lt_main.
      ENDLOOP.
    ENDIF.

    " 6) BOM section for FERT with BOM in plant
    DATA lt_fert_bom TYPE ty_t_matnr.
    SELECT DISTINCT ma~matnr
      FROM mast AS ma
      INNER JOIN mara AS mm
        ON mm~matnr = ma~matnr
      WHERE ma~werks = @p_werks
        AND mm~mtart = 'FERT'
      INTO TABLE @lt_fert_bom.

    " Read texts for FERTs
    DATA lt_makt_f TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    IF lt_fert_bom IS NOT INITIAL.
      SELECT makt~matnr,
             makt~maktx
        FROM makt
        WHERE makt~matnr IN @lt_fert_bom
          AND makt~spras = @sy-langu
        INTO TABLE @lt_makt_f.
    ENDIF.

    " Add FERT rows into BOM section
    IF lt_fert_bom IS NOT INITIAL.
      DATA ls_bom TYPE ty_bom.
      LOOP AT lt_fert_bom ASSIGNING FIELD-SYMBOL(<l_fert>).
        CLEAR ls_bom.
        ls_bom-kind  = 'FERT'.
        ls_bom-matnr = <l_fert>.
        ls_bom-werks = p_werks.

        READ TABLE lt_makt_f ASSIGNING FIELD-SYMBOL(<l_makt_f>) WITH KEY matnr = <l_fert>.
        IF sy-subrc = 0.
          ls_bom-maktx = <l_makt_f>-maktx.
        ENDIF.

        READ TABLE lt_stock_agg ASSIGNING FIELD-SYMBOL(<l_stk_f>) WITH KEY matnr = <l_fert>.
        IF sy-subrc = 0.
          ls_bom-stock = <l_stk_f>-qty.
        ENDIF.

        DATA(l_has_move_f) = abap_false.
        READ TABLE lt_move_matnr WITH KEY table_line = <l_fert> TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          l_has_move_f = abap_true.
        ENDIF.

        IF l_has_move_f = abap_true.
          ls_bom-status = '입출고 있음'.
        ELSEIF ls_bom-stock > 0.
          ls_bom-status = '재고만 있음'.
        ELSE.
          ls_bom-status = ''.
        ENDIF.

        APPEND ls_bom TO lt_bom.
      ENDLOOP.
    ENDIF.

    " 7) BOM components of those FERTs (show even if no stock/movement -> 'BOM 만 있음')
    IF lt_fert_bom IS NOT INITIAL.
      " Get STLNR list for the FERT BOMs
      DATA lt_stlnr TYPE STANDARD TABLE OF mast-stlnr WITH EMPTY KEY.
      SELECT DISTINCT mast~stlnr
        FROM mast
        WHERE mast~werks = @p_werks
          AND mast~matnr IN @lt_fert_bom
        INTO TABLE @lt_stlnr.

      IF lt_stlnr IS NOT INITIAL.
        DATA lt_comp TYPE ty_t_matnr.
        SELECT DISTINCT stpo~idnrk
          FROM stpo
          WHERE stpo~stlnr IN @lt_stlnr
          INTO TABLE @lt_comp.

        IF lt_comp IS NOT INITIAL.
          " Read component texts
          DATA lt_makt_c TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
          SELECT makt~matnr,
                 makt~maktx
            FROM makt
            WHERE makt~matnr IN @lt_comp
              AND makt~spras = @sy-langu
            INTO TABLE @lt_makt_c.

          LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<l_comp>).
            CLEAR ls_bom.
            ls_bom-kind  = 'COMP'.
            ls_bom-matnr = <l_comp>.
            ls_bom-werks = p_werks.

            READ TABLE lt_makt_c ASSIGNING FIELD-SYMBOL(<l_makt_c>) WITH KEY matnr = <l_comp>.
            IF sy-subrc = 0.
              ls_bom-maktx = <l_makt_c>-maktx.
            ENDIF.

            READ TABLE lt_stock_agg ASSIGNING FIELD-SYMBOL(<l_stk_c>) WITH KEY matnr = <l_comp>.
            IF sy-subrc = 0.
              ls_bom-stock = <l_stk_c>-qty.
            ENDIF.

            DATA(l_has_move_c) = abap_false.
            READ TABLE lt_move_matnr WITH KEY table_line = <l_comp> TRANSPORTING NO FIELDS.
            IF sy-subrc = 0.
              l_has_move_c = abap_true.
            ENDIF.

            IF l_has_move_c = abap_true.
              ls_bom-status = '입출고 있음'.
            ELSEIF ls_bom-stock > 0.
              ls_bom-status = '재고만 있음'.
            ELSE.
              ls_bom-status = 'BOM 만 있음'.
            ENDIF.

            APPEND ls_bom TO lt_bom.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.

    " 8) Display ALVs
    DATA lo_alv TYPE REF TO cl_salv_table.

    " Main list ALV
    cl_sal