REPORT ZAI_260504_2015.

TABLES mara.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks,
  s_matnr FOR mara-matnr.

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
        status    TYPE c LENGTH 20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov     TYPE ty_t_key.
    DATA lt_stk     TYPE ty_t_stk.
    DATA lt_keys    TYPE ty_t_key.
    DATA lt_tmp     TYPE ty_t_key.
    DATA lt_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_det     TYPE ty_t_matdet.
    DATA lt_result  TYPE ty_t_result.
    DATA ls_key     TYPE ty_key.
    DATA ls_det     TYPE ty_matdet.
    DATA ls_res     TYPE ty_result.
    DATA lv_stock   TYPE mard-labst.
    DATA lo_alv     TYPE REF TO cl_salv_table.

* Movement keys (MSEG + MKPF with MKPF~BUDAT)
    IF s_budat IS INITIAL AND s_werks IS INITIAL AND s_matnr IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS INITIAL AND s_werks IS INITIAL AND s_matnr IS NOT INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mseg~matnr IN @s_matnr
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS INITIAL AND s_werks IS NOT INITIAL AND s_matnr IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mseg~werks IN @s_werks
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS INITIAL AND s_werks IS NOT INITIAL AND s_matnr IS NOT INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mseg~werks IN @s_werks
          AND mseg~matnr IN @s_matnr
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS NOT INITIAL AND s_werks IS INITIAL AND s_matnr IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS NOT INITIAL AND s_werks IS INITIAL AND s_matnr IS NOT INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
          AND mseg~matnr IN @s_matnr
        INTO TABLE @lt_mov.
    ELSEIF s_budat IS NOT INITIAL AND s_werks IS NOT INITIAL AND s_matnr IS INITIAL.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks
        INTO TABLE @lt_mov.
    ELSE.
      SELECT DISTINCT
        mseg~matnr,
        mseg~werks
        FROM mseg
        INNER JOIN mkpf
          ON mkpf~mblnr = mseg~mblnr
         AND mkpf~mjahr = mseg~mjahr
        WHERE mkpf~budat IN @s_budat
          AND mseg~werks IN @s_werks
          AND mseg~matnr IN @s_matnr
        INTO TABLE @lt_mov.
    ENDIF.

* Current stock per material/plant (MARD) where total <> 0
    IF s_werks IS INITIAL AND s_matnr IS INITIAL.
      SELECT
        matnr,
        werks,
        SUM( labst ) AS qty
        FROM mard
        GROUP BY matnr, werks
        HAVING SUM( labst ) <> 0
        INTO TABLE @lt_stk.
    ELSEIF s_werks IS INITIAL AND s_matnr IS NOT INITIAL.
      SELECT
        matnr,
        werks,
        SUM( labst ) AS qty
        FROM mard
        WHERE matnr IN @s_matnr
        GROUP BY matnr, werks
        HAVING SUM( labst ) <> 0
        INTO TABLE @lt_stk.
    ELSEIF s_werks IS NOT INITIAL AND s_matnr IS INITIAL.
      SELECT
        matnr,
        werks,
        SUM( labst ) AS qty
        FROM mard
        WHERE werks IN @s_werks
        GROUP BY matnr, werks
        HAVING SUM( labst ) <> 0
        INTO TABLE @lt_stk.
    ELSE.
      SELECT
        matnr,
        werks,
        SUM( labst ) AS qty
        FROM mard
        WHERE werks IN @s_werks
          AND matnr IN @s_matnr
        GROUP BY matnr, werks
        HAVING SUM( labst ) <> 0
        INTO TABLE @lt_stk.
    ENDIF.

* Build union of keys from movements and stock
    lt_keys = lt_mov.
    lt_tmp  = VALUE ty_t_key(
                FOR ls IN lt_stk
                ( matnr = ls-matnr
                  werks = ls-werks ) ).
    LOOP AT lt_tmp ASSIGNING FIELD-SYMBOL(<lk>).
      READ TABLE lt_keys WITH KEY matnr = <lk>-matnr
                                 werks = <lk>-werks
           TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND <lk> TO lt_keys.
      ENDIF.
    ENDLOOP.

* Apply material filter from s_matnr (safety, if not already applied)
    IF s_matnr IS NOT INITIAL.
      DELETE lt_keys WHERE NOT ( matnr IN s_matnr ).
    ENDIF.

* Prepare material list for details
    lt_matnr = VALUE #( FOR k IN lt_keys ( k-matnr ) ).
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

* Read material details with text
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
        INTO TABLE @lt_det
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

* Build result with status and stock qty
    LOOP AT lt_keys INTO ls_key.
      CLEAR ls_res.
      ls_res-matnr = ls_key-matnr.
      ls_res-werks = ls_key-werks.

* Map details
      READ TABLE lt_det INTO ls_det WITH KEY matnr = ls_key-matnr.
      IF sy-subrc = 0.
        ls_res-mtart = ls_det-mtart.
        ls_res-matkl = ls_det-matkl.
        ls_res-maktx = ls_det-makt