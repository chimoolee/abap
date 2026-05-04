REPORT ZAI_260504_1526.

PARAMETERS p_werks TYPE werks_d.
PARAMETERS p_dfr  TYPE budat DEFAULT sy-datum.
PARAMETERS p_dto  TYPE budat DEFAULT sy-datum.

INITIALIZATION.
  p_dfr = sy-datum - 30.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES ty_matnr_tab TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES: BEGIN OF ty_item,
             matnr  TYPE mara-matnr,
             maktx  TYPE makt-maktx,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             stock  TYPE mard-labst,
             status TYPE c LENGTH 20,
           END OF ty_item.
    TYPES ty_item_tab TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

    CLASS-METHODS get_moved_materials
      IMPORTING
        i_werks   TYPE werks_d
        i_dfr     TYPE budat
        i_dto     TYPE budat
      RETURNING VALUE(rt_matnr) TYPE ty_matnr_tab.

    CLASS-METHODS get_stock_materials
      IMPORTING
        i_werks   TYPE werks_d
      RETURNING VALUE(rt_items) TYPE ty_item_tab.

    CLASS-METHODS get_texts_and_attrs
      CHANGING
        ct_items  TYPE ty_item_tab.

    CLASS-METHODS build_main_list
      IMPORTING
        it_moved  TYPE ty_matnr_tab
        it_stock  TYPE ty_item_tab
      RETURNING VALUE(rt_main) TYPE ty_item_tab.

    CLASS-METHODS get_bom_component_only
      IMPORTING
        i_werks    TYPE werks_d
        i_dfr      TYPE budat
        i_dto      TYPE budat
        it_exclude TYPE ty_matnr_tab
      RETURNING VALUE(rt_bom_only) TYPE ty_item_tab.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_moved TYPE ty_matnr_tab.
    DATA lt_stock TYPE ty_item_tab.
    DATA lt_main  TYPE ty_item_tab.
    DATA lt_bom   TYPE ty_item_tab.
    DATA lo_alv   TYPE REF TO cl_salv_table.

    lt_moved = get_moved_materials(
      i_werks = p_werks
      i_dfr   = p_dfr
      i_dto   = p_dto ).

    lt_stock = get_stock_materials( i_werks = p_werks ).

    lt_main = build_main_list(
      it_moved = lt_moved
      it_stock = lt_stock ).

    get_texts_and_attrs( CHANGING ct_items = lt_main ).

    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_main ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      |자재 리스트 (입출고 또는 재고 보유) 플랜트: { p_werks } 기간: { p_dfr }~{ p_dto }| ).
    lo_alv->display( ).

    DATA lt_excl TYPE ty_matnr_tab.
    LOOP AT lt_main ASSIGNING FIELD-SYMBOL(<ls_mn>).
      APPEND <ls_mn>-matnr TO lt_excl.
    ENDLOOP.

    lt_bom = get_bom_component_only(
      i_werks    = p_werks
      i_dfr      = p_dfr
      i_dto      = p_dto
      it_exclude = lt_excl ).

    IF lt_bom IS NOT INITIAL.
      get_texts_and_attrs( CHANGING ct_items = lt_bom ).
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_bom ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->get_display_settings( )->set_list_header(
        |BOM 전용 목록 (재고/입출고 없음, BOM 요소로만 존재) 플랜트: { p_werks }| ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.

  METHOD get_moved_materials.
    DATA lt_mat TYPE ty_matnr_tab.

    SELECT DISTINCT s~matnr
      FROM mseg AS s
      INNER JOIN mkpf AS h
        ON h~mblnr = s~mblnr
       AND h~mjahr = s~mjahr
      WHERE ( @i_werks IS INITIAL OR s~werks = @i_werks )
        AND h~budat BETWEEN @i_dfr AND @i_dto
        AND s~matnr IS NOT NULL
      INTO TABLE @lt_mat.

    rt_matnr = lt_mat.
  ENDMETHOD.

  METHOD get_stock_materials.
    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
      WHERE ( @i_werks IS INITIAL OR mard~werks = @i_werks )
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @DATA(lt_agg).

    DATA lt_items TYPE ty_item_tab.
    LOOP AT lt_agg ASSIGNING FIELD-SYMBOL(<ls_a>).
      APPEND VALUE ty_item(
        matnr  = <ls_a>-matnr
        stock  = <ls_a>-qty
        status = |재고만 있음| ) TO lt_items.
    ENDLOOP.

    rt_items = lt_items.
  ENDMETHOD.

  METHOD get_texts_and_attrs.
    IF ct_items IS INITIAL.
      RETURN.
    ENDIF.

    DATA lt_matnr TYPE ty_matnr_tab.
    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<ls_i1>).
      APPEND <ls_i1>-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    SELECT mara~matnr,
           mara~mtart,
           mara~matkl,
           mara~meins
      FROM mara
      FOR ALL ENTRIES IN @lt_matnr
      WHERE mara~matnr = @lt_matnr-table_line
      INTO TABLE @DATA(lt_mara).

    SELECT makt~matnr,
           makt~maktx
      FROM makt
      FOR ALL ENTRIES IN @lt_matnr
      WHERE makt~matnr = @lt_matnr-table_line
        AND makt~spras = @sy-langu
      INTO TABLE @DATA(lt_makt).

    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<ls_itm>).
      READ TABLE lt_mara ASSIGNING FIELD-SYMBOL(<ls_ma>)
        WITH KEY matnr = <ls_itm>-matnr.
      IF sy-subrc = 0.
        <ls_itm>-mtart = <ls_ma>-mtart.
        <ls_itm>-matkl = <ls_ma>-matkl.
        <ls_itm>-meins = <ls_ma>-meins.
      ENDIF.
      READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<ls_tx>)
        WITH KEY matnr = <ls_itm>-matnr.
      IF sy-subrc = 0.
        <ls_itm>-maktx = <ls_tx>-maktx.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_main_list.
    DATA lt_main TYPE ty_item_tab.

    APPEND LINES OF it_stock TO lt_main.

    LOOP AT it_moved ASSIGNING FIELD-SYMBOL(<lv_mov>).
      READ TABLE lt_main ASSIGNING FIELD-SYMBOL(<ls_m>)
        WITH KEY matnr = <lv_mov>.
      IF sy-subrc = 0.
        <ls_m>-status = |입출고 있음|.
      ELSE.
        APPEND VALUE ty_item(
          matnr  = <lv_mov>
          stock  = CONV mard-labst( 0 )
          status = |입출고 있음| ) TO lt_main.
      ENDIF.
    ENDLOOP.

    rt_main = lt_main.
  ENDMETHOD.

  METHOD get_bom_component_only.
    DATA lt_comp TYPE ty_matnr_tab.

    SELECT DISTINCT c~idnrk
      FROM mast AS a
      INNER JOIN mara AS h
        ON h~matnr = a~matnr
      INNER JOIN stpo AS c
        ON c~stlnr = a~stlnr
      WHERE ( @i_werks IS INITIAL OR a~werks = @i_werks )
        AND h~mtart = 'FERT'
        AND c~idnrk IS NOT NULL
      INTO TABLE @lt_comp.

    IF it_exclude IS NOT INITIAL AND lt_comp IS NOT INITIAL.
      SORT lt_comp.
      SORT it_exclude.
      DATA lt_tmp TYPE ty_matnr_tab.
      LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<lv_c>).
        READ TABLE it_exclude WITH KEY table_line = <lv_c>
             TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND <lv_c> TO lt_tmp.
        ENDIF.
      ENDLOOP.
      lt_comp = lt_tmp.
    ENDIF.

    IF lt_comp IS INITIAL.
      RETURN.
    ENDIF.

    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
      FOR ALL ENTRIES IN @lt_comp
      WHERE mard~matnr = @lt_comp-table_line
        AND ( @i_werks IS INITIAL OR mard~werks = @i_werks )
      GROUP BY mard~matnr
      INTO TABLE @DATA(lt_comp_stock).

    DATA lt_no_stock TYPE ty_matnr_tab.
    LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<lv_allc>).
      READ TABLE lt_comp_stock ASSIGNING FIELD-SYMBOL(<ls_cs>)
        WITH KEY matnr = <lv_allc>.
      IF sy-subrc <> 0 OR <ls_cs>-qty = 0.
        APPEND <lv_allc> TO lt_no_stock.
      ENDIF.
    ENDLOOP.

    IF lt_no_stock IS INITIAL.
      RETURN.
    ENDIF.

    SELECT DISTINCT s~matnr
      FROM mseg AS s
      INNER JOIN mkpf AS h
        ON h~mblnr = s~mblnr
       AND h~mjahr = s~mjahr
      FOR ALL ENTRIES IN @lt_no_stock
      WHERE s~matnr = @lt_no_stock-table_line
        AND ( @i_werks IS INITIAL OR s~werks = @i_werks )
        AND h~budat BETWEEN @i_dfr AND @i_dto
      INTO TABLE @DATA(lt_mov_exist).

    DATA lt_final TYPE ty_matnr_tab.
    LOOP AT lt_no_stock ASSIGNING FIELD-SYMBOL(<lv_ns>).
      READ TABLE lt_mov_exist WITH KEY table_line = <lv_ns>
           TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND <lv_ns> TO lt_final.
      ENDIF.
    ENDLOOP.

    DATA lt_items TYPE ty_item_tab.
    LOOP AT lt_final ASSIGNING FIELD-SYMBOL(<lv_fin>).
      APPEND VALUE ty_item(
        matnr  = <lv_fin>
        stock  = CONV mard-labst( 0 )
        status = |BOM 만 있음| ) TO lt_items.
    ENDLOOP.

    rt_bom_only = lt_items.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).