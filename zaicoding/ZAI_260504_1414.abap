REPORT ZAI_260504_1414.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_datfr TYPE sy-datum OBLIGATORY.
PARAMETERS p_datto TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES ty_matnr_tab TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             werks TYPE mard-werks,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_attr,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             matkl TYPE mara-matkl,
             meins TYPE mara-meins,
             maktx TYPE makt-maktx,
           END OF ty_attr.
    TYPES ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_res,
             matnr  TYPE mara-matnr,
             werks  TYPE werks_d,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             maktx  TYPE makt-maktx,
             stock  TYPE mard-labst,
             status TYPE char20,
           END OF ty_res.
    TYPES ty_t_res TYPE STANDARD TABLE OF ty_res WITH EMPTY KEY.

    DATA lt_move_matnr TYPE ty_matnr_tab.
    DATA lt_stock      TYPE ty_t_stock.
    DATA lt_all_matnr  TYPE ty_matnr_tab.
    DATA lt_attr       TYPE ty_t_attr.
    DATA lt_main       TYPE ty_t_res.
    DATA lt_bom_only   TYPE ty_t_res.
    DATA lo_alv        TYPE REF TO cl_salv_table.

    " 1) Materials with movements in period (MATDOC)
    SELECT DISTINCT
           md~matnr
      FROM matdoc AS md
      WHERE md~werks       = @p_werks
        AND md~budat_mkpf >= @p_datfr
        AND md~budat_mkpf <= @p_datto
        AND md~matnr       <> ''
      INTO TABLE @lt_move_matnr.

    " 2) Materials with current stock > 0 at plant (MARD)
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard AS mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @lt_stock.

    " 3) Union of materials (movement or stock)
    lt_all_matnr = lt_move_matnr.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      APPEND <ls_stk>-matnr TO lt_all_matnr.
    ENDLOOP.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    " 4) Attributes (MARA + MAKT with language)
    IF lt_all_matnr IS NOT INITIAL.
      SELECT
        a~matnr,
        a~mtart,
        a~matkl,
        a~meins,
        t~maktx
        FROM mara AS a
        LEFT OUTER JOIN makt AS t
          ON t~matnr = a~matnr
         AND t~spras = @sy-langu
        WHERE a~matnr IN @lt_all_matnr
        INTO TABLE @lt_attr.
    ENDIF.

    " 5) Build quick lookup sets
    DATA lt_move_set TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
    lt_move_set = lt_move_matnr.

    DATA lt_stock_by_matnr TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr.
    lt_stock_by_matnr = lt_stock.

    " 6) Compose main result set
    LOOP AT lt_attr ASSIGNING FIELD-SYMBOL(<ls_attr>).
      DATA(lv_stock_qty) = CONV mard-labst( 0 ).
      READ TABLE lt_stock_by_matnr ASSIGNING FIELD-SYMBOL(<ls_stk_by>)
           WITH TABLE KEY matnr = <ls_attr>-matnr.
      IF sy-subrc = 0.
        lv_stock_qty = <ls_stk_by>-qty.
      ENDIF.

      DATA(lv_has_move) = xsdbool( line_exists( lt_move_set[ table_line = <ls_attr>-matnr ] ) ).

      DATA(ls_res) = VALUE ty_res(
          matnr  = <ls_attr>-matnr
          werks  = p_werks
          mtart  = <ls_attr>-mtart
          matkl  = <ls_attr>-matkl
          meins  = <ls_attr>-meins
          maktx  = <ls_attr>-maktx
          stock  = lv_stock_qty
          status = COND char20(
                      WHEN lv_has_move = abap_true THEN '입출고 있음'
                      WHEN lv_stock_qty > 0         THEN '재고만 있음'
                      ELSE '' ) ).
      " Only include those with move or stock as requested
      IF ls_res-status IS NOT INITIAL.
        APPEND ls_res TO lt_main.
      ENDIF.
    ENDLOOP.

    " 7) BOM-only components for FERT headers at plant (no stock and no movement)
    DATA lt_fert_hdr TYPE ty_matnr_tab.
    SELECT
      mast~matnr
      FROM mast AS mast
      INNER JOIN mara AS a
        ON a~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND a~mtart   = 'FERT'
      INTO TABLE @lt_fert_hdr.
    SORT lt_fert_hdr.
    DELETE ADJACENT DUPLICATES FROM lt_fert_hdr.

    IF lt_fert_hdr IS NOT INITIAL.
      DATA lt_comp TYPE ty_matnr_tab.
      SELECT DISTINCT
             stpo~idnrk
        FROM stpo AS stpo
        INNER JOIN mast AS mast
          ON stpo~stlnr = mast~stlnr
        INNER JOIN mara AS a
          ON a~matnr = mast~matnr
        WHERE mast~werks = @p_werks
          AND a~mtart   = 'FERT'
          AND stpo~idnrk <> ''
        INTO TABLE @lt_comp.

      IF lt_comp IS NOT INITIAL.
        " Remove those already in main set (have stock or movement)
        SORT lt_comp.
        DELETE ADJACENT DUPLICATES FROM lt_comp.

        " Build a set of already shown materials
        DATA lt_shown TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.
        lt_shown = lt_all_matnr.

        " Keep only BOM components not in shown set
        DATA lt_bom_only_matnr TYPE ty_matnr_tab.
        LOOP AT lt_comp ASSIGNING FIELD-SYMBOL(<lv_c>).
          IF NOT line_exists( lt_shown[ table_line = <lv_c> ] ).
            APPEND <lv_c> TO lt_bom_only_matnr.
          ENDIF.
        ENDLOOP.

        IF lt_bom_only_matnr IS NOT INITIAL.
          DATA lt_bom_attr TYPE ty_t_attr.
          SELECT
            a~matnr,
            a~mtart,
            a~matkl,
            a~meins,
            t~maktx
            FROM mara AS a
            LEFT OUTER JOIN makt AS t
              ON t~matnr = a~matnr
             AND t~spras = @sy-langu
            WHERE a~matnr IN @lt_bom_only_matnr
            INTO TABLE @lt_bom_attr.

          LOOP AT lt_bom_attr ASSIGNING FIELD-SYMBOL(<ls_ba>).
            APPEND VALUE ty_res(
              matnr  = <ls_ba>-matnr
              werks  = p_werks
              mtart  = <ls_ba>-mtart
              matkl  = <ls_ba>-matkl
              meins  = <ls_ba>-meins
              maktx  = <ls_ba>-maktx
              stock  = CONV mard-labst( 0 )
              status = 'BOM 만 있음' ) TO lt_bom_only.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.

    " 8) Display ALV - Main list (movements or stock)
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_main ).
    lo_alv->display( ).

    " 9) Display ALV - BOM-only components (if any)
    IF lt_bom_only IS NOT INITIAL.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_bom_only ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).