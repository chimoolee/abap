REPORT ZAI_260504_1835.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_move,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_move,
      ty_t_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY,
      BEGIN OF ty_stock,
        matnr TYPE mard-matnr,
        werks TYPE mard-werks,
        labst TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
      BEGIN OF ty_matdet,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_matdet,
      ty_t_matdet TYPE STANDARD TABLE OF ty_matdet WITH EMPTY KEY,
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        werks TYPE mard-werks,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        labst TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_move   TYPE ty_t_move.
    DATA lt_stock  TYPE ty_t_stock.
    DATA lt_keys   TYPE ty_t_move.
    DATA lt_matdet TYPE ty_t_matdet.
    DATA lt_result TYPE ty_t_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Movements by plant and posting date
    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    SORT lt_move BY matnr werks.

    " 2) Current stock (non-zero) by plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS labst
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0.

    SORT lt_stock BY matnr werks.

    " 3) Union keys (materials per plant) from movements and stocks
    lt_keys = lt_move.
    LOOP AT lt_stock INTO DATA(ls_stock_key).
      APPEND VALUE ty_move( matnr = ls_stock_key-matnr
                            werks = ls_stock_key-werks ) TO lt_keys.
    ENDLOOP.
    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    IF lt_keys IS INITIAL.
      MESSAGE '선택 조건에 해당하는 데이터가 없습니다.' TYPE 'S'.
      RETURN.
    ENDIF.

    " 4) Collect material list
    LOOP AT lt_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 5) Read material details with text
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_matdet
      WHERE mara~matnr IN @lt_matnr.

    SORT lt_matdet BY matnr.

    " 6) Build final result
    LOOP AT lt_keys INTO ls_key.
      DATA(lv_has_move) = abap_false.
      READ TABLE lt_move WITH KEY matnr = ls_key-matnr
                                 werks = ls_key-werks
                        TRANSPORTING NO FIELDS
                        BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_move = abap_true.
      ENDIF.

      DATA(lv_labst) = CONV mard-labst( 0 ).
      READ TABLE lt_stock INTO ls_stock_key
           WITH KEY matnr = ls_key-matnr
                    werks = ls_key-werks
           BINARY SEARCH.
      IF sy-subrc = 0.
        lv_labst = ls_stock_key-labst.
      ENDIF.

      DATA(ls_matdet) = VALUE ty_matdet( ).
      READ TABLE lt_matdet INTO ls_matdet
           WITH KEY matnr = ls_key-matnr
           BINARY SEARCH.

      DATA(lv_status) = CONV char20( '' ).
      IF lv_has_move = abap_true.
        lv_status = '입출고 있음'.
      ELSE.
        lv_status = '재고만 있음'.
      ENDIF.

      APPEND VALUE ty_result(
        matnr  = ls_key-matnr
        werks  = ls_key-werks
        mtart  = ls_matdet-mtart
        matkl  = ls_matdet-matkl
        maktx  = ls_matdet-m