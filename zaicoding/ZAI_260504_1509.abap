REPORT ZAI_260504_1509.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE sy-datum OBLIGATORY.
PARAMETERS p_endda TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lo_alv TYPE REF TO cl_salv_table.

    IF p_begda > p_endda.
      MESSAGE '시작일이 종료일보다 클 수 없습니다.' TYPE 'E'.
    ENDIF.

    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Materials with movements in period and plant (MATDOC)
    DATA lt_mov_mats TYPE ty_t_matnr.
    SELECT DISTINCT m~matnr
      FROM matdoc AS m
      WHERE m~werks = @p_werks
        AND m~budat_mkpf BETWEEN @p_begda AND @p_endda
      INTO TABLE @lt_mov_mats.

    " Current stock per material in plant (MARD)
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             werks TYPE werks_d,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    DATA lt_stock TYPE ty_t_stock.

    SELECT mard~matnr,
           mard~werks,
           SUM( mard~labst ) AS labst
      FROM mard AS mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " Union of materials from movement and stock
    DATA lt_all_mats TYPE ty_t_matnr.
    lt_all_mats = lt_mov_mats.
    DATA lt_tmp_mats TYPE ty_t_matnr.
    lt_tmp_mats = VALUE ty_t_matnr( FOR s IN lt_stock ( s-matnr ) ).
    APPEND LINES OF lt_tmp_mats TO lt_all_mats.
    SORT lt_all_mats BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_all_mats COMPARING table_line.

    " Material master and text
    TYPES: BEGIN OF ty_mara_s,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             meins TYPE mara-meins,
           END OF ty_mara_s.
    TYPES ty_t_mara_s TYPE STANDARD TABLE OF ty_mara_s WITH EMPTY KEY.
    DATA lt_mara TYPE ty_t_mara_s.

    IF lt_all_mats IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             mara~meins
        FROM mara AS mara
        WHERE mara~matnr IN @lt_all_mats
        INTO TABLE @lt_mara.
    ENDIF.

    TYPES: BEGIN OF ty_makt_s,
             matnr TYPE mara-matnr,
             maktx TYPE makt-maktx,
           END OF ty_makt_s.
    TYPES ty_t_makt_s TYPE STANDARD TABLE OF ty_makt_s WITH EMPTY KEY.
    DATA lt_makt TYPE ty_t_makt_s.

    IF lt_all_mats IS NOT INITIAL.
      SELECT makt~matnr,
             makt~maktx
        FROM makt AS makt
        WHERE makt~matnr IN @lt_all_mats
          AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.
    ENDIF.

    " Output 1: General list
    TYPES: BEGIN OF ty_out,
             matnr   TYPE mara-matnr,
             maktx   TYPE makt-maktx,
             mtart   TYPE mara-mtart,
             werks   TYPE werks_d,
             labst   TYPE mard-labst,
             has_mov TYPE abap_bool,
             status  TYPE c LENGTH 20,
           END OF ty_out.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.
    DATA lt_out TYPE ty_t_out.

    LOOP AT lt_all_mats ASSIGNING FIELD-SYMBOL(<mat>).
      DATA(ls_out) = VALUE ty_out( ).
      ls_out-matnr = <mat>.
      ls_out-werks = p_werks.

      READ TABLE lt_stock ASSIGNING FIELD-SYMBOL(<s>)
        WITH KEY matnr = <mat> werks = p_werks.
      IF sy-subrc = 0.
        ls_out-labst = <s>-labst.
      ELSE.
        CLEAR ls_out-labst.
      ENDIF.

      READ TABLE lt_mara ASSIGNING FIELD-SYMBOL(<mm>)
        WITH KEY matnr = <mat>.
      IF sy-subrc = 0.
        ls_out-mtart = <mm>-mtart.
      ENDIF.

      READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<tx>)
        WITH KEY matnr = <mat>.
      IF sy-subrc = 0.
        ls_out-maktx = <tx>-maktx.
      ENDIF.

      READ TABLE lt_mov_mats WITH KEY table_line = <mat>
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls_out-has_mov = abap_true.
      ELSE.
        ls_out-has_mov = abap_false.
      ENDIF.

      IF ls_out-has_mov = abap_true AND ls_out-labst IS NOT INITIAL.
        ls_out-status = '입출고 및 재고'.
      ELSEIF ls_out-has_mov = abap_true AND ls_out-labst IS INITIAL.
        ls_out-status = '입출고만 있음'.
      ELSEIF ls_out-has_mov = abap_false AND ls_out-labst IS NOT INITIAL.
        ls_out-status = '재고만 있음'.
      ELSE.
        CONTINUE.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_out ).
        lo_alv->get_display_settings( )->set_list_header(
          value = '자재 리스트 - 입출고/재고 현황' ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.

    " Section 2: Finished goods with BOM and BOM-only components
    DATA lt_hdr_mats TYPE ty_t_matnr.
    SELECT DISTINCT mast~matnr
      FROM mast AS mast
      INNER JOIN mara AS mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_hdr_mats.

    TYPES ty_t_out2 TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.
    DATA lt_out2 TYPE ty_t_out2.

    LOOP AT lt_hdr_mats ASSIGNING <mat>.
      DATA(ls2) = VALUE ty_out( ).
      ls2-matnr = <mat>.
      ls2-werks = p_werks.

      READ TABLE lt_mara ASSIGNING <mm> WITH KEY matnr = <mat>.
      IF sy-subrc = 0.
        ls2-mtart = <mm>-mtart.
      ENDIF.

      READ TABLE lt_makt ASSIGNING <tx> WITH KEY matnr = <mat>.
      IF sy-subrc = 0.
        ls2-maktx = <tx>-maktx.
      ENDIF.

      READ TABLE lt_stock ASSIGNING <s>
        WITH KEY matnr = <mat> werks = p_werks.
      IF sy-subrc = 0.
        ls2-labst = <s>-labst.
      ENDIF.

      READ TABLE lt_mov_mats WITH KEY table_line = <mat>
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls2-has_mov = abap_true.
      ELSE.
        ls2-has_mov = abap_false.
      ENDIF.

      IF ls2-has_mov = abap_true AND ls2-labst IS NOT INITIAL.
        ls2-status = '입출고 및 재고'.
      ELSEIF ls2-has_mov = abap_true AND ls2-labst IS INITIAL.
        ls2-status = '입출고만 있음'.
      ELSEIF ls2-has_mov = abap_false AND ls2-labst IS NOT INITIAL.
        ls2-status = '재고만 있음'.
      ELSE.
        ls2-status = 'BOM 보유'.
      ENDIF.

      APPEND ls2 TO lt_out2.
    ENDLOOP.

    " Components only in BOM and not in movement/stock
    DATA lt_comp_mats TYPE ty_t_matnr.
    IF lt_hdr_mats IS NOT INITIAL.
      SELECT DISTINCT stpo~idnrk
        FROM stpo AS stpo
        INNER JOIN mast AS mast
          ON mast~stlnr = stpo~stlnr
        WHERE mast~werks = @p_werks
        INTO TABLE @lt_comp_mats.
    ENDIF.

    SORT lt_comp_mats BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_comp_mats COMPARING table_line.

    " Helper set: materials that have movement or stock
    DATA lt_have_any TYPE ty_t_matnr.
    lt_have_any = lt_mov_mats.
    APPEND LINES OF lt_tmp_mats TO lt_have_any.
    SORT lt_have_any BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_have_any COMPARING table_line.

    LOOP AT lt_comp_mats ASSIGNING <mat>.
      READ TABLE lt_have_any WITH KEY table_line = <mat>
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        CONTINUE.
      ENDIF.

      DATA(lsc) = VALUE ty_out( ).
      lsc-matnr = <mat>.
      lsc-werks = p_werks.
      lsc-status = 'BOM 만 있음'.
      lsc-has_mov = abap_false.
      CLEAR lsc-labst.

      READ TABLE lt_mara ASSIGNING <mm> WITH KEY matnr = <mat>.
      IF sy-subrc = 0.
        lsc-mtart = <mm>-mtart.
      ENDIF.

      READ TABLE lt_makt ASSIGNING <tx> WITH KEY matnr = <mat>.
      IF sy-subrc = 0.
        lsc-maktx = <tx>-maktx.
      ENDIF.

      APPEND lsc TO lt_out2.
    ENDLOOP.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_out2 ).
        lo_alv->get_display_settings( )->set_list_header(
          value = 'BOM 관련 자재 섹션 - 완제품 및 BOM 전용 요소' ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).