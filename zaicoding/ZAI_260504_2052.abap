REPORT ZAI_260504_2052.

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
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
      END OF ty_key,
      ty_t_key TYPE SORTED TABLE OF ty_key WITH UNIQUE KEY matnr werks,

      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE SORTED TABLE OF ty_stock WITH UNIQUE KEY matnr werks,

      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE HASHED TABLE OF ty_attr WITH UNIQUE KEY matnr,

      BEGIN OF ty_result,
        matnr       TYPE mara-matnr,
        werks       TYPE mseg-werks,
        mtart       TYPE mara-mtart,
        matkl       TYPE mara-matkl,
        maktx       TYPE makt-maktx,
        stock_total TYPE mard-labst,
        status      TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov_keys TYPE ty_t_key.
    DATA lt_stock    TYPE ty_t_stock.
    DATA lt_all_keys TYPE ty_t_key.
    DATA lt_attr     TYPE ty_t_attr.
    DATA lt_result   TYPE ty_t_result.

    " 1) Movements: MKPF (BUDAT) + MSEG (WERKS) -> distinct MATNR/WERKS
    SELECT mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @DATA(lt_mov_tmp)
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    SORT lt_mov_tmp BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_mov_tmp COMPARING matnr werks.
    lt_mov_keys = CORRESPONDING ty_t_key( lt_mov_tmp ).

    " 2) Current stock per MATNR/WERKS with non-zero total
    SELECT matnr,
           werks,
           SUM( labst ) AS qty
      FROM mard
      WHERE werks IN @s_werks
      GROUP BY matnr, werks
      HAVING SUM( labst ) <> 0
      INTO TABLE @DATA(lt_stock_tmp).

    lt_stock = CORRESPONDING ty_t_stock( lt_stock_tmp ).

    " 3) Union keys: movements U non-zero stock
    lt_all_keys = lt_mov_keys.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_stk>).
      INSERT VALUE ty_key( matnr = <ls_stk>-matnr werks = <ls_stk>-werks ) INTO TABLE lt_all_keys.
    ENDLOOP.

    IF lt_all_keys IS INITIAL.
      " Nothing to show
      cl_demo_output=>display( VALUE string( ) ).
      RETURN.
    ENDIF.

    " 4) Build MATNR list for attribute read
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr TYPE ty_t_matnr.

    LOOP AT lt_all_keys INTO DATA(ls_key).
      APPEND ls_key-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 5) Read attributes from MARA/MAKT
    SELECT mara~matnr,
           mara~mtart,
           mara~matkl,
           makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @DATA(lt_attr_tmp)
      WHERE mara~matnr IN @lt_matnr.

    lt_attr = CORRESPONDING ty_t_attr( lt_attr_tmp ).

    " 6) Build result
    LOOP AT lt_all_keys INTO ls_key.
      DATA(lv_stock) = CONV mard-labst( 0 ).
      READ TABLE lt_stock ASSIGNING <ls_st>
        WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks.
      IF sy-subrc = 0.
        lv_stock = <ls_st>-qty.
      ENDIF.

      DATA(lv_status) = CONV char20( '' ).
      READ TABLE lt_mov_keys WITH TABLE KEY matnr = ls_key-matnr werks = ls_key-werks
        TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        lv_status = '입출고 있음'.
      ELSE.
        lv_status = '재고만 있음'.
      ENDIF.

      READ TABLE lt_attr ASSIGNING FIELD-SYMBOL(<ls_attr>)
        WITH TABLE KEY matnr = ls_key-matnr.

      APPEND VALUE ty_result(
        matnr       = ls_key-matnr
        werks       = ls_key-werks
        mtart       = COND mara-mtart( WHEN <ls_attr> IS ASSIGNED THEN <ls_attr>-mtart ELSE '' )
        matkl       = COND mara-matkl( WHEN <ls_attr> IS ASSIGNED THEN <ls_attr>-matkl ELSE '' )
        maktx       = COND makt-maktx( WHEN <ls_attr> IS ASSIGNED THEN <ls_attr>-maktx ELSE '' )
        stock_total = lv_stock
        status      = lv_status ) TO lt_result.
    ENDLOOP.

    " 7) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).