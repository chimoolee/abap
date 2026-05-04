REPORT ZAI_260504_1829.

TABLES: mkpf, mseg.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        werks TYPE mseg-werks,
        qty   TYPE mard-labst,
        stat  TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

    CLASS-METHODS get_movements
      IMPORTING
        it_werks    TYPE STANDARD TABLE OF mseg-werks WITH EMPTY KEY
        it_budat    TYPE STANDARD TABLE OF mkpf-budat WITH EMPTY KEY
      RETURNING VALUE(rt_mov) TYPE ty_t_key.

    CLASS-METHODS get_stocks
      IMPORTING
        it_werks     TYPE STANDARD TABLE OF mseg-werks WITH EMPTY KEY
      RETURNING VALUE(rt_stk) TYPE ty_t_stock.

    CLASS-METHODS get_attributes
      IMPORTING
        it_matnr     TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY
      RETURNING VALUE(rt_attr) TYPE ty_t_attr.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_mov TYPE ty_t_key.
    DATA lt_stk TYPE ty_t_stock.
    DATA lt_all_keys TYPE ty_t_key.
    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_attr TYPE ty_t_attr.
    DATA lt_result TYPE ty_t_result.

    " Prepare elementary tables for IN conditions
    DATA lt_werks TYPE STANDARD TABLE OF mseg-werks WITH EMPTY KEY.
    DATA lt_budat TYPE STANDARD TABLE OF mkpf-budat WITH EMPTY KEY.

    " Move select-options to elementary tables
    LOOP AT s_werks ASSIGNING FIELD-SYMBOL(<lsw>) WHERE sign = 'I' AND option = 'EQ'.
      APPEND <lsw>-low TO lt_werks.
    ENDLOOP.
    IF lt_werks IS INITIAL.
      " If no specific werks entered, allow all by selecting distinct from T001W later
      " For simplicity, leave lt_werks initial and handle with WHERE only when not initial
    ENDIF.

    LOOP AT s_budat ASSIGNING FIELD-SYMBOL(<lsd>) WHERE sign = 'I' AND option = 'BT'.
      " Split ranges into elementary list is complex; instead pass full select-option in SQL
    ENDLOOP.

    " Fetch movements per material/plant
    lt_mov = get_movements( it_werks = lt_werks it_budat = lt_budat ).

    " Fetch current stocks > 0 per material/plant
    lt_stk = get_stocks( it_werks = lt_werks ).

    " Union keys from movements and stocks
    DATA lt_keys_hash TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.
    LOOP AT lt_mov INTO DATA(ls_mov).
      INSERT ls_mov INTO TABLE lt_keys_hash.
    ENDLOOP.
    LOOP AT lt_stk INTO DATA(ls_stk).
      DATA(ls_key) = VALUE ty_key( matnr = ls_stk-matnr werks = ls_stk-werks ).
      INSERT ls_key INTO TABLE lt_keys_hash.
    ENDLOOP.

    " Build unique material list
    LOOP AT lt_keys_hash INTO DATA(ls_key2).
      APPEND ls_key2-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " Fetch attributes
    lt_attr = get_attributes( it_matnr = lt_matnr ).

    " Prepare quick lookup tables
    DATA lt_attr_hash TYPE HASHED TABLE OF ty_attr WITH UNIQUE KEY matnr.
    lt_attr_hash = lt_attr.

    DATA lt_stk_hash TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.
    lt_stk_hash = lt_stk.

    DATA lt_mov_hash TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.
    lt_mov_hash = lt_mov.

    " Build final result
    LOOP AT lt_keys_hash INTO DATA(ls_k).
      READ TABLE lt_attr_hash WITH TABLE KEY matnr = ls_k-matnr INTO DATA(ls_a).
      IF sy-subrc <> 0.
        CLEAR ls_a.
        ls_a-matnr = ls_k-matnr.
      ENDIF.

      READ TABLE lt_stk_hash WITH TABLE KEY matnr = ls_k-matnr werks = ls_k-werks INTO DATA(ls_s).
      IF sy-subrc <> 0.
        CLEAR ls_s.
      ENDIF.

      READ TABLE lt_mov_hash WITH TABLE KEY matnr = ls_k-matnr werks = ls_k-werks INTO DATA(ls_m).
      DATA(lv_stat) = COND char20(
        WHEN sy-subrc = 0 THEN '입출고 실적'
        ELSE '재고만 있음'
      ).

      APPEND VALUE ty_result(
        matnr = ls_a-matnr
        mtart = ls_a-mtart
        matkl = ls_a-matkl
        maktx = ls_a-maktx
        werks = ls_k-werks
        qty   = ls_s-qty
        stat  = lv_stat
      ) TO lt_result.
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

  METHOD get_movements.
    DATA lt_mov TYPE ty_t_key.

    " Select movements per material/plant within date and plant selections
    SELECT DISTINCT