REPORT ZAI_260504_1354.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_dfrom TYPE sy-datum OBLIGATORY.
PARAMETERS p_dto   TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_out,
             section   TYPE char7,
             matnr     TYPE mara-matnr,
             mtart     TYPE mara-mtart,
             matkl     TYPE mara-matkl,
             meins     TYPE mara-meins,
             maktx     TYPE makt-maktx,
             has_mov   TYPE abap_bool,
             has_stock TYPE abap_bool,
             status    TYPE char15,
           END OF ty_out.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES: BEGIN OF ty_bom_comp,
             header_matnr TYPE mara-matnr,
             comp_matnr   TYPE mara-matnr,
           END OF ty_bom_comp.
    TYPES ty_t_bom_comp TYPE STANDARD TABLE OF ty_bom_comp WITH EMPTY KEY.

    CLASS-METHODS get_mov_mats
      IMPORTING i_werks TYPE werks_d
                i_dfrom TYPE sy-datum
                i_dto   TYPE sy-datum
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stock_mats
      IMPORTING i_werks TYPE werks_d
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_material_attrs
      IMPORTING it_matnr TYPE ty_t_matnr
      RETURNING VALUE(rt_data) TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    CLASS-METHODS get_fert_bom_components
      IMPORTING it_fert TYPE ty_t_matnr
                i_werks TYPE werks_d
      RETURNING VALUE(rt_comp) TYPE ty_t_matnr.

    CLASS-METHODS build_status
      IMPORTING it_all    TYPE ty_t_matnr
                it_mov    TYPE ty_t_matnr
                it_stock  TYPE ty_t_matnr
      RETURNING VALUE(rt_out) TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    DATA lt_mov   TYPE ty_t_matnr.
    DATA lt_stock TYPE ty_t_matnr.
    DATA lt_all   TYPE ty_t_matnr.
    DATA lt_out   TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.
    DATA lt_fert  TYPE ty_t_matnr.
    DATA lt_bomc  TYPE ty_t_matnr.
    DATA lt_bom_only TYPE ty_t_matnr.
    DATA lt_bom_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    IF p_dfrom > p_dto.
      MESSAGE 'From-date must be before To-date' TYPE 'E'.
    ENDIF.

    lt_mov   = get_mov_mats( i_werks = p_werks i_dfrom = p_dfrom i_dto = p_dto ).
    lt_stock = get_stock_mats( i_werks = p_werks ).

    " Union of movement and stock materials
    lt_all = lt_mov.
    APPEND LINES OF lt_stock TO lt_all.
    SORT lt_all.
    DELETE ADJACENT DUPLICATES FROM lt_all.

    " Build main output with status
    lt_out = build_status( it_all = lt_all it_mov = lt_mov it_stock = lt_stock ).

    " Collect FERT materials from main list
    DATA(lt_all_attrs) = get_material_attrs( lt_all ).
    LOOP AT lt_all_attrs ASSIGNING FIELD-SYMBOL(<a>) WHERE mtart = 'FERT'.
      APPEND <a>-matnr TO lt_fert.
    ENDLOOP.
    SORT lt_fert.
    DELETE ADJACENT DUPLICATES FROM lt_fert.

    IF lt_fert IS NOT INITIAL.
      " Get BOM components for FERT with BOM in plant
      lt_bomc = get_fert_bom_components( it_fert = lt_fert i_werks = p_werks ).
      IF lt_bomc IS NOT INITIAL.
        " Retain only components not already in main list (no stock/movements)
        lt_bom_only = lt_bomc.
        SORT lt_all.
        SORT lt_bom_only.
        DELETE ADJACENT DUPLICATES FROM lt_bom_only.
        LOOP AT lt_bom_only ASSIGNING FIELD-SYMBOL(<c>).
          READ TABLE lt_all WITH KEY table_line = <c> BINARY SEARCH TRANSPORTING NO FIELDS.
          IF sy-subrc = 0.
            DELETE lt_bom_only INDEX sy-tabix.
          ENDIF.
        ENDLOOP.
        IF lt_bom_only IS NOT INITIAL.
          lt_bom_out = get_material_attrs( lt_bom_only ).
          LOOP AT lt_bom_out ASSIGNING FIELD-SYMBOL(<bo>).
            <bo>-section   = 'BOM'.
            <bo>-has_mov   = abap_false.
            <bo>-has_stock = abap_false.
            <bo>-status    = 'BOM 만 있음'.
          ENDLOOP.
          APPEND LINES OF lt_bom_out TO lt_out.
        ENDIF.
      ENDIF.
    ENDIF.

    " Fill attributes for main rows (section '기본')
    LOOP AT lt_out ASSIGNING FIELD-SYMBOL(<o>) WHERE section IS INITIAL.
      <o>-section = '기본'.
    ENDLOOP.

    " Enrich main rows with attributes (maktx, mtart, etc.) where not yet set
    " Build list of matnr missing attributes
    DATA lt_need_attrs TYPE ty_t_matnr.
    LOOP AT lt_out ASSIGNING <o>.
      IF <o>-mtart IS INITIAL OR <o>-meins IS INITIAL OR <o>-maktx IS INITIAL.
        APPEND <o>-matnr TO lt_need_attrs.
      ENDIF.
    ENDLOOP.
    IF lt_need_attrs IS NOT INITIAL.
      SORT lt_need_attrs.
      DELETE ADJACENT DUPLICATES FROM lt_need_attrs.
      DATA(lt_attr_fill) = get_material_attrs( lt_need_attrs ).
      LOOP AT lt_out ASSIGNING <o>.
        READ TABLE lt_attr_fill ASSIGNING FIELD-SYMBOL(<af>) WITH KEY matnr = <o>-matnr.
        IF sy-subrc = 0.
          <o>-mtart = <af>-mtart.
          <o>-matkl = <af>-matkl.
          <o>-meins = <af>-meins.
          <o>-maktx = <af>-maktx.
        ENDIF.
      ENDLOOP.
    ENDIF.

    " Display with SALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_out ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
        MESSAGE 'ALV display error' TYPE 'E'.
    ENDTRY.
  ENDMETHOD.

  METHOD get_mov_mats.
    DATA lt TYPE ty_t_matnr.
    SELECT matdoc~matnr
      FROM matdoc
      WHERE matdoc~werks       = @i_werks
        AND matdoc~budat_mkpf >= @i_dfrom
        AND matdoc~budat_mkpf <= @i_dto
      GROUP BY matdoc~matnr
      INTO TABLE @lt.
    rt_matnr = lt.
  ENDMETHOD.

  METHOD get_stock_mats.
    DATA lt TYPE ty_t_matnr.
    SELECT mard~matnr
      FROM mard
      WHERE mard~werks = @i_werks
        AND mard~labst > 0
      GROUP BY mard~matnr
      INTO TABLE @lt.
    rt_matnr = lt.
  ENDMETHOD.

  METHOD get_material_attrs.
    DATA lt_attrs TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      RETURN.
    ENDIF.

    " Get MARA attributes
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    SELECT mara~matnr,
           mara~mtart,
           mara~matkl,
           mara~meins
      FROM mara
      WHERE mara~matnr IN @it_matnr
      INTO TABLE @DATA(lt_mara_sel).

    " Get MAKT texts
    SELECT makt~matnr,
           makt~maktx
      FROM makt
      WHERE makt~matnr IN @it_matnr
        AND makt~spras = @sy-langu
      INTO TABLE @DATA(lt_makt_sel).

    LOOP AT it_matnr ASSIGNING FIELD-SYMBOL(<m>).
      DATA ls TYPE ty_out.
      ls-matnr = <m>.
      READ TABLE lt_mara_sel ASSIGNING FIELD-SYMBOL(<ra>) WITH KEY matnr = <m>.
      IF sy-subrc = 0.
        ls-mtart = <ra>-mtart.
        ls-matkl = <ra>-matkl.
        ls-meins = <ra>-meins.
      ENDIF.
      READ TABLE lt_makt_sel ASSIGNING FIELD-SYMBOL(<rt>) WITH KEY matnr = <m>.
      IF sy-subrc = 0.
        ls-maktx = <rt>-maktx.
      ENDIF.
      APPEND ls TO lt_attrs.
    ENDLOOP.

    rt_data = lt_attrs.
  ENDMETHOD.

  METHOD get_fert_bom_components.
    rt_comp = VALUE ty_t_matnr( ).
    IF it_fert IS INITIAL.
      RETURN.
    ENDIF.

    " Get BOM assignments for FERT in plant
    SELECT mast~matnr,
           mast~stlnr,
           mast~stlal
      FROM mast
      WHERE mast~matnr IN @it_fert
        AND mast~werks = @i_werks
      INTO TABLE @DATA(lt_mast).
    IF lt_mast IS INITIAL.
      RETURN.
    ENDIF.

    " Join MAST to STPO to get components
    SELECT m~matnr    AS header_matnr,
           p~idnrk    AS comp_matnr
      FROM mast AS m
      INNER JOIN stpo AS p
        ON p~stlnr = m~stlnr
       AND p~stlal = m~stlal
      WHERE m~matnr IN @it_fert
        AND m~werks = @i_werks
      INTO TABLE @DATA(lt_bom).
    IF lt_bom IS INITIAL.
      RETURN.
    ENDIF.

    " Distinct component list
    DATA lt_comp TYPE ty_t_matnr.
    LOOP AT lt_bom ASSIGNING FIELD-SYMBOL(<b>).
      APPEND <b>-comp_matnr TO lt_comp.
    ENDLOOP.
    SORT lt_comp.
    DELETE ADJACENT DUPLICATES FROM lt_comp.

    rt_comp = lt_comp.
  ENDMETHOD.

  METHOD build_status.
    DATA lt_attrs TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.
    DATA lt_res   TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    IF it_all IS INITIAL.
      RETURN.
    ENDIF.

    " For quick lookups
    DATA lt_mov_s TYPE ty_t_matnr.
    DATA lt_stk_s TYPE ty_t_matnr.
    lt_mov_s = it_mov.
    lt_stk_s = it_stock.
    SORT lt_mov_s.
    SORT lt_stk_s.

    lt_attrs = get_material_attrs( it_all ).

    LOOP AT lt_attrs ASSIGNING FIELD-SYMBOL(<r>).
      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.
      READ TABLE lt_mov_s WITH KEY table_line = <r>-matnr BINARY SEARCH TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.
      READ TABLE lt_stk_s WITH KEY table_line = <r>-matnr BINARY SEARCH TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      <r>-has_mov   = lv_has_mov.
      <r>-has_stock = lv_has_stk.

      IF lv_has_mov = abap_true AND lv_has_stk = abap_true.
        <r>-status = '입출고+재고'.
      ELSEIF lv_has_mov = abap_true AND lv_has_stk = abap_false.
        <r>-status = '입출고 있음'.
      ELSEIF lv_has_mov = abap_false AND lv_has_stk = abap_true.
        <r>-status = '재고만 있음'.
      ELSE.
        <r>-status = ''.
      ENDIF.

      APPEND <r> TO lt_res.
    ENDLOOP.

    rt_out = lt_res.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).