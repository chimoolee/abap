REPORT ZAI_260504_1803.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        source TYPE char40,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result      TYPE ty_t_result.
    DATA lt_result_bom  TYPE ty_t_result.

    DATA lt_mov         TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock       TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_union       TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_cand    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_only    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lo_alv TYPE REF TO cl_salv_table.

*   1) Materials with goods movements for given posting date and plant
    SELECT DISTINCT
           mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

*   2) Materials with current stock not equal to zero for selected plants
    SELECT matnr
      FROM mard
      INTO TABLE @lt_stock
      WHERE werks IN @s_werks
        AND labst <> 0.

*   3) Union of movement and stock materials
    lt_union = lt_mov.
    APPEND LINES OF lt_stock TO lt_union.
    SORT lt_union.
    DELETE ADJACENT DUPLICATES FROM lt_union.

*   4) Attributes and text for union materials
    IF lt_union IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_result
        WHERE mara~matnr IN @lt_union.
    ENDIF.

*   5) Mark source: movement or stock-only
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<ls_res>).
      IF line_exists( lt_mov[ table_line = <ls_res>-matnr ] ).
        <ls_res>-source = '입출고 실적 있음'.
      ELSEIF line_exists( lt_stock[ table_line = <ls_res>-matnr ] ).
        <ls_res>-source = '재고만 있음'.
      ENDIF.
    ENDLOOP.

*   6) BOM candidates for FERT/HALB in selected plants
    SELECT DISTINCT
           mast~matnr
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      INTO TABLE @lt_bom_cand
      WHERE mara~mtart IN ('FERT','HALB')
        AND mast~werks IN @s_werks.

*   7) BOM-only materials = candidates minus already listed
    SORT lt_bom_cand.
    LOOP AT lt_bom_cand INTO DATA(lv_bmat).
      IF NOT line_exists( lt_union[ table_line = lv_bmat ] ).
        APPEND lv_bmat TO lt_bom_only.
      ENDIF.
    ENDLOOP.

*   8) Fetch attributes for BOM-only and set source
    IF lt_bom_only IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_result_bom
        WHERE mara~matnr IN @lt_bom_only.

      LOOP AT lt_result_bom ASSIGNING FIELD-SYMBOL(<ls_bom>).
        <ls_bom>-source = 'BOM 에 만 있음'.
      ENDLOOP.
    ENDIF.

*   9) Display ALV - main result
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->display( ).

*   10) Display ALV - BOM-only on next page
    IF lt_result_bom IS NOT INITIAL.
      NEW-PAGE.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_result_bom ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).