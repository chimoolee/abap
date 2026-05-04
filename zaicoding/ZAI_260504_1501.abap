REPORT ZAI_260504_1501.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_beg  TYPE sy-datum DEFAULT sy-datum.
PARAMETERS p_end  TYPE sy-datum DEFAULT sy-datum.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES: BEGIN OF ty_stock,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock.
    TYPES ty_t_matnr  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    TYPES ty_t_stock  TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES: BEGIN OF ty_main,
             matnr      TYPE mara-matnr,
             maktx      TYPE makt-maktx,
             werks      TYPE werks_d,
             mtart      TYPE mara-mtart,
             stock_qty  TYPE mard-labst,
             status     TYPE char20,
           END OF ty_main.
    TYPES ty_t_main TYPE STANDARD TABLE OF ty_main WITH EMPTY KEY.

    TYPES: BEGIN OF ty_bom,
             kind       TYPE char5,     "헤더/요소
             matnr      TYPE mara-matnr,
             maktx      TYPE makt-maktx,
             werks      TYPE werks_d,
             mtart      TYPE mara-mtart,
             stock_qty  TYPE mard-labst,
             status     TYPE char20,
           END OF ty_bom.
    TYPES ty_t_bom TYPE STANDARD TABLE OF ty_bom WITH EMPTY KEY.

    CLASS-METHODS select_movements
      IMPORTING i_werks TYPE werks_d
                i_beg   TYPE sy-datum
                i_end   TYPE sy-datum
      RETURNING VALUE(rt_move) TYPE ty_t_matnr.
    CLASS-METHODS select_stock
      IMPORTING i_werks TYPE werks_d
      RETURNING VALUE(rt_stock) TYPE ty_t_stock.
    CLASS-METHODS select_bom_headers
      IMPORTING i_werks TYPE werks_d
      RETURNING VALUE(rt_hdr) TYPE ty_t_matnr.
    CLASS-METHODS select_bom_components
      IMPORTING i_werks TYPE werks_d
      RETURNING VALUE(rt_comp) TYPE ty_t_matnr.
    CLASS-METHODS select_texts
      IMPORTING it_matnr TYPE ty_t_matnr
      RETURNING VALUE(rt_texts) TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    CLASS-METHODS select_mara
      IMPORTING it_matnr TYPE ty_t_matnr
      RETURNING VALUE(rt_mara) TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    CLASS-METHODS build_main
      IMPORTING it_move  TYPE ty_t_matnr
                it_stock TYPE ty_t_stock
                it_texts TYPE STANDARD TABLE OF makt WITH EMPTY KEY
                it_mara  TYPE STANDARD TABLE OF mara WITH EMPTY KEY
                i_werks  TYPE werks_d
      RETURNING VALUE(rt_main) TYPE ty_t_main.
    CLASS-METHODS build_bom
      IMPORTING it_hdr   TYPE ty_t_matnr
                it_comp  TYPE ty_t_matnr
                it_move  TYPE ty_t_matnr
                it_stock TYPE ty_t_stock
                it_texts TYPE STANDARD TABLE OF makt WITH EMPTY KEY
                it_mara  TYPE STANDARD TABLE OF mara WITH EMPTY KEY
                i_werks  TYPE werks_d
      RETURNING VALUE(rt_bom) TYPE ty_t_bom.
    CLASS-METHODS show_alv
      IMPORTING it_table TYPE STANDARD TABLE
                i_title  TYPE string.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lv_beg TYPE sy-datum VALUE p_beg.
    DATA lv_end TYPE sy-datum VALUE p_end.

    IF lv_beg GT lv_end.
      DATA lv_tmp TYPE sy-datum.
      lv_tmp = lv_beg.
      lv_beg = lv_end.
      lv_end = lv_tmp.
    ENDIF.

    DATA(lt_move) = select_movements( i_werks = p_werks i_beg = lv_beg i_end = lv_end ).
    DATA(lt_stock) = select_stock( i_werks = p_werks ).

    "Collect all materials needed for text/type lookup
    DATA lt_keys TYPE ty_t_matnr.
    APPEND LINES OF lt_move TO lt_keys.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<s>).
      IF <s>-qty NE 0.
        IF line_exists( lt_keys[ table_line = <s>-matnr ] ) IS INITIAL.
          APPEND <s>-matnr TO lt_keys.
        ENDIF.
      ENDIF.
    ENDLOOP.

    DATA(lt_bom_hdr)  = select_bom_headers( i_werks = p_werks ).
    DATA(lt_bom_comp) = select_bom_components( i_werks = p_werks ).

    APPEND LINES OF lt_bom_hdr  TO lt_keys.
    APPEND LINES OF lt_bom_comp TO lt_keys.

    "Unique-ify lt_keys (simple dedup)
    DATA lt_all TYPE ty_t_matnr.
    LOOP AT lt_keys ASSIGNING FIELD-SYMBOL(<k>).
      IF line_exists( lt_all[ table_line = <k> ] ) IS INITIAL.
        APPEND <k> TO lt_all.
      ENDIF.
    ENDLOOP.

    DATA(lt_texts) = select_texts( lt_all ).
    DATA(lt_mara)  = select_mara( lt_all ).

    DATA(lt_main) = build_main(
      it_move  = lt_move
      it_stock = lt_stock
      it_texts = lt_texts
      it_mara  = lt_mara
      i_werks  = p_werks ).

    DATA(lt_bom) = build_bom(
      it_hdr   = lt_bom_hdr
      it_comp  = lt_bom_comp
      it_move  = lt_move
      it_stock = lt_stock
      it_texts = lt_texts
      it_mara  = lt_mara
      i_werks  = p_werks ).

    DATA lv_title1 TYPE string.
    lv_title1 = |자재 실적/재고 현황 (플랜트 { p_werks } 기간 { lv_beg }~{ lv_end })|.

    DATA lv_title2 TYPE string.
    lv_title2 = |BOM 관련 자재 (플랜트 { p_werks })|.

    show_alv( it_table = lt_main i_title = lv_title1 ).
    show_alv( it_table = lt_bom  i_title = lv_title2 ).
  ENDMETHOD.

  METHOD select_movements.
    DATA lt_move TYPE ty_t_matnr.
    SELECT DISTINCT md~matnr
      FROM matdoc AS md
      WHERE md~werks       = @i_werks
        AND md~budat_mkpf >= @i_beg
        AND md~budat_mkpf <= @i_end
      INTO TABLE @lt_move.
    rt_move = lt_move.
  ENDMETHOD.

  METHOD select_stock.
    DATA lt_stock TYPE ty_t_stock.
    SELECT mr~matnr,
           SUM( mr~labst ) AS qty
      FROM mard AS mr
      WHERE mr~werks = @i_werks
      GROUP BY mr~matnr
      INTO TABLE @lt_stock.
    rt_stock = lt_stock.
  ENDMETHOD.

  METHOD select_bom_headers.
    DATA lt_hdr TYPE ty_t_matnr.
    SELECT DISTINCT sk~matnr
      FROM stko AS sk
      WHERE sk~stlty = 'M'
        AND sk~werks = @i_werks
        AND sk~matnr IS NOT NULL
      INTO TABLE @lt_hdr.
    rt_hdr = lt_hdr.
  ENDMETHOD.

  METHOD select_bom_components.
    DATA lt_comp TYPE ty_t_matnr.
    SELECT DISTINCT sp~idnrk
      FROM stpo AS sp
      INNER JOIN stko AS sk
        ON  sp~stlty = sk~stlty
        AND sp~stlnr = sk~stlnr
        AND sp~stlal = sk~stlal
      WHERE sk~stlty = 'M'
        AND sk~werks = @i_werks
        AND sp~idnrk IS NOT NULL
      INTO TABLE @lt_comp.
    rt_comp = lt_comp.
  ENDMETHOD.

  METHOD select_texts.
    DATA lt_texts TYPE STANDARD TABLE OF makt WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      rt_texts = lt_texts.
      RETURN.
    ENDIF.
    SELECT ma~matnr, ma~spras, ma~maktx
      FROM makt AS ma
      FOR ALL ENTRIES IN @it_matnr
      WHERE ma~matnr = @it_matnr-table_line
        AND ma~spras = @sy-langu
      INTO TABLE @lt_texts.
    rt_texts = lt_texts.
  ENDMETHOD.

  METHOD select_mara.
    DATA lt_mara TYPE STANDARD TABLE OF mara WITH EMPTY KEY.
    IF it_matnr IS INITIAL.
      rt_mara = lt_mara.
      RETURN.
    ENDIF.
    SELECT ma~matnr, ma~mtart
      FROM mara AS ma
      FOR ALL ENTRIES IN @it_matnr
      WHERE ma~matnr = @it_matnr-table_line
      INTO TABLE @lt_mara.
    rt_mara = lt_mara.
  ENDMETHOD.

  METHOD build_main.
    DATA lt_main TYPE ty_t_main.
    DATA