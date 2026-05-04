REPORT ZAI_260504_1823.

SELECT-OPTIONS: s_budat FOR mkpf-budat,
                 s_werks FOR mard-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_key,
        matnr      TYPE mara-matnr,
        werks      TYPE mard-werks,
        has_mvt    TYPE abap_bool,
        has_stock  TYPE abap_bool,
        labst      TYPE mard-labst,
      END OF ty_key,
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr       TYPE mara-matnr,
        werks       TYPE mard-werks,
        mtart       TYPE mara-mtart,
        matkl       TYPE mara-matkl,
        maktx       TYPE makt-maktx,
        labst       TYPE mard-labst,
        status_text TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_keys    TYPE ty_t_key.
    DATA lt_mard    TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.
    DATA lt_mseg    TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY.
    DATA lt_attr    TYPE ty_t_attr.
    DATA lt_result  TYPE ty_t_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " 1) Stock > 0 per plant
    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @DATA(lt_mard_raw)
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    LOOP AT lt_mard_raw ASSIGNING FIELD-SYMBOL(<ls_mard>).
      DATA(ls_key) = VALUE ty_key(
        matnr     = <ls_mard>-matnr
        werks     = <ls_mard>-werks
        has_mvt   = abap_false
        has_stock = abap_true
        labst     = <ls_mard>-labst ).
      APPEND ls_key TO lt_keys.
    ENDLOOP.

    " 2) Movements by posting date and plant
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @DATA(lt_mseg_raw)
      WHERE mseg~werks IN @s_werks
        AND mkpf~budat IN @s_budat.

    LOOP AT lt_mseg_raw ASSIGNING FIELD-SYMBOL(<ls_mseg>).
      " Try to find existing key (maybe from stock). Update or append.
      READ TABLE lt_keys ASSIGNING FIELD-SYMBOL(<ls_key>)
        WITH KEY matnr = <ls_mseg>-matnr werks = <ls_mseg>-werks.
      IF sy-subrc = 0.
        <ls_key>-has_mvt = abap_true.
      ELSE.
        DATA(ls_key_new) = VALUE ty_key(
          matnr     = <ls_mseg>-matnr
          werks     = <ls_mseg>-werks
          has_mvt   = abap_true
          has_stock = abap_false
          labst     = 0 ).
        APPEND ls_key_new TO lt_keys.
      ENDIF.
    ENDLOOP.

    " 3) Prepare material list for attributes
    LOOP AT lt_keys ASSIGNING FIELD-SYMBOL(<ls_k>).
      APPEND <ls_k>-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    IF lt_matnr IS NOT INITIAL.
      " 4) Read attributes (MARA + MAKT, text in logon language)
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_attr
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    " 5) Build final result
    LOOP AT lt_keys ASSIGNING <ls_k>.
      READ TABLE lt_attr ASSIGNING FIELD-SYMBOL(<ls_a>)
        WITH KEY matnr = <ls_k>-matnr.
      DATA(lv_status) = COND char20(
        WHEN <ls_k>-has_mvt = abap_true THEN '입출고 있음'
        ELSE '재고만 있음' ).
      APPEND VALUE ty_result(
        matnr       = <ls_k>-matnr
        werks       = <ls_k>-werks
        mtart       = COND mara-mtart( WHEN <ls_a> IS ASSIGNED THEN <ls_a>-mtart ELSE '' )
        matkl       = COND mara-matkl( WHEN <ls_a> IS ASSIGNED THEN <ls_a>-matkl ELSE '' )
        maktx       = COND makt-maktx( WHEN <ls_a> IS ASSIGNED THEN <ls_a>-maktx ELSE '' )
        labst       = <ls_k>-labst
        status_text = lv_status ) TO lt_result.
    ENDLOOP.

    " 6) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).