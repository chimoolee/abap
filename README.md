[README.md](https://github.com/user-attachments/files/26628338/README.md)
# ABAP AI Code Generation Framework (ZAICODING Edition)

## 🚀 Overview

This repository defines a production-ready **AI-driven ABAP code
generation framework** for SAP S/4HANA 2022 (ABAP 7.56).

ZAICODING is a practical implementation that: - Converts natural
language → ABAP REPORT - Uses OpenAI Responses API - Applies automatic
syntax correction & stabilization - Generates executable programs
directly in SE38

------------------------------------------------------------------------

## ⚙️ Key Features

-   Natural language → ABAP code
-   Model: gpt-5.4
-   Temperature configurable (default 0.2)
-   Auto program naming: `ZAI_YYMMDD_HHMM`
-   Auto program creation (INSERT / GENERATE REPORT)
-   Auto correction engine
-   SE38 auto launch on success

------------------------------------------------------------------------

## 🧠 Architecture

Prompt → OpenAI → ABAP Extraction → Auto Fix → Generate → Activate

------------------------------------------------------------------------

## 📌 Core Rules (VERY IMPORTANT)

### 1. REPORT Rule

-   Only ONE REPORT statement allowed
-   Duplicates are auto-removed

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

or

``` abap
DATA(lv_mtart) = CONV mara-mtart( 'FERT' ).
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

ZAICODING automatically fixes:

  Issue              Auto Fix
  ------------------ -------------------
  @'FERT'            → 'FERT'
  VALUE mara-mtart   → TYPE + VALUE
  Duplicate REPORT   → keep first
  Broken keywords    → repaired
  SALV misuse        → factory pattern

------------------------------------------------------------------------

## ▶️ Execution Flow

1.  Enter prompt
2.  Call OpenAI
3.  Extract ABAP
4.  Auto fix
5.  Generate program

### ✔ Success

→ SE38 opens automatically with program name

### ❌ Failure

→ Error + source displayed

------------------------------------------------------------------------

## 🧪 Example

Prompt:

    플랜트 1000 기준 자재 조회 ALV 만들어줘

Result: → Fully runnable ABAP REPORT

------------------------------------------------------------------------

## ⚠️ Important Notes

-   Replace API key before use
-   Always validate generated code
-   ABAP_START / ABAP_END must NOT be pasted into SE38

------------------------------------------------------------------------

## 🧩 Next Step (Recommended)

Upgrade to:

👉 JSON parsing via /UI2/CL_JSON\
👉 Double-pass validation (Generator → Validator)

------------------------------------------------------------------------

## 👨‍💻 Maintainer

Chimoo Lee\
SAP S/4HANA Logistics / ABAP Consultant
