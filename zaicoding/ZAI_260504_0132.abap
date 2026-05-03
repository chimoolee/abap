REPORT ZAI_260504_0132.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_row,
             kunnr TYPE vbak-kunnr,
             name1 TYPE kna1-name1,
             waerk TYPE vbak-waerk,
             netwr TYPE vbak-netwr,
           END OF ty_row.
    DATA lt_data TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    DATA lo_alv TYPE REF TO cl_salv_table.

    SELECT
      vbak~kunnr,
      kna1~name1,
      vbak~waerk,
      SUM( vbak~netwr ) AS netwr
      FROM vbak AS vbak
      INNER JOIN kna1 AS kna1
        ON kna1~kunnr = vbak~kunnr
      WHERE vbak~vkorg = '1010'
      GROUP BY
        vbak~kunnr,
        kna1~name1,
        vbak~waerk
      INTO TABLE @lt_data.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_data ).

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).