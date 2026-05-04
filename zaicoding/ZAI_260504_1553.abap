REPORT ZAI_260504_1553.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_from  TYPE sy-datum.
PARAMETERS p_to    TYPE sy-datum.

INITIALIZATION.
  p_to   = sy-datum.
  p_from = sy-datum - 30.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_stock_sum,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock_sum.
    TYPES ty_t_stock_sum TYPE STANDARD TABLE OF ty_stock_sum WITH EMPTY KEY.

    TYPES: BEGIN OF ty_out,
             matnr   TYPE mara-matnr,
             werks   TYPE werks_d,
             maktx   TYPE makt-maktx,
             stock   TYPE mard-labst,
             mvmt    TYPE abap_bool,
             remark  TYPE string,
             section TYPE string,
           END OF ty_out.
    TYPES ty_t_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    TYPES: BEGIN OF ty_makt,
             matnr TYPE makt-matnr,
             spras TYPE makt-spras,
             maktx TYPE makt-maktx,
           END OF ty_makt.
    TYPES ty_t_makt TYPE STANDARD TABLE OF ty_makt WITH EMPTY KEY.

    CLASS-METHODS get_mvmt
      IMPORTING
        i_werks TYPE werks_d
        i_from  TYPE sy-datum
        i_to    TYPE sy-datum
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stock_nonzero
      IMPORTING
        i_werks TYPE werks_d
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_stock_sum
      IMPORTING
        i_werks  TYPE werks_d
        it_matnr TYPE ty_t_matnr
      RETURNING VALUE(rt_sum) TYPE ty_t_stock_sum.

    CLASS-METHODS get_fg_with_bom
      IMPORTING
        i_werks TYPE werks_d
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_bom_components
      IMPORTING
        i_werks TYPE werks_d
      RETURNING VALUE(rt_matnr) TYPE ty_t_matnr.

    CLASS-METHODS get_texts
      IMPORTING
        it_matnr TYPE ty_t_matnr
      RETURNING VALUE(rt_texts) TYPE ty_t_makt.

    CLASS-METHODS build_output
      IMPORTING
        i_werks      TYPE werks_d
        it_mvmt      TYPE ty_t_matnr
        it_stock     TYPE ty_t_matnr
        it_bom_fg    TYPE ty_t_matnr
        it_bom_only  TYPE ty_t_matnr
        it_stock_sum TYPE ty_t_stock_sum
      RETURNING VALUE(rt_out) TYPE ty_t_out.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mvmt      TYPE ty_t_matnr.
    DATA lt_stock     TYPE ty_t_matnr.
    DATA lt_bom_fg    TYPE ty_t_matnr.
    DATA lt_bom_comp  TYPE ty_t_matnr.
    DATA lt_bom_only  TYPE ty_t_matnr.
    DATA lt_sum       TYPE ty_t_stock_sum.
    DATA lt_out       TYPE ty_t_out.
    DATA lo_alv       TYPE REF TO cl_salv_table.

    IF p_from IS INITIAL OR p_to IS INITIAL OR p_from > p_to.
      MESSAGE '기간을 올바르게 입력하세요.' TYPE 'S' DISPLAY LIKE 'E'.
      RETURN.
    ENDIF.

    lt_mvmt     = get_mvmt( i_werks = p_werks i_from = p_from i_to = p_to ).
    lt_stock    = get_stock_nonzero( i_werks = p_werks ).
    lt_bom_fg   = get_fg_with_bom( i_werks = p_werks ).
    lt_bom_comp = get_bom_components( i_werks = p_werks ).

    DATA lt_union TYPE ty_t_matnr.
    lt_union = lt_mvmt.
    APPEND LINES OF lt_stock TO lt_union.
    SORT lt_union.
    DELETE ADJACENT DUPLICATES FROM lt_union.

    DATA lt_bom_only_calc TYPE ty_t_matnr.
    IF lt_bom_comp IS NOT INITIAL.
      LOOP AT lt_bom_comp ASSIGNING FIELD-SYMBOL(<mcomp>).
        READ TABLE lt_union WITH KEY table_line = <mcomp> TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          APPEND <mcomp> TO lt_bom_only_calc.
        ENDIF.
      ENDLOOP.
      SORT lt_bom_only_calc.
      DELETE ADJACENT DUPLICATES FROM lt_bom_only_calc.
    ENDIF.
    lt_bom_only = lt_bom_only_calc.

    DATA lt_main TYPE ty_t_matnr.
    lt_main = lt_union.
    IF lt_main IS NOT INITIAL.
      lt_sum = get_stock_sum( i_werks = p_werks it_matnr = lt_main ).
    ENDIF.

    lt_out = build_output(
      i_werks      = p_werks
      it_mvmt      = lt_mvmt
      it_stock     = lt_stock
      it_bom_fg    = lt_bom_fg
      it_bom_only  = lt_bom_only
      it_stock_sum = lt_sum ).

    IF lt_out IS INITIAL.
      MESSAGE '데이터가 없습니다.' TYPE 'S'.
      RETURN.
    ENDIF.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out ).

    lo_alv->get_display_settings( )->set_list_header(
      value = '플랜트 ' && p_werks && ' 자재 현황: 입출고/재고 및 BOM 정보' ).
    lo_alv->display( ).
  ENDMETHOD.

  METHOD get_mvmt.
    DATA lt TYPE ty_t_matnr.
    SELECT DISTINCT
           mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
     WHERE mseg~werks = @i_werks
       AND mkpf~budat BETWEEN @i_from AND @i_to
      INTO TABLE @lt
      UP TO 100000 ROWS.
    rt_matnr = lt.
    SORT rt_matnr.
    DELETE ADJACENT DUPLICATES FROM rt_matnr.
  ENDMETHOD.

  METHOD get_stock_nonzero.
    DATA lt TYPE ty_t_matnr.
    SELECT DISTINCT
           mard~matnr
      FROM mard
     WHERE mard~werks = @i_werks
       AND mard~labst > 0
      INTO TABLE @lt
      UP TO 100000 ROWS.
    rt_matnr = lt.
    SORT rt_matnr.
    DELETE ADJACENT DUPLICATES FROM rt_matnr.
  ENDMETHOD.

  METHOD get_stock_sum.
    DATA lt TYPE ty_t_stock_sum.
    IF it_matnr IS INITIAL.
      rt_sum = lt.
      RETURN.
    ENDIF.

    DATA lr_matnr TYPE RANGE OF mara-matnr.
    LOOP AT it_matnr ASSIGNING FIELD-SYMBOL(<m>).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = <m> ) TO lr_matnr.
    ENDLOOP.

    SELECT
           mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard
     WHERE mard~werks = @i_werks
       AND mard~matnr IN @lr_matnr
     GROUP BY mard~matnr
      INTO TABLE @lt.
    rt_sum = lt.
  ENDMETHOD.

  METHOD get_fg_with_bom.
    DATA lt TYPE ty_t_matnr.
    SELECT DISTINCT
           mast~matnr
      FROM mast
      INNER JOIN mara AS ma
        ON ma~matnr = mast~matnr
     WHERE mast~werks = @i_werks
       AND ma~mtart = 'FERT'
      INTO TABLE @lt
      UP TO 100000 ROWS.
    rt_matnr = lt.
    SORT rt_matnr.
    DELETE ADJACENT DUPLICATES FROM rt_matnr.
  ENDMETHOD.

  METHOD get_bom_components.
    DATA lt TYPE ty_t_matnr.
    SELECT DISTINCT
           stpo~idnrk
      FROM mast
      INNER JOIN stko
        ON stko~stlnr = mast~stlnr
       AND stko~stlal = mast~stlal
      INNER JOIN stpo
        ON stpo~stlnr = stko~stlnr
     WHERE mast~werks = @i_werks
      INTO TABLE @lt
      UP TO 100000 ROWS.
    rt_matnr = lt.
    SORT rt_matnr.
    DELETE ADJACENT DUPLICATES FROM rt_matnr.
  ENDMETHOD.

  METHOD get_texts.
    DATA lt TYPE ty_t_makt.
    IF it_matnr IS INITIAL.
      rt_texts = lt.
      RETURN.
    ENDIF.

    DATA lr_matnr TYPE RANGE OF mara-matnr.
    LOOP AT it_matnr ASSIGNING FIELD-SYMBOL(<m>).
      APPEND VALUE #( sign = 'I' option = 'EQ' low = <m> ) TO lr_matnr.
    ENDLOOP.

    SELECT
           makt~matnr,
           makt~spras,
           makt~maktx
      FROM makt
     WHERE makt~matnr IN @lr_matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt.
    rt_texts = lt.
  ENDMETHOD.

  METHOD build_output.
    DATA lt_all   TYPE ty_t_matnr.
    DATA lt_texts TYPE ty_t_makt.
    DATA lt_out   TYPE ty_t_out.

    lt_all = it_mvmt.
    APPEND LINES OF it_stock TO lt_all.
    APPEND LINES OF it_bom_only TO lt_all.
    SORT lt_all.
    DELETE ADJACENT DUPLICATES FROM lt_all.

    IF lt_all IS NOT INITIAL.
      lt_texts = get_texts( lt_all ).
    ENDIF.

    DATA lt_main TYPE ty_t_matnr.
    lt_main = it_mvmt.
    APPEND LINES OF it_stock TO lt_main.
    SORT lt_main.
    DELETE ADJACENT DUPLICATES FROM lt_main.

    LOOP AT lt_main ASSIGNING FIELD-SYMBOL(<m>).
      DATA(ls) = VALUE ty_out( ).
      ls-matnr = <m>.
      ls-werks = i_werks.

      READ TABLE it_mvmt WITH KEY table_line = <m> TRANSPORTING NO FIELDS.
      ls-mvmt = COND abap_bool( WHEN sy-subrc = 0 THEN abap_true ELSE abap_false ).

      READ TABLE it_stock WITH KEY table_line = <m> TRANSPORTING NO FIELDS.
      IF sy-subrc = 0 AND ls-mvmt = abap_false.
        ls-remark = '재고만 있음'.
      ELSEIF ls-mvmt = abap_true.
        ls-remark = '입출고 있음'.
      ELSE.
        ls-remark = ''.
      ENDIF.

      READ TABLE it_bom_fg WITH KEY table_line = <m> TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        ls-section = '완제품(BOM)'.
      ELSE.
        ls-section = '일반'.
      ENDIF.

      READ TABLE lt_texts ASSIGNING FIELD-SYMBOL(<tx>)
        WITH KEY matnr = <m> spras = sy-langu.
      IF sy-subrc = 0.
        ls-maktx = <tx>-maktx.
      ENDIF.

      READ TABLE it_stock_sum ASSIGNING FIELD-SYMBOL(<ss>) WITH KEY matnr = <m>.
      IF sy-subrc = 0.
        ls-stock = <ss>-qty.
      ELSE.
        ls-stock = 0.
      ENDIF.

      APPEND ls TO lt_out.
    ENDLOOP.

    LOOP AT it_bom_only ASSIGNING FIELD-SYMBOL(<c>).
      DATA(lc) = VALUE ty_out( ).
      lc-matnr   = <c>.
      lc-werks   = i_werks.
      lc-mvmt    = abap_false.
      lc-remark  = 'BOM 만 있음'.
      lc-section = 'BOM 요소'.
      READ TABLE lt_texts ASSIGNING FIELD-SYMBOL(<tc>)
        WITH KEY matnr = <c> spras = sy-langu.
      IF sy-subrc = 0.
        lc-maktx = <tc>-maktx.
      ENDIF.
      lc-stock = 0.
      APPEND lc TO lt_out.
    ENDLOOP.

    SORT lt_out BY section matnr.
    rt_out = lt_out.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).