REPORT ZAI_260504_1657.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR mkpf-budat OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_result,
             matnr    TYPE mara-matnr,
             mtart    TYPE mara-mtart,
             meins    TYPE mara-meins,
             maktx    TYPE makt-maktx,
             category TYPE char30,
           END OF ty_result.
    TYPES ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.
    TYPES ty_t_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mat_mov     TYPE ty_t_matnr.
    DATA lt_mat_stock   TYPE ty_t_matnr.
    DATA lt_mat_bomcomp TYPE ty_t_matnr.
    DATA lt_all_mat     TYPE ty_t_matnr.
    DATA lt_final       TYPE ty_t_result.
    DATA ls_res         TYPE ty_result.

    IF s_budat[] IS INITIAL.
      DATA(lv_from) = sy-datum - 30.
      DATA(lv_to)   = sy-datum.
      APPEND VALUE #( sign = 'I' option = 'BT' low = lv_from high = lv_to ) TO s_budat.
    ENDIF.

    SELECT DISTINCT s~matnr
      FROM mseg AS s
      INNER JOIN mkpf AS h
        ON h~mblnr = s~mblnr
       AND h~mjahr = s~mjahr
      WHERE s~werks = @p_werks
        AND h~budat IN @s_budat
      INTO TABLE @lt_mat_mov.

    SELECT DISTINCT d~matnr
      FROM mard AS d
      WHERE d~werks = @p_werks
        AND d~labst > 0
      INTO TABLE @lt_mat_stock.

    SELECT DISTINCT stpo~idnrk
      FROM mast AS m
      INNER JOIN mara AS mh
        ON mh~matnr = m~matnr
      INNER JOIN stpo AS stpo
        ON stpo~stlnr = m~stlnr
      WHERE m~werks = @p_werks
        AND mh~mtart = 'FERT'
      INTO TABLE @lt_mat_bomcomp.

    LOOP AT lt_mat_mov INTO DATA(lv_matnr_a).
      CLEAR ls_res.
      ls_res-matnr    = lv_matnr_a.
      ls_res-category = '입출고실적 있음'.
      APPEND ls_res TO lt_final.
      APPEND lv_matnr_a TO lt_all_mat.
    ENDLOOP.

    LOOP AT lt_mat_stock INTO DATA(lv_matnr_b).
      IF line_exists( lt_all_mat[ table_line = lv_matnr_b ] ).
        CONTINUE.
      ENDIF.
      CLEAR ls_res.
      ls_res-matnr    = lv_matnr_b.
      ls_res-category = '재고만 있음'.
      APPEND ls_res TO lt_final.
      APPEND lv_matnr_b TO lt_all_mat.
    ENDLOOP.

    LOOP AT lt_mat_bomcomp INTO DATA(lv_matnr_c).
      IF line_exists( lt_all_mat[ table_line = lv_matnr_c ] ).
        CONTINUE.
      ENDIF.
      CLEAR ls_res.
      ls_res-matnr    = lv_matnr_c.
      ls_res-category = 'BOM 에 만 있음'.
      APPEND ls_res TO lt_final.
      APPEND lv_matnr_c TO lt_all_mat.
    ENDLOOP.

    IF lt_all_mat IS NOT INITIAL.
      SELECT a~matnr, a~mtart, a~meins
        FROM mara AS a
        FOR ALL ENTRIES IN @lt_all_mat
        WHERE a~matnr = @lt_all_mat-table_line
        INTO TABLE @DATA(lt_mara).

      SELECT t~matnr, t~maktx
        FROM makt AS t
        FOR ALL ENTRIES IN @lt_all_mat
        WHERE t~matnr = @lt_all_mat-table_line
          AND t~spras = @sy-langu
        INTO TABLE @DATA(lt_makt).

      SORT lt_mara BY matnr.
      SORT lt_makt BY matnr.

      LOOP AT lt_final INTO ls_res.
        READ TABLE lt_mara INTO DATA(ls_mara)
          WITH KEY matnr = ls_res-matnr BINARY SEARCH.
        IF sy-subrc = 0.
          ls_res-mtart = ls_mara-mtart.
          ls_res-meins = ls_mara-meins.
        ENDIF.
        READ TABLE lt_makt INTO DATA(ls_makt)
          WITH KEY matnr = ls_res-matnr BINARY SEARCH.
        IF sy-subrc = 0.
          ls_res-maktx = ls_makt-maktx.
        ENDIF.
        MODIFY lt_final FROM ls_res.
      ENDLOOP.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_final
    ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).