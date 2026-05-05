REPORT ZAI_260505_2223.

TABLES mara.

SELECT-OPTIONS:
  s_budat FOR mkpf~budat,
  s_werks FOR mseg~werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_pair,
        matnr TYPE mara-matnr,
        werks TYPE werks_d,
      END OF ty_pair,
      ty_t_pair TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY,
      BEGIN OF ty_mdata,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mdata,
      ty_t_mdata TYPE STANDARD TABLE OF ty_mdata WITH EMPTY KEY,
      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE werks_d,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_mov_matnr   TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_stock_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_union       TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lt_mov_pairs   TYPE ty_t_pair.
    DATA lt_stock_pairs TYPE ty_t_pair.
    DATA lt_pairs_all   TYPE ty_t_pair.

    DATA lt_mdata  TYPE ty_t_mdata.
    DATA lt_result TYPE ty_t_result.

    SELECT DISTINCT
      mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
      INTO TABLE @lt_mov_matnr.

    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
      INTO TABLE @lt_mov_pairs.

    SELECT DISTINCT
      mard~matnr
      FROM mard
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0
      INTO TABLE @lt_stock_matnr.

    SELECT DISTINCT
      mard~matnr,
      mard~werks
      FROM mard
      WHERE mard~werks IN @s_werks
        AND mard~labst <> 0
      INTO TABLE @lt_stock_pairs.

    APPEND LINES OF lt_mov_matnr   TO lt_union.
    APPEND LINES OF lt_stock_matnr TO lt_union.
    SORT lt_union BY table_line.
    DELETE ADJACENT DUPLICATES FROM lt_union COMPARING table_line.

    IF lt_union IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_mdata
      WHERE mara~matnr IN @lt_union.

    SORT lt_mdata BY matnr.

    APPEND LINES OF lt_mov_pairs   TO lt_pairs_all.
    APPEND LINES OF lt_stock_pairs TO lt_pairs_all.
    SORT lt_pairs_all BY matnr werks.
    DELETE ADJACENT DUPLICATES FROM lt_pairs_all COMPARING matnr werks.

    SORT lt_mov_pairs BY matnr werks.
    SORT lt_stock_pairs BY matnr werks.

    DATA ls_res TYPE ty_result.
    LOOP AT lt_pairs_all ASSIGNING FIELD-SYMBOL(<ls_pair>).
      CLEAR ls_res.
      ls_res-matnr = <ls_pair>-matnr.
      ls_res-werks = <ls_pair>-werks.

      READ TABLE lt_mdata ASSIGNING FIELD-SYMBOL(<ls_md>)
           WITH KEY matnr = <ls_pair>-matnr BINARY SEARCH.
      IF sy-subrc = 0.
        ls_res-mtart = <ls_md>-mtart.
        ls_res-matkl = <ls_md>-matkl.
        ls_res-maktx = <ls_md>-maktx.
      ENDIF.

      DATA(lv_has_mov) = abap_false.
      DATA(lv_has_stk) = abap_false.

      READ TABLE lt_mov_pairs TRANSPORTING NO FIELDS
           WITH KEY matnr = <ls_pair>-matnr
                    werks = <ls_pair>-werks BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_mov = abap_true.
      ENDIF.

      READ TABLE lt_stock_pairs TRANSPORTING NO FIELDS
           WITH KEY matnr = <ls_pair>-matnr
                    werks = <ls_pair>-werks BINARY SEARCH.
      IF sy-subrc = 0.
        lv_has_stk = abap_true.
      ENDIF.

      IF lv_has_mov = abap_true.
        ls_res-status = '입출고 있음'.
      ELSEIF lv_has_stk = abap_true.
        ls_res-status = '재고만 있음'.
      ELSE.
        CONTINUE.
      ENDIF.

      APPEND ls_res TO lt_result.
    ENDLOOP.

    IF lt_result IS INITIAL.
      WRITE: / '선택한 조건에 해당하는 자재가 없습니다.'.
      RETURN.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_result ).

        lo_alv->get_functions( )->set_all( abap_true ).
        lo_alv->get_columns( )->set_optimize( abap_true ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx_msg).
        WRITE: / 'ALV 오류: ', lx_msg->get_text( ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).