REPORT ZAI_260504_1812.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_result,
        kunnr TYPE kna1-kunnr,
        name1 TYPE kna1-name1,
        land1 TYPE kna1-land1,
        ort01 TYPE kna1-ort01,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_result TYPE ty_t_result.
    DATA lo_alv    TYPE REF TO cl_salv_table.

    SELECT
      kna1~kunnr,
      kna1~name1,
      kna1~land1,
      kna1~ort01
      FROM kna1
      INTO TABLE @lt_result.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->get_display_settings( )->set_striped_pattern( abap_true ).
    lo_alv->get_columns( )->set_optimize( abap_true ).
    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).