REPORT ZAI_260505_2243.

TABLES mkpf.
TABLES mseg.

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
      ty_h_key TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks,

      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,

      BEGIN OF ty_matinfo,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_matinfo,
      ty_t_matinfo TYPE STANDARD TABLE OF ty_matinfo WITH EMPTY KEY,

      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        stock  TYPE mard-labst,
        status TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_move_keys TYPE ty_t_key.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_keys      TYPE ty_h_key.
    DATA lt_move_set  TYPE ty_h_key.
    DATA lt_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matinfo   TYPE ty_t_matinfo.
    DATA lt_result    TYPE ty_t_result.
    DATA ls_res       TYPE ty_result.
    DATA lo_alv       TYPE REF TO cl_salv_table.

    " Movements within posting date and plant
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

    " Current non-zero stock per material/plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @lt_stock.

    " Build union key set
    LOOP AT lt_move_keys INTO DATA(ls_mk).
      INSERT ls_mk INTO TABLE lt_keys.
      INSERT ls_mk INTO TABLE lt_move_set.
    ENDLOOP.

    LOOP AT lt_stock INTO DATA(ls_stk).
      DATA(ls_key) = VALUE ty_key( matnr = ls_stk-matnr werks = ls_stk-werks ).
      INSERT ls_key INTO TABLE lt_keys.
    ENDLOOP.

    " Prepare material list
    LOOP AT lt_keys INTO DATA(ls_key2).
      APPEND ls_key2-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " Read material master and text
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
        INTO TABLE @lt_matinfo
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    " Build result
    LOOP AT lt_keys INTO DATA(ls_k).
      CLEAR ls_res.
      ls_res-matnr = ls_k-matnr.
      ls_res-werks = ls_k-werks.

      READ TABLE lt_matinfo INTO DATA(ls_mi) WITH KEY matnr = ls_k-matnr.
      IF sy-subrc = 0.
        ls_res-mtart = ls_mi-mtart.
        ls_res-matkl = ls_mi-matkl.
        ls_res-maktx = ls_mi-maktx.
      ENDIF.

      READ TABLE lt_stock INTO DATA(ls_s2)
        WITH KEY matnr = ls_k-matnr werks = ls_k-werks.
      IF sy-subrc = 0.
        ls_res-stock = ls_s2-qty.
      ELSE.
        CLEAR ls_res-stock.
      ENDIF.

      READ TABLE lt_move_set TRANSPORTING NO FIELDS
        WITH KEY matnr = ls_k-matnr werks = ls_k-werks.
      IF sy-subrc = 0.
        ls_res-status = '입출고 실적'.
      ELSE.
        ls_res-status = '재고만 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " Display ALV
    IF lt_result IS INITIAL.
      WRITE: / '선택 조건에 해당하는 데이터가 없습니다.'.
    ELSE.
      TRY.
          cl_salv_table=>factory(
            IMPORTING
              r_salv_table = lo_alv
            CHANGING
              t_table      = lt_result ).
          lo_alv->get_functions( )->set_all( abap_true ).
          lo_alv->display( ).
        CATCH cx_salv_msg INTO DATA(lx).
          WRITE: / 'ALV 표시 중 오류:', lx->get_text( ).
      ENDTRY.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).