REPORT ZAI_260505_1850.

SELECT-OPTIONS: s_budat FOR mkpf~budat,
                 s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_mov,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_mov,
      ty_t_mov TYPE STANDARD TABLE OF ty_mov WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_stk,
        matnr TYPE mard-matnr,
        werks TYPE mard-werks,
        qty   TYPE mard-labst,
      END OF ty_stk,
      ty_t_stk TYPE STANDARD TABLE OF ty_stk WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_comb,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        qty    TYPE mard-labst,
        status TYPE c LENGTH 20,
      END OF ty_comb,
      ty_t_comb TYPE STANDARD TABLE OF ty_comb WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_matinfo,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_matinfo,
      ty_t_matinfo TYPE STANDARD TABLE OF ty_matinfo WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
        werks TYPE werks_d,
        qty   TYPE mard-labst,
        stat  TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov     TYPE ty_t_mov.
    DATA lt_stk     TYPE ty_t_stk.
    DATA lt_comb    TYPE ty_t_comb.
    DATA lt_matinfo TYPE ty_t_matinfo.
    DATA lt_result  TYPE ty_t_result.
    DATA lt_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    " Movements by posting date and plant
    IF s_budat[] IS INITIAL AND s_werks[] IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mov.
    ELSEIF s_budat[] IS INITIAL AND s_werks[] IS NOT INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mov
        WHERE mseg~werks IN @s_werks.
    ELSEIF s_budat[] IS NOT INITIAL AND s_werks[] IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mov
        WHERE mkpf~budat IN @s_budat.
    ELSE.
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
    ENDIF.

    " Current stock by plant: only non-zero totals
    IF s_werks[] IS INITIAL.
      SELECT
        mard~matnr,
        mard~werks,
        SUM( mard~labst ) AS qty
        FROM mard
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) > 0
        INTO TABLE @lt_stk.
    ELSE.
      SELECT
        mard~matnr,
        mard~werks,
        SUM( mard~labst ) AS qty
        FROM mard
        WHERE mard~werks IN @s_werks
        GROUP BY mard~matnr, mard~werks
        HAVING SUM( mard~labst ) > 0
        INTO TABLE @lt_stk.
    ENDIF.

    " Hash helpers
    TYPES: ty_h_mov TYPE HASHED TABLE OF ty_mov WITH UNIQUE KEY matnr werks.
    DATA lt_h_mov TYPE ty_h_mov.
    lt_h_mov = lt_mov.

    TYPES: ty_h_stk TYPE HASHED TABLE OF ty_stk WITH UNIQUE KEY matnr werks.
    DATA lt_h_stk TYPE ty_h_stk.
    lt_h_stk = lt_stk.

    " Combine: movements first (status '입출고 있음')
    DATA ls_comb TYPE ty_comb.
    DATA ls_stk  TYPE ty_stk.

    LOOP AT lt_mov INTO DATA(ls_mov).
      CLEAR ls_comb.
      ls_comb-matnr = ls_mov-matnr.
      ls_comb-werks = ls_mov-werks.
      READ TABLE lt_h_stk INTO ls_stk WITH TABLE KEY matnr = ls_mov-matnr werks = ls_mov-werks.
      IF sy-subrc = 0.
        ls_comb-qty = ls_stk-qty.
      ELSE.
        CLEAR ls_comb-qty.
      ENDIF.
      ls_comb-status = '입출고 있음'.
      APPEND ls_comb TO lt_comb.
    ENDLOOP.

    " Add pure stock-only keys (status '재고만 있음')
    LOOP AT lt_stk INTO ls_stk.
      READ TABLE lt_h_mov WITH TABLE KEY matnr = ls_stk-matnr werks = ls_stk-werks TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        CLEAR ls_comb.
        ls_comb-matnr = ls_stk-matnr.
        ls_comb-werks = ls_stk-werks.
        ls_comb-qty   = ls_stk-qty.
        ls_comb-status = '재고만 있음'.
        APPEND ls_comb TO lt_comb.
      ENDIF.
    ENDLOOP.

    " Collect material numbers for text/type fetch
    SORT lt_comb BY matnr.
    LOOP AT lt_comb INTO ls_comb.
      APPEND ls_comb-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

    " Fetch material