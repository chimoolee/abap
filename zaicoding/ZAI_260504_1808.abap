REPORT ZAI_260504_1808.

TYPES:
  BEGIN OF ty_result,
    kunnr TYPE kna1-kunnr,
    name1 TYPE kna1-name1,
    land1 TYPE kna1-land1,
    ort01 TYPE kna1-ort01,
    pstlz TYPE kna1-pstlz,
    regio TYPE kna1-regio,
    stras TYPE kna1-stras,
    telf1 TYPE kna1-telf1,
  END OF ty_result,
  ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    DATA lt_result TYPE ty_t_result.
    DATA lo_alv TYPE REF TO cl_salv_table.

    SELECT
      kna1~kunnr,
      kna1~name1,
      kna1~land1,
      kna1~ort01,
      kna1~pstlz,
      kna1~regio,
      kna1~stras,
      kna1~telf1
      FROM kna1
      INTO TABLE @lt_result.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_functions( )->set_all( abap_true ).
    lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).