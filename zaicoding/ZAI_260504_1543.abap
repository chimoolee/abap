REPORT ZAI_260504_1543.

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
             stock TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mm,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             meins TYPE mara-meins,
             maktx TYPE makt-maktx,
           END OF ty_mm.
    TYPES ty_t_mm TYPE STANDARD TABLE OF ty_mm WITH EMPTY KEY.

    TYPES: BEGIN OF ty_main,
             matnr  TYPE mara-matnr,
             mtart  TYPE mara-mtart,
             maktx  TYPE makt-maktx,
             stock  TYPE mard-labst,
             status TYPE char20,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    TYPES: BEGIN OF ty_bom_pair,
             header TYPE mara-matnr,
             comp   TYPE mara-matnr,
           END OF ty_bom_pair.
    TYPES ty_t_bom_pair TYPE STANDARD TABLE OF ty_bom_pair WITH EMPTY KEY.

    TYPES: BEGIN OF ty_bom_only,
             comp_matnr   TYPE mara-matnr,
             comp_text    TYPE makt-maktx,
             header_matnr TYPE mara-matnr,
             header_text  TYPE makt-maktx,
             remark       TYPE char20,
           END OF ty_bom_only.
    TYPES ty_t_bom_only TYPE STANDARD TABLE OF ty_bom_only WITH EMPTY KEY.

    CLASS-METHODS get_mov_mat
      IMPORTING
        VALUE(i_werks) TYPE werks_d
        VALUE(i_begda) TYPE sy-datum
        VALUE(i_endda) TYPE sy-datum
      RETURNING
        VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stock_by_mat
      IMPORTING
        VALUE(i_werks) TYPE werks_d
      RETURNING
        VALUE(rt_stock) TYPE ty_t_stock.

    CLASS-METHODS get_mara_makt
      IMPORTING
        VALUE(it_matnr) TYPE ty_t_matnr
      RETURNING
        VALUE(rt_mm) TYPE ty_t_mm.

    CLASS-METHODS build_main_list
      IMPORTING
        VALUE(it_mm)     TYPE ty_t_mm
        VALUE(it_mov)    TYPE ty_t_matnr
        VALUE(it_stock)  TYPE ty_t_stock
      RETURNING
        VALUE(rt_main) TYPE ty_t_main.

    CLASS-METHODS get_bom_pairs_for_fert
      IMPORTING
        VALUE(i_werks) TYPE werks_d
      RETURNING
        VALUE(rt_pairs) TYPE ty_t_bom_pair.

    CLASS-METHODS build_bom_only
      IMPORTING
        VALUE(it_pairs) TYPE ty_t_bom_pair
        VALUE(it_mov)   TYPE ty_t_matnr
        VALUE(it_stock) TYPE ty_t_stock
      RETURNING
        VALUE(rt_bom_only) TYPE ty_t_bom_only.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mov    TYPE ty_t_matnr.
    DATA lt_stock  TYPE ty_t_stock.
    DATA lt_all    TYPE ty_t_matnr.
    DATA lt_mm     TYPE ty_t_mm.
    DATA lt_main   TYPE ty_t_main.
    DATA lt_pairs  TYPE ty_t_bom_pair.
    DATA lt_bom    TYPE ty_t_bom_only.
    DATA lo_alv    TYPE REF TO cl_salv_table.

    lt_mov = get_mov_mat( i_werks = p_werks i_begda = p_begda i_endda = p_endda ).
    lt_stock = get_stock_by_mat( i_werks = p_werks ).

    " Build union list of materials from movements and stock
    lt_all = lt_mov.
    DATA ls_stock TYPE ty_stock.
    LOOP AT lt_stock INTO ls_stock.
      APPEND ls_stock-matnr TO lt_all.
    ENDLOOP.
    SORT lt_all.
    DELETE ADJACENT DUPLICATES FROM lt_all.

    IF lt_all IS NOT INITIAL.
      lt_mm = get_mara_makt( it_matnr = lt_all ).
      lt_main = build_main_list( it_mm = lt_mm it_mov = lt_mov it_stock = lt_stock ).

      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_main ).
      lo_alv->get_display_settings( )->set_list_header(
        value = |플랜트 { p_werks } 자재 현황: 기간 { p_begda } ~ { p_endda }| ).
      lo_alv->display( ).
    ENDIF.

    " BOM-only section for finished goods
    lt_pairs = get_bom_pairs_for_fert( i_werks = p_werks ).
    IF lt_pairs IS NOT INITIAL.
      lt_bom = build_bom_only( it_pairs = lt_pairs it_mov = lt_mov it_stock = lt_stock ).
      IF lt_bom IS NOT INITIAL.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_bom ).
        lo_alv->get_display_settings( )->set_list_header(
          value = |플랜트 { p_werks } BOM 요소 목록 (재고/입출고 없음: "BOM 만 있음")| ).
        lo_alv->display( ).
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD get_mov_mat.
    DATA lt_mat TYPE ty_t_matnr.
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mseg~werks = @i_werks
        AND mkpf~budat BETWEEN @i_begda AND @i_endda
      INTO TABLE @lt_mat.
    rt_matnr = lt_mat.
  ENDMETHOD.

  METHOD get_stock_by_mat.
    DATA lt_stock TYPE ty_t_stock.
    SELECT mard~matnr,
           SUM( mard~labst ) AS stock
      FROM mard
      WHERE mard~werks = @i_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.
    rt_stock = lt_stock.
  ENDMETHOD.

  METHOD get_mara_makt.
    DATA lt_mm TYPE ty_t_mm.
    IF it_matnr IS INITIAL.
      rt_mm = lt_mm.
      RETURN.
    ENDIF.
    SELECT mara~matnr,
           mara~mtart,
           mara~meins,
           makt~maktx
      FROM mara
      LEFT OUTER JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      WHERE mara~matnr IN @it_matnr
      INTO TABLE @lt_mm.
    rt_mm = lt_mm.
  ENDMETHOD.

  METHOD build_main_list.
    DATA lt_main TYPE ty_t_main.
    DATA: ls_mm    TYPE ty_mm,
          ls_main  TYPE ty_main,
          ls_stock TYPE ty_stock.

    DATA lt_mov_s TYPE ty_t_matnr.
    DATA lt_stock_s TYPE ty_t_stock.
    lt_mov_s = it_mov.
    lt_stock_s = it_stock.
    SORT lt_mov_s.
    SORT lt_stock_s BY matnr.

    LOOP AT it_mm INTO ls_mm.
      CLEAR ls_main.
      ls_main-matnr = ls_mm-matnr.
      ls_main-mtart = ls_mm-mtart.
      ls_main-maktx = ls_mm-maktx.

      READ TABLE lt_stock_s INTO ls_stock WITH KEY matnr = ls_mm-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_main-stock = ls_stock-stock.
      ELSE.
        ls_main-stock = 0.
      ENDIF.

      DATA lv_in_mov TYPE abap_bool.
      lv_in_mov = abap_false.
      READ TABLE lt_mov_s WITH KEY table_line = ls_mm-matnr TRANSPORTING NO FIELDS
           BINARY SEARCH.
      IF sy-subrc = 0.
        lv_in_mov = abap_true.
      ENDIF.

      IF lv_in_mov = abap_true AND ls_main-stock <> 0.
        ls_main-status = '입출고+재고'.
      ELSEIF lv_in_mov = abap_true.
        ls_main-status = '입출고 있음'.
      ELSE.
        ls_main-status = '재고만 있음'.
      ENDIF.

      APPEND ls_main TO lt_main.
    ENDLOOP.

    SORT lt_main BY matnr.
    rt_main = lt_main.
  ENDMETHOD.

  METHOD get_bom_pairs_for_fert.
    DATA lt_pairs TYPE ty_t_bom_pair.
    " Headers: FERT with BOM in plant
    SELECT stko~matnr AS header,
           stpo~idnrk AS comp
      FROM stko
      INNER JOIN stpo
        ON stpo~stlnr = stko~stlnr
      INNER JOIN mara
        ON mara~matnr = stko~matnr
      WHERE stko~werks = @i_werks
        AND mara~mtart = @'FERT'
      INTO TABLE @lt_pairs.
    DELETE ADJACENT DUPLICATES FROM lt_pairs COMPARING header comp.
    rt_pairs = lt_pairs.
  ENDMETHOD.

  METHOD build_bom_only.
    DATA lt_bom TYPE ty_t_bom_only.
    DATA lt_mov_s TYPE ty_t_matnr.
    DATA lt_stock_s TYPE ty_t_stock.
    lt_mov_s = it_mov.
    lt_stock_s = it_stock.
    SORT lt_mov_s.
    SORT lt_stock_s BY matnr.

    " Collect unique component and header matnrs for text retrieval
    DATA lt_comp TYPE ty_t_matnr.
    DATA lt_head TYPE ty_t_matnr.
    DATA ls_pair TYPE ty_bom_pair.
    LOOP AT it_pairs INTO ls_pair.
      APPEND ls_pair-comp TO lt_comp.
      APPEND ls_pair-header TO lt_head.
    ENDLOOP.
    SORT lt_comp.
    DELETE ADJACENT DUPLICATES FROM lt_comp.
    SORT lt_head.
    DELETE ADJACENT DUPLICATES FROM lt_head.

    " Fetch texts
    DATA lt_comp_mm TYPE ty_t_mm.
    DATA lt_head_mm TYPE ty_t_mm.
    IF lt_comp IS NOT INITIAL.
      lt_comp_mm = get_mara_makt( it_matnr = lt_comp ).
    ENDIF.
    IF lt_head IS NOT INITIAL.
      lt_head_mm = get_mara_makt( it_matnr = lt_head ).
    ENDIF.
    SORT lt_comp_mm BY matnr.
    SORT lt_head_mm BY matnr.

    DATA ls_bom TYPE ty_bom_only.
    DATA ls_stock TYPE ty_stock.
    DATA ls_cmm TYPE ty_mm.
    DATA ls_hmm TYPE ty_mm.
    LOOP AT it_pairs INTO ls_pair.
      " Skip component if it has movement or non-zero stock
      READ TABLE lt_mov_s WITH KEY table_line = ls_pair-comp
           TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.
      READ TABLE lt_stock_s INTO ls_stock WITH KEY matnr = ls_pair-comp
           BINARY SEARCH.
      IF sy-subrc = 0 AND ls_stock-stock <> 0.
        CONTINUE.
      ENDIF.

      CLEAR ls_bom.
      ls_bom-comp_matnr = ls_pair-comp.
      READ TABLE lt_comp_mm