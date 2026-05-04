REPORT ZAI_260504_1629.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES: BEGIN OF ty_kna1,
             kunnr TYPE kna1-kunnr,
             name1 TYPE kna1-name1,
             name2 TYPE kna1-name2,
             land1 TYPE kna1-land1,
             ort01 TYPE kna1-ort01,
             pstlz TYPE kna1-pstlz,
             regio TYPE kna1-regio,
             stras TYPE kna1-stras,
             telf1 TYPE kna1-telf1,
             telfx TYPE kna1-telfx,
             spras TYPE kna1-spras,
             stcd1 TYPE kna1-stcd1,
             stcd2 TYPE kna1-stcd2,
             umsat TYPE kna1-umsat,
             umjah TYPE kna1-umjah,
             uwaer TYPE kna1-uwaer,
             erdat TYPE kna1-erdat,
             sperr TYPE kna1-sperr,
             loevm TYPE kna1-loevm,
             ktokd TYPE kna1-ktokd,
           END OF ty_kna1.

    DATA lt_data TYPE STANDARD TABLE OF ty_kna1 WITH EMPTY KEY.
    DATA lo_alv  TYPE REF TO cl_salv_table.

    SELECT
      kna1~kunnr,
      kna1~name1,
      kna1~name2,
      kna1~land1,
      kna1~ort01,
      kna1~pstlz,
      kna1~regio,
      kna1~stras,
      kna1~telf1,
      kna1~telfx,
      kna1~spras,
      kna1~stcd1,
      kna1~stcd2,
      kna1~umsat,
      kna1~umjah,
      kna1~uwaer,
      kna1~erdat,
      kna1~sperr,
      kna1~loevm,
      kna1~ktokd
      FROM kna1
      INTO TABLE @lt_data.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = lt_data ).
        lo_alv->display( ).
      CATCH cx_salv_msg INTO DATA(lx).
        MESSAGE lx->get_text( ) TYPE 'S'.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).