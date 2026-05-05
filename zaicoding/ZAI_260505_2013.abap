REPORT ZAI_260505_2013.

SELECT-OPTIONS s_budat FOR mkpf~budat.
SELECT-OPTIONS s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        stock TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mov,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_mov,
      ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        stock TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov   TYPE ty_t_mov.
    DATA lt_stock TYPE ty_t_stock.
    DATA lt_keys  TYPE ty_t_key.
    DATA lt_attr  TYPE ty_t_attr.
    DATA lt_result TYPE ty_t_result.

    " Movement keys by plant and posting date
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
      INTO TABLE @lt_mov.

    " Current stock per material/plant (sum over storage locations), only non-zero
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS stock
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " Build union keys
    DATA ls_key TYPE ty_key.
    LOOP AT lt_mov INTO DATA(ls_mov).
      ls_key-matnr = ls_mov-matnr.
      ls_key-werks = ls_mov-werks.
      APPEND ls_key TO lt_keys.
    ENDLOOP.
    LOOP AT lt_stock INTO DATA(ls_stock).
      ls_key-matnr = ls_stock-matnr.
      ls_key-werks = ls_stock-werks.
      APPEND ls_key TO lt_keys.
    ENDLOOP.

    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    IF lt_keys IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " Read attributes and text
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      FOR ALL ENTRIES IN @lt_keys
      WHERE mara~matnr = @lt_keys-matnr
      INTO TABLE @lt_attr.

    SORT lt_attr BY matnr.

    " Prepare hashed lookup tables
    DATA lt_mov_h TYPE HASHED TABLE OF ty_mov WITH UNIQUE KEY matnr werks.
    DATA lt_stock_h TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.
    lt_mov_h = lt_mov.
    lt_stock_h = lt_stock.

    " Build result
    DATA ls_result TYPE ty_result.
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_result.
      ls_result-matnr = ls_key-matnr.
      ls_result-werks = ls_key-werks.

      READ TABLE lt_attr INTO DATA(ls_attr) WITH KEY matnr = ls_key-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_result-mtart = ls_attr-mtart.
        ls_result-matkl = ls_attr-matkl.
        ls_result-maktx = ls_attr-maktx.
      ENDIF.

      READ TABLE lt_stock_h INTO ls_stock WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        ls_result-stock = ls_stock-stock.
      ELSE.
        ls_result-stock = 0.
      ENDIF.

      READ TABLE lt_mov_h INTO ls_mov WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        ls_result-status = '입출고 있음'.
      ELSEIF ls_result-stock <> 0.
        ls_result-status = '재고만 있음'.
      ELSE.
        ls_result-status = '해당 없음'.
      ENDIF.

      APPEND ls_result TO lt_result.
    ENDLOOP.

    IF lt_result IS INITIAL.
      WRITE: / '표시할 데이터가 없습니다.'.
      RETURN.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).