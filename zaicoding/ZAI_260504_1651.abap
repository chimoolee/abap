REPORT ZAI_260504_1651.

SELECT-OPTIONS s_budat FOR mkpf-budat.
PARAMETERS p_werks TYPE werks_d OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_stock_sum,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock_sum.
    TYPES ty_t_stock_sum TYPE STANDARD TABLE OF ty_stock_sum WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mat_info,
             matnr TYPE mara-matnr,
             meins TYPE mara-meins,
             maktx TYPE makt-maktx,
           END OF ty_mat_info.
    TYPES ty_t_mat_info TYPE STANDARD TABLE OF ty_mat_info WITH EMPTY KEY.

    TYPES: BEGIN OF ty_result,
             section TYPE char12,
             matnr   TYPE mara-matnr,
             maktx   TYPE makt-maktx,
             werks   TYPE werks_d,
             qty     TYPE mard-labst,
             meins   TYPE mara-meins,
             remark  TYPE char20,
           END OF ty_result.
    TYPES ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_sum TYPE ty_t_stock_sum.
    DATA lt_all_main  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_comp  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_info_main TYPE ty_t_mat_info.
    DATA lt_info_bom  TYPE ty_t_mat_info.
    DATA lt_display   TYPE ty_t_result.

    DATA ls_res       TYPE ty_result.
    DATA ls_stock     TYPE ty_stock_sum.
    DATA ls_info      TYPE ty_mat_info.

    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
     WHERE mseg~werks = @p_werks
       AND mkpf~budat IN @s_budat
      INTO TABLE @lt_mov_matnr.

    SORT lt_mov_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_mov_matnr.

    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
     WHERE mard~werks = @p_werks
     GROUP BY mard~matnr
    HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock_sum.

    lt_all_main = lt_mov_matnr.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    LOOP AT lt_stock_sum INTO ls_stock.
      APPEND ls_stock-matnr TO lt_stock_matnr.
    ENDLOOP.
    APPEND LINES OF lt_stock_matnr TO lt_all_main.
    SORT lt_all_main.
    DELETE ADJACENT DUPLICATES FROM lt_all_main.

    IF lt_all_main IS NOT INITIAL.
      SELECT a~matnr,
             a~meins,
             t~maktx
        FROM mara AS a
        LEFT OUTER JOIN makt AS t
          ON t~matnr = a~matnr
         AND t~spras = @sy-langu
       WHERE a~matnr IN @lt_all_main
        INTO TABLE @lt_info_main.
    ENDIF.

    SORT lt_stock_sum BY matnr.
    SORT lt_info_main BY matnr.

    LOOP AT lt_all_main INTO DATA(lv_matnr).
      CLEAR ls_res.
      ls_res-section = '메인'.
      ls_res-matnr   = lv_matnr.
      ls_res-werks   = p_werks.
      READ TABLE lt_info_main INTO ls_info
           WITH KEY matnr = lv_matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-meins = ls_info-meins.
        ls_res-maktx = ls_info-maktx.
      ENDIF.
      READ TABLE lt_stock_sum INTO ls_stock
           WITH KEY matnr = lv_matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-qty = ls_stock-qty.
      ELSE.
        CLEAR ls_res-qty.
      ENDIF.
      READ TABLE lt_mov_matnr WITH KEY table_line = lv_matnr
           TRANSPORTING NO FIELDS BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-remark = '입출고 실적 있음'.
      ELSE.
        ls_res-remark = '재고만 있음'.
      ENDIF.
      APPEND ls_res TO lt_display.
    ENDLOOP.

    SELECT DISTINCT stpo~idnrk
      FROM mast
      INNER JOIN mara AS mh
        ON mh~matnr = mast~matnr
      INNER JOIN stpo
        ON stpo~stlnr = mast~stlnr
     WHERE mast~werks = @p_werks
       AND mh~mtart  = 'FERT'
      INTO TABLE @lt_bom_comp.

    SORT lt_bom_comp.
    DELETE ADJACENT DUPLICATES FROM lt_bom_comp.

    IF lt_bom_comp IS NOT INITIAL AND lt_all_main IS NOT INITIAL.
      DATA lt_bom_only TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
      DATA lv_comp TYPE mara-matnr.
      LOOP AT lt_bom_comp INTO lv_comp.
        READ TABLE lt_all_main WITH KEY table_line = lv_comp
             TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc <> 0.
          APPEND lv_comp TO lt_bom_only.
        ENDIF.
      ENDLOOP.
      lt_bom_comp = lt_bom_only.
    ENDIF.

    IF lt_bom_comp IS NOT INITIAL.
      DATA lt_bom_final TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
      LOOP AT lt_bom_comp INTO DATA(lv_bmat).
        READ TABLE lt_stock_sum WITH KEY matnr = lv_bmat
             TRANSPORTING NO FIELDS BINARY SEARCH.
        IF sy-subrc <> 0.
          APPEND lv_bmat TO lt_bom_final.
        ENDIF.
      ENDLOOP.
      lt_bom_comp = lt_bom_final.
    ENDIF.

    IF lt_bom_comp IS NOT INITIAL.
      SELECT a~matnr,
             a~meins,
             t~maktx
        FROM mara AS a
        LEFT OUTER JOIN makt AS t
          ON t~matnr = a~matnr
         AND t~spras = @sy-langu
       WHERE a~matnr IN @lt_bom_comp
        INTO TABLE @lt_info_bom.

      SORT lt_info_bom BY matnr.

      LOOP AT lt_bom_comp INTO DATA(lv_bonly).
        CLEAR ls_res.
        ls_res-section = 'BOM 전용'.
        ls_res-matnr   = lv_bonly.
        ls_res-werks   = p_werks.
        ls_res-qty     = 0.
        READ TABLE lt_info_bom INTO ls_info
             WITH KEY matnr = lv_bonly BINARY SEARCH.
        IF sy-subrc = 0.
          ls_res-meins = ls_info-meins.
          ls_res-maktx = ls_info-maktx.
        ENDIF.
        ls_res-remark  = 'BOM 에 만 있음'.
        APPEND ls_res TO lt_display.
      ENDLOOP.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_display ).

    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      '자재 목록 - 메인(입출고/재고) 및 BOM 전용' && '' ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).