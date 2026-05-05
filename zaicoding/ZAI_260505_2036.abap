REPORT ZAI_260505_2036.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,
  s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_mov,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
      END OF ty_mov,
      ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY,
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        labst TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        labst TYPE mard-labst,
        status TYPE char20,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        labst TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov   TYPE ty_t_mov.
    DATA lt_stock TYPE ty_t_stock.
    DATA lt_keys  TYPE ty_t_key.
    DATA lt_result TYPE ty_t_result.

    " 1) Materials with movements in period and plant
    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr IS NOT INITIAL.

    " 2) Current stock not zero in selected plants
    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    " 3) Build combined key list
    DATA ls_key TYPE ty_key.
    DATA ls_mov TYPE ty_mov.
    DATA ls_stock TYPE ty_stock.

    " Helper hashed index for quick stock lookup
    TYPES: BEGIN OF ty_hs_key,
             matnr TYPE mara-matnr,
             werks TYPE mseg-werks,
           END OF ty_hs_key.
    TYPES ty_hs_tab TYPE HASHED TABLE OF ty_stock
                     WITH UNIQUE KEY matnr werks.

    DATA lt_stock_h TYPE ty_hs_tab.
    lt_stock_h = lt_stock.

    LOOP AT lt_mov INTO ls_mov.
      CLEAR ls_key.
      ls_key-matnr = ls_mov-matnr.
      ls_key-werks = ls_mov-werks.
      READ TABLE lt_stock_h INTO ls_stock
           WITH TABLE KEY matnr = ls_mov-matnr
                          werks = ls_mov-werks.
      IF sy-subrc = 0.
        ls_key-labst = ls_stock-labst.
      ELSE.
        CLEAR ls_key-labst.
      ENDIF.
      ls_key-status = '입출고 실적 있음'.
      APPEND ls_key TO lt_keys.
    ENDLOOP.

    " Add stock-only entries (no movement)
    LOOP AT lt_stock INTO ls_stock.
      READ TABLE lt_keys WITH KEY matnr = ls_stock-matnr
                                  werks = ls_stock-werks
                           TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        CLEAR ls_key.
        ls_key-matnr = ls_stock-matnr.
        ls_key-werks = ls_stock-werks.
        ls_key-labst = ls_stock-labst.
        ls_key-status = '재고만 있음'.
        APPEND ls_key TO lt_keys.
      ENDIF.
    ENDLOOP.

    IF lt_keys IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Enrich with MARA/MAKT
    TYPES: BEGIN OF ty_map,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             matkl TYPE mara-matkl,
             maktx TYPE makt-maktx,
           END OF ty_map,
           ty_t_map TYPE STANDARD TABLE OF ty_map WITH EMPTY KEY.

    DATA lt_map TYPE ty_t_map.
    DATA ls_map TYPE ty_map.

    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_map
      FOR ALL ENTRIES IN @lt_keys
      WHERE mara~matnr = @lt_keys-matnr.

    SORT lt_map BY matnr.

    DATA ls_res TYPE ty_result.
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_res.
      ls_res-matnr = ls_key-matnr.
      ls_res-werks = ls_key-werks.
      ls_res-labst = ls_key-labst.
      ls_res-status = ls_key-status.

      READ TABLE lt_map INTO ls_map WITH KEY matnr = ls_key-matnr
                                     BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = ls_map-mtart.
        ls_res-matkl = ls_map-matkl.
        ls_res-maktx = ls_map-maktx.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " 5) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        WRITE: / 'ALV 오류: ', lx_msg->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).