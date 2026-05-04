REPORT ZAI_260504_1744.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR mkpf-budat OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_base,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_base,
      ty_t_base TYPE STANDARD TABLE OF ty_base WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mov,
        matnr   TYPE mara-matnr,
        mov_qty TYPE mseg-menge,
      END OF ty_mov,
      ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        stock TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr   TYPE mara-matnr,
        werks   TYPE werks_d,
        mtart   TYPE mara-mtart,
        matkl   TYPE mara-matkl,
        maktx   TYPE makt-maktx,
        mov_qty TYPE mseg-menge,
        stock   TYPE mard-labst,
        status  TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CLASS-METHODS get_main_results
      RETURNING VALUE(rt_result) TYPE ty_t_result.

    CLASS-METHODS get_bom_only_results
      RETURNING VALUE(rt_result) TYPE ty_t_result.

    CLASS-METHODS display_alv
      IMPORTING it_data TYPE ty_t_result
                iv_title TYPE string.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_main TYPE ty_t_result.
    DATA lt_bom  TYPE ty_t_result.

    lt_main = get_main_results( ).
    lt_bom  = get_bom_only_results( ).

    display_alv( it_data = lt_main
                 iv_title = '입출고/재고 자재 목록' ).

    display_alv( it_data = lt_bom
                 iv_title = 'BOM 에만 있음 (완제품 BOM 요소)' ).
  ENDMETHOD.

  METHOD get_main_results.
    DATA lt_mov   TYPE ty_t_mov.
    DATA lt_stock TYPE ty_t_stock.

    DATA lt_all_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Movements in period for plant
    SELECT
      mseg~matnr,
      SUM( mseg~menge ) AS mov_qty
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mseg~werks = @p_werks
        AND mkpf~budat IN @s_budat
      GROUP BY mseg~matnr
      INTO TABLE @lt_mov.

    " Current stock by plant (sum across storage locations)
    SELECT
      mard~matnr,
      SUM( mard~labst ) AS stock
      FROM mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      INTO TABLE @lt_stock.

    " Build combined material list: movement or non-zero stock
    DATA ls_mov TYPE ty_mov.
    LOOP AT lt_mov INTO ls_mov.
      APPEND ls_mov-matnr TO lt_all_matnr.
    ENDLOOP.

    DATA ls_stock TYPE ty_stock.
    LOOP AT lt_stock INTO ls_stock.
      IF ls_stock-stock IS NOT INITIAL.
        APPEND ls_stock-matnr TO lt_all_matnr.
      ENDIF.
    ENDLOOP.

    SORT lt_all_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr COMPARING table_line.

    IF lt_all_matnr IS INITIAL.
      RETURN.
    ENDIF.

    " Read base material texts and types
    DATA lt_base TYPE ty_t_base.
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      WHERE mara~matnr IN @lt_all_matnr
      INTO TABLE @lt_base.

    " Build result
    DATA lt_result TYPE ty_t_result.
    DATA ls_base TYPE ty_base.
    DATA ls_res  TYPE ty_result.

    LOOP AT lt_base INTO ls_base.
      CLEAR ls_res.
      ls_res-matnr = ls_base-matnr.
      ls_res-werks = p_werks.
      ls_res-mtart = ls_base-mtart.
      ls_res-matkl = ls_base-matkl.
      ls_res-maktx = ls_base-maktx.

      READ TABLE lt_mov INTO ls_mov WITH KEY matnr = ls_base-matnr.
      IF sy-subrc = 0.
        ls_res-mov_qty = ls_mov-mov_qty.
      ELSE.
        CLEAR ls_res-mov_qty.
      ENDIF.

      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_base-matnr.
      IF sy-subrc = 0.
        ls_res-stock = ls_stock-stock.
      ELSE.
        CLEAR ls_res-stock.
      ENDIF.

      IF ls_res-mov_qty IS INITIAL AND ls_res-stock IS NOT INITIAL.
        ls_res-status = '재고만 있음'.
      ELSEIF ls_res-mov_qty IS NOT INITIAL AND ls_res-stock IS INITIAL.
        ls_res-status = '입출고만 있음'.
      ELSEIF ls_res-mov_qty IS NOT INITIAL AND ls_res-stock IS NOT INITIAL.
        ls_res-status = '입출고/재고 있음'.
      ELSE.
        CONTINUE. " Should not happen due to union filter
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    rt_result = lt_result.
  ENDMETHOD.

  METHOD get_bom_only_results.
    DATA lt_hdr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_comp    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_mov_c   TYPE ty_t_mov.
    DATA lt_stock_c TYPE ty_t_stock.

    " Finished goods with BOM in plant
    SELECT DISTINCT
      mast~matnr
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_hdr.

    IF lt_hdr IS INITIAL.
      RETURN.
    ENDIF.

    " Components of those BOMs
    SELECT DISTINCT
      stpo~idnrk
      FROM mast
      INNER JOIN stpo
        ON stpo~stlnr = mast~stlnr
       AND stpo~stlal = mast~stlal
      WHERE mast~werks = @p_werks
        AND mast~matnr IN @lt_hdr
      INTO TABLE @lt_comp.

    DELETE lt_comp WHERE table_line IS INITIAL.
    SORT lt_comp BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_comp COMPARING table_line.

    IF lt_comp IS INITIAL.
      RETURN.
    ENDIF.

    " Movements for components in period/plant
    SELECT
      mseg~matnr,
      SUM( mseg~menge ) AS mov_qty
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mseg~werks = @p_werks
        AND mkpf~budat IN @s_budat
        AND mseg~matnr IN @lt_comp
      GROUP BY mseg~matnr
      INTO TABLE @lt_mov_c.

    " Current stock for components at plant
    SELECT
      mard~matnr,
      SUM( mard~labst ) AS stock
      FROM mard
      WHERE mard~werks = @p_werks
        AND mard~matnr IN @lt_comp
      GROUP BY mard~matnr
      INTO TABLE @lt_stock_c.

    " Determine BOM-only components (no movement and zero stock)
    DATA lt_bom_only TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lv_matnr TYPE mara-matnr.
    LOOP AT lt_comp INTO lv_matnr.
      DATA(ls_mc) = VALUE ty_mov( ).
      DATA(ls_sc) = VALUE ty_stock( ).

      READ TABLE lt_mov_c INTO ls_mc WITH KEY matnr = lv_matnr.
      READ TABLE lt_stock_c INTO ls_sc WITH KEY matnr = lv_matnr.

      IF ( ls_mc-mov_qty IS INITIAL ) AND ( ls_sc-stock IS INITIAL ).
        APPEND lv_matnr TO lt_bom_only.
      ENDIF.
    ENDLOOP.

    IF lt_bom_only IS INITIAL.
      RETURN.
    ENDIF.

    " Read base data/texts for BOM-only materials
    DATA lt_base TYPE ty_t_base.
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      WHERE mara~matnr IN @lt_bom_only
      INTO TABLE @lt_base.

    " Build BOM-only result rows
    DATA lt_result TYPE ty_t_result.
    DATA ls_base TYPE ty_base.
    DATA ls_res  TYPE ty_result.

    LOOP AT lt_base INTO ls_base.
      CLEAR ls_res.
      ls_res-matnr  = ls_base-matnr.
      ls_res-werks  = p_werks.
      ls_res-mtart  = ls_base-mtart.
      ls_res-matkl  = ls_base-matkl.
      ls_res-maktx  = ls_base-maktx.
      CLEAR ls_res-mov_qty.
      CLEAR ls_res-stock.
      ls_res-status = 'BOM 에 만 있음'.
      APPEND ls_res TO lt_result.
    ENDLOOP.

    rt_result = lt_result.
  ENDMETHOD.

  METHOD display_alv.
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = it_data ).

    IF iv_title IS NOT INITIAL.
      DATA(lo_display) = lo_alv->get_display_settings( ).
      lo_display->set_list_header( value = iv_title ).
    ENDIF.

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).