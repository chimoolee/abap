REPORT ZAI_260504_1841.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
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
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_mat,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mat,
      ty_t_mat TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        qty    TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    CLASS-METHODS get_move_keys
      IMPORTING
        VALUE(ir_werks) TYPE RANGE OF t001w-werks
        VALUE(ir_budat) TYPE RANGE OF mkpf-budat
      RETURNING
        VALUE(rt_keys)  TYPE ty_t_key.

    CLASS-METHODS get_stock
      IMPORTING
        VALUE(ir_werks) TYPE RANGE OF t001w-werks
      RETURNING
        VALUE(rt_stock) TYPE ty_t_stock.

    CLASS-METHODS get_materials
      IMPORTING
        VALUE(it_matnr) TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY
      RETURNING
        VALUE(rt_mat)   TYPE ty_t_mat.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_move_keys TYPE ty_t_key.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_keys      TYPE ty_t_key.
    DATA lt_result    TYPE ty_t_result.

    lt_move_keys = get_move_keys( ir_werks = s_werks ir_budat = s_budat ).
    lt_stock     = get_stock( ir_werks = s_werks ).

    lt_keys = lt_move_keys.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_s>).
      APPEND VALUE ty_key( matnr = <ls_s>-matnr werks = <ls_s>-werks ) TO lt_keys.
    ENDLOOP.
    SORT lt_keys BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_keys COMPARING matnr werks.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    LOOP AT lt_keys ASSIGNING FIELD-SYMBOL(<ls_k>).
      APPEND <ls_k>-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    DATA lt_mat TYPE ty_t_mat.
    IF lt_matnr IS NOT INITIAL.
      lt_mat = get_materials( lt_matnr ).
    ENDIF.

    TYPES:
      BEGIN OF ty_move_flag,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_move_flag.
    DATA lt_move_flag TYPE STANDARD TABLE OF ty_move_flag WITH EMPTY KEY.
    LOOP AT lt_move_keys ASSIGNING FIELD-SYMBOL(<ls_mk>).
      APPEND VALUE ty_move_flag(
        matnr = <ls_mk>-matnr
        werks = <ls_mk>-werks ) TO lt_move_flag.
    ENDLOOP.
    SORT lt_move_flag BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_move_flag COMPARING matnr werks.

    SORT lt_stock BY matnr werks.

    DATA lt_mat_sorted TYPE ty_t_mat.
    lt_mat_sorted = lt_mat.
    SORT lt_mat_sorted BY matnr.

    LOOP AT lt_keys ASSIGNING <ls_k>.
      DATA(ls_res) = VALUE ty_result( ).
      ls_res-matnr = <ls_k>-matnr.
      ls_res-werks = <ls_k>-werks.

      READ TABLE lt_mat_sorted ASSIGNING FIELD-SYMBOL(<ls_mat>)
        WITH KEY matnr = <ls_k>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = <ls_mat>-mtart.
        ls_res-matkl = <ls_mat>-matkl.
        ls_res-maktx = <ls_mat>-maktx.
      ENDIF.

      READ TABLE lt_stock ASSIGNING <ls_s>
        WITH KEY matnr = <ls_k>-matnr werks = <ls_k>-werks BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-qty = <ls_s>-qty.
      ELSE.
        CLEAR ls_res-qty.
      ENDIF.

      READ TABLE lt_move_flag TRANSPORTING NO FIELDS
        WITH KEY matnr = <ls_k>-matnr werks = <ls_k>-werks BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-status = |입출고 있음|.
      ELSEIF ls_res-qty IS NOT INITIAL AND ls_res-qty <> 0.
        ls_res-status = |재고만 있음|.
      ELSE.
        ls_res-status = |재고만 있음|.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      '자재 실적/재고 현황 - 플랜트 및 전기일 기준' ).
    lo_alv->display( ).
  ENDMETHOD.

  METHOD get_move_keys.
    DATA lt_keys TYPE ty_t_key.

    IF ir_werks IS INITIAL.
      SELECT DISTINCT
             mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO