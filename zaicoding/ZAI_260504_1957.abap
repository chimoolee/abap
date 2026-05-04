REPORT ZAI_260504_1957.

TABLES mara.

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
      ty_t_key     TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
      ty_t_key_h   TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks,
      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr_h  TYPE HASHED TABLE OF ty_attr WITH UNIQUE KEY matnr,
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE mseg-werks,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_post        TYPE ty_t_key.
    DATA lt_stock_keys  TYPE ty_t_key.
    DATA lt_union_hash  TYPE ty_t_key_h.
    DATA lt_post_hash   TYPE ty_t_key_h.
    DATA lt_result      TYPE ty_t_result.
    DATA lt_attr        TYPE ty_t_attr_h.
    DATA lt_matnr       TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lr_werks TYPE RANGE OF mseg-werks.
    DATA lr_budat TYPE RANGE OF mkpf-budat.

    IF s_werks IS INITIAL.
      APPEND VALUE #( sign = 'I' option = 'BT' low = '0000' high = 'ZZZZ' ) TO lr_werks.
    ELSE.
      lr_werks = s_werks[].
    ENDIF.

    IF s_budat IS INITIAL.
      APPEND VALUE #( sign = 'I' option = 'BT' low = '19000101' high = '99991231' ) TO lr_budat.
    ELSE.
      lr_budat = s_budat[].
    ENDIF.

    SELECT DISTINCT
           s~matnr,
           s~werks
      FROM mseg AS s
      INNER JOIN mkpf AS k
        ON k~mblnr = s~mblnr
       AND k~mjahr = s~mjahr
     WHERE k~budat IN @lr_budat
       AND s~werks IN @lr_werks
      INTO TABLE @lt_post.

    lt_post_hash = CORRESPONDING ty_t_key_h( lt_post ).

    SELECT
      mard~matnr