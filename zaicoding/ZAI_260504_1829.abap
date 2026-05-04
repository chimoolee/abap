REPORT ZAI_260504_1829.

SELECT-OPTIONS s_budat FOR mkpf-budat.
SELECT-OPTIONS s_werks FOR t001w-werks.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.
  METHOD run.
    TYPES:
      BEGIN OF ty_post,
        matnr TYPE mseg-matnr,
        werks TYPE mseg-werks,
      END OF ty_post,
      ty_t_post TYPE STANDARD TABLE OF ty_post WITH EMPTY KEY,

      BEGIN OF ty_stock,
        matnr TYPE mard-matnr,
        werks TYPE mard-werks,
        qty   TYPE mard-labst,
      END OF ty_stock,
      ty_t_stock TYPE STANDARD TABLE OF ty_stock WITH EMPTY KEY,

      BEGIN OF ty_pair,
        matnr   TYPE mara-matnr,
        werks   TYPE t001w-werks,
        has_post TYPE abap_bool,
        qty     TYPE mard-labst,
      END OF ty_pair,
      ty_t_pair TYPE STANDARD TABLE OF ty_pair WITH EMPTY KEY,

      BEGIN OF ty_mat,
        matnr TYPE mara-matnr,
        mtart TYPE mara-mtart,
        matkl TYPE mara-matkl,
        maktx TYPE makt-maktx,
      END OF ty_mat,
      ty_t_mat TYPE STANDARD TABLE OF ty_mat WITH EMPTY KEY,

      BEGIN OF ty_result,
        matnr  TYPE mara-matnr,
        werks  TYPE t001w-werks,
        mtart  TYPE mara-mtart,
        matkl  TYPE mara-matkl,
        maktx  TYPE makt-maktx,
        qty    TYPE mard-labst,
        status TYPE char20,
      END OF ty_result,
      ty_t_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    DATA lt_post    TYPE ty_t_post.
    DATA lt_stock   TYPE ty_t_stock.
    DATA lt_pairs   TYPE ty_t_pair.
    DATA lt_mat     TYPE ty_t_mat.
    DATA lt_result  TYPE ty_t_result.

    " 1) Materials with postings by posting date/plant (MKPF/MSEG join)
    SELECT DISTINCT
      mseg~matnr,
      mseg~werks
      FROM mseg
      INNER JOIN mkpf
        ON mkpf~mblnr = mseg~mblnr
       AND mkpf~mjahr = mseg~mjahr
      INTO TABLE @lt_post
      WHERE mkpf~budat IN @s_budat
        AND mseg~werks IN @s_werks
        AND mseg~matnr <> ''.

    " 2) Materials with current non-zero stock by plant
    SELECT
      mard~matnr,
      mard~werks,
      SUM( mard~labst ) AS qty
      FROM mard
      WHERE mard~werks IN @s_werks
      GROUP BY mard~matnr, mard~werks
      HAVING SUM( mard~labst ) > 0
      INTO TABLE @lt_stock.

    " 3) Build union of material/plant pairs with flags and qty
    DATA lt_pairs_h TYPE HASHED TABLE OF ty_pair
      WITH UNIQUE KEY matnr werks.
    DATA ls_pair TYPE ty_pair.

    LOOP AT lt_post INTO DATA(ls_post).
      CLEAR ls_pair.
      ls_pair-matnr   = ls_post-matnr.
      ls_pair-werks   = ls_post-werks.
      ls_pair-has_post = abap_true.
      ls_pair-qty     = 0.
      INSERT ls_pair INTO TABLE lt_pairs_h.
    ENDLOOP.

    LOOP AT lt_stock INTO DATA(ls_stock).
      READ TABLE lt_pairs_h INTO ls_pair
        WITH TABLE KEY matnr = ls_stock-matnr werks = ls_stock-werks.
      IF sy-subrc = 0.
        ls_pair-qty = ls_stock-qty.
        MODIFY TABLE lt_pairs_h FROM ls_pair.
      ELSE.
        CLEAR ls_pair.
        ls_pair-matnr   = ls_stock-matnr.
        ls_pair-werks   = ls_stock-werks.
        ls_pair-has_post = abap_false.
        ls_pair-qty     = ls_stock-qty.
        INSERT ls_pair INTO TABLE lt_pairs_h.
      ENDIF.
    ENDLOOP.

    lt_pairs = CORRESPONDING #( lt_pairs_h ).

    " 4) Collect unique materials for attribute/text fetch
    TYPES ty_t_matnr TYPE STANDARD TABLE OF mara-matnr WITH EMPTY KEY.
    DATA lt_matnr TYPE ty_t_matnr.

    LOOP AT lt_pairs INTO ls_pair.
      APPEND ls_pair-matnr TO lt_matnr.
    ENDLOOP.
    SORT lt_matnr.
    DELETE ADJACENT DUPLICATES FROM lt_matnr.

    " 5) Fetch material attributes and text
    IF lt_matnr IS NOT INITIAL.
      SELECT
        mara~matnr,
        mara~mtart,
        mara~matkl,
        makt~maktx
        FROM mara
        LEFT JOIN makt
          ON makt~matnr = mara~matnr
         AND makt~spras = @sy-langu
        INTO TABLE @lt_mat
        WHERE mara~matnr IN @lt_matnr.
    ENDIF.

    " 6) Build final result
    DATA ls_result TYPE ty_result.
    LOOP AT lt_pairs INTO ls_pair.
      CLEAR ls_result.
      ls_result-matnr = ls_pair-matnr.
      ls_result-werks = ls_pair-werks.
      ls_result-qty   = ls_pair-qty.

      READ TABLE lt_mat INTO DATA(ls_mat)
        WITH KEY matnr = ls_pair-matnr.
      IF sy-subrc = 0.
        ls_result-mtart = ls_mat-mtart.
        ls_result-matkl = ls_mat-matkl.
        ls_result-maktx = ls_mat-maktx.
      ENDIF.

      IF ls_pair-has_post = abap_true.
        ls_result-status = '입출고실적 있음'.
      ELSE.
        ls_result-status = '재고만 있음'.
      ENDIF.

      APPEND ls_result TO lt_result.
    ENDLOOP.

    " 7) Display ALV
    DATA lo_alv TYPE REF TO cl_salv_table.
    cl_salv_table=>factory(
      IMPORTING
        r_salv_table = lo_alv
      CHANGING
        t_table      = lt_result ).
    lo_alv->get_columns( )->