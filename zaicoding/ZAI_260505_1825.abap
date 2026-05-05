REPORT ZAI_260505_1825.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        stock  TYPE mard-labst,
        status TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_key,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_key,
      ty_t_key TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.

    TYPES:
      BEGIN OF ty_mov,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_mov,
      ty_t_mov TYPE HASHED TABLE OF ty_mov WITH UNIQUE KEY matnr werks.

    TYPES:
      BEGIN OF ty_stk,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
        labst TYPE mard-labst,
      END OF ty_stk,
      ty_t_stk TYPE HASHED TABLE OF ty_stk WITH UNIQUE KEY matnr werks.

    TYPES:
      BEGIN OF ty_mara,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
      END OF ty_mara,
      ty_t_mara TYPE HASHED TABLE OF ty_mara WITH UNIQUE KEY matnr.

    TYPES:
      BEGIN OF ty_makt,
        matnr TYPE mara-matnr,
        maktx TYPE makt-maktx,
      END OF ty_makt,
      ty_t_makt TYPE HASHED TABLE OF ty_makt WITH UNIQUE KEY matnr.

    DATA lt_result TYPE ty_t_result.
    DATA lt_keys   TYPE ty_t_key.
    DATA lt_mov    TYPE ty_t_mov.
    DATA lt_stk    TYPE ty_t_stk.
    DATA lt_mara   TYPE ty_t_mara.
    DATA lt_makt   TYPE ty_t_makt.

    " 1) Materials with movements within date and plant
    SELECT DISTINCT
           mseg~matnr,
           mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @DATA(lt_mov_raw)
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks.

    lt_mov = CORRESPONDING ty_t_mov( lt_mov_raw ).

    " 2) Materials with current stock not zero for selected plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS labst
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) <> 0
      INTO TABLE @DATA(lt_stk_raw).

    lt_stk = CORRESPONDING ty_t_stk(