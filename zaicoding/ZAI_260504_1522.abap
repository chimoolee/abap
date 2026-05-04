REPORT ZAI_260504_1522.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_datef TYPE sy-datum DEFAULT sy-datum OBLIGATORY.
PARAMETERS p_datet TYPE sy-datum DEFAULT sy-datum OBLIGATORY.
PARAMETERS p_year  TYPE char4 DEFAULT sy-datum(4).

INITIALIZATION.
  p_datef = sy-datum - 30.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES ty_t_matnr_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.

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
             category  TYPE char10,
             matnr     TYPE mara-matnr,
             werks     TYPE mard-werks,
             mtart     TYPE mara-mtart,
             maktx     TYPE makt-maktx,
             stock_qty TYPE mard-labst,
             has_move  TYPE abap_bool,
             status    TYPE char20,
           END OF ty_sec.
    TYPES ty_t_sec TYPE STANDARD TABLE OF ty_sec WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mard_sel,
             matnr TYPE mara-matnr,
             werks TYPE mard-werks,
             lgort TYPE mard-lgort,
             labst TYPE mard-labst,
           END OF ty_mard_sel.
    TYPES ty_t_mard_sel TYPE STANDARD TABLE OF ty_mard_sel WITH EMPTY KEY.

    TYPES: BEGIN OF ty_makt_sel,
             matnr TYPE mara-matnr,
             spras TYPE sylangu,
             maktx TYPE makt-maktx,
           END OF ty_makt_sel.
    TYPES ty_t_makt_sel TYPE STANDARD TABLE OF ty_makt_sel WITH EMPTY KEY.

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
        VALUE(rt_stock) TYPE ty_t_mard_sel.

    CLASS-METHODS get_maktx
      IMPORTING
        !it_matnr TYPE ty_t_matnr
      RETURNING
        VALUE(rt_texts) TYPE ty_t_makt_sel.

    CLASS-METHODS get_fg_with_bom
      IMPORTING
        !iv_werks TYPE werks_d
      RETURNING
        VALUE(rt_fg) TYPE ty_t_matnr.

    CLASS-METHODS get_bom_components_only
      IMPORTING
        !iv_werks  TYPE werks_d
        !it_exclude TYPE ty_t_matnr
      RETURNING
        VALUE(rt_comp) TYPE ty_t_matnr.

    CLASS-METHODS to_set
      IMPORTING
        !it_tab TYPE ty_t_matnr
      RETURNING
        VALUE(rt_set) TYPE ty_t_matnr_set.

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

    DATA(lt_mov_matnr) = get_mov_matnrs(
      iv_werks = lv_werks
      iv_datef = lv_datef
      iv_datet = lv_datet ).

    DATA(lt_mard) = get_stock_by_matnr( iv_werks = lv_werks ).

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

    DATA lt_main TYPE ty_t_main.
    DATA lt_main_matnr TYPE lcl_app=>ty_t_matnr.

    LOOP AT lt_mov_matnr ASSIGNING FIELD-SYMBOL(<lv_mmatnr>).
      APPEND <lv_mmatnr> TO lt_main_matnr.
    ENDLOOP.

    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      IF <ls_stk>-qty IS NOT INITIAL.
        APPEND <ls_stk>-matnr TO lt_main_matnr.
      ENDIF.
    ENDLOOP.

    DATA lt_main_set TYPE lcl_app=>ty_t_matnr_set.
    lt_main_set = to_set( lt_main_matnr ).

    DATA lt_main_keys TYPE lcl_app=>ty_t_matnr.
    LOOP AT lt_main_set ASSIGNING FIELD-SYMBOL(<lv_mn>).
      APPEND <lv_mn> TO lt_main_keys.
    ENDLOOP.

    TYPES: BEGIN OF ty_mara_sel,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
           END OF ty_mara_sel.
    TYPES ty_t_mara_sel TYPE STANDARD TABLE OF ty_mara_sel WITH EMPTY KEY.
    DATA lt_mara TYPE ty_t_mara_sel.

    IF lt_main_keys IS NOT INITIAL.
      SELECT mara~matnr, mara~mtart
        FROM mara
        WHERE mara~matnr IN @lt_main_keys
        INTO TABLE @lt_mara.
    ENDIF.

    DATA lt_makt TYPE ty_t_makt_sel.
    lt_makt = get_maktx( lt_main_keys ).

    DATA lt_mov_set TYPE lcl_app=>ty_t_matnr_set.
    lt_mov_set = to_set( lt_mov_matnr ).

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
        CONTINUE.
      ENDIF.

      APPEND ls_main TO lt_main.
    ENDLOOP.

    DATA lt_fg_bom TYPE lcl_app=>ty_t_matnr.
    lt_fg_bom = get_fg_with_bom( iv_werks = lv_werks ).

    DATA lt_bom_only TYPE lcl_app=>ty_t_matnr.
    lt_bom_only = get_bom_components_only(
      iv_werks  = lv_werks
      it_exclude = lt_main_keys ).

    DATA lt_sec_keys TYPE lcl_app=>ty_t_matnr.
    LOOP AT lt_fg_bom ASSIGNING FIELD-SYMBOL(<lv_fg>).
      APPEND <lv_fg> TO lt_sec_keys.
    ENDLOOP.
    LOOP AT lt_bom_only ASSIGNING FIELD-SYMBOL(<lv_bo>).
      APPEND <lv_bo> TO lt_sec_keys.
    ENDLOOP.

    DATA lt_sec_set TYPE lcl_app=>ty_t_matnr_set.
    lt_sec_set = to_set( lt_sec_keys ).

    DATA lt_sec_keys_u TYPE lcl_app=>ty_t_matnr.
    LOOP AT lt_sec_set ASSIGNING FIELD-SYMBOL(<lv_sk>).
      APPEND <lv_sk> TO lt_sec_keys_u.
    ENDLOOP.

    DATA lt_mara_sec TYPE ty_t_mara_sel.
    IF lt_sec_keys_u IS NOT INITIAL.
      SELECT mara~matnr, mara~mtart
        FROM mara
        WHERE mara~matnr IN @lt_sec_keys_u
        INTO TABLE @lt_mara_sec.
    ENDIF.

    DATA lt_makt_sec TYPE ty_t_makt_sel.
    lt_makt_sec = get_maktx( lt_sec_keys_u ).

    DATA lt_sec TYPE ty_t_sec.

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
    DATA lt_mard TYPE ty_t_mard_sel.
    SELECT mard~matnr, mard~werks, mard~lgort, mard~labst
      FROM mard
      WHERE mard~werks = @iv_werks
      INTO TABLE @lt_mard.
    rt_stock = lt_mard.
  ENDMETHOD.

  METHOD get_maktx.
    DATA lt_makt TYPE ty_t_makt_sel.
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
    DATA lt_comp TYPE ty_t_matnr.
    SELECT DISTINCT stpo~idnrk
      FROM mast
      INNER JOIN stpo
        ON stpo~stlnr = mast~stlnr
      WHERE mast~werks = @iv_werks
        AND stpo~idnrk <> ''
      INTO TABLE @lt_comp.

    IF lt_comp IS NOT INITIAL AND it_exclude IS NOT INITIAL.
      DATA lt_ex_set TYPE lcl_app=>ty_t_matnr_set.
      lt_ex_set = to_set( it_exclude ).
      DELETE lt_comp WHERE table_line IN lt_ex_set.
    ENDIF.

    rt_comp = lt_comp.
  ENDMETHOD.

  METHOD to_set.
    DATA lt_set TYPE ty_t_matnr_set.
    LOOP AT it_tab ASSIGNING FIELD-SYMBOL(<lv>).
      INSERT <lv> INTO TABLE lt_set.
    ENDLOOP.
    rt_set = lt_set.
  ENDMETHOD.

  METHOD display_main.
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = it_data ).
        lo_alv->get_display_settings( )->set_list_header(
          value = |메인 목록: 입출고 실적 있거나 재고 보유 자재| ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'ALV 표시 중 오류가 발생했습니다.' TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD display_sec.
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = it_data ).
        lo_alv->get_display_settings( )->set_list_header(
          value = |별도 섹션: BOM 관련 자재 (완제품 및 BOM 전용)| ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'ALV 표시 중 오류가 발생했습니다.' TYPE 'E'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).