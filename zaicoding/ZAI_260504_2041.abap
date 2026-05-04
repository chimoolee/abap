REPORT ZAI_260504_2041.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_key,
      ty_t_key_std  TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
      ty_t_key_hash TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.

    TYPES:
      BEGIN OF ty_move,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_move,
      ty_t_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mard-matnr,
        werks TYPE mard-werks,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock_std  TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
      ty_t_stock_hash TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.

    TYPES:
      BEGIN OF ty_mat,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mat,
      ty_t_mat_hash TYPE HASHED TABLE OF ty_mat WITH UNIQUE KEY matnr.

    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE mseg-werks,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        qty    TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_move      TYPE ty_t_move.
    DATA lt_stock     TYPE ty_t_stock_std.
    DATA lt_stock_h   TYPE ty_t_stock_hash.
    DATA lt_keys      TYPE ty_t_key_hash.
    DATA lt_keys_std  TYPE ty_t_key_std.
    DATA lt_mat       TYPE ty_t_mat_hash.
    DATA lt_result    TYPE ty_t_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lo_alv TYPE REF TO cl_salv_table.

    " Movements by posting date and plant
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr IS NOT NULL.

    " Current non-zero stock per material and plant
    SELECT
      matnr,
      werks,
      SUM( labst ) AS qty
      FROM mard
      WHERE werks IN @s_werks
      GROUP BY matnr, werks
      HAVING SUM( labst ) <> 0
      INTO TABLE @lt_stock.

    lt_stock_h = lt_stock.

    " Build union key set (matnr, werks)
    LOOP AT lt_move INTO DATA(ls_move).
      INSERT VALUE ty_key( matnr = ls_move-matnr werks = ls_move-werks ) INTO TABLE lt_keys.
    ENDLOOP.

    LOOP AT lt_stock INTO DATA(ls_stock).
      INSERT VALUE ty_key( matnr = ls_stock-matnr werks = ls_stock-werks ) INTO TABLE lt_keys.
    ENDLOOP.

    lt_keys_std = CORRESPONDING ty_t_key_std( lt_keys ).

    " Prepare material list for text/master data
    LOOP AT lt_keys_std INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS NOT INITIAL.
      DATA lt_mat_tmp TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_mat_tmp
        WHERE mara~matnr IN @lt_matnr.
      lt_mat = CORRESPONDING ty_t_mat_hash( lt_mat_tmp ).
    ENDIF.

    " Build final result
    LOOP AT lt_keys_std INTO ls_key.
      DATA(ls_res) = VALUE ty_result( matnr = ls_key-matnr werks = ls_key-werks ).
      " Material master/text
      READ TABLE lt_mat WITH TABLE KEY matnr = ls_key-matnr INTO DATA(ls_mat).
      IF sy-subrc = 0.
        ls_res-mtart = ls_mat-mtart.
        ls_res-matkl = ls_mat-matkl.
        ls_res-maktx = ls_mat-maktx.
      ENDIF.

      " Stock qty if any
      READ TABLE lt_stock_h WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks INTO DATA(ls_stk).
      IF sy-subrc = 0.
        ls_res-qty = ls_stk-qty.
      ELSE.
        ls_res-qty = 0.
      ENDIF.

      " Status
      DATA(lv_has_move) = abap_false.
      READ TABLE lt_move WITH KEY matnr = ls_key-matnr werks = ls_key-werks TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_has_move = abap_true.
      ENDIF.

      IF lv_has_move = abap_true AND ls_res-qty <> 0.
        ls_res-status = '입출고+재고'.
      ELSEIF lv_has_move = abap_true AND ls_res-qty = 0.
        ls_res-status = '입출고 실적 있음'.
      ELSEIF lv_has_move = abap_false AND ls_res-qty <> 0.
        ls_res-status = '재고만 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " Display
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