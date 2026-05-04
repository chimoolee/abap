REPORT ZAI_260504_2023.

SELECT-OPTIONS:
  s_budat FOR mkpf-budat,
  s_werks FOR mseg-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

TYPES:
  BEGIN OF ty_key,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
  END OF ty_key,
  ty_t_key TYPE STANDARD TABLE OF ty_key WITH EMPTY KEY,
  ty_t_key_h TYPE HASHED TABLE OF ty_key WITH UNIQUE KEY matnr werks.

TYPES:
  BEGIN OF ty_stock,
    matnr TYPE mara-matnr,
    werks TYPE mseg-werks,
    labst TYPE mard-labst,
  END OF ty_stock,
  ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,
  ty_t_stock_h TYPE HASHED TABLE OF ty_stock WITH UNIQUE KEY matnr werks.

TYPES:
  BEGIN OF ty_mm,
    matnr TYPE mara-matnr,
    mtart TYPE mara-mtart,
    matkl TYPE mara-matkl,
    maktx TYPE makt-maktx,
  END OF ty_mm,
  ty_t_mm_h TYPE HASHED TABLE OF ty_mm WITH UNIQUE KEY matnr.

TYPES:
  BEGIN OF ty_result,
    matnr  TYPE mara-matnr,
    werks  TYPE mseg-werks,
    mtart  TYPE mara-mtart,
    matkl  TYPE mara-matkl,
    maktx  TYPE makt-maktx,
    labst  TYPE mard-labst