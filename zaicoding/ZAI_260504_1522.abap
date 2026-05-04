REPORT ZAI_260504_1522.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_datef TYPE sy-datum DEFAULT sy-datum - 30 OBLIGATORY.
PARAMETERS p_datet TYPE sy-datum DEFAULT sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES: BEGIN OF ty_main,
             matnr     TYPE mara-matnr,
             werks     TYPE mard-werks,
             mtart     TYPE mara-mtart,
             maktx     TYPE makt-maktx,
             stock_qty TYPE mard-labst,
             has_move  TYPE abap_bool,
             status    TYPE char20,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    TYPES: BEGIN OF ty_sec,
             category  TYPE char10, "FG_BOM or BOM_ONLY
             matnr     TYPE mara-matnr,
             werks     TYPE mard-werks,
             mtart     TYPE mara-mtart,
             maktx     TYPE makt-maktx,
             stock_qty TYPE mard-labst,
             has_move  TYPE abap_bool,
             status    TYPE char20,
           END OF ty_sec.
    TYPES ty_t_sec TYPE STANDARD TABLE OF ty_sec WITH EMPTY KEY.

    CLASS-METHODS get_mov_matnrs
      IMPORTING
        !iv_werks TYPE werks_d
        !iv_datef TYPE sy-datum
        !iv_datet TYPE sy-datum
      RETURNING
        VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stock_by_matnr
      IMPORTING
        !iv_werks TYPE werks_d
      RETURNING
        VALUE(rt_stock) TYPE STANDARD TABLE OF mard WITH EMPTY KEY.

    CLASS-METHODS get_maktx
      IMPORTING
        !it_matnr TYPE ty_t_matnr
      RETURNING
        VALUE(rt_texts) TYPE STANDARD TABLE OF makt WITH EMPTY KEY.

    CLASS-METHODS get_fg_with_bom
      IMPORTING
        !iv_werks TYPE werks_d
      RETURNING
        VALUE(rt_fg) TYPE ty_t_matnr.

    CLASS-METHODS get_bom_components_only
      IMPORTING
        !iv_werks TYPE werks_d
        !it_exclude TYPE ty_t_matnr
      RETURNING
        VALUE(rt_comp) TYPE ty_t_matnr.

    CLASS-METHODS to_set
      IMPORTING
        !it_tab TYPE ty_t_matnr
      RETURNING
        VALUE(rt_set) TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.

    CLASS-METHODS display_main
      IMPORTING
        !it_data TYPE ty_t_main.

    CLASS-METHODS display_sec
      IMPORTING
        !it_data TYPE ty_t_sec.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lv_werks TYPE werks_d VALUE p_werks.
    DATA lv_datef TYPE sy-datum VALUE p_datef.
    DATA lv_datet TYPE sy-datum VALUE p_datet.

    IF lv_datef > lv_datet.
      MESSAGE '시작일이 종료일보다 클 수 없습니다.' TYPE 'E'.
    ENDIF.

    " 1) Movement materials in period
    DATA(lt_mov_matnr) = get_mov_matnrs(
      iv_werks = lv_werks
      iv_datef = lv_datef
      iv_datet = lv_datet ).

    " 2) Current stock per material in plant
    DATA(lt_mard) = get_stock_by_matnr( iv_werks = lv_werks ).

    " Build stock aggregation
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             werks TYPE mard-werks,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    DATA lt_stock TYPE ty_t_stock.
    DATA ls_stock TYPE ty_stock.

    SORT lt_mard BY matnr werks.
    LOOP AT lt_mard ASSIGNING FIELD-SYMBOL(<ls_mard>).
      IF <ls_mard>-labst IS INITIAL.
        CONTINUE.
      ENDIF.
      READ TABLE lt_stock ASSIGNING FIELD-SYMBOL(<ls_s>)
        WITH KEY matnr = <ls_mard>-matnr werks = <ls_mard>-werks.
      IF sy-subrc <> 0.
        ls_stock-matnr = <ls_mard>-matnr.
        ls_stock-werks = <ls_mard>-werks.
        ls_stock-qty   = <ls_mard>-labst.
        APPEND ls_stock TO lt_stock.
      ELSE.
        <ls_s>-qty = <ls_s>-qty + <ls_mard>-labst.
      ENDIF.
    ENDLOOP.

    " Main material list: movement OR stock<>0
    DATA lt_main TYPE ty_t_main.
    DATA lt_main_matnr TYPE lcl_app=>ty_t_matnr.

    " Add movement materials
    LOOP AT lt_mov_matnr ASSIGNING FIELD-SYMBOL(<lv_mmatnr>).
      APPEND <lv_mmatnr> TO lt_main_matnr.
    ENDLOOP.

    " Add stock materials (qty <> 0)
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      IF <ls_stk>-qty IS NOT INITIAL.
        APPEND <ls_stk>-matnr TO lt_main_matnr.
      ENDIF.
    ENDLOOP.

    " Unique set of main materials
    DATA lt_main_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_main_set = to_set( lt_main_matnr ).

    " Fetch master data for main materials
    DATA lt_main_keys TYPE lcl_app=>ty_t_matnr.
    LOOP AT lt_main_set ASSIGNING FIELD-SYMBOL(<lv_mn>).
      APPEND <lv_mn> TO lt_main_keys.
    ENDLOOP.

    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    IF lt_main_keys IS NOT INITIAL.
      SELECT mara~matnr, mara~mtart
        FROM mara
        WHERE mara~matnr IN @lt_main_keys
        INTO TABLE @lt_mara.
    ENDIF.

    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    lt_makt = get_maktx( lt_main_keys ).

    " Build movement set for quick lookup
    DATA lt_mov_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_mov_set = to_set( lt_mov_matnr ).

    " Assemble main rows
    LOOP AT lt_mara ASSIGNING FIELD-SYMBOL(<ls_mara>).
      DATA(ls_main) = VALUE ty_main(
        matnr = <ls_mara>-matnr
        werks = lv_werks
        mtart = <ls_mara>-mtart ).

      READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<ls_makt>)
        WITH KEY matnr = <ls_mara>-matnr spras = sy-langu.
      IF sy-subrc = 0.
        ls_main-maktx = <ls_makt>-maktx.
      ENDIF.

      READ TABLE lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk2>)
        WITH KEY matnr = <ls_mara>-matnr werks = lv_werks.
      IF sy-subrc = 0.
        ls_main-stock_qty = <ls_stk2>-qty.
      ENDIF.

      READ TABLE lt_mov_set WITH KEY table_line = <ls_mara>-matnr
        TRANSPORTING NO FIELDS.
      ls_main-has_move = xsdbool( sy-subrc = 0 ).

      IF ls_main-has_move = abap_true.
        ls_main-status = '입출고 실적 있음'.
      ELSEIF ls_main-stock_qty IS NOT INITIAL.
        ls_main-status = '재고만 있음'.
      ELSE.
        CONTINUE. " Should not happen due to selection logic
      ENDIF.

      APPEND ls_main TO lt_main.
    ENDLOOP.

    " 3) Finished goods with BOM (separate section)
    DATA lt_fg_bom TYPE lcl_app=>ty_t_matnr.
    lt_fg_bom = get_fg_with_bom( iv_werks = lv_werks ).

    " 4) BOM-only components without stock or movements
    DATA lt_bom_only TYPE lcl_app=>ty_t_matnr.
    lt_bom_only = get_bom_components_only(
      iv_werks  = lv_werks
      it_exclude = lt_main_keys ).

    " Fetch master and texts for section materials (FG with BOM + BOM-only)
    DATA lt_sec_keys TYPE lcl_app=>ty_t_matnr.
    LOOP AT lt_fg_bom ASSIGNING FIELD-SYMBOL(<lv_fg>).
      APPEND <lv_fg> TO lt_sec_keys.
    ENDLOOP.
    LOOP AT lt_bom_only ASSIGNING FIELD-SYMBOL(<lv_bo>).
      APPEND <lv_bo> TO lt_sec_keys.
    ENDLOOP.

    DATA lt_sec_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_sec_set = to_set( lt_sec_keys ).

    DATA lt_sec_keys_u TYPE lcl_app=>ty_t_matnr.
    LOOP AT lt_sec_set ASSIGNING FIELD-SYMBOL(<lv_sk>).
      APPEND <lv_sk> TO lt_sec_keys_u.
    ENDLOOP.

    DATA lt_mara_sec TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    IF lt_sec_keys_u IS NOT INITIAL.
      SELECT mara~matnr, mara~mtart
        FROM mara
        WHERE mara~matnr IN @lt_sec_keys_u
        INTO TABLE @lt_mara_sec.
    ENDIF.

    DATA lt_makt_sec TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    lt_makt_sec = get_maktx( lt_sec_keys_u ).

    " Assemble section rows
    DATA lt_sec TYPE ty_t_sec.

    " Finished goods with BOM
    LOOP AT lt_fg_bom ASSIGNING <lv_fg>.
      READ TABLE lt_mara_sec ASSIGNING FIELD-SYMBOL(<ls_mara_s>)
        WITH KEY matnr = <lv_fg>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      DATA(ls_sec_fg) = VALUE ty_sec(
        category = 'FG_BOM'
        matnr    = <ls_mara_s>-matnr
        werks    = lv_werks
        mtart    = <ls_mara_s>-mtart ).

      READ TABLE lt_makt_sec ASSIGNING FIELD-SYMBOL(<ls_makt_s>)
        WITH KEY matnr = <lv_fg> spras = sy-langu.
      IF sy-subrc = 0.
        ls_sec_fg-maktx = <ls_makt_s>-maktx.
      ENDIF.

      READ TABLE lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk_fg>)
        WITH KEY matnr = <lv_fg> werks = lv_werks.
      IF sy-subrc = 0.
        ls_sec_fg-stock_qty = <ls_stk_fg>-qty.
      ENDIF.

      READ TABLE lt_mov_set WITH KEY table_line = <lv_fg>
        TRANSPORTING NO FIELDS.
      ls_sec_fg-has_move = xsdbool( sy-subrc = 0 ).

      IF ls_sec_fg-has_move = abap_true.
        ls_sec_fg-status = '입출고 실적 있음'.
      ELSEIF ls_sec_fg-stock_qty IS NOT INITIAL.
        ls_sec_fg-status = '재고만 있음'.
      ELSE.
        ls_sec_fg-status = 'BOM 만 있음'.
      ENDIF.

      APPEND ls_sec_fg TO lt_sec.
    ENDLOOP.

    " BOM-only components (no stock, no movements)
    LOOP AT lt_bom_only ASSIGNING <lv_bo>.
      READ TABLE lt_mara_sec ASSIGNING <ls_mara_s>
        WITH KEY matnr = <lv_bo>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA(ls_sec_bo) = VALUE ty_sec(
        category = 'BOM_ONLY'
        matnr    = <ls_mara_s>-matnr
        werks    = lv_werks
        mtart    = <ls_mara_s>-mtart
        status   = 'BOM 만 있음' ).

      READ TABLE lt_makt_sec ASSIGNING <ls_makt_s>
        WITH KEY matnr = <lv_bo> spras = sy-langu.
      IF sy-subrc = 0.
        ls_sec_bo-maktx = <ls_makt_s>-maktx.
      ENDIF.

      ls_sec_bo-stock_qty = 0.
      ls_sec_bo-has_move  = abap_false.

      APPEND ls_sec_bo TO lt_sec.
    ENDLOOP.

    " Display
    display_main( lt_main ).
    display_sec( lt_sec ).
  ENDMETHOD.

  METHOD get_mov_matnrs.
    DATA lt_matnr TYPE ty_t_matnr.
    SELECT DISTINCT matdoc~matnr
      FROM matdoc
      WHERE matdoc~werks = @iv_werks
        AND matdoc~budat BETWEEN @iv_datef AND @iv_datet
      INTO TABLE @lt_matnr.
    rt_matnr = lt_matnr.
  ENDMETHOD.

  METHOD get_stock_by_matnr.
    DATA lt_mard TYPE STANDARD TABLE OF mard WITH EMPTY KEY.
    SELECT mard~matnr, mard~werks, mard~lgort, mard~labst
      FROM mard
      WHERE mard~werks = @iv_werks
      INTO TABLE @lt_mard.
    rt_stock = lt_mard.
  ENDMETHOD.

  METHOD get_maktx.
    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT makt~matnr, makt~spras, makt~maktx
      FROM makt
      WHERE makt~matnr IN @it_matnr
        AND makt~spras = @sy-langu
      INTO TABLE @lt_makt.
    rt_texts = lt_makt.
  ENDMETHOD.

  METHOD get_fg_with_bom.
    " Finished goods (FERT) that have a BOM in the plant
    DATA lt_fg TYPE ty_t_matnr.
    SELECT DISTINCT mara~matnr
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @iv_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_fg.
    rt_fg = lt_fg.
  ENDMETHOD.

  METHOD get_bom_components_only.
    " Components in BOMs of the plant, excluding materials provided in it_exclude
    DATA lt_comp TYPE ty_t_matnr.
    IF it_exclude IS INITIAL.
      " Still fine; simply no exclusion
    ENDIF.
    SELECT DISTINCT stpo~idnrk
      FROM mast
      INNER JOIN stpo
        ON stpo~stlnr = mast~stlnr
      WHERE mast~werks = @iv_werks
      INTO TABLE @lt_comp.

    " Exclude any that have stock or movements (passed via it_exclude list)
    IF lt_comp IS NOT INITIAL AND it_exclude IS NOT INITIAL.
      DATA lt_ex_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
      lt_ex_set = to_set( it_exclude ).
      DELETE lt_comp WHERE table_line IN lt_ex_set.
    ENDIF.

    " Keep only those that truly have no stock or movements in plant:
    " We already excluded 'main' list. Return remaining as