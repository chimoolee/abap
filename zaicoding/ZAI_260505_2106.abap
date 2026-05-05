REPORT ZAI_260505_2106.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,
  s_werks FOR mard~werks.

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
        stock  TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.

    " Material lists (elementary) per hard rules
    DATA lt_mov_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Stock aggregation by material
    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    DATA lt_stock_agg TYPE ty_t_stock.

    " 1) Materials with goods movements in date/plant
    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov_matnr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Materials with current non-zero stock in selected plants
    SELECT DISTINCT
      mard~matnr
      FROM mard
      INTO TABLE @lt_stock_matnr
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    " 3) Union of both material lists
    APPEND LINES OF lt_mov_matnr   TO lt_all_matnr.
    APPEND LINES OF lt_stock_matnr TO lt_all_matnr.
    SORT lt_all_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_all_matnr.

    " Early exit if nothing to show
    IF lt_all_matnr IS INITIAL.
      DATA msg TYPE string.
      msg = '선택된 조건에 해당하는 자재가 없습니다.'.
      WRITE / msg.
      RETURN.
    ENDIF.

    " 4) Stock aggregation for display (sum over selected plants)
    SELECT
      mard~matnr,
      SUM( mard~labst ) AS qty
      FROM mard
      INTO TABLE @lt_stock_agg
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr.

    SORT lt_mov_matnr.
    SORT lt_stock_matnr.
    SORT lt_stock_agg BY matnr.

    " 5) Read basic material master and text for union set
    TYPES:
      BEGIN OF ty_mm,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mm,
      ty_t_mm TYPE STANDARD TABLE OF ty_mm WITH EMPTY KEY.

    DATA lt_mm TYPE ty_t_mm.

    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_mm
      WHERE mara~matnr IN @lt_all_matnr.

    " 6) Build final result with status
    DATA ls_mm    TYPE ty_mm.
    DATA ls_res   TYPE ty_result.
    DATA ls_stock TYPE ty_stock.

    LOOP AT lt_mm INTO ls_mm.
      CLEAR ls_res.
      MOVE-CORRESPONDING ls_mm TO ls_res.

      READ TABLE lt_stock_agg INTO ls_stock WITH KEY matnr = ls_mm-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-stock = ls_stock-qty.
      ELSE.
        CLEAR ls_res-stock.
      ENDIF.

      " Status
      DATA lv_has_mov TYPE abap_bool VALUE abap_false.
      READ TABLE lt_mov_matnr WITH KEY table_line = ls_mm-matnr TRANSPORTING NO FIELDS
           BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_res-status = '입출고 있음'.
      ELSEIF ls_res-stock IS NOT INITIAL AND ls_res-stock <> 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        " Should not occur due to union, but keep safe
        ls_res-status = '기타'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " 7) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        WRITE: / 'ALV 표시 중 오류: ', lx_msg->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).