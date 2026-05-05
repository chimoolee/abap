REPORT ZAI_260505_0907.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_base,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_base,
      ty_t_base TYPE STANDARD TABLE OF ty_base WITH EMPTY KEY,
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock  TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_all    TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_base   TYPE ty_t_base.
    DATA lt_result TYPE ty_t_result.

    " Materials with movements by posting date/plant
    IF s_werks[] IS INITIAL AND s_budat[] IS INITIAL.
      SELECT DISTINCT
        mseg~matnr
        FROM mseg
        INTO TABLE @lt_mov.
    ELSEIF s_werks[] IS INITIAL AND s_budat[] IS NOT INITIAL.
      SELECT DISTINCT
        mseg~matnr
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = m