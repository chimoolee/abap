REPORT ZAI_260504_2015.

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
      ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
      BEGIN OF ty_stk,
        matnr TYPE mara-matnr,
        werks TYPE mseg-werks,
        qty   TYPE mard-labst,
      END OF ty_stk,
      ty_t_stk TYPE STANDARD TABLE OF ty_stk WITH EMPTY KEY,
      BEGIN OF ty_matdet,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_matdet,
      ty_t_matdet TYPE STANDARD TABLE OF ty_matdet WITH EMPTY KEY,
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

    DATA lt_mov   TYPE ty_t_key.
    DATA lt_stk   TYPE ty_t_stk.
    DATA lt_keys  TYPE ty_t_key.
    DATA lt_tmp   TYPE ty_t_key.
    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_det   TYPE ty_t_matdet.
    DATA lt_result TYPE ty_t_result.

    " Movement keys (MSEG + MKPF with BUDAT)
    IF s_budat IS INITIAL AND s_werks IS INITIAL.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS INITIAL AND s_werks IS NOT INITIAL.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mseg~werks IN @s_werks
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS NOT INITIAL AND s_werks IS INITIAL.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mov.
    ELSE.
      SELECT mseg~matnr,
             mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks
        GROUP BY mseg~matnr, mseg~werks
        INTO TABLE @lt_mov.
    ENDIF.

    " Current stock per material/plant (MARD) where total != 0
    IF s_werks IS INITIAL.
      SELECT matnr,
             werks,
             SUM( labst ) AS qty
        FROM mard
        GROUP BY matnr, werks
        HAVING SUM( labst ) <> 0
        INTO TABLE @lt_stk.
    ELSE.
      SELECT matnr,
             werks,
             SUM( labst ) AS qty
        FROM mard
        WHERE werks IN @s_werks
        GROUP BY matnr, werks
        HAVING SUM( labst ) <> 0
        INTO TABLE @lt_stk.
    ENDIF.

    " Build union of keys from movements and stock
    lt_keys = lt_mov.
    lt_tmp  = VALUE ty_t_key( FOR ls IN lt_stk ( matnr = ls-matnr werks = ls-werks ) ).
    LOOP AT lt_tmp ASSIGNING FIELD-SYMBOL(<lk>).
      READ TABLE lt_keys WITH KEY matnr = <lk>-matnr werks =