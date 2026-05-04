REPORT ZAI_260504_2127.

TABLES mara.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  CLASS-METHODS run.
    TYPES:
      BEGIN OF ty_move,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
      END OF ty_move,
      ty_t_move TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY,

      BEGIN OF ty_stock,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        labst TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,

      BEGIN OF ty_attr,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_attr,
      ty_t_attr TYPE STANDARD TABLE OF ty_attr WITH EMPTY KEY,

      BEGIN OF ty_pair,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
      END OF ty_pair,
      ty_t_pair TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY,

      BEGIN OF ty_result,
        matnr     TYPE mara-matnr,
        werks     TYPE mseg-werks,
        mtart     TYPE mara-mtart,
        matkl     TYPE mara-matkl,
        maktx     TYPE makt-maktx,
        stock_qty TYPE mard-labst,
        status    TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_move       TYPE ty_t_move.
    DATA lt_stock_raw  TYPE ty_t_stock.
    DATA lt_stock_sum  TYPE ty_t_stock.
    DATA lt_union      TYPE ty_t_pair.
    DATA lt_matnr      TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_attr       TYPE ty_t_attr.
    DATA lt_result     TYPE ty_t_result.

    DATA ls_move       TYPE ty_move.
    DATA ls_stock_r    TYPE ty_stock.
    DATA ls_stock_s    TYPE ty_stock.
    DATA ls_pair       TYPE ty_pair.
    DATA ls_attr       TYPE ty_attr.
    DATA ls_result     TYPE ty_result.

    DATA lo_alv TYPE REF TO cl_salv_table.

    " 1) Materials with goods movements in selected date and plant
    SELECT DISTINCT
           m~matnr,
           m~werks
      FROM mseg AS m
      INNER JOIN mkpf AS k
        ON k~mblnr = m~mblnr
       AND k~mjahr = m~mjahr
      INTO TABLE @lt_move
      WHERE k~budat IN @s_budat
        AND m~werks IN @s_werks
        AND m~matnr IS NOT INITIAL.

    " 2) Current stock (> 0) per plant
    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @lt_stock_raw
      WHERE mard~werks IN @s_werks
        AND mard~labst > 0
        AND mard~matnr IS NOT INITIAL.

    " Aggregate stock by MATNR+WERKS
    SORT lt_stock_raw BY matnr werks.
    CLEAR ls_stock_s.
    LOOP AT lt_stock_raw INTO ls_stock_r.
      IF ls_stock_s-matnr IS INITIAL OR
         ls_stock_s-matnr <> ls_stock_r-matnr OR
         ls_stock_s-werks <> ls_stock_r-werks.
        IF ls_stock_s-matnr IS NOT INITIAL.
          APPEND ls_stock_s TO lt_stock_sum.
        ENDIF.
        MOVE-CORRESPONDING ls_stock_r TO ls_stock_s.
      ELSE.
        ls_stock_s-labst = ls_stock_s-labst + ls_stock_r-lab