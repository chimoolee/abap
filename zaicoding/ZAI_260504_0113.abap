REPORT ZAI_260504_0113.

SELECT-OPTIONS s_vkorg FOR vbak-vkorg OBLIGATORY.
SELECT-OPTIONS s_audat FOR vbak-audat.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_row,
             kunnr     TYPE vbak-kunnr,
             name1     TYPE kna1-name1,
             waerk     TYPE vbak-waerk,
             netwr_sum TYPE vbak-netwr,
           END OF ty_row.

    DATA lt_data TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    DATA ls_row  TYPE ty_row.

    IF s_audat[] IS INITIAL.
      SELECT
        vbak~kunnr,
        kna1~name1,
        vbak~waerk,
        SUM( vbak~netwr ) AS netwr_sum
        FROM vbak AS vbak
        INNER JOIN kna1 AS kna1
          ON kna1~kunnr = vbak~kunnr
        WHERE vbak~vkorg IN @s_vkorg
        GROUP BY vbak~kunnr, kna1~name1, vbak~waerk
        INTO TABLE @lt_data.
    ELSE.
      SELECT
        vbak~kunnr,
        kna1~name1,
        vbak~waerk,
        SUM( vbak~netwr ) AS netwr_sum
        FROM vbak AS vbak
        INNER JOIN kna1 AS kna1
          ON kna1~kunnr = vbak~kunnr
        WHERE vbak~vkorg IN @s_vkorg
          AND vbak~audat IN @s_audat
        GROUP BY vbak~kunnr, kna1~name1, vbak~waerk
        INTO TABLE @lt_data.
    ENDIF.

    IF lt_data IS INITIAL.
      MESSAGE '조회 결과가 없습니다.' TYPE 'S'.
      RETURN.
    ENDIF.

    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_data ).

    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

    DATA(lo_cols) = lo_alv->get_columns( ).
    TRY.
        lo_cols->get_column( 'KUNNR' )->set_short_text( '고객' ).
        lo_cols->get_column( 'NAME1' )->set_short_text( '고객명' ).
        lo_cols->get_column( 'WAERK' )->set_short_text( '통화' ).
        lo_cols->get_column( 'NETWR_SUM' )->set_short_text( '주문금액합계' ).
      CATCH cx_salv_not_found.
    ENDTRY.

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).