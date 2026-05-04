REPORT ZAI_260504_1550.

PARAMETERS p_werks TYPE werks_d OBLIGATORY.
PARAMETERS p_begda TYPE sy-datum DEFAULT sy-datum.
PARAMETERS p_endda TYPE sy-datum DEFAULT sy-datum.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lv_werks TYPE werks_d VALUE p_werks.
    DATA lv_begda TYPE sy-datum VALUE p_begda.
    DATA lv_endda TYPE sy-datum VALUE p_endda.

    TYPES: ty_matnr_tab TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.

    DATA lt_move  TYPE ty_matnr_tab.
    DATA lt_stock TYPE ty_matnr_tab.
    DATA lt_all   TYPE HASHED TABLE OF mara-matnr WITH UNIQUE KEY table_line.

    SELECT DISTINCT mseg~matnr
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      WHERE mseg~werks = @lv_werks
        AND mkpf~budat BETWEEN @lv_begda AND @lv_endda
      INTO TABLE @lt_move.

    SELECT mard~matnr
      FROM mard
      WHERE mard~werks = @lv_werks
        AND mard~labst > 0
      INTO TABLE @lt_stock.

    LOOP AT lt_move INTO DATA(lv_matnr).
      INSERT lv_matnr INTO TABLE lt_all.
    ENDLOOP.
    LOOP AT lt_stock INTO lv_matnr.
      INSERT lv_matnr INTO TABLE lt_all.
    ENDLOOP.

    TYPES: BEGIN OF ty_row,
             category TYPE char20,
             matnr    TYPE mara-matnr,
             maktx    TYPE makt-maktx,
             mtart    TYPE mara-mtart,
             matkl    TYPE mara-matkl,
             meins    TYPE mara-meins,
             status   TYPE char20,
           END OF ty_row.
    TYPES ty_t_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.

    DATA lt_main TYPE ty_t_row.
    DATA lt_bomsec TYPE ty_t_row.

    IF lt_all IS NOT INITIAL.
      DATA lt_info TYPE STANDARD TABLE OF
        SORTED BY matnr
        WITH UNIQUE KEY matnr.
      TYPES: BEGIN OF ty_info,
               matnr TYPE mara-matnr,
               mtart TYPE mara-mtart,
               matkl TYPE mara-matkl,
               meins TYPE mara-meins,
               maktx TYPE makt-maktx,
             END OF ty_info.
      DATA: lt_info_tab TYPE STANDARD TABLE OF ty_info WITH EMPTY KEY.

      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             mara~meins,
             makt~maktx
        FROM mara
        INNER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        WHERE mara~matnr IN @lt_all
        INTO TABLE @lt_info_tab.

      LOOP AT lt_info_tab INTO DATA(ls_info).
        DATA(lv_status) = COND char20(
          WHEN line_exists( lt_move[ table_line = ls_info-matnr ] )
          THEN '입출고 있음'
          ELSE '재고만 있음' ).
        APPEND VALUE ty_row(
          category = '전체'
          matnr    = ls_info-matnr
          maktx    = ls_info-maktx
          mtart    = ls_info-mtart
          matkl    = ls_info-matkl
          meins    = ls_info-meins
          status   = lv_status ) TO lt_main.
      ENDLOOP.
    ENDIF.

    DATA lt_fert_bom TYPE ty_matnr_tab.
    SELECT DISTINCT mast~matnr
      FROM mast
      INNER JOIN mara
        ON mara~matnr = mast~matnr
      WHERE mast~werks = @lv_werks
        AND mara~mtart = 'FERT'
      INTO TABLE @lt_fert_bom.

    IF lt_fert_bom IS NOT INITIAL.
      DATA lt_fert_info TYPE STANDARD TABLE OF ty_info WITH EMPTY KEY.
      SELECT mara~matnr,
             mara~mtart,
             mara~matkl,
             mara~meins,
             makt~maktx
        FROM mara
        INNER JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        WHERE mara~matnr IN @lt_fert_bom
        INTO TABLE @lt_fert_info.

      LOOP AT lt_fert_info INTO DATA(ls_fert).
        DATA(lv_fstat) = COND char20(
          WHEN line_exists( lt_move[ table_line = ls_fert-matnr ] )
          THEN '입출고 있음'
          ELSE COND char20(
                 WHEN line_exists( lt_stock[ table_line = ls_fert-matnr ] )
                 THEN '재고만 있음'
                 ELSE 'BOM 만 있음' ) ).
        APPEND VALUE ty_row(
          category = '완제품(BOM)'
          matnr    = ls_fert-matnr
          maktx    = ls_fert-maktx
          mtart    = ls_fert-mtart
          matkl    = ls_fert-matkl
          meins    = ls_fert-meins
          status   = lv_fstat ) TO lt_bomsec.
      ENDLOOP.

      DATA lt_comp TYPE ty_matnr_tab.
      SELECT DISTINCT stpo~idnrk
        FROM mast
        INNER JOIN stpo
          ON stpo~stlnr = mast~stlnr
        WHERE mast~werks = @lv_werks
        INTO TABLE @lt_comp.

      IF lt_comp IS NOT INITIAL.
        " Keep only components that have neither movement nor stock
        DATA lt_comp_only TYPE ty_matnr_tab.
        LOOP AT lt_comp INTO lv_matnr.
          IF NOT line_exists( lt_move[ table_line = lv_matnr ] )
             AND NOT line_exists( lt_stock[ table_line = lv_matnr ] ).
            APPEND lv_matnr TO lt_comp_only.
          ENDIF.
        ENDLOOP.

        IF lt_comp_only IS NOT INITIAL.
          DATA lt_comp_info TYPE STANDARD TABLE OF ty_info WITH EMPTY KEY.
          SELECT mara~matnr,
                 mara~mtart,
                 mara~matkl,
                 mara~meins,
                 makt~maktx
            FROM mara
            INNER JOIN makt
              ON makt~matnr = mara~matnr
             AND makt~spras = @sy-langu
            WHERE mara~matnr IN @lt_comp_only
            INTO TABLE @lt_comp_info.

          LOOP AT lt_comp_info INTO DATA(ls_comp).
            APPEND VALUE ty_row(
              category = 'BOM 요소'
              matnr    = ls_comp-matnr
              maktx    = ls_comp-maktx
              mtart    = ls_comp-mtart
              matkl    = ls_comp-matkl
              meins    = ls_comp-meins
              status   = 'BOM 만 있음' ) TO lt_bomsec.
          ENDLOOP.
        ENDIF.
      ENDIF.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_main ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      '전체 자재 현황: 입출고 실적 또는 현재 재고가 있는 자재' ).
    lo_alv->display( ).

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_bomsec ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_list_header(
      'BOM 섹션: BOM 보유 완제품 및 재고/입출고 없음의 BOM 요소' ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).