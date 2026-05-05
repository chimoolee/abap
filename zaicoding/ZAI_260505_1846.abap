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

    DATA lt_keys   TYPE ty_t_key.
    DATA lt_mov    TYPE ty_t_key.
    DATA lt_stock  TYPE ty_t_key.
    DATA lt_info   TYPE ty_t_mara_info.
    DATA lt_result TYPE ty_t_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lr_matnr TYPE RANGE OF mara-matnr.

    DATA ls_key   TYPE ty_key.
    DATA ls_info  TYPE ty_mara_info.
    DATA ls_res   TYPE ty_result.
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
      CLEAR ls_key.
      ls_key-matnr = ls_mov_raw-matnr.
      ls_key-werks = ls_mov_raw-werks.
      ls_key-has_mov = abap_true.
      APPEND ls_key TO lt_mov.
    ENDLOOP.

    " 2) Materials with non-zero current stock in selected plants
    SELECT
      mard~matnr,
      mard~werks
      FROM mard
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0
      GROUP BY mard~matnr, mard~werks
      INTO TABLE @DATA(lt_stock_raw).

    LOOP AT lt_stock_raw INTO DATA(ls_stock_raw).
      CLEAR ls_key.
      ls_key-matnr = ls_stock_raw-matnr.
      ls_key-werks = ls_stock_raw-werks.
      ls_key-has_stock = abap_true.
      APPEND ls_key TO lt_stock.
    ENDLOOP.

    " 3) Merge movement and stock keys
    DATA lt_all TYPE ty_t_key.
    APPEND LINES OF lt_mov   TO lt_all.
    APPEND LINES OF lt_stock TO lt_all.

    SORT lt_all BY matnr werks.
    DATA lt_merged TYPE ty_t_key.

    LOOP AT lt_all INTO ls_key.
      READ TABLE lt_merged INTO DATA(ls_exist)
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        IF ls_key-has_mov = abap_true.
          ls_exist-has_mov = abap_true.
        ENDIF.
        IF ls_key-has_stock = abap_true.
          ls_exist-has_stock = abap_true.
        ENDIF.
        MODIFY lt_merged FROM ls_exist
          TRANSPORTING has_mov has_stock
          WHERE matnr = ls_exist-matnr AND werks = ls_exist-werks.
      ELSE.
        APPEND ls_key TO lt_merged.
      ENDIF.
    ENDLOOP.

    " 4) Build material list and range for info select
    LOOP AT lt_merged INTO ls_key.
      APPEND ls_key-matnr TO lt_matnr.
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
    IF lr_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~mat