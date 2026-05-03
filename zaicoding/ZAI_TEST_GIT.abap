REPORT ZAI_TEST_GIT.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_row,
             matnr TYPE mara-matnr,
             ersda TYPE mara-ersda,
             maktx TYPE makt-maktx,
           END OF ty_row.

    DATA lt_data TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY.
    DATA lo_alv TYPE REF TO cl_salv_table.

    SELECT a~matnr,
           a~ersda,
           b~maktx
      FROM mara AS a
      LEFT OUTER JOIN makt AS b
        ON b~matnr = a~matnr
       AND b~spras = @sy-langu
      INTO TABLE @lt_data
      ORDER BY a~ersda DESCENDING, a~matnr ASCENDING
      UP TO 3 ROWS.

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