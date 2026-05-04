REPORT ZAI_260504_1512.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE sy-datum OBLIGATORY.
PARAMETERS p_endda TYPE sy-datum DEFAULT sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lv_begda TYPE sy-datum.
    DATA lv_endda TYPE sy-datum.

    lv_begda = p_begda.
    lv_endda = p_endda.

    IF lv_begda GT lv_endda.
      DATA lv_tmp TYPE sy-datum.
      lv_tmp = lv_begda.
      lv_begda = lv_endda.
      lv_endda = lv_tmp.
    ENDIF.

    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             labst TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mat,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             maktx TYPE makt-maktx,
           END OF ty_mat.
    TYPES ty_t_mat TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.

    TYPES: BEGIN OF ty_result,
             matnr   TYPE mara-matnr,
             werks   TYPE werks_d,
             mtart   TYPE mara-mtart,
             maktx   TYPE makt-maktx,
             stock   TYPE mard-labst,
             has_mov TYPE abap_bool,
             note    TYPE char20,
           END OF ty_result.
    TYPES ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov     TYPE ty_t_matnr.
    DATA lt_stock   TYPE ty_t_stock.
    DATA lt_all     TYPE ty_t_matnr.
    DATA lt_matinfo TYPE ty_t_mat.
    DATA lt_main    TYPE ty_t_result.

    " 1) Materials with movements in the period (MATDOC)
    SELECT matdoc~matnr
      FROM matdoc
      WHERE matdoc~werks = @p_werks
        AND matdoc~budat BETWEEN @lv_begda AND @lv_endda
      GROUP BY matdoc~matnr
      INTO TABLE @lt_mov.

    " 2) Current stock by material (MARD), aggregated by MATNR
    SELECT mard~matnr,
           SUM( mard~labst ) AS labst
      FROM mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      INTO TABLE @lt_stock.
    DELETE lt_stock WHERE labst = 0.

    " 3) Union of materials from movement and stock
    lt_all = lt_mov.
    DATA ls_stock LIKE LINE OF lt_stock.
    LOOP AT lt_stock INTO ls_stock.
      IF line_exists( lt_all[ table_line = ls_stock-matnr ] ) = abap_false.
        APPEND ls_stock-matnr TO lt_all.
      ENDIF.
    ENDLOOP.

    " 4) Fetch material type and description
    IF lt_all IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             makt~maktx
        FROM mara
        LEFT OUTER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        WHERE mara~matnr IN @lt_all
        INTO TABLE @lt_matinfo.
    ENDIF.

    " 5) Build main result list
    DATA ls_res TYPE ty_result.
    DATA ls_mat TYPE ty_mat.
    LOOP AT lt_matinfo INTO ls_mat.
      CLEAR ls_res.
      ls_res-matnr = ls_mat-matnr.
      ls_res-werks = p_werks.
      ls_res-mtart = ls_mat-mtart.
      ls_res-maktx = ls_mat-maktx.
      READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_mat-matnr.
      IF sy-subrc = 0.
        ls_res-stock = ls_stock-labst.
      ELSE.
        ls_res-stock = 0.
      ENDIF.
      IF line_exists( lt_mov[ table_line = ls_mat-matnr ] ).
        ls_res-has_mov = abap_true.
      ELSE.
        ls_res-has_mov = abap_false.
      ENDIF.
      IF ls_res-has_mov = abap_false AND ls_res-stock NE 0.
        ls_res-note = '재고만 있음'.
      ELSE.
        CLEAR ls_res-note.
      ENDIF.
      APPEND ls_res TO lt_main.
    ENDLOOP.

    " 6) BOM-related section
    TYPES ty_t_bom_mats TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lt_fert_bom  TYPE ty_t_bom_mats.
    DATA lt_comp_all  TYPE ty_t_bom_mats.
    DATA lt_comp_only TYPE ty_t_bom_mats.

    " 6a) Finished goods with BOM (via MAST for the plant)
    SELECT DISTINCT mast~matnr
      FROM mast
      WHERE mast~werks = @p_werks
      INTO TABLE @lt_fert_bom.

    IF lt_fert_bom IS NOT INITIAL.
      DATA lt_fert_info TYPE ty_t_mat.
      SELECT mara~matnr,
             mara~mtart,
             makt~maktx
        FROM mara
        LEFT OUTER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        WHERE mara~matnr IN @lt_fert_bom
          AND mara~mtart = 'FERT'
        INTO TABLE @lt_fert_info.

      DATA lt_bom_res TYPE ty_t_result.
      LOOP AT lt_fert_info INTO ls_mat.
        CLEAR ls_res.
        ls_res-matnr = ls_mat-matnr.
        ls_res-werks = p_werks.
        ls_res-mtart = ls_mat-mtart.
        ls_res-maktx = ls_mat-maktx.
        READ TABLE lt_stock INTO ls_stock WITH KEY matnr = ls_mat-matnr.
        IF sy-subrc = 0.
          ls_res-stock = ls_stock-labst.
        ELSE.
          ls_res-stock = 0.
        ENDIF.
        IF line_exists( lt_mov[ table_line = ls_mat-matnr ] ).
          ls_res-has_mov = abap_true.
        ELSE.
          ls_res-has_mov = abap_false.
        ENDIF.
        IF ls_res-has_mov = abap_false AND ls_res-stock = 0.
          ls_res-note = 'BOM 만 있음'.
        ELSEIF ls_res-has_mov = abap_false AND ls_res-stock NE 0.
          ls_res-note = '재고만 있음'.
        ELSE.
          CLEAR ls_res-note.
        ENDIF.
        APPEND ls_res TO lt_bom_res.
      ENDLOOP.

      " 6b) Components that are only BOM elements (no stock, no movement)
      SELECT DISTINCT stpo~idnrk
        FROM mast
        INNER JOIN stpo
          ON stpo~stlnr = mast~stlnr
        WHERE mast~werks = @p_werks
        INTO TABLE @lt_comp_all.

      LOOP AT lt_comp_all ASSIGNING FIELD-SYMBOL(<lv_comp>).
        IF line_exists( lt_all[ table_line = <lv_comp> ] ) = abap_false.
          APPEND <lv_comp> TO lt_comp_only.
        ENDIF.
      ENDLOOP.

      IF lt_comp_only IS NOT INITIAL.
        DATA lt_comp_info TYPE ty_t_mat.
        SELECT mara~matnr,
               mara~mtart,
               makt~maktx
          FROM mara
          LEFT OUTER JOIN makt
            ON makt~matnr = mara~matnr
           AND makt~spras = @sy-langu
          WHERE mara~matnr IN @lt_comp_only
          INTO TABLE @lt_comp_info.

        LOOP AT lt_comp_info INTO ls_mat.
          CLEAR ls_res.
          ls_res-matnr = ls_mat-matnr.
          ls_res-werks = p_werks.
          ls_res-mtart = ls_mat-mtart.
          ls_res-maktx = ls_mat-maktx.
          ls_res-stock = 0.
          ls_res-has_mov = abap_false.
          ls_res-note = 'BOM 만 있음'.
          APPEND ls_res TO lt_bom_res.
        ENDLOOP.
      ENDIF.

      IF lt_bom_res IS INITIAL.
        WRITE: / 'BOM 섹션: 표시할 데이터가 없습니다.'.
      ELSE.
        WRITE: / 'BOM 섹션 - 완제품 및 구성요소'.
        DATA lo_alv_b TYPE REF TO cl_salv_table.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv_b
          CHANGING
            t_table      = lt_bom_res ).
        lo_alv_b->display( ).
      ENDIF.
    ELSE.
      WRITE: / 'BOM 섹션: 해당 플랜트에 대한 BOM 데이터가 없습니다.'.
    ENDIF.

    " Display main section
    IF lt_main IS INITIAL.
      WRITE: / '메인 섹션: 기간 내 입출고 또는 현재 재고가 있는 자재가 없습니다.'.
    ELSE.
      WRITE: / '메인 섹션 - 입출고 실적 또는 재고 보유 자재'.
      DATA lo_alv TYPE REF TO cl_salv_table.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_main ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).