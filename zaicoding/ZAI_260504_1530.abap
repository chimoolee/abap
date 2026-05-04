REPORT ZAI_260504_1530.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_datf TYPE sy-datum.
PARAMETERS p_datt TYPE sy-datum.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lo_alv TYPE REF TO cl_salv_table.

    TYPES: BEGIN OF ty_main,
             matnr  TYPE mara-matnr,
             maktx  TYPE makt-maktx,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             qty    TYPE mard-labst,
             status TYPE c LENGTH 20,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    DATA lt_main TYPE ty_t_main.
    DATA lt_bom  TYPE ty_t_main.

    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_mov_matnr TYPE ty_t_matnr.
    DATA lt_all_mats  TYPE ty_t_matnr.
    DATA lt_bom_fert  TYPE ty_t_matnr.
    DATA lt_bom_comp  TYPE ty_t_matnr.
    DATA lt_bom_cand  TYPE ty_t_matnr.
    DATA lt_bom_only  TYPE ty_t_matnr.

    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.
    DATA lt_stock TYPE ty_t_stock.

    TYPES: BEGIN OF ty_mara,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             matkl TYPE mara-matkl,
             meins TYPE mara-meins,
           END OF ty_mara.
    TYPES ty_t_mara TYPE STANDARD TABLE OF ty_mara WITH EMPTY KEY.
    DATA lt_mara TYPE ty_t_mara.

    TYPES: BEGIN OF ty_makt,
             matnr TYPE mara-matnr,
             maktx TYPE makt-maktx,
           END OF ty_makt.
    TYPES ty_t_makt TYPE STANDARD TABLE OF ty_makt WITH EMPTY KEY.
    DATA lt_makt TYPE ty_t_makt.

    DATA lv_today TYPE sy-datum.
    lv_today = sy-datum.

    IF p_datf IS INITIAL AND p_datt IS INITIAL.
      DATA(lv_from) = lv_today.
      lv_from = lv_from - 30.
      p_datf = lv_from.
      p_datt = lv_today.
    ENDIF.

    IF p_datf GT p_datt.
      DATA(lv_tmp) = p_datf.
      p_datf = p_datt.
      p_datt = lv_tmp.
    ENDIF.

    SELECT DISTINCT m~matnr
      FROM mseg AS m
      INNER JOIN mkpf AS k
        ON k~mblnr = m~mblnr
       AND k~mjahr = m~mjahr
     WHERE m~werks = @p_werks
       AND k~budat BETWEEN @p_datf AND @p_datt
      INTO TABLE @lt_mov_matnr.

    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
     WHERE mard~werks = @p_werks
     GROUP BY mard~matnr
    HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    lt_all_mats = lt_mov_matnr.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<s>).
      APPEND <s>-matnr TO lt_all_mats.
    ENDLOOP.
    SORT lt_all_mats.
    DELETE ADJACENT DUPLICATES FROM lt_all_mats.

    IF lt_all_mats IS NOT INITIAL.
      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             mara~meins
        FROM mara
       WHERE mara~matnr IN @lt_all_mats
        INTO TABLE @lt_mara.

      SELECT makt~matnr,
             makt~maktx
        FROM makt
       WHERE makt~matnr IN @lt_all_mats
         AND makt~spras = @sy-langu
        INTO TABLE @lt_makt.
      SORT lt_makt BY matnr.
    ENDIF.

    SORT lt_stock BY matnr.
    SORT lt_mov_matnr.
    LOOP AT lt_all_mats ASSIGNING FIELD-SYMBOL(<mat>).
      READ TABLE lt_mara ASSIGNING FIELD-SYMBOL(<ma>)
        WITH KEY matnr = <mat>.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      DATA(lv_qty) = CONV mard-labst( 0 ).
      READ TABLE lt_stock ASSIGNING FIELD-SYMBOL(<st>)
        WITH KEY matnr = <mat> BINARY SEARCH.
      IF sy-subrc = 0.
        lv_qty = <st>-qty.
      ENDIF.

      DATA(lv_has_mov) = abap_false.
      READ TABLE lt_mov_matnr WITH KEY table_line = <mat>
        BINARY SEARCH TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      DATA(lv_status) = ||.
      IF lv_has_mov = abap_true.
        lv_status = |입출고 있음|.
      ELSE.
        lv_status = |재고만 있음|.
      ENDIF.

      DATA(lv_maktx) = ||.
      READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<mk>)
        WITH KEY matnr = <mat> BINARY SEARCH.
      IF sy-subrc = 0.
        lv_maktx = <mk>-maktx.
      ENDIF.

      APPEND VALUE ty_main(
        matnr  = <ma>-matnr
        maktx  = lv_maktx
        mtart  = <ma>-mtart
        matkl  = <ma>-matkl
        meins  = <ma>-meins
        qty    = lv_qty
        status = lv_status ) TO lt_main.
    ENDLOOP.

    SELECT DISTINCT mast~matnr
      FROM mast AS mast
      INNER JOIN mara AS ma
        ON ma~matnr = mast~matnr
     WHERE mast~werks = @p_werks
       AND ma~mtart = 'FERT'
      INTO TABLE @lt_bom_fert.

    IF lt_bom_fert IS NOT INITIAL.
      SELECT DISTINCT stpo~idnrk
        FROM stpo AS stpo
        INNER JOIN mast AS mast
          ON stpo~stlnr = mast~stlnr
       WHERE mast~werks = @p_werks
        INTO TABLE @lt_bom_comp.
    ENDIF.

    lt_bom_cand = lt_bom_fert.
    APPEND LINES OF lt_bom_comp TO lt_bom_cand.
    SORT lt_bom_cand.
    DELETE ADJACENT DUPLICATES FROM lt_bom_cand.

    SORT lt_all_mats.
    LOOP AT lt_bom_cand ASSIGNING FIELD-SYMBOL(<bmat>).
      READ TABLE lt_all_mats WITH KEY table_line = <bmat>
        BINARY SEARCH TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND <bmat> TO lt_bom_only.
      ENDIF.
    ENDLOOP.

    IF lt_bom_only IS NOT INITIAL.
      DATA lt_bom_mara TYPE ty_t_mara.
      DATA lt_bom_makt TYPE ty_t_makt.

      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             mara~meins
        FROM mara
       WHERE mara~matnr IN @lt_bom_only
        INTO TABLE @lt_bom_mara.

      SELECT makt~matnr,
             makt~maktx
        FROM makt
       WHERE makt~matnr IN @lt_bom_only
         AND makt~spras = @sy-langu
        INTO TABLE @lt_bom_makt.
      SORT lt_bom_makt BY matnr.

      LOOP AT lt_bom_mara ASSIGNING <ma>.
        DATA(lv_bm_maktx) = ||.
        READ TABLE lt_bom_makt ASSIGNING <mk>
          WITH KEY matnr = <ma>-matnr BINARY SEARCH.
        IF sy-subrc = 0.
          lv_bm_maktx = <mk>-maktx.
        ENDIF.

        APPEND VALUE ty_main(
          matnr  = <ma>-matnr
          maktx  = lv_bm_maktx
          mtart  = <ma>-mtart
          matkl  = <ma>-matkl
          meins  = <ma>-meins
          qty    = 0
          status = |BOM 만 있음| ) TO lt_bom.
      ENDLOOP.
    ENDIF.

    IF lt_main IS INITIAL AND lt_bom IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    IF lt_main IS NOT INITIAL.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_main ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->set_screen_popup(
        start_column = 5
        end_column   = 200
        start_line   = 1
        end_line     = 20 ).
      lo_alv->display( ).
    ENDIF.

    IF lt_bom IS NOT INITIAL.
      cl_salv_table=>factory(
        IMPORTING
          r_salv_table = lo_alv
        CHANGING
          t_table      = lt_bom ).
      lo_alv->get_functions( )->set_all( abap_true ).
      lo_alv->get_columns( )->set_optimize( abap_true ).
      lo_alv->set_screen_popup(
        start_column = 5
        end_column   = 200
        start_line   = 21
        end_line     = 40 ).
      lo_alv->display( ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).