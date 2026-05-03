REPORT ZAI_260504_0021.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_kna1_row,
             kunnr TYPE kna1-kunnr,
             name1 TYPE kna1-name1,
             land1 TYPE kna1-land1,
             ort01 TYPE kna1-ort01,
             pstlz TYPE kna1-pstlz,
             regio TYPE kna1-regio,
             telf1 TYPE kna1-telf1,
           END OF ty_kna1_row.
    DATA lt_kna1 TYPE STANDARD TABLE OF ty_kna1_row WITH EMPTY KEY.
    DATA lo_alv TYPE REF TO cl_salv_table.

    SELECT
      k~kunnr,
      k~name1,
      k~land1,
      k~ort01,
      k~pstlz,
      k~regio,
      k~telf1
      FROM kna1 AS k
      INTO TABLE @lt_kna1.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_kna1 ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).