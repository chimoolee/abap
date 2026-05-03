REPORT ZAI_260504_0121.

PARAMETERS p_vkorg TYPE vbak-vkorg OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_out,
             kunnr        TYPE kna1-kunnr,
             name1        TYPE kna1-name1,
             waerk        TYPE vbak-waerk,
             total_netwr  TYPE vbak-netwr,
             order_cnt    TYPE i,
           END OF ty_out.

    DATA lt_out TYPE STANDARD TABLE OF ty_out WITH EMPTY KEY.

    SELECT
      a~kunnr          AS kunnr,
      b~name1          AS name1,
      a~waerk          AS waerk,
      SUM( a~netwr )   AS total_netwr,
      COUNT( * )       AS order_cnt
      FROM vbak AS a
      INNER JOIN kna1 AS b
        ON b~kunnr = a~kunnr
      WHERE a~vkorg = @p_vkorg
      GROUP BY a~kunnr, b~name1, a~waerk
      INTO TABLE @lt_out.

    DATA lo_alv TYPE REF TO cl_salv_table.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_out ).

    lo_alv->get_columns( )->set_optimize( abap_true ).

    DATA(lo_cols) = lo_alv->get_columns( ).
    TRY.
        lo_cols->get_column( 'KUNNR' )->set_long_text( 'Customer' ).
        lo_cols->get_column( 'NAME1' )->set_long_text( 'Customer Name' ).
        lo_cols->get_column( 'WAERK' )->set_long_text( 'Currency' ).
        lo_cols->get_column( 'TOTAL_NETWR' )->set_long_text( 'Total Order Value' ).
        lo_cols->get_column( 'ORDER_CNT' )->set_long_text( 'Order Count' ).
      CATCH cx_salv_not_found.
    ENDTRY.

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).