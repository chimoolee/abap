REPORT ZAI_260504_2006.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE mard-werks,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_master,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_master,
      ty_t_master TYPE STANDARD TABLE OF ty_master WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        werks  TYPE mseg-werks,
        qty    TYPE mard-labst,
        status TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov    TYPE ty_t_key.
    DATA lt_stock  TYPE ty_t_stock.
    DATA lt_keys   TYPE ty_t_key.
    DATA lt_master TYPE ty_t_master.
    DATA lt_result TYPE ty_t_result.

    DATA ls_key TYPE ty_key.
    DATA ls_stk TYPE ty_stock.
    DATA ls_mst TYPE ty_master.
    DATA ls_res TYPE ty_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Materials with goods movements (posting date and plant)
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    " 2) Materials with current non-zero stock by plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0.

    " 3) Union keys of movement and non-zero stock
    lt_keys = VALUE #( ).
    APPEND LINES OF lt_mov TO lt_keys.
    LOOP AT lt_stock INTO ls_stk.
      ls_key-matnr = ls_stk-matnr.
      ls_key-werks = ls_stk-werks.
      APPEND ls_key TO lt_keys.
    ENDLOOP.

    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    " 4) Prepare master data and texts
    LOOP AT lt_keys INTO ls_key.
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_master
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    SORT lt_master BY matnr.
    SORT lt_mov BY matnr werks.
    SORT lt_stock BY matnr werks.

    " 5) Build result
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_res.
      ls_res-matnr = ls_key-matnr.
      ls_res-werks = ls_key-werks.

      READ TABLE lt_master INTO ls_mst
        WITH KEY matnr = ls_key-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = ls_mst-mtart.
        ls_res-matkl = ls_mst-matkl.
        ls_res-maktx = ls_mst-maktx.
      ENDIF.

      READ TABLE lt_stock INTO ls_stk
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-qty = ls_stk-qty.
      ELSE.
        CLEAR ls_res-qty.
      ENDIF.

      READ TABLE lt_mov WITH KEY matnr = ls_key-matnr
                                   werks = ls_key-werks
           TRANSPORTING NO FIELDS
           BINARY SEARCH.
      IF sy-subrc <> 0 AND ls_res-qty <> 0.
        ls_res-status = '재고만 있음'.
      ELSE.
        CLEAR ls_res-status.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result
    ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.