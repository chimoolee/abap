REPORT ZAI_260505_2008.

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
      ty_t_attr TYPE HASHED TABLE OF ty_attr WITH UNIQUE KEY matnr,
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

    DATA lt_move_keys TYPE ty_t_key.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_keys      TYPE ty_t_key.
    DATA lt_result    TYPE ty_t_result.
    DATA lt_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_attr      TYPE ty_t_attr.

    " 1) Movement-based materials by plant and posting date
    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move_keys
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Current stock (non-zero) per material and plant
    SELECT
      matnr,
      werks,
      SUM( labst ) AS qty
      FROM mard
      INTO TABLE @lt_stock
      WHERE werks IN @s_werks
      GROUP BY matnr, werks
      HAVING SUM( labst ) <> 0.

    " 3) Build union of keys (materials/plants from movement or non-zero stock)
    lt_keys = lt_move_keys.
    APPEND LINES OF lt_stock TO lt_keys.
    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    IF lt_keys IS INITIAL.
      WRITE: / '선택 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    " 4) Prepare material number list for attribute select
    LOOP AT lt_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 5) Read basic material attributes and text
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @DATA(lt_attr_raw)
      WHERE mara~matnr IN @lt_matnr.

    lt_attr = CORRESPONDING ty_t_attr( lt_attr_raw ).

    " 6) Build result rows with status
    LOOP AT lt_keys INTO ls_key.
      DATA(ls_res) = VALUE ty_result(
        matnr = ls_key-matnr
        werks = ls_key-werks
        stock = 0
        status = '' ).

      " Attributes
      READ TABLE lt_attr WITH TABLE KEY matnr = ls_key-matnr INTO DATA(ls_attr).
      IF sy-subrc = 0.
        ls_res-mtart = ls_attr-mtart.
        ls_res-matkl = ls_attr-matkl.
        ls_res-maktx = ls_attr-maktx.
      ENDIF.

      " Stock qty (non-zero list already filtered, but read exact value)
      READ TABLE lt_stock WITH KEY matnr = ls_key-matnr werks = ls_key-werks INTO DATA(ls_stk).
      IF sy-subrc = 0.
        ls_res-stock = ls_stk-qty.
      ENDIF.

      " Status
      READ TABLE lt_move_keys WITH KEY matnr = ls_key-matnr werks = ls_key-werks TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0 AND ls_res-stock <> 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        ls_res-status = '입출고 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " 7) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_sAlv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        WRITE: / 'ALV 오류: ', lx->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).