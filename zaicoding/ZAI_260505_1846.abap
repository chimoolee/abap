REPORT ZAI_260505_1846.

SELECT-OPTIONS s_budat FOR mkpf~budat.
SELECT-OPTIONS s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr     TYPE mara-matnr,
        werks     TYPE mard-werks,
        has_mov   TYPE abap_bool,
        has_stock TYPE abap_bool,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mara_info,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mara_info,
      ty_t_mara_info TYPE STANDARD TABLE OF ty_mara_info WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        werks  TYPE mard-werks,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov    TYPE ty_t_key.
    DATA lt_stock  TYPE ty_t_key.
    DATA lt_result TYPE ty_t_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lr_matnr TYPE RANGE OF mara-matnr.
    DATA lr_line  LIKE LINE OF lr_matnr.

    " 1) Materials with movements in selected plants and posting dates
    SELECT
      m~matnr,
      m~werks
      FROM mseg AS m
      INNER JOIN mkpf AS k
        ON k~mblnr = m~mblnr
       AND k~mjahr = m~mjahr
      WHERE m~werks IN @s_werks
        AND k~budat IN @s_budat
      GROUP BY m~matnr, m~werks
      INTO TABLE @DATA(lt_mov_raw).

    LOOP AT lt_mov_raw INTO DATA(ls_mov_raw).
      DATA(ls_key) = VALUE ty_key(
        matnr     = ls_mov_raw-matnr
        werks     = ls_mov_raw-werks
        has_mov   = abap_true
        has_stock = abap_false ).
      APPEND ls_key TO lt_mov.
    ENDLOOP.

    " 2) Materials with non-zero current stock in selected plants
    SELECT
      mard~matnr,
      mard~werks
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @DATA(lt_stock_raw).

    LOOP AT lt_stock_raw INTO DATA(ls_stock_raw).
      DATA(ls_key2) = VALUE ty_key(
        matnr     = ls_stock_raw-matnr
        werks     = ls_stock_raw-werks
        has_mov   = abap_false
        has_stock = abap_true ).
      APPEND ls_key2 TO lt_stock.
    ENDLOOP.

    " 3) Merge movement and stock keys
    DATA lt_all TYPE ty_t_key.
    APPEND LINES OF lt_mov   TO lt_all.
    APPEND LINES OF lt_stock TO lt_all.

    SORT lt_all BY matnr werks.
    DATA lt_merged TYPE ty_t_key.

    LOOP AT lt_all INTO DATA(ls_all).
      READ TABLE lt_merged INTO DATA(ls_exist)
        WITH KEY matnr = ls_all-matnr werks = ls_all-werks.
      IF sy-subrc = 0.
        IF ls_all-has_mov = abap_true.
          ls_exist-has_mov = abap_true.
        ENDIF.
        IF ls_all-has_stock = abap_true.
          ls_exist-has_stock = abap_true.
        ENDIF.
        MODIFY lt_merged FROM ls_exist
          TRANSPORTING has_mov has_stock
          WHERE matnr = ls_exist-matnr AND werks = ls_exist-werks.
      ELSE.
        APPEND ls_all TO lt_merged.
      ENDIF.
    ENDLOOP.

    " 4) Build material number list and range
    LOOP AT lt_merged INTO DATA(ls_mg).
      APPEND ls_mg-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    LOOP AT lt_matnr INTO DATA(lv_matnr).
      CLEAR lr_line.
      lr_line-sign = 'I'.
      lr_line-option = 'EQ'.
      lr_line-low = lv_matnr.
      APPEND lr_line TO lr_matnr.
    ENDLOOP.

    " 5) Read material master + text
    DATA lt_info TYPE ty_t_mara_info.
    IF lr_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_info
        WHERE mara~matnr IN @lr_matnr.
    ENDIF.

    " 6) Build final result with status
    LOOP AT lt_merged INTO DATA(ls_row).
      READ TABLE lt_info INTO DATA(ls_info)
        WITH KEY matnr = ls_row-matnr.
      DATA(lv_status) = COND char20(
        WHEN ls_row-has_mov = abap_true AND ls_row-has_stock = abap_true
          THEN '입출고+재고'
        WHEN ls_row-has_mov = abap_true
          THEN '입출고 있음'
        WHEN ls_row-has_stock = abap_true
          THEN '재고만 있음'
        ELSE ' ' ).

      APPEND VALUE ty_result(
        matnr  = ls_row-matnr
        mtart  = ls_info-mtart
        matkl  = ls_info-matkl
        maktx  = ls_info-maktx
        werks  = ls_row-werks
        status = lv_status ) TO lt_result.
    ENDLOOP.

    " 7) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).