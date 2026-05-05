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
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_move_keys TYPE ty_t_key.
    DATA lt_stock     TYPE ty_t_stock.
    DATA lt_keys_all  TYPE ty_t_key.
    DATA lt_matinfo   TYPE ty_t_matinfo.
    DATA lt_result    TYPE ty_t_result.
    DATA lo_alv       TYPE REF TO cl_salv_table.

    " 1) Materials with movements in date/plant
    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
     INTO TABLE @lt_move_keys
     WHERE ( @s_budat[] IS INITIAL OR mkpf~budat IN @s_budat )
       AND ( @s_werks[] IS INITIAL OR mseg~werks IN @s_werks ).

    " 2) Current stock > 0 aggregated per material/plant
    SELECT
      matnr,
      werks,
      SUM( labst ) AS qty
      FROM mard
      WHERE ( @s_werks[] IS INITIAL OR werks IN @s_werks )
      GROUP BY matnr, werks
      HAVING SUM( labst ) > 0
      INTO TABLE @lt_stock.

    " 3) Union keys: movement keys + stock keys
    lt_keys_all = lt_move_keys.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      DATA(ls_key) = VALUE ty_key( matnr = <ls_stk>-matnr werks = <ls_stk>-werks ).
      IF line_exists( lt_keys_all[ matnr = ls_key-matnr werks = ls_key-werks ] ) = abap_false.
        APPEND ls_key TO lt_keys_all.
      ENDIF.
    ENDLOOP.

    " If nothing to show, still provide empty ALV safely
    IF lt_keys_all IS INITIAL.
      " Build minimal empty result with message row
      APPEND VALUE ty_result(
        matnr  = ''
        werks  = ''
        mtart  = ''
        matkl  = ''
        maktx  = '데이터 없음'
        stock  = 0
        status = ' '
      ) TO lt_result.
      cl_salv_table=>factory(
        IMPORTING r_salv_table = lo_alv
        CHANGING  t_table      = lt_result ).
      lo_alv->display( ).
      RETURN.
    ENDIF.

    " 4) Prepare list of material numbers for info/text select
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr TYPE ty_t_matnr.
    LOOP AT lt_keys_all ASSIGNING FIELD-SYMBOL(<ls_key_all>).
      APPEND <ls_key_all>-matnr TO lt_matnr.
    ENDLOOP.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 5) Read material info and text
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

    " 6) Build hashed helpers for fast lookup
    DATA lt_matinfo_h TYPE ty_t_matinfo.
    lt_matinfo_h = lt_matinfo.
    SORT lt_matinfo_h BY matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matinfo_h COMPARING matnr.

    DATA lt_stock_h TYPE ty_t_stock.
    lt_stock_h = lt_stock.
    SORT lt_stock_h BY matnr werks.

    " 7) Compose final result with status
    LOOP AT lt_keys_all ASSIGNING <ls_key_all>.
      DATA(ls_res) = VALUE ty_result(
         matnr = <ls_key_all>-matnr
         werks = <ls_key_all>-werks
         mtart = ''
         matkl = ''
         maktx = ''
         stock = 0
         status = '' ).

      READ TABLE lt_matinfo_h ASSIGNING FIELD-SYMBOL(<ls_mi>)
        WITH KEY matnr = <ls_key_all>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = <ls_mi>-mtart.
        ls_res-matkl = <ls_mi>-matkl.
        ls_res-maktx = <ls_mi>-maktx.
      ENDIF.

      READ TABLE lt_stock_h ASSIGNING FIELD-SYMBOL(<ls_stk2>)
        WITH KEY matnr = <ls_key_all>-matnr werks = <ls_key_all>-werks
        BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-stock = <ls_stk2>-qty.
      ELSE.
        ls_res-stock = 0.
      ENDIF.

      IF line_exists( lt_move_keys[ matnr = <ls_key_all>-matnr
                                    werks = <ls_key_all>-werks ] ).
        ls_res-status = '입출고 있음'.
      ELSE.
        ls_res-status = '재고만 있음'.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    " 8) Display ALV
    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = lt_result ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).