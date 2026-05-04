REPORT ZAI_260504_1009.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_row,
             vbeln TYPE vbak-vbeln,
             auart TYPE vbak-auart,
             vkorg TYPE vbak-vkorg,
             vtweg TYPE vbak-vtweg,
             spart TYPE vbak-spart,
             kunnr TYPE vbak-kunnr,
             name1 TYPE kna1-name1,
             erdat TYPE vbak-erdat,
             netwr TYPE vbak-netwr,
             waerk TYPE vbak-waerk,
           END OF ty_row.

    DATA lt_data TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    DATA lo_alv TYPE REF TO cl_salv_table.
    DATA lo_cols TYPE REF TO cl_salv_columns_table.
    DATA lo_col  TYPE REF TO cl_salv_column_table.

    SELECT
      vbak~vbeln,
      vbak~auart,
      vbak~vkorg,
      vbak~vtweg,
      vbak~spart,
      vbak~kunnr,
      kna1~name1,
      vbak~erdat,
      vbak~netwr,
      vbak~waerk
      FROM vbak AS vbak
      LEFT OUTER JOIN kna1 AS kna1
        ON kna1~kunnr = vbak~kunnr
      INTO TABLE @lt_data.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_data ).
      CATCH cx_salv_msg.
        RETURN.
    ENDTRY.

    lo_cols = lo_alv->get_columns( ).

    lo_col = lo_cols->get_column( 'VBELN' ).
    lo_col->set_short_text( 'Sales Ord.' ).
    lo_col->set_medium_text( 'Sales Order' ).
    lo_col->set_long_text( 'Sales Order Number' ).

    lo_col = lo_cols->get_column( 'AUART' ).
    lo_col->set_short_text( 'Type' ).
    lo_col->set_medium_text( 'Order Type' ).
    lo_col->set_long_text( 'Sales Document Type' ).

    lo_col = lo_cols->get_column( 'VKORG' ).
    lo_col->set_short_text( 'SOrg' ).
    lo_col->set_medium_text( 'Sales Org.' ).
    lo_col->set_long_text( 'Sales Organization' ).

    lo_col = lo_cols->get_column( 'VTWEG' ).
    lo_col->set_short_text( 'DCh' ).
    lo_col->set_medium_text( 'Dist. Channel' ).
    lo_col->set_long_text( 'Distribution Channel' ).

    lo_col = lo_cols->get_column( 'SPART' ).
    lo_col->set_short_text( 'Div' ).
    lo_col->set_medium_text( 'Division' ).
    lo_col->set_long_text( 'Division' ).

    lo_col = lo_cols->get_column( 'KUNNR' ).
    lo_col->set_short_text( 'Customer' ).
    lo_col->set_medium_text( 'Sold-to' ).
    lo_col->set_long_text( 'Sold-to Party' ).

    lo_col = lo_cols->get_column( 'NAME1' ).
    lo_col->set_short_text( 'Name' ).
    lo_col->set_medium_text( 'Customer Name' ).
    lo_col->set_long_text( 'Customer Name (Sold-to)' ).

    lo_col = lo_cols->get_column( 'ERDAT' ).
    lo_col->set_short_text( 'Created' ).
    lo_col->set_medium_text( 'Created On' ).
    lo_col->set_long_text( 'Creation Date' ).

    lo_col = lo_cols->get_column( 'NETWR' ).
    lo_col->set_short_text( 'Net' ).
    lo_col->set_medium_text( 'Net Value' ).
    lo_col->set_long_text( 'Net Value of the Sales Order' ).

    lo_col = lo_cols->get_column( 'WAERK' ).
    lo_col->set_short_text( 'Crcy' ).
    lo_col->set_medium_text( 'Currency' ).
    lo_col->set_long_text( 'Document Currency' ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_list_header( 'Customer Sales Orders' ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).