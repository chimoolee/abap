REPORT ZAI_260504_2112.

TABLES mara.

SELECT-OPTIONS: s_budat FOR mkpf-budat,
                 s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_mov,
             matnr TYPE mseg-matnr,
             werks TYPE mseg-werks,
           END OF ty_mov,
           ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY.

    TYPES: BEGIN OF ty_attr,
             matnr TYPE mara-matnr,
             mtart TYPE mara-mtart,
             matkl TYPE mara-matkl,
             maktx TYPE makt-maktx,
           END OF ty_attr,
           ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY.

    TYPES: BEGIN OF ty_union,
             matnr TYPE mara-matnr,
             werks TYPE mseg-werks,
           END OF ty_union,
           ty_t_union TYPE STANDARD TABLE OF ty_union WITH EMPTY KEY.

    TYPES: BEGIN OF ty_result,
             matnr  TYPE mara-matnr,
             werks  TYPE mseg-werks,
             mtart  TYPE mara-mtart,
             matkl  TYPE mara-matkl,
             maktx  TYPE makt-maktx,
             status TYPE char20,
           END OF ty_result,
           ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov    TYPE ty_t_mov.
    DATA lt_stock  TYPE ty_t_mov.
    DATA lt_union  TYPE ty_t_union.
    DATA lt_attr   TYPE ty_t_attr.
    DATA lt_result TYPE ty_t_result.
    DATA ls_union  TYPE ty_union.
    DATA ls_attr   TYPE ty_attr.
    DATA ls_res    TYPE ty_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_mov
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    SELECT
      mard~matnr,
      mard~werks
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0.

    lt_union = CORRESPONDING #( lt_mov ).
    APPEND LINES OF CORRESPONDING ty_t_union( lt_stock ) TO lt_union.
    SORT lt_union BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_union COMPARING matnr werks.

    LOOP AT lt_union INTO ls_union.
      APPEND ls_union-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

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
        INTO TABLE @lt_attr
        WHERE mara~matnr IN @lt_matnr.
      SORT lt_attr BY matnr.
    ENDIF.

    SORT lt_mov   BY matnr werks.
    SORT lt_stock BY matnr werks.

    LOOP AT lt_union INTO ls_union.
      CLEAR ls_res.
      ls_res-matnr = ls_union-matnr.