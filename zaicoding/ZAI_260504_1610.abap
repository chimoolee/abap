REPORT ZAI_260504_1610.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE mkpf-budat OBLIGATORY.
PARAMETERS p_endda TYPE mkpf-budat OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lo_alv TYPE REF TO cl_salv_table.

    TYPES:
      ty_matnr_tab TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY,
      BEGIN OF ty_row1,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        meins  TYPE mara-meins,
        maktx  TYPE makt-maktx,
        labst  TYPE mard-labst,
        status TYPE c LENGTH 20,
      END OF ty_row1,
      ty_t_row1 TYPE STANDARD TABLE OF ty_row1 WITH EMPTY KEY,
      BEGIN OF ty_row2,
        matnr_fert TYPE mara-matnr,
        matnr_comp TYPE mara-matnr,
        comp_maktx TYPE makt-maktx,
        meins      TYPE mara-meins,
        status     TYPE c LENGTH 20,
      END OF ty_row2,
      ty_t_row2 TYPE STANDARD TABLE OF ty_row2 WITH EMPTY KEY.

    DATA lt_move_mats TYPE ty_matnr_tab.
    DATA lt_stock_mats TYPE ty_matnr_tab.
    DATA lt_all_mats TYPE ty_matnr_tab.
    DATA lt_out1 TYPE ty_t_row1.
    DATA lt_out2 TYPE ty_t_row2.

    " Materials with movements in period for plant
    SELECT DISTINCT
      ms~matnr
      FROM mseg AS ms
      INNER JOIN mkpf AS mk
        ON mk~mblnr = ms~mblnr
       AND mk~mjahr = ms~mjahr
     WHERE ms~werks = @p_werks
       AND mk~budat BETWEEN @p_begda AND @p_endda
      INTO TABLE @lt_move_mats.

    " Materials with current stock <> 0 in plant
    SELECT DISTINCT
      md~matnr
      FROM mard AS md
     WHERE md~werks = @p_werks
       AND md~labst <> 0
      INTO TABLE @lt_stock_mats.

    " Union of both sets
    lt_all_mats = lt_move_mats.
    APPEND LINES OF lt_stock_mats TO lt_all_mats.
    SORT lt_all_mats BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_all_mats.

    " Master data for all materials
    TYPES: BEGIN OF ty_mdat,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             meins TYPE mara-meins,
             maktx TYPE makt-maktx,
           END OF ty_mdat.
    TYPES ty_t_mdat TYPE STANDARD TABLE OF ty_mdat WITH EMPTY KEY.
    DATA lt_mdat TYPE ty_t_mdat.

    IF lt_all_mats IS NOT INITIAL.
      SELECT ma~matnr,
             ma~mtart,
             ma~meins,
             mt~maktx
        FROM mara AS ma
        LEFT OUTER JOIN makt AS mt
          ON mt~matnr = ma~matnr
         AND mt~spras = @sy-langu
       FOR ALL ENTRIES IN @lt_all_mats
       WHERE ma~matnr = @lt_all_mats-table_line
        INTO TABLE @lt_mdat.
    ENDIF.

    " Stock quantities per material in plant
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    DATA lt_stock TYPE ty_t_stock.

    IF lt_all_mats IS NOT INITIAL.
      SELECT md~matnr,
             SUM( md~labst ) AS labst
        FROM mard AS md
       WHERE md~werks = @p_werks
         AND md~matnr IN @lt_all_mats
       GROUP BY md~matnr
        INTO TABLE @lt_stock.
    ENDIF.

    " Build first output list with status
    DATA ls_row1 TYPE ty_row1.
    LOOP AT lt_all_mats INTO DATA(lv_matnr).
      CLEAR ls_row1.
      ls_row1-matnr = lv_matnr.
      READ TABLE lt_mdat INTO DATA(ls_mdat) WITH KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        ls_row1-mtart = ls_mdat-mtart.
        ls_row1-meins = ls_mdat-meins.
        ls_row1-maktx = ls_mdat-maktx.
      ENDIF.
      READ TABLE lt_stock INTO DATA(ls_stk) WITH KEY matnr = lv_matnr.
      IF sy-subrc = 0.
        ls_row1-labst = ls_stk-labst.
      ELSE.
        ls_row1-labst = 0.
      ENDIF.
      DATA(lv_has_move) = abap_false.
      READ TABLE lt_move_mats WITH KEY table_line = lv_matnr TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_move = abap_true.
      ENDIF.
      IF lv_has_move = abap_true.
        ls_row1-status = '입출고 있음'.
      ELSEIF ls_row1-labst <> 0.
        ls_row1-status = '재고만 있음'.
      ELSE.
        ls_row1-status = '상태 없음'.
      ENDIF.
      APPEND ls_row1 TO lt_out1.
    ENDLOOP.

    SORT lt_out1 BY matnr.

    " BOM-based section
    TYPES: BEGIN OF ty_fert_hdr,
             matnr TYPE mara-matnr,
           END OF ty_fert_hdr.
    TYPES ty_t_fert_hdr TYPE STANDARD TABLE OF ty_fert_hdr WITH EMPTY KEY.
    DATA lt_fert_hdr TYPE ty_t_fert_hdr.

    SELECT DISTINCT
      ma~matnr
      FROM mast AS ma
      INNER JOIN mara AS mr
        ON mr~matnr = ma~matnr
     WHERE ma~werks = @p_werks
       AND mr~mtart = 'FERT'
      INTO TABLE @lt_fert_hdr.

    DATA lt_comp_mat TYPE ty_matnr_tab.
    IF lt_fert_hdr IS NOT INITIAL.
      SELECT DISTINCT
        ma~matnr AS matnr_fert,
        sp~idnrk  AS matnr_comp
        FROM mast AS ma
        INNER JOIN stpo AS sp
          ON sp~stlty = ma~stlty
         AND sp~stlnr = ma~stlnr
         AND sp~stlal = ma~stlal
       FOR ALL ENTRIES IN @lt_fert_hdr
       WHERE ma~matnr = @lt_fert_hdr-matnr
        INTO TABLE @DATA(lt_fert_comp).

      IF lt_fert_comp IS NOT INITIAL.
        LOOP AT lt_fert_comp INTO DATA(ls_fc).
          APPEND ls_fc-matnr_comp TO lt_comp_mat.
        ENDLOOP.
        SORT lt_comp_mat BY table_line.
        DELETE ADJACENT DUPLICATES FROM lt_comp_mat.
      ENDIF.
    ENDIF.

    DATA lt_comp_stock TYPE ty_t_stock.
    IF lt_comp_mat IS NOT INITIAL.
      SELECT md~matnr,
             SUM( md~labst ) AS labst
        FROM mard AS md
       WHERE md~werks = @p_werks
         AND md~matnr IN @lt_comp_mat
       GROUP BY md~matnr
        INTO TABLE @lt_comp_stock.
    ENDIF.

    DATA lt_comp_move TYPE ty_matnr_tab.
    IF lt_comp_mat IS NOT INITIAL.
      SELECT DISTINCT
        ms~matnr
        FROM mseg AS ms
        INNER JOIN mkpf AS mk
          ON mk~mblnr = ms~mblnr
         AND mk~mjahr = ms~mjahr
       WHERE ms~werks = @p_werks
         AND mk~budat BETWEEN @p_begda AND @p_endda
         AND ms~matnr IN @lt_comp_mat
        INTO TABLE @lt_comp_move.
    ENDIF.

    DATA lt_comp_mdat TYPE ty_t_mdat.
    IF lt_comp_mat IS NOT INITIAL.
      SELECT ma~matnr,
             ma~mtart,
             ma~meins,
             mt~maktx
        FROM mara AS ma
        LEFT OUTER JOIN makt AS mt
          ON mt~matnr = ma~matnr
         AND mt~spras = @sy-langu
       FOR ALL ENTRIES IN @lt_comp_mat
       WHERE ma~matnr = @lt_comp_mat-table_line
        INTO TABLE @lt_comp_mdat.
    ENDIF.

    DATA ls_row2 TYPE ty_row2.
    IF lt_fert_hdr IS NOT INITIAL AND lt_comp_mat IS NOT INITIAL.
      LOOP AT lt_fert_comp INTO DATA(ls_fcomp).
        DATA(lv_comp) = ls_fcomp-matnr_comp.
        READ TABLE lt_comp_move WITH KEY table_line = lv_comp TRANSPORTING NO FIELDS.
        IF sy-subrc = 0.
          CONTINUE.
        ENDIF.
        READ TABLE lt_comp_stock INTO ls_stk WITH KEY matnr = lv_comp.
        IF sy-subrc = 0 AND ls_stk-labst <> 0.
          CONTINUE.
        ENDIF.
        CLEAR ls_row2.
        ls_row2-matnr_fert = ls_fcomp-matnr_fert.
        ls_row2-matnr_comp = lv_comp.
        READ TABLE lt_comp_mdat INTO ls_mdat WITH KEY matnr = lv_comp.
        IF sy-subrc = 0.
          ls_row2-comp_maktx = ls_mdat-maktx.
          ls_row2-meins      = ls_mdat-meins.
        ENDIF.
        ls_row2-status = 'BOM 만 있음'.
        APPEND ls_row2 TO lt_out2.
      ENDLOOP.
    ENDIF.

    SORT lt_out2 BY matnr_fert matnr_comp.

    IF lt_out1 IS INITIAL AND lt_out2 IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 데이터가 없습니다.'.
      RETURN.
    ENDIF.

    WRITE: / '섹션 1: 자재 리스트 - 입출고 또는 재고 보유'.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out1 ).
    lo_alv->display( ).

    IF lt_out2 IS NOT INITIAL.
      WRITE: / '섹션 2: FERT BOM 구성품 - 입출고 및 재고 없음( BOM 만 있음 )'.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_out2 ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).