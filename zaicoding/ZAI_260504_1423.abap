REPORT ZAI_260504_1423.

TYPES:
  BEGIN OF ty_result,
    matnr TYPE mara-matnr,
    mtart TYPE mara-mtart,
    matkl TYPE mara-matkl,
    maktx TYPE makt-maktx,
  END OF ty_result,
  ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

DATA lt_result TYPE ty_t_result.
DATA lo_alv TYPE REF TO cl_salv_table.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    SELECT
      mara~matnr,
      mara~mtart,
      mara~matkl,
      makt~maktx
      FROM mara
      LEFT JOIN makt
        ON makt~matnr = mara~matnr
       AND makt~spras = @sy-langu
      INTO TABLE @lt_result
      UP TO 10 ROWS.

    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).

    lo_alv->display( ).
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).