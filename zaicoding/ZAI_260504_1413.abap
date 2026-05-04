REPORT ZAI_260504_1413.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_dfrom TYPE sy-datum OBLIGATORY.
PARAMETERS p_dto   TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_out,
             matnr  TYPE mara-matnr,
             werks  TYPE mard-werks,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             meins  TYPE mara-meins,
             maktx  TYPE makt-maktx,
             stock  TYPE mard-labst,
             status TYPE char20,
           END OF ty_out.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    CLASS-METHODS get_movement_materials
      IMPORTING
        iv_werks TYPE werks_d
        id_from  TYPE sy-datum
        id_to    TYPE sy-datum
      RETURNING
        VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stock_data
      IMPORTING
        iv_werks  TYPE werks_d
      EXPORTING
        VALUE(et_mard)   TYPE STANDARD TABLE OF mard WITH EMPTY KEY
        VALUE(et_matnr)  TYPE ty_t_matnr.

    CLASS-METHODS get_texts
      IMPORTING
        it_matnr TYPE ty_t_matnr
      RETURNING
        VALUE(rt_makt) TYPE STANDARD TABLE OF makt WITH EMPTY KEY.

    CLASS-METHODS get_mara
      IMPORTING
        it_matnr TYPE ty_t_matnr
      RETURNING
        VALUE(rt_mara) TYPE STANDARD TABLE OF mara WITH EMPTY KEY.

    CLASS-METHODS build_main_list
      IMPORTING
        iv_werks TYPE werks_d
        it_mv    TYPE ty_t_matnr
        it_mard  TYPE STANDARD TABLE OF mard WITH EMPTY KEY
        it_all   TYPE ty_t_matnr
      RETURNING
        VALUE(rt_out) TYPE ty_t_out.

    CLASS-METHODS get_bom_only_components
      IMPORTING
        iv_werks TYPE werks_d
        it_excl  TYPE ty_t_matnr
      RETURNING
        VALUE(rt_comp) TYPE ty_t_matnr.

    CLASS-METHODS display_alv
      IMPORTING
        it_data TYPE ty_t_out
        iv_title TYPE string.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    IF p_dfrom GT p_dto.
      MESSAGE 'From-date must be <= To-date' TYPE 'E'.
    ENDIF.

    DATA(lt_mv_mat) = get_movement_materials(
                        iv_werks = p_werks
                        id_from  = p_dfrom
                        id_to    = p_dto ).

    DATA lt_mard TYPE STANDARD TABLE OF mard WITH EMPTY KEY.
    DATA lt_stk_mat TYPE ty_t_matnr.
    get_stock_data(
      EXPORTING
        iv_werks  = p_werks
      EXPORTING
        et_mard   = lt_mard
        et_matnr  = lt_stk_mat ).

    " Union of movement and stock materials
    DATA lt_all_mat TYPE ty_t_matnr.
    lt_all_mat = lt_mv_mat.
    APPEND LINES OF lt_stk_mat TO lt_all_mat.
    SORT lt_all_mat.
    DELETE ADJACENT DUPLICATES FROM lt_all_mat.

    " Build main output list
    DATA(lt_main) = build_main_list(
                      iv_werks = p_werks
                      it_mv    = lt_mv_mat
                      it_mard  = lt_mard
                      it_all   = lt_all_mat ).

    display_alv(
      it_data = lt_main
      iv_title = |자재 목록 - 입출고/재고 현황 (플랜트 { p_werks } 기간 { p_dfrom }~{ p_dto })| ).

    " BOM-only components (no stock, no movement), within BOMs used in the plant
    DATA(lt_bom_only) = get_bom_only_components(
                          iv_werks = p_werks
                          it_excl  = lt_all_mat ).

    IF lt_bom_only IS NOT INITIAL.
      DATA(lt_mara_b) = get_mara( lt_bom_only ).
      DATA(lt_makt_b) = get_texts( lt_bom_only ).

      DATA lt_bom_out TYPE ty_t_out.
      LOOP AT lt_mara_b ASSIGNING FIELD-SYMBOL(<ls_mara_b>).
        DATA(ls_out_b) = VALUE ty_out(
                           matnr  = <ls_mara_b>-matnr
                           werks  = p_werks
                           mtart  = <ls_mara_b>-mtart
                           matkl  = <ls_mara_b>-matkl
                           meins  = <ls_mara_b>-meins
                           stock  = 0
                           status = |BOM 만 있음| ).
        READ TABLE lt_makt_b ASSIGNING FIELD-SYMBOL(<ls_makt_b>)
          WITH KEY matnr = <ls_mara_b>-matnr spras = sy-langu.
        IF sy-subrc = 0.
          ls_out_b-maktx = <ls_makt_b>-maktx.
        ENDIF.
        APPEND ls_out_b TO lt_bom_out.
      ENDLOOP.

      display_alv(
        it_data = lt_bom_out
        iv_title = |BOM 구성요소 - 재고/입출고 없음 (플랜트 { p_werks })| ).
    ENDIF.
  ENDMETHOD.

  METHOD get_movement_materials.
    DATA lt_matnr TYPE ty_t_matnr.
    SELECT DISTINCT ms~matnr
      FROM mseg AS ms
      INNER JOIN mkpf AS mk
        ON mk~mblnr = ms~mblnr
       AND mk~mjahr = ms~mjahr
      WHERE ms~werks = @iv_werks
        AND mk~budat BETWEEN @id_from AND @id_to
      INTO TABLE @lt_matnr.
    rt_matnr = lt_matnr.
  ENDMETHOD.

  METHOD get_stock_data.
    CLEAR: et_mard, et_matnr.
    SELECT mard~matnr,
           mard~werks,
           mard~lgort,
           mard~labst
      FROM mard
      WHERE mard~werks = @iv_werks
        AND mard~labst <> 0
      INTO TABLE @et_mard.

    IF et_mard IS NOT INITIAL.
      DATA lt_tmp TYPE ty_t_matnr.
      LOOP AT et_mard ASSIGNING FIELD-SYMBOL(<ls_mard>).
        APPEND <ls_mard>-matnr TO lt_tmp.
      ENDLOOP.
      SORT lt_tmp.
      DELETE ADJACENT DUPLICATES FROM lt_tmp.
      et_matnr = lt_tmp.
    ENDIF.
  ENDMETHOD.

  METHOD get_texts.
    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT makt~matnr,
           makt~spras,
           makt~maktx
      FROM makt
      WHERE makt~matnr IN @it_matnr
        AND makt~spras = @sy-langu
      INTO TABLE @lt_makt.
    rt_makt = lt_makt.
  ENDMETHOD.

  METHOD get_mara.
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      RETURN.
    ENDIF.
    SELECT mara~matnr,
           mara~mtart,
           mara~matkl,
           mara~meins
      FROM mara
      WHERE mara~matnr IN @it_matnr
      INTO TABLE @lt_mara.
    rt_mara = lt_mara.
  ENDMETHOD.

  METHOD build_main_list.
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    DATA lt_makt TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    lt_mara = get_mara( it_all ).
    lt_makt = get_texts( it_all ).

    DATA lt_mv_index TYPE ty_t_matnr.
    lt_mv_index = it_mv.
    SORT lt_mv_index.
    DATA lt_stk_index TYPE ty_t_matnr.
    LOOP AT it_mard ASSIGNING FIELD-SYMBOL(<ls_mard2>).
      APPEND <ls_mard2>-matnr TO lt_stk_index.
    ENDLOOP.
    SORT lt_stk_index.
    DELETE ADJACENT DUPLICATES FROM lt_stk_index.

    DATA lt_out TYPE ty_t_out.
    LOOP AT lt_mara ASSIGNING FIELD-SYMBOL(<ls_mara>).
      DATA(lv_has_mv) = xsdbool( line_exists( lt_mv_index[ table_line = <ls_mara>-matnr ] ) ).
      DATA(lv_has_stk) = xsdbool( line_exists( lt_stk_index[ table_line = <ls_mara>-matnr ] ) ).

      IF lv_has_mv = abap_false AND lv_has_stk = abap_false.
        CONTINUE.
      ENDIF.

      DATA(lv_stock) = CONV mard-labst( 0 ).
      IF lv_has_stk = abap_true.
        " Sum stock from MARD for the material in the plant
        LOOP AT it_mard ASSIGNING FIELD-SYMBOL(<ls_mard3>) WHERE matnr = <ls_mara>-matnr.
          lv_stock = lv_stock + <ls_mard3>-labst.
        ENDLOOP.
      ENDIF.

      DATA(ls_out) = VALUE ty_out(
                       matnr  = <ls_mara>-matnr
                       werks  = iv_werks
                       mtart  = <ls_mara>-mtart
                       matkl  = <ls_mara>-matkl
                       meins  = <ls_mara>-meins
                       stock  = lv_stock
                       status = COND char20(
                                   WHEN lv_has_mv = abap_true THEN |입출고 있음|
                                   WHEN lv_has_stk = abap_true THEN |재고만 있음|
                                   ELSE | | ) ).

      READ TABLE lt_makt ASSIGNING FIELD-SYMBOL(<ls_makt>) WITH KEY matnr = <ls_mara>-matnr spras = sy-langu.
      IF sy-subrc = 0.
        ls_out-maktx = <ls_makt>-maktx.
      ENDIF.

      APPEND ls_out TO lt_out.
    ENDLOOP.

    rt_out = lt_out.
  ENDMETHOD.

  METHOD get_bom_only_components.
    DATA lt_comp_all TYPE ty_t_matnr.
    " Components used in BOMs assigned to the given plant
    SELECT DISTINCT sp~idnrk
      FROM mast AS ma
      INNER JOIN stpo AS sp
        ON sp~stln