REPORT ZAI_260504_2023.

SELECT-OPTIONS:
  s_budat FOR sy-datum,
  s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

TYPES:
  BEGIN OF ty_move,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
  END OF ty_move,
  ty_t_move   TYPE STANDARD TABLE OF ty_move WITH EMPTY KEY,
  ty_t_move_h TYPE HASHED TABLE OF ty_move WITH UNIQUE KEY matnr werks.

TYPES:
  BEGIN OF ty_stock,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
    labst TYPE mard-labst,
  END OF ty_stock,
  ty_t_stock   TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
  ty_t_stock_h TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.

TYPES:
  BEGIN OF ty_mm,
    matnr TYPE mara-matnr,
    mtart TYPE mara-mtart,
    matkl TYPE mara-matkl,
    maktx TYPE makt-maktx,
  END OF ty_mm,
  ty_t_mm   TYPE STANDARD TABLE OF ty_mm WITH EMPTY KEY,
  ty_t_mm_h TYPE HASHED TABLE OF ty_mm WITH UNIQUE KEY matnr.

TYPES:
  BEGIN OF ty_result,
    matnr  TYPE mara-matnr,
    werks  TYPE mseg-werks,
    mtart  TYPE mara-mtart,
    matkl  TYPE mara-matkl,
    maktx  TYPE makt-maktx,
    labst  TYPE mard-labst,
    status TYPE c LENGTH 20,
  END OF ty_result,
  ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_move     TYPE ty_t_move.
    DATA lt_move_h   TYPE ty_t_move_h.
    DATA lt_stock    TYPE ty_t_stock.
    DATA lt_stock_h  TYPE ty_t_stock_h.
    DATA lt_mm       TYPE ty_t_mm.
    DATA lt_mm_h     TYPE ty_t_mm_h.
    DATA lt_result   TYPE ty_t_result.

    DATA lt_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lo_alv TYPE REF TO cl_salv_table.

* 1) Movements by posting date and plant
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_move
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr IS NOT NULL.

    lt_move_h = CORRESPONDING ty_t_move_h( lt_move ).

* 2) Current non-zero stock by plant
    SELECT
      mard~matnr,
      mard~werks,
      mard~labst
      FROM mard
      INTO TABLE @lt_stock
      WHERE mard~werks IN @s_werks
        AND mard~labst > 0.

    lt_stock_h = CORRESPONDING ty_t_stock_h( lt_stock ).

* 3) Build material list from movements and stocks
    LOOP AT lt_move ASSIGNING FIELD-SYMBOL(<ls_m>).
      APPEND <ls_m>-matnr TO lt_matnr.
    ENDLOOP.
    LOOP AT lt_stock ASSIGNING FIELD-SYMBOL(<ls_s>).
      APPEND <ls_s>-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_matnr COMPARING table_line.

* 4) Read material master and text
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
        INTO TABLE @lt_mm
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    lt_mm_h = CORRESPONDING ty_t_mm_h( lt_mm ).

* 5) Build result for materials with movements
    LOOP AT lt_move ASSIGNING <ls_m>.
      DATA(ls_res) = VALUE ty_result(
        matnr = <ls_m>-matnr
        werks = <ls_m>-werks
        mtart = VALUE mara-mtart( )
        matkl = VALUE mara-matkl( )
        maktx = VALUE makt-maktx( )
        labst = VALUE mard-labst( )
        status = '입출고 있음' ).

      READ TABLE lt_mm_h ASSIGNING FIELD-SYMBOL(<ls_mm>)
        WITH TABLE KEY matnr = <ls_m>-matnr.
      IF sy-subrc = 0.
        ls_res-mtart = <ls_mm>-mtart.
        ls_res-matkl = <ls_mm>-matkl.
        ls_res-maktx = <ls_mm>-maktx.
      ENDIF.

      READ TABLE lt_stock_h ASSIGNING FIELD-SYMBOL(<ls_stk>)
        WITH TABLE KEY matnr = <ls_m>-matnr werks = <ls_m>-werks.
      IF sy-subrc = 0.
        ls_res-labst = <ls_stk>-labst.
      ELSE.
        ls_res-labst = 0.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

* 6) Add stocks with no movements: status '재고만 있음'
    LOOP AT lt_stock ASSIGNING <ls_s>.
      READ TABLE lt_move_h TRANSPORTING NO FIELDS
        WITH TABLE KEY matnr = <ls_s>-matnr werks = <ls_s>-werks.
      IF sy-subrc <> 0.
        DATA(ls_res2) = VALUE ty_result(
          matnr = <ls_s>-matnr
          werks = <ls_s>-werks
          mtart = VALUE mara-mtart( )
          matkl = VALUE mara-matkl( )
          maktx = VALUE makt-maktx( )
          labst = <ls_s>-labst
          status = '재고만 있음' ).

        READ TABLE lt_mm_h ASSIGNING <ls_mm>
          WITH TABLE KEY matnr = <ls_s>-matnr.
        IF sy-subrc = 0.
          ls_res2-mtart = <ls_mm>-mtart.
          ls_res2-matkl = <ls_mm>-matkl.
          ls_res2-maktx = <ls_mm>-maktx.
        ENDIF.

        APPEND ls_res2 TO lt_result.
      ENDIF.
    ENDLOOP.

* 7) Display
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).
        lo_alv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).