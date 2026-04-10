[README.md](https://github.com/user-attachments/files/26628456/README.md)
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
