REPORT ZAI_260504_1505.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
SELECT-OPTIONS s_budat FOR sy-datum OBLIGATORY.
PARAMETERS p_year TYPE char4 DEFAULT sy-datum(4).

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lo_alv TYPE REF TO cl_salv_table.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             werks TYPE werks_d,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_mat,
             matnr TYPE mara-matnr,
             matkl TYPE mara-matkl,
             mtart TYPE mara-mtart,
             meins TYPE mara-meins,
             maktx TYPE makt-maktx,
           END OF ty_mat.

    TYPES: BEGIN OF ty_result,
             matnr  TYPE mara-matnr,
             werks  TYPE werks_d,
             maktx  TYPE makt-maktx,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             stock  TYPE mard-labst,
             status TYPE char20,
           END OF ty_result.

    DATA lt_mov_matnr TYPE ty_t_matnr.
    DATA lt_stock     TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    DATA lt_all_matnr TYPE ty_t_matnr.
    DATA lt_mat       TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.
    DATA lt_main      TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.
    DATA lt_bom_only  TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    " Materials with movements in date range and plant (MKPF/MSEG)
    SELECT DISTINCT
           ms~matnr
      FROM mseg AS ms
      INNER JOIN mkpf AS mk
        ON mk~mblnr = ms~mblnr
       AND mk~mjahr = ms~mjahr
     WHERE ms~werks = @p_werks
       AND mk~budat IN @s_budat
      INTO TABLE @lt_mov_matnr.

    " Current stock not zero in plant
    SELECT mard~matnr,
           mard~werks,
           SUM( mard~labst ) AS qty
      FROM mard AS mard
     WHERE mard~werks = @p_werks
     GROUP BY mard~matnr, mard~werks
    HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " Union of materials (movement or stock)
    lt_all_matnr = lt_mov_matnr.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stock>).
      INSERT <ls_stock>-matnr INTO TABLE lt_all_matnr.
    ENDLOOP.

    " Material master data + description
    IF lt_all_matnr IS NOT INITIAL.
      SELECT mara~matnr,
             mara~matkl,
             mara~mtart,
             mara~meins,
             makt~maktx
        FROM mara AS mara
        INNER JOIN makt AS makt
          ON makt~matnr = mara~matnr
       WHERE mara~matnr IN @lt_all_matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_mat.
    ENDIF.

    " Helpers
    DATA lt_stock_by_mat TYPE HASHED TABLE OF ty_stock
                         WITH UNIQUE KEY matnr werks.
    lt_stock_by_mat = lt_stock.

    DATA lt_mov_set TYPE HASHED TABLE OF mara-matnr
                    WITH UNIQUE KEY table_line.
    lt_mov_set = lt_mov_matnr.

    " Build main result
    LOOP AT lt_mat ASSIGNING FIELD-SYMBOL(<ls_mat>).
      DATA(lv_stock_qty) = CONV mard-labst( 0 ).
      READ TABLE lt_stock_by_mat ASSIGNING FIELD-SYMBOL(<ls_s>)
           WITH TABLE KEY matnr = <ls_mat>-matnr werks = p_werks.
      IF sy-subrc = 0.
        lv_stock_qty = <ls_s>-qty.
      ENDIF.

      DATA(lv_status) = CONV char20( '' ).
      READ TABLE lt_mov_set WITH TABLE KEY table_line = <ls_mat>-matnr
           TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_status = '입출고 있음'.
      ELSE.
        lv_status = '재고만 있음'.
      ENDIF.

      APPEND VALUE ty_result(
               matnr  = <ls_mat>-matnr
               werks  = p_werks
               maktx  = <ls_mat>-maktx
               mtart  = <ls_mat>-mtart
               matkl  = <ls_mat>-matkl
               meins  = <ls_mat>-meins
               stock  = lv_stock_qty
               status = lv_status ) TO lt_main.
    ENDLOOP.

    " BOM-only components for FERT with BOM in plant
    DATA lt_fert_with_bom TYPE ty_t_matnr.
    SELECT DISTINCT mast~matnr
      FROM mast AS mast
      INNER JOIN mara AS mara
        ON mara~matnr = mast~matnr
     WHERE mast~werks = @p_werks
       AND mara~mtart = 'FERT'
      INTO TABLE @lt_fert_with_bom.

    DATA lt_stlnr TYPE STANDARD TABLE OF stko-stlnr WITH EMPTY KEY.
    IF lt_fert_with_bom IS NOT INITIAL.
      SELECT DISTINCT mast~stlnr
        FROM mast AS mast
       WHERE mast~werks = @p_werks
         AND mast~matnr IN @lt_fert_with_bom
        INTO TABLE @lt_stlnr.
    ENDIF.

    DATA lt_bom_comp TYPE ty_t_matnr.
    IF lt_stlnr IS NOT INITIAL.
      SELECT DISTINCT stpo~idnrk
        FROM stpo AS stpo
       WHERE stpo~stlnr IN @lt_stlnr
        INTO TABLE @lt_bom_comp.
    ENDIF.

    " Exclude materials already in main list (movement or stock)
    IF lt_bom_comp IS NOT INITIAL.
      DATA lt_main_set TYPE HASHED TABLE OF mara-matnr
                       WITH UNIQUE KEY table_line.
      LOOP AT lt_main ASSIGNING FIELD-SYMBOL(<ls_main_mat>).
        INSERT <ls_main_mat>-matnr INTO TABLE lt_main_set.
      ENDLOOP.

      DATA lt_bom_only_mat TYPE ty_t_matnr.
      LOOP AT lt_bom_comp ASSIGNING FIELD-SYMBOL(<lv_comp>).
        READ TABLE lt_main_set WITH TABLE KEY table_line = <lv_comp>
             TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          INSERT <lv_comp> INTO TABLE lt_bom_only_mat.
        ENDIF.
      ENDLOOP.

      " Read MARA/MAKT for BOM-only components
      IF lt_bom_only_mat IS NOT INITIAL.
        DATA lt_bom_mat TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.
        SELECT mara~matnr,
               mara~matkl,
               mara~mtart,
               mara~meins,
               makt~maktx
          FROM mara AS mara
          INNER JOIN makt AS makt
            ON makt~matnr = mara~matnr
         WHERE mara~matnr IN @lt_bom_only_mat
           AND makt~spras = @sy-langu
          INTO TABLE @lt_bom_mat.

        LOOP AT lt_bom_mat ASSIGNING FIELD-SYMBOL(<ls_bm>).
          APPEND VALUE ty_result(
                   matnr  = <ls_bm>-matnr
                   werks  = p_werks
                   maktx  = <ls_bm>-maktx
                   mtart  = <ls_bm>-mtart
                   matkl  = <ls_bm>-matkl
                   meins  = <ls_bm>-meins
                   stock  = 0
                   status = 'BOM 만 있음' ) TO lt_bom_only.
        ENDLOOP.
      ENDIF.
    ENDIF.

    " Display
    IF lt_main IS INITIAL AND lt_bom_only IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 데이터가 없습니다.'.
      RETURN.
    ENDIF.

    WRITE: / '자재 리스트 - 입출고 또는 재고 보유'.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_main ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).

    IF lt_bom_only IS NOT INITIAL.
      SKIP.
      WRITE: / 'BOM 요소만 등록된 자재'.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_bom_only ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).