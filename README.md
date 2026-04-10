[README.md](https://github.com/user-attachments/files/26641491/README.md)
# ABAP AI Code Generation Framework (ZAICODING Integrated Edition)

## 🚀 Overview

This repository defines a **production-ready AI-driven ABAP code
generation framework** for SAP S/4HANA 2022 (ABAP 7.56).

It combines: - Enterprise ABAP AI architecture - ZAICODING practical
implementation - OpenAI Responses API integration - Automatic correction
& stabilization engine

------------------------------------------------------------------------

## ⚙️ Key Features

-   Natural language → ABAP REPORT
-   Model: gpt-5.4
-   Temperature configurable (default 0.2)
-   Auto program naming: ZAI_YYMMDD_HHMM
-   INSERT REPORT + GENERATE REPORT
-   Auto correction engine (critical)
-   SE38 auto launch on success

------------------------------------------------------------------------

## 🧠 Architecture

User Prompt\
↓\
ZAI Generator\
↓\
OpenAI API\
↓\
ABAP Extraction (ABAP_START \~ ABAP_END)\
↓\
Auto Fix Engine\
↓\
Program Build\
↓\
Activation / SE38

------------------------------------------------------------------------

## 🏗 Enterprise Architecture

ZAI_MAIN (REPORT)\
├─ ZCL_ZAI_PROMPT_ANALYZER\
├─ ZCL_ZAI_METADATA_READER\
├─ ZCL_ZAI_OPENAI_CLIENT\
├─ ZCL_ZAI_CODE_EXTRACTOR\
├─ ZCL_ZAI_SYNTAX_CHECKER\
├─ ZCL_ZAI_REPAIR_ENGINE\
└─ ZCL_ZAI_PROGRAM_BUILDER

------------------------------------------------------------------------

## 📌 Core Rules (VERY IMPORTANT)

### 1. REPORT Rule

-   Only ONE REPORT statement allowed
-   Duplicate REPORT automatically removed

------------------------------------------------------------------------

### 2. Open SQL Rule

-   ❌ SELECT \* 금지
-   ✅ Explicit field only
-   ✅ @ only for variables

❌ Wrong:

``` abap
WHERE mtart = @'FERT'
```

✅ Correct:

``` abap
WHERE mtart = 'FERT'
```

------------------------------------------------------------------------

### 3. Elementary Type Rule (CRITICAL)

❌ Wrong:

``` abap
DATA(lv_mtart) = VALUE mara-mtart( 'FERT' ).
```

✅ Correct:

``` abap
DATA lv_mtart TYPE mara-mtart VALUE 'FERT'.
```

------------------------------------------------------------------------

### 4. SALV Rule

❌ Wrong:

``` abap
NEW cl_salv_table( )
CREATE OBJECT lo_alv.
```

✅ Correct:

``` abap
DATA lo_alv TYPE REF TO cl_salv_table.

cl_salv_table=>factory(
  IMPORTING r_salv_table = lo_alv
  CHANGING  t_table      = lt_data ).
```

------------------------------------------------------------------------

### 5. Partial SELECT Rule

Must define local TYPES when selecting subset fields.

------------------------------------------------------------------------

## 🔧 Auto Correction Engine

Automatically fixes:

  Issue              Fix
  ------------------ --------------
  @'FERT'            → 'FERT'
  VALUE mara-mtart   → TYPE VALUE
  Duplicate REPORT   → remove
  Broken syntax      → repair
  SALV misuse        → factory

------------------------------------------------------------------------

## 🔁 Execution Flow

1.  Prompt 입력
2.  OpenAI 호출
3.  ABAP 추출
4.  자동 보정
5.  프로그램 생성

### ✔ 성공

→ SE38 자동 호출

### ❌ 실패

→ 오류 + 소스 표시

------------------------------------------------------------------------

## 🧪 Example

Prompt:

    플랜트 1000 기준 자재 조회 ALV 만들어줘

------------------------------------------------------------------------

## ⚠️ Important Notes

-   API Key 교체 필수
-   생성 코드 반드시 검증
-   ABAP_START / ABAP_END 는 SE38에 넣으면 안됨

------------------------------------------------------------------------

## 🧩 Enterprise Rules

-   Exactly one REPORT
-   No markdown
-   No explanation text
-   Clean ABAP only
-   Explicit fields only
-   CL_SALV_TABLE=\>FACTORY only

------------------------------------------------------------------------

## 🧠 Advanced Rules (Stability)

-   CS/CP predicate → NOT or NS 사용
-   SELECT-OPTIONS → DDIC 변수 사용
-   Z/Y namespace only scan
-   recursion depth limit = 8
-   hotspot ALV navigation 권장
-   CONCATENATE numeric → 문자 변환 필수

------------------------------------------------------------------------

## 🔧 Technical Setup

### SM59

-   Host: api.openai.com
-   Path: /v1/responses
-   SSL 필수

### STRUST

-   인증서 체인 필요

------------------------------------------------------------------------

## 🧩 Next Step

-   /UI2/CL_JSON parsing
-   Double-pass validation

------------------------------------------------------------------------

## 👨‍💻 Maintainer

Chimoo Lee


---

## 🆕 ZAICODING Improvement Update

The following enhancements were added to improve practical generation stability in SAP S/4HANA 2022 ABAP 7.56.

### 1. DDIC Metadata Injection

Before sending the prompt to OpenAI, ZAICODING can detect the likely main table from the user request and read real DDIC fields from `DD03L`.

Purpose:
- reduce hallucinated field names
- prevent invalid components such as non-existent MARA fields
- improve field-level accuracy

Recommended approach:

```abap
SELECT fieldname
  FROM dd03l
  WHERE tabname  = @iv_tabname
    AND as4local = 'A'
    AND as4vers  = '0000'
  ORDER BY position
  INTO TABLE @rt_fields.
```

Prompt augmentation rule:

- inject confirmed field names into the prompt
- explicitly instruct the model to use only confirmed DDIC fields
- forbid invented field names

Example guidance:

```text
Confirmed DDIC fields for table MARA are: MATNR, ERSDA, ERNAM, ...
Never invent field names that are not confirmed in DDIC.
```

### 2. "Show All Fields" Request Handling

If the user explicitly requests all fields, for example:

- 전부
- 전체
- 모든 필드
- all fields

then ZAICODING should allow the model to use the **real DDIC full table type** and `SELECT *` for that specific request.

Rule:

- when all fields are requested, prefer the real DDIC structure
- do not enumerate all fields manually
- do not build a fragile local `TYPES` list for full-table output

Recommended instruction:

```text
If the user explicitly requests to show all fields of one DDIC table, you may use SELECT * into the full DDIC table type of that table.
In that case, do not enumerate fields manually.
When all fields are requested, prefer the real DDIC structure instead of a local TYPES definition.
```

This is especially useful for requests such as:

- "HAWA 자재마스터 전부 표시"
- "MARA 전체 필드 보여줘"

### 3. Main Table Detection Logic

ZAICODING can map common user phrases to representative SAP tables before prompt generation.

Examples:

- 자재 / MARA → `MARA`
- 고객 / KNA1 → `KNA1`
- 벤더 / 공급업체 / LFA1 → `LFA1`
- 판매오더 / VBAK → `VBAK`
- VBAP → `VBAP`
- MSEG → `MSEG`
- MARD → `MARD`

This helps drive DDIC metadata lookup and improves prompt precision.

### 4. Existing Auto-Fix Rules Retained

The current stabilization rules remain active:

- duplicate `REPORT` removal
- invalid host literal fix  
  `@'FERT'` → `'FERT'`
- elementary DDIC initialization fix  
  `VALUE mara-mtart( 'FERT' )` → `TYPE mara-mtart VALUE 'FERT'`
- SALV misuse fix  
  `NEW cl_salv_table( )` / `CREATE OBJECT lo_alv` → `CL_SALV_TABLE=>FACTORY`
- damaged keyword repair  
  `ATA:` → `DATA:`  
  `TART-OF-SELECTION.` → `START-OF-SELECTION.`

### 5. Practical Prompt Rules Added

Additional rules recommended for ZAICODING:

- Never invent DDIC fields.
- Use only confirmed DDIC fields when metadata is provided.
- If all fields are requested, prefer the true DDIC table type and `SELECT *`.
- If only partial fields are requested, use explicit field lists and local `TYPES`.
- Use English literals for generated message text and ALV headers for higher encoding stability.

### 6. Practical Outcome

These improvements specifically target failures such as:

- hallucinated DDIC fields like invalid MARA components
- over-enumerated field lists for full-table display requests
- unstable code generation for "show everything" style prompts

With these changes, ZAICODING becomes more reliable for both:

- full-table browse style reports
- partial-field ALV report generation

### 7. Recommended Next Step

For maximum stability, the next upgrade should be:

- structured Responses API parsing via `/UI2/CL_JSON`
- optional double-pass validation  
  Generator → Validator / Repair
