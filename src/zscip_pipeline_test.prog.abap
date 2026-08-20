*&---------------------------------------------------------------------*
*& Report ZSCIP_PIPELINE_TEST
*&---------------------------------------------------------------------*
*& DEMO DATA - 파이프라인 테스트용 (E2E: Claude -> OpenClaw -> Git -> SAP)
*& 2025년 고객별 청구 매출액 (목업 데이터)
*&---------------------------------------------------------------------*
REPORT zscip_pipeline_test.

TYPES: BEGIN OF ty_billing,
         kunnr TYPE kunnr,       " 고객번호
         name1 TYPE name1_gp,    " 고객명
         netwr TYPE netwr,       " 2025년 청구액
       END OF ty_billing.

DATA: gt_billing TYPE STANDARD TABLE OF ty_billing,
      gs_billing TYPE ty_billing.

START-OF-SELECTION.

* DEMO DATA - 파이프라인 테스트용 (실제 테이블 미접근, 하드코딩 샘플)
  gs_billing-kunnr = '0000001000'.
  gs_billing-name1 = 'Alpha Trading GmbH'.
  gs_billing-netwr = '1250000.00'.
  APPEND gs_billing TO gt_billing.

  gs_billing-kunnr = '0000001001'.
  gs_billing-name1 = 'Beta Manufacturing Co.'.
  gs_billing-netwr = '873500.50'.
  APPEND gs_billing TO gt_billing.

  gs_billing-kunnr = '0000001002'.
  gs_billing-name1 = 'Gamma Retail Ltd.'.
  gs_billing-netwr = '2145000.00'.
  APPEND gs_billing TO gt_billing.

  gs_billing-kunnr = '0000001003'.
  gs_billing-name1 = 'Delta Services Inc.'.
  gs_billing-netwr = '456200.75'.
  APPEND gs_billing TO gt_billing.

  gs_billing-kunnr = '0000001004'.
  gs_billing-name1 = 'Epsilon Logistics'.
  gs_billing-netwr = '1789900.00'.
  APPEND gs_billing TO gt_billing.

END-OF-SELECTION.

  WRITE: / '고객번호', 15 '고객명', 55 '2025년 청구액'.
  ULINE.
  LOOP AT gt_billing INTO gs_billing.
    WRITE: / gs_billing-kunnr, 15 gs_billing-name1, 55 gs_billing-netwr.
  ENDLOOP.
