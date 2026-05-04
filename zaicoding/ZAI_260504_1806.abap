REPORT ZAI_260504_1806.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr       TYPE mara-matnr,
        mtart       TYPE mara-mtart,
        matkl       TYPE mara-matkl,
        maktx       TYPE makt-maktx,
        status_text TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result       TYPE ty_t_result.
    DATA lt_result_bom   TYPE ty_t_result.

    DATA lt_mov_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_sel_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_bom_matnr    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_add_bom_only TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with movements in date/plant
    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr IS NOT NULL.

    " 2) Materials with current stock <> 0 in the plants
    SELECT DISTINCT mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0
        AND mard~matnr IS NOT NULL.

    " 3) Union of movement and stock materials
    lt_sel_matnr = lt_mov_matnr.
    INSERT LINES OF lt_stock_matnr INTO TABLE lt_sel_matnr.

    " 4) Build first result list with MARA/MAKT join
    IF lt_sel_matnr IS NOT INITIAL.
      TYPES:
        BEGIN OF ty_sel_mara,
          matnr TYPE mara-matnr,
          mtart TYPE mara-mtart,
          matkl TYPE mara-matkl,
          maktx TYPE makt-maktx,
        END OF ty_sel_mara,
        ty_t_sel_mara TYPE STANDARD TABLE OF ty_sel_mara WITH EMPTY KEY.

      DATA lt_sel_mara TYPE ty_t_sel_mara.

      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_sel_mara
        WHERE mara~matnr IN @lt_sel_matnr.

      DATA ls_res TYPE ty_result.
      DATA ls_row TYPE ty_sel_mara.
      LOOP AT lt_sel_mara INTO ls_row.
        CLEAR ls_res.
        ls_res-matnr = ls_row-matnr.
        ls_res-mtart = ls_row-mtart.
        ls_res-matkl = ls_row-matkl.
        ls_res-maktx = ls_row-maktx.
        IF line_exists( lt_mov_matnr[ table_line = ls_row-matnr ] ).
          ls_res-status_text = '입출고 실적 있음'.
        ELSEIF line_exists( lt_stock_matnr[ table_line = ls_row-matnr ] ).
          ls_res-status_text = '재고만 있음'.
        ELSE.
          ls_res-status_text = ''.
        ENDIF.
        APPEND ls_res TO lt_result.
      ENDLOOP.
    ENDIF.

    " 5) Find additional FERT/HALB with BOM only (in plants), not in first list
    SELECT DISTINCT mast~matnr
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      INTO TABLE @lt_bom_matnr
      WHERE mast~werks IN @s_werks
        AND mara~mtart IN ('FERT','HALB')
        AND mast~matnr IS NOT NULL.

    IF lt_bom_matnr IS NOT INITIAL.
      lt_add_bom_only = lt_bom_matnr.
      " Remove ones already in first selection
      DELETE lt_add_bom_only WHERE table_line IN lt_sel_matnr.

      IF lt_add_bom_only IS NOT INITIAL.
        TYPES:
          BEGIN OF ty_bom_mara,
            matnr TYPE mara-matnr,
            mtart TYPE mara-mtart,
            matkl TYPE mara-matkl,
            maktx TYPE makt-maktx,
          END OF ty_bom_mara,
          ty_t_bom_mara TYPE STANDARD TABLE OF ty_bom_mara WITH EMPTY KEY.

        DATA lt_bom_mara TYPE ty_t_bom_mara.

        SELECT mara~matnr,
               mara~mtart,
               mara~matkl,
               makt~maktx
          FROM mara
          LEFT JOIN makt
            ON makt~matnr = mara~matnr
           AND makt~spras = @sy-langu
          INTO TABLE @lt_bom_mara
          WHERE mara~matnr IN @lt_add_bom_only.

        DATA ls_bom TYPE ty_bom_mara.
        DATA ls_res2 TYPE ty_result.
        LOOP AT lt_bom_mara INTO ls_bom.
          CLEAR ls_res2.
          ls_res2-matnr = ls_bom-matnr.
          ls_res2-mtart = ls_bom-mtart.
          ls_res2-matkl = ls_bom-matkl.
          ls_res2-maktx = ls_bom-maktx.
          ls_res2-status_text = 'BOM 에 만 있음'.
          APPEND ls_res2 TO lt_result_bom.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " 6) Display ALV: first page
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).

    " 7) Display ALV: second page (BOM only)
    IF lt_result_bom IS NOT INITIAL.
      DATA lo_alv2 TYPE REF TO cl_salv_table.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv2
        CHANGING
          t_table      = lt_result_bom ).

      lo_alv2->get_functions( )->set_all( abap_true ).
      lo_alv2->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).