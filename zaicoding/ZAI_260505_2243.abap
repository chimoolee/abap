REPORT ZAI_260505_2243.

TABLES mara.

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
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY,
      BEGIN OF ty_result,
        matnr     TYPE mara-matnr,
        werks     TYPE werks_d,
        mtart     TYPE mara-mtart,
        matkl     TYPE mara-matkl,
        maktx     TYPE makt-maktx,
        stock_qty TYPE mard-labst,
        status    TYPE string,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov    TYPE ty_t_key.
    DATA lt_stock  TYPE ty_t_stock.
    DATA lt_keys   TYPE ty_t_key.
    DATA lt_attr   TYPE ty_t_attr.
    DATA lt_result TYPE ty_t_result.

    " 1) Movements (MSEG/MKPF) by posting date and plant
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
        AND mseg~matnr IS NOT NULL.

    " 2) Current stock > 0 by plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @lt_stock.

    " 3) Union of keys from movements and stock
    lt_keys = VALUE #( BASE lt_keys FOR ls IN lt_mov ( matnr = ls-matnr werks = ls-werks ) ).
    lt_keys = VALUE #( BASE lt_keys FOR ls IN lt_stock ( matnr = ls-matnr werks = ls-werks ) ).
    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    IF lt_keys IS INITIAL.
      WRITE: / '선택한 조건의 데이터가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Read attributes/texts for all materials in scope
    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    LOOP AT lt_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_attr
      WHERE mara~matnr IN @lt_matnr.

    SORT lt_attr BY matnr.
    SORT lt_mov BY matnr werks.
    SORT lt_stock BY matnr werks.

    " 5) Build result
    LOOP AT lt_keys INTO ls_key.
      DATA(ls_res) = VALUE ty_result( ).
      ls_res-matnr = ls_key-matnr.
      ls_res-werks = ls_key-werks.

      READ TABLE lt_attr INTO DATA(ls_attr)
        WITH KEY matnr = ls_key-matnr
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = ls_attr-mtart.
        ls_res-matkl = ls_attr-matkl.
        ls_res-maktx = ls_attr-maktx.
      ENDIF.

      READ TABLE lt_stock INTO DATA(ls_stk)
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-stock_qty = ls_stk-qty.
      ELSE.
        ls_res-stock_qty = 0.
      ENDIF.

      READ TABLE lt_mov TRANSPORTING NO FIELDS
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-status = '입출고 있음'.
      ELSE.
        ls_res-status = '재고만 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        WRITE: / 'ALV 표시 중 오류:', lx_msg->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).