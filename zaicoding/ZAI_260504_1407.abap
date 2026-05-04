REPORT ZAI_260504_1407.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE sy-datum OBLIGATORY.
PARAMETERS p_endda TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_main,
             matnr  TYPE mara-matnr,
             maktx  TYPE makt-maktx,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             labst  TYPE mard-labst,
             status TYPE string,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    TYPES: BEGIN OF ty_bomsec,
             matnr  TYPE mara-matnr,
             maktx  TYPE makt-maktx,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             status TYPE string,
           END OF ty_bomsec.
    TYPES ty_t_bomsec TYPE STANDARD TABLE OF ty_bomsec WITH EMPTY KEY.

    CLASS-METHODS get_movements
      IMPORTING i_werks TYPE werks_d
                i_begda TYPE sy-datum
                i_endda TYPE sy-datum
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stocks
      IMPORTING i_werks TYPE werks_d
      RETURNING VALUE(rt_stock) TYPE ty_t_stock.

    CLASS-METHODS get_texts
      IMPORTING it_matnr TYPE ty_t_matnr
      RETURNING VALUE(rt_texts) TYPE STANDARD TABLE OF makt WITH EMPTY KEY.

    CLASS-METHODS fill_main
      IMPORTING it_all    TYPE ty_t_matnr
                it_mov    TYPE ty_t_matnr
                it_stock  TYPE ty_t_stock
      RETURNING VALUE(rt_main) TYPE ty_t_main.

    CLASS-METHODS build_bom_section
      IMPORTING i_werks TYPE werks_d
                it_mov  TYPE ty_t_matnr
                it_stock TYPE ty_t_stock
      RETURNING VALUE(rt_bom) TYPE ty_t_bomsec.

    CLASS-METHODS display_alv
      IMPORTING it_tab TYPE STANDARD TABLE
                iv_title TYPE string.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mov   TYPE ty_t_matnr.
    DATA lt_stock TYPE ty_t_stock.
    DATA lt_all   TYPE ty_t_matnr.
    DATA lt_main  TYPE ty_t_main.
    DATA lt_bom   TYPE ty_t_bomsec.

    lt_mov   = get_movements( i_werks = p_werks i_begda = p_begda i_endda = p_endda ).
    lt_stock = get_stocks( i_werks = p_werks ).

    " Union of materials having movements or non-zero stock
    lt_all = lt_mov.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      INSERT <ls_stk>-matnr INTO TABLE lt_all.
    ENDLOOP.

    lt_main = fill_main( it_all = lt_all it_mov = lt_mov it_stock = lt_stock ).
    lt_bom  = build_bom_section( i_werks = p_werks it_mov = lt_mov it_stock = lt_stock ).

    display_alv( it_tab = lt_main iv_title = |자재 목록 (입출고/재고)| ).
    display_alv( it_tab = lt_bom  iv_title = |BOM 관련 섹션 (완제품 BOM, BOM 만 있음)| ).
  ENDMETHOD.

  METHOD get_movements.
    SELECT DISTINCT
           md~matnr
      FROM matdoc AS md
      WHERE md~werks       = @i_werks
        AND md~pstng_date >= @i_begda
        AND md~pstng_date <= @i_endda
      INTO TABLE @rt_matnr.
  ENDMETHOD.

  METHOD get_stocks.
    SELECT
      m~matnr,
      m~labst
      FROM mard AS m
      WHERE m~werks = @i_werks
        AND m~labst <> 0
      INTO TABLE @rt_stock.
  ENDMETHOD.

  METHOD get_texts.
    DATA lt_texts TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT
      t~matnr,
      t~spras,
      t~maktx
      FROM makt AS t
      FOR ALL ENTRIES IN @it_matnr
      WHERE t~matnr = @it_matnr-table_line
        AND t~spras = @sy-langu
      INTO TABLE @lt_texts.
    rt_texts = lt_texts.
  ENDMETHOD.

  METHOD fill_main.
    DATA lt_texts TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    DATA lt_mara  TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    DATA ls_main  TYPE ty_main.

    IF it_all IS INITIAL.
      RETURN.
    ENDIF.

    " Basic data
    SELECT
      a~matnr,
      a~mtart,
      a~matkl,
      a~meins
      FROM mara AS a
      FOR ALL ENTRIES IN @it_all
      WHERE a~matnr = @it_all-table_line
      INTO TABLE @lt_mara.

    lt_texts = get_texts( it_matnr = it_all ).

    LOOP AT lt_mara ASSIGNING FIELD-SYMBOL(<la>).
      CLEAR ls_main.
      ls_main-matnr = <la>-matnr.
      ls_main-mtart = <la>-mtart.
      ls_main-matkl = <la>-matkl.
      ls_main-meins = <la>-meins.

      READ TABLE lt_texts ASSIGNING FIELD-SYMBOL(<ltx>) WITH KEY matnr = <la>-matnr spras = sy-langu.
      IF sy-subrc = 0.
        ls_main-maktx = <ltx>-maktx.
      ENDIF.

      READ TABLE it_stock ASSIGNING FIELD-SYMBOL(<ls_stk>) WITH KEY matnr = <la>-matnr.
      IF sy-subrc = 0.
        ls_main-labst = <ls_stk>-labst.
      ENDIF.

      DATA(lv_has_mov) = abap_false.
      READ TABLE it_mov WITH KEY table_line = <la>-matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_main-status = |입출고있음|.
      ELSE.
        ls_main-status = |재고만 있음|.
      ENDIF.

      APPEND ls_main TO rt_main.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_bom_section.
    DATA lt_fert_bom TYPE ty_t_matnr.
    DATA lt_comp_all TYPE ty_t_matnr.
    DATA lt_comp_filtered TYPE ty_t_matnr.
    DATA lt_texts TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    DATA ls_bom TYPE ty_bomsec.

    " Finished goods with BOM in plant
    SELECT DISTINCT
           ma~matnr
      FROM mast AS ma
      INNER JOIN mara AS a
        ON a~matnr = ma~matnr
      WHERE ma~werks = @i_werks
        AND a~mtart = 'FERT'
      INTO TABLE @lt_fert_bom.

    " Component materials used in BOMs of the plant
    SELECT DISTINCT
           st~idnrk
      FROM mast AS ma
      INNER JOIN stpo AS st
        ON st~stlnr = ma~stlnr
      WHERE ma~werks = @i_werks
      INTO TABLE @lt_comp_all.

    " Filter components: no movement and no stock
    LOOP AT lt_comp_all ASSIGNING FIELD-SYMBOL(<lcomp>).
      READ TABLE i_mov WITH KEY table_line = <lcomp> TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      READ TABLE i_stock ASSIGNING FIELD-SYMBOL(<ls_stk>) WITH KEY matnr = <lcomp>.
      IF sy-subrc = 0 AND <ls_stk>-labst <> 0.
        CONTINUE.
      ENDIF.
      INSERT <lcomp> INTO TABLE lt_comp_filtered.
    ENDLOOP.

    " Collect all materials for BOM section text/basic data
    DATA lt_all_bom TYPE ty_t_matnr.
    lt_all_bom = lt_fert_bom.
    LOOP AT lt_comp_filtered ASSIGNING FIELD-SYMBOL(<lc2>).
      INSERT <lc2> INTO TABLE lt_all_bom.
    ENDLOOP.
    IF lt_all_bom IS INITIAL.
      RETURN.
    ENDIF.

    SELECT
      a~matnr,
      a~mtart,
      a~matkl,
      a~meins
      FROM mara AS a
      FOR ALL ENTRIES IN @lt_all_bom
      WHERE a~matnr = @lt_all_bom-table_line
      INTO TABLE @lt_mara.

    lt_texts = get_texts( it_matnr = lt_all_bom ).

    " Build FERT BOM rows
    LOOP AT lt_fert_bom ASSIGNING FIELD-SYMBOL(<lfb>).
      CLEAR ls_bom.
      READ TABLE lt_mara ASSIGNING FIELD-SYMBOL(<la>) WITH KEY matnr = <lfb>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ls_bom-matnr = <la>-matnr.
      ls_bom-mtart = <la>-mtart.
      ls_bom-matkl = <la>-matkl.
      ls_bom-meins = <la>-meins.
      READ TABLE lt_texts ASSIGNING FIELD-SYMBOL(<ltx>) WITH KEY matnr = <la>-matnr spras = sy-langu.
      IF sy-subrc = 0.
        ls_bom-maktx = <ltx>-maktx.
      ENDIF.
      ls_bom-status = |완제품 BOM|.
      APPEND ls_bom TO rt_bom.
    ENDLOOP.

    " Build BOM-only component rows
    LOOP AT lt_comp_filtered ASSIGNING FIELD-SYMBOL(<lcf>).
      CLEAR ls_bom.
      READ TABLE lt_mara ASSIGNING <la> WITH KEY matnr = <lcf>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.
      ls_bom-matnr = <la>-matnr.
      ls_bom-mtart = <la>-mtart.
      ls_bom-matkl = <la>-matkl.
      ls_bom-meins = <la>-meins.
      READ TABLE lt_texts ASSIGNING <ltx> WITH KEY matnr = <la>-matnr spras = sy-langu.
      IF sy-subrc = 0.
        ls_bom-maktx = <ltx>-maktx.
      ENDIF.
      ls_bom-status = |BOM 만 있음|.
      APPEND ls_bom TO rt_bom.
    ENDLOOP.
  ENDMETHOD.

  METHOD display_alv.
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = it_tab ).
        lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>single ).
        lo_alv->get_display_settings( )->set_list_header( iv_title ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).