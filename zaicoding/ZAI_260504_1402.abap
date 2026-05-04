REPORT ZAI_260504_1402.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_dfrom TYPE sy-datum OBLIGATORY.
PARAMETERS p_dto   TYPE sy-datum OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    " Types
    TYPES: BEGIN OF ty_stock_sum,
             matnr TYPE mara-matnr,
             qty   TYPE mard-labst,
           END OF ty_stock_sum.

    TYPES: ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_out,
             section   TYPE char10,
             matnr     TYPE mara-matnr,
             maktx     TYPE makt-maktx,
             mtart     TYPE mara-mtart,
             werks     TYPE mard-werks,
             labst     TYPE mard-labst,
             status    TYPE char20,
             has_mov   TYPE abap_bool,
             has_stock TYPE abap_bool,
             has_bom   TYPE abap_bool,
           END OF ty_out.

    DATA lo_alv TYPE REF TO cl_salv_table.

    DATA lt_mov_matnr   TYPE ty_t_matnr.
    DATA lt_stock_sum   TYPE STANDARD TABLE OF ty_stock_sum WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE ty_t_matnr.
    DATA lt_union_gen   TYPE ty_t_matnr.

    DATA lt_fert_hdr    TYPE ty_t_matnr.
    DATA lt_bom_comp    TYPE ty_t_matnr.
    DATA lt_bom_all     TYPE ty_t_matnr.

    " 1) Materials with movements in MATDOC for plant and period
    SELECT DISTINCT md~matnr
      FROM matdoc AS md
      WHERE md~werks = @p_werks
        AND md~budat_mkpf BETWEEN @p_dfrom AND @p_dto
        AND md~matnr <> ''
      INTO TABLE @lt_mov_matnr.

    " 2) Materials with non-zero stock in MARD (sum per material on plant)
    SELECT mard~matnr,
           SUM( mard~labst ) AS qty
      FROM mard AS mard
      WHERE mard~werks = @p_werks
      GROUP BY mard~matnr
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock_sum.

    " Extract material numbers with stock
    IF lt_stock_sum IS NOT INITIAL.
      DATA(ls_stock) = VALUE ty_stock_sum( ).
      LOOP AT lt_stock_sum INTO ls_stock.
        APPEND ls_stock-matnr TO lt_stock_matnr.
      ENDLOOP.
    ENDIF.

    " 3) General union (movement OR stock)
    lt_union_gen = VALUE #( BASE lt_mov_matnr FOR mat IN lt_stock_matnr ( mat ) ).

    " Remove duplicates in union
    SORT lt_union_gen BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_union_gen COMPARING table_line.

    " 4) Build general output rows
    IF lt_union_gen IS NOT INITIAL.
      DATA lt_mara TYPE STANDARD TABLE OF mara-mtart WITH EMPTY KEY. "placeholder to satisfy syntax grouping (not used)
      " Fetch descriptions and types for union materials
      DATA lt_mara_info TYPE STANDARD TABLE OF ty_mara_info WITH EMPTY KEY.
      TYPES: BEGIN OF ty_mara_info,
               matnr TYPE mara-matnr,
               mtart TYPE mara-mtart,
             END OF ty_mara_info.
      SELECT ma~matnr,
             ma~mtart
        FROM mara AS ma
        FOR ALL ENTRIES IN @lt_union_gen
        WHERE ma~matnr = @lt_union_gen-table_line
        INTO TABLE @lt_mara_info.

      DATA lt_makt TYPE STANDARD TABLE OF ty_makt_info WITH EMPTY KEY.
      TYPES: BEGIN OF ty_makt_info,
               matnr TYPE makt-matnr,
               maktx TYPE makt-maktx,
             END OF ty_makt_info.
      SELECT mk~matnr,
             mk~maktx
        FROM makt AS mk
        FOR ALL ENTRIES IN @lt_union_gen
        WHERE mk~matnr = @lt_union_gen-table_line
          AND mk~spras = @sy-langu
        INTO TABLE @lt_makt.

      " Helper reads using READ TABLE for info lookup
      DATA ls_out TYPE ty_out.
      DATA ls_mara_i TYPE ty_mara_info.
      DATA ls_makt_i TYPE ty_makt_info.

      LOOP AT lt_union_gen ASSIGNING FIELD-SYMBOL(<mat>).
        CLEAR ls_out.
        ls_out-section = 'GENERAL'.
        ls_out-matnr   = <mat>.
        ls_out-werks   = p_werks.

        READ TABLE lt_mara_info INTO ls_mara_i WITH KEY matnr = <mat> BINARY SEARCH.
        IF sy-subrc = 0.
          ls_out-mtart = ls_mara_i-mtart.
        ENDIF.

        READ TABLE lt_makt INTO ls_makt_i WITH KEY matnr = <mat> BINARY SEARCH.
        IF sy-subrc = 0.
          ls_out-maktx = ls_makt_i-maktx.
        ENDIF.

        " Flags
        ls_out-has_mov = COND abap_bool( WHEN line_exists( lt_mov_matnr[ table_line = <mat> ] ) THEN abap_true ELSE abap_false ).
        ls_out-has_stock = COND abap_bool( WHEN line_exists( lt_stock_matnr[ table_line = <mat> ] ) THEN abap_true ELSE abap_false ).

        " Stock qty from lt_stock_sum
        READ TABLE lt_stock_sum INTO DATA(ls_ss) WITH KEY matnr = <mat> BINARY SEARCH.
        IF sy-subrc = 0.
          ls_out-labst = ls_ss-qty.
        ELSE.
          ls_out-labst = 0.
        ENDIF.

        " Status
        IF ls_out-has_mov = abap_true.
          ls_out-status = '입출고 실적 있음'.
        ELSEIF ls_out-has_stock = abap_true.
          ls_out-status = '재고만 있음'.
        ELSE.
          ls_out-status = ''.
        ENDIF.

        APPEND ls_out TO lt_out.
      ENDLOOP.
    ENDIF.

    " 5) BOM section for finished goods and their components
    " 5.1 Finished goods with BOM header assignments
    SELECT DISTINCT ma~matnr
      FROM mast AS mast
      INNER JOIN mara AS ma
        ON ma~matnr = mast~matnr
      WHERE mast~werks = @p_werks
        AND ma~mtart = 'FERT'
      INTO TABLE @lt_fert_hdr.

    " 5.2 Components of those BOMs
    IF lt_fert_hdr IS NOT INITIAL.
      SELECT DISTINCT stpo~idnrk
        FROM mast AS mast
        INNER JOIN mara AS ma
          ON ma~matnr = mast~matnr
        INNER JOIN stpo AS stpo
          ON stpo~stlnr = mast~stlnr
        WHERE mast~werks = @p_werks
          AND ma~mtart = 'FERT'
          AND stpo~idnrk <> ''
        INTO TABLE @lt_bom_comp.
    ENDIF.

    " Combine BOM section materials (headers + components)
    lt_bom_all = VALUE #( BASE lt_fert_hdr FOR m IN lt_bom_comp ( m ) ).
    SORT lt_bom_all BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_bom_all COMPARING table_line.

    " Fetch MARA and MAKT for BOM materials
    IF lt_bom_all IS NOT INITIAL.
      TYPES: BEGIN OF ty_mara2,
               matnr TYPE mara-matnr,
               mtart TYPE mara-mtart,
             END OF ty_mara2.
      DATA lt_mara2 TYPE STANDARD TABLE OF ty_mara2 WITH EMPTY KEY.
      SELECT ma~matnr,
             ma~mtart
        FROM mara AS ma
        FOR ALL ENTRIES IN @lt_bom_all
        WHERE ma~matnr = @lt_bom_all-table_line
        INTO TABLE @lt_mara2.

      DATA lt_makt2 TYPE STANDARD TABLE OF ty_makt_info WITH EMPTY KEY.
      SELECT mk~matnr,
             mk~maktx
        FROM makt AS mk
        FOR ALL ENTRIES IN @lt_bom_all
        WHERE mk~matnr = @lt_bom_all-table_line
          AND mk~spras = @sy-langu
        INTO TABLE @lt_makt2.

      " For status calculation, we need to know if material has movement or stock
      LOOP AT lt_bom_all ASSIGNING FIELD-SYMBOL(<bmat>).
        DATA(ls_bom_out) = VALUE ty_out( ).
        ls_bom_out-section = 'BOM'.
        ls_bom_out-matnr   = <bmat>.
        ls_bom_out-werks   = p_werks.

        READ TABLE lt_mara2 INTO DATA(ls_mara2) WITH KEY matnr = <bmat> BINARY SEARCH.
        IF sy-subrc = 0.
          ls_bom_out-mtart = ls_mara2-mtart.
        ENDIF.
        READ TABLE lt_makt2 INTO DATA(ls_makt2) WITH KEY matnr = <bmat> BINARY SEARCH.
        IF sy-subrc = 0.
          ls_bom_out-maktx = ls_makt2-maktx.
        ENDIF.

        ls_bom_out-has_mov   = COND abap_bool( WHEN line_exists( lt_mov_matnr[ table_line = <bmat> ] ) THEN abap_true ELSE abap_false ).
        ls_bom_out-has_stock = COND abap_bool( WHEN line_exists( lt_stock_matnr[ table_line = <bmat> ] ) THEN abap_true ELSE abap_false ).

        READ TABLE lt_stock_sum INTO DATA(ls_ss2) WITH KEY matnr = <bmat> BINARY SEARCH.
        IF sy-subrc = 0.
          ls_bom_out-labst = ls_ss2-qty.
        ELSE.
          ls_bom_out-labst = 0.
        ENDIF.

        IF ls_bom_out-has_mov = abap_true.
          ls_bom_out-status = '입출고 실적 있음'.
        ELSEIF ls_bom_out-has_stock = abap_true.
          ls_bom_out-status = '재고만 있음'.
        ELSE.
          ls_bom_out-status = 'BOM 만 있음'.
        ENDIF.

        APPEND ls_bom_out TO lt_out.
      ENDLOOP.
    ENDIF.

    " Final display
    IF lt_out IS INITIAL.
      MESSAGE '표시할 데이터가 없습니다.' TYPE 'S'.
      RETURN.
    ENDIF.

    " Sort for readability: section, status, matnr
    SORT lt_out BY section status matnr.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out ).

    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).