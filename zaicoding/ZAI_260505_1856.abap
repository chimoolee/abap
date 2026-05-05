REPORT ZAI_260505_1856.

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
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr       TYPE mara-matnr,
        werks       TYPE werks_d,
        labst_total TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_matdet,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_matdet,
      ty_t_matdet TYPE STANDARD TABLE OF ty_matdet WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr       TYPE mara-matnr,
        werks       TYPE werks_d,
        mtart       TYPE mara-mtart,
        matkl       TYPE mara-matkl,
        maktx       TYPE makt-maktx,
        labst_total TYPE mard-labst,
        status_txt  TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_move_keys  TYPE ty_t_key.
    DATA lt_stock_agg  TYPE ty_t_stock.
    DATA lt_union_keys TYPE ty_t_key.
    DATA lt_matnr      TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matdet     TYPE ty_t_matdet.
    DATA lt_result     TYPE ty_t_result.

    " Movements: materials with material documents by date/plant
    IF s_budat[] IS INITIAL AND s_werks[] IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_move_keys.
    ELSEIF s_budat[] IS INITIAL AND s_werks[] IS NOT INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_move_keys
        WHERE mseg~werks IN @s_werks.
    ELSEIF s_budat[] IS NOT INITIAL AND s_werks[] IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_move_keys
        WHERE mkpf~budat IN @s_budat.
    ELSE.
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
    ENDIF.

    " Current stock > 0 aggregated by material/plant
    IF s_werks[] IS INITIAL.
      SELECT
        mard~matnr,
        mard~werks,
        SUM( mard~labst ) AS labst_total
        FROM mard
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) > 0
        INTO TABLE @lt_stock_agg.
    ELSE.
      SELECT
        mard~matnr,
        mard~werks,
        SUM( mard~labst ) AS labst_total
        FROM mard
        WHERE mard~werks IN @s_werks
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) > 0
        INTO TABLE @lt_stock_agg.
    ENDIF.

    " Build union of movement keys and stock keys
    lt_union_keys = lt_move_keys.
    LOOP AT lt_stock_agg INTO DATA(ls_stk).
      APPEND VALUE ty_key( matnr = ls_stk-matnr werks = ls_stk-werks ) TO lt_union_keys.
    ENDLOOP.

    SORT lt_union_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_union_keys COMPARING matnr werks.

    " Prepare material list for details
    LOOP AT lt_union_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

    " Get material master details (MARA + MAKT in logon language)
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
        INTO TABLE @lt_matdet
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    " Build final result
    LOOP AT lt_union_keys INTO ls_key.
      DATA(lv_labst) = CONV mard-labst( 0 ).
      READ TABLE lt_stock_agg INTO ls_stk
        WITH KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        lv_labst = ls_stk-labst_total.
      ENDIF.

      DATA(ls_det) = VALUE ty_matdet( ).
      READ TABLE lt_matdet INTO ls_det WITH KEY matnr = ls_key-matnr.

      DATA(lv_status) = CONV char20( '' ).
      READ TABLE lt_move_keys WITH KEY matnr = ls_key-matnr werks = ls_key-werks
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_status = '입출고 있음'.
      ELSE.
        lv_status = '재고만 있음'.
      ENDIF.

      APPEND VALUE ty_result(
        matnr       = ls_key-matnr
        werks       = ls_key-werks
        mtart       = ls_det-mtart
        matkl       = ls_det-matkl
        maktx       = ls_det-maktx
        labst_total = lv_labst
        status_txt  = lv_status ) TO lt_result.
    ENDLOOP.

    " Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).