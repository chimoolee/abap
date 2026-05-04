REPORT ZAI_260504_1442.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_dlo   TYPE sy-datum DEFAULT sy-datum.
PARAMETERS p_dhi   TYPE sy-datum DEFAULT sy-datum.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_res,
             matnr       TYPE mara-matnr,
             mtart       TYPE mara-mtart,
             maktx       TYPE makt-maktx,
             has_mov     TYPE abap_bool,
             has_stock   TYPE abap_bool,
             status_text TYPE char20,
           END OF ty_res.
    TYPES ty_t_res TYPE STANDARD TABLE OF ty_res WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mara_s,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
           END OF ty_mara_s.
    TYPES ty_t_mara_s TYPE STANDARD TABLE OF ty_mara_s WITH EMPTY KEY.

    TYPES: BEGIN OF ty_makt_s,
             matnr TYPE makt-matnr,
             maktx TYPE makt-maktx,
           END OF ty_makt_s.
    TYPES ty_t_makt_s TYPE STANDARD TABLE OF ty_makt_s WITH EMPTY KEY.

    TYPES: BEGIN OF ty_parent,
             parent TYPE mara-matnr,
             stlnr  TYPE mast-stlnr,
           END OF ty_parent.
    TYPES ty_t_parent TYPE STANDARD TABLE OF ty_parent WITH EMPTY KEY.
    TYPES ty_t_stlnr TYPE STANDARD TABLE OF stpo-stlnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_bom_only,
             parent  TYPE mara-matnr,
             comp    TYPE mara-matnr,
             comp_tx TYPE makt-maktx,
             note    TYPE char20,
           END OF ty_bom_only.
    TYPES ty_t_bom_only TYPE STANDARD TABLE OF ty_bom_only WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stpo_map,
             stlnr TYPE stpo-stlnr,
             matnr TYPE mara-matnr,
           END OF ty_stpo_map.
    TYPES ty_t_stpo_map TYPE STANDARD TABLE OF ty_stpo_map WITH EMPTY KEY.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    IF p_dlo GT p_dhi.
      MESSAGE '시작일이 종료일보다 클 수 없습니다.' TYPE 'E'.
      RETURN.
    ENDIF.

    DATA lt_mov_matnr   TYPE ty_t_matnr.
    DATA lt_stock_matnr TYPE ty_t_matnr.
    DATA lt_all_matnr   TYPE ty_t_matnr.

    SELECT matdoc~matnr
      FROM matdoc
      WHERE matdoc~werks = @p_werks
        AND matdoc~budat BETWEEN @p_dlo AND @p_dhi
        AND matdoc~matnr IS NOT NULL
      INTO TABLE @lt_mov_matnr.
    SORT lt_mov_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_mov_matnr.

    SELECT mard~matnr
      FROM mard
      WHERE mard~werks = @p_werks
        AND mard~labst <> 0
        AND mard~matnr IS NOT NULL
      INTO TABLE @lt_stock_matnr.
    SORT lt_stock_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_stock_matnr.

    lt_all_matnr = lt_mov_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_all_matnr.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    DATA lt_res TYPE ty_t_res.

    IF lt_all_matnr IS NOT INITIAL.
      DATA lt_mara TYPE ty_t_mara_s.
      SELECT mara~matnr, mara~mtart
        FROM mara
        WHERE mara~matnr IN @lt_all_matnr
        INTO TABLE @lt_mara.

      DATA lt_makt TYPE ty_t_makt_s.
      SELECT makt~matnr, makt~maktx
        FROM makt
        WHERE makt~spras = @sy-langu
          AND makt~matnr IN @lt_all_matnr
        INTO TABLE @lt_makt.

      SORT lt_mara BY matnr.
      SORT lt_makt BY matnr.
      SORT lt_mov_matnr.
      SORT lt_stock_matnr.

      DATA ls_res TYPE ty_res.
      LOOP AT lt_mara ASSIGNING FIELD-SYMBOL(<ls_ma>).
        CLEAR ls_res.
        ls_res-matnr = <ls_ma>-matnr.
        ls_res-mtart = <ls_ma>-mtart.

        READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<ls_tx>)
          WITH KEY matnr = <ls_ma>-matnr BINARY SEARCH.
        IF sy-subrc = 0.
          ls_res-maktx = <ls_tx>-maktx.
        ENDIF.

        READ TABLE lt_mov_matnr WITH KEY table_line = <ls_ma>-matnr
          TRANSPORTING NO FIELDS BINARY SEARCH.
        ls_res-has_mov = xsdbool( sy-subrc = 0 ).

        READ TABLE lt_stock_matnr WITH KEY table_line = <ls_ma>-matnr
          TRANSPORTING NO FIELDS BINARY SEARCH.
        ls_res-has_stock = xsdbool( sy-subrc = 0 ).

        IF ls_res-has_mov = abap_true.
          ls_res-status_text = '입출고 있음'.
        ELSE.
          ls_res-status_text = '재고만 있음'.
        ENDIF.

        APPEND ls_res TO lt_res.
      ENDLOOP.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_res ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      value = '자재 목록 - 입출고 또는 재고 존재' ).
    lo_alv->display( ).

    DATA lt_parents TYPE ty_t_parent.
    SELECT mast~matnr AS parent, mast~stlnr
      FROM mast
      INNER JOIN mara AS ma
        ON ma~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND ma~mtart = 'FERT'
      INTO TABLE @lt_parents.
    SORT lt_parents BY stlnr.

    DATA lt_bom_only TYPE ty_t_bom_only.

    IF lt_parents IS NOT INITIAL.
      DATA lt_stlnr TYPE ty_t_stlnr.
      lt_stlnr = VALUE #( FOR ls IN lt_parents ( ls-stlnr ) ).

      DATA lt_comp_all TYPE ty_t_matnr.
      SELECT stpo~idnrk
        FROM stpo
        WHERE stpo~stlnr IN @lt_stlnr
          AND stpo~idnrk IS NOT NULL
        INTO TABLE @lt_comp_all.
      SORT lt_comp_all.
      DELETE ADJACENT DUPLICATES FROM lt_comp_all.

      SORT lt_mov_matnr.
      SORT lt_stock_matnr.

      DATA lt_bom_comp_only TYPE ty_t_matnr.
      LOOP AT lt_comp_all ASSIGNING FIELD-SYMBOL(<lv_cmat>).
        READ TABLE lt_mov_matnr WITH KEY table_line = <lv_cmat>
          TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.
        READ TABLE lt_stock_matnr WITH KEY table_line = <lv_cmat>
          TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.
        APPEND <lv_cmat> TO lt_bom_comp_only.
      ENDLOOP.
      SORT lt_bom_comp_only.
      DELETE ADJACENT DUPLICATES FROM lt_bom_comp_only.

      IF lt_bom_comp_only IS NOT INITIAL.
        DATA lt_comp_tx TYPE ty_t_makt_s.
        SELECT makt~matnr, makt~maktx
          FROM makt
          WHERE makt~spras = @sy-langu
            AND makt~matnr IN @lt_bom_comp_only
          INTO TABLE @lt_comp_tx.
        SORT lt_comp_tx BY matnr.

        DATA lt_map TYPE ty_t_stpo_map.
        SELECT stpo~stlnr, stpo~idnrk AS matnr
          FROM stpo
          WHERE stpo~stlnr IN @lt_stlnr
            AND stpo~idnrk IN @lt_bom_comp_only
          INTO TABLE @lt_map.
        SORT lt_map BY stlnr matnr.

        LOOP AT lt_map ASSIGNING FIELD-SYMBOL(<ls_map>).
          READ TABLE lt_parents ASSIGNING FIELD-SYMBOL(<ls_par>)
            WITH KEY stlnr = <ls_map>-stlnr BINARY SEARCH.
          IF sy-subrc <> 0.
            CONTINUE.
          ENDIF.

          DATA ls_bom TYPE ty_bom_only.
          ls_bom-parent = <ls_par>-parent.
          ls_bom-comp   = <ls_map>-matnr.

          READ TABLE lt_comp_tx ASSIGNING FIELD-SYMBOL(<ls_ctx>)
            WITH KEY matnr = <ls_map>-matnr BINARY SEARCH.
          IF sy-subrc = 0.
            ls_bom-comp_tx = <ls_ctx>-maktx.
          ENDIF.

          ls_bom-note = 'BOM 만 있음'.
          APPEND ls_bom TO lt_bom_only.
        ENDLOOP.
      ENDIF.
    ENDIF.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_bom_only ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      value = '완제품 BOM 요소 - 재고/실적 없음 (BOM 만 있음)' ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).