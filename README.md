# ABAP AI Code Generation Framework
## ZAICODING Integrated Edition for SAP S/4HANA 2022 ABAP 7.56

---

## 1. Purpose

This README defines the operating standard for **ZAICODING**, an AI-assisted ABAP code generation framework.

ZAICODING converts natural language requests into runnable ABAP REPORT programs for SAP S/4HANA 2022.

The main goal is not only to generate ABAP source code, but also to:

- reduce hallucinated DDIC fields
- enforce ABAP 7.56 compatible syntax
- follow Clean ABAP style
- generate complete runnable REPORT programs
- automatically repair common AI-generated ABAP errors
- validate generated programs with `GENERATE REPORT`
- improve practical stability for SAP repository analysis tasks

---

## 2. Target Environment

| Item | Standard |
|---|---|
| SAP version | SAP S/4HANA 2022 |
| ABAP version | ABAP 7.56 |
| Main program | `ZAICODING` |
| Generated program name | `ZAI_YYMMDD_HHMM` |
| AI API | OpenAI Responses API |
| Recommended model | `gpt-5.4` or latest stable GPT model |
| Default temperature | `0.2` |
| Output type | Full executable ABAP REPORT |
| ALV standard | `CL_SALV_TABLE=>FACTORY` |

---

## 3. High-Level Flow

```text
User Prompt
  ↓
Fixed Base Prompt Injection
  ↓
Prompt Analyzer
  ↓
Main Table Detection
  ↓
DDIC Metadata Injection
  ↓
OpenAI Responses API Call
  ↓
ABAP Code Extraction
  ↓
Auto-Fix / Repair Engine
  ↓
INSERT REPORT
  ↓
GENERATE REPORT
  ↓
Success: show generated source or open SE38
Failure: show error and saved source
```

---

## 4. Recommended ZAICODING Components

```text
ZAICODING / ZAI_MAIN
 ├─ Prompt Analyzer
 ├─ DDIC Metadata Reader
 ├─ OpenAI Client
 ├─ ABAP Code Extractor
 ├─ Auto-Fix Engine
 ├─ Syntax Checker
 ├─ Program Builder
 ├─ Prompt History Manager
 └─ Result Viewer / Download Handler
```

Recommended class-style architecture:

```text
ZCL_ZAI_PROMPT_ANALYZER
ZCL_ZAI_METADATA_READER
ZCL_ZAI_OPENAI_CLIENT
ZCL_ZAI_CODE_EXTRACTOR
ZCL_ZAI_REPAIR_ENGINE
ZCL_ZAI_SYNTAX_CHECKER
ZCL_ZAI_PROGRAM_BUILDER
ZCL_ZAI_PROMPT_HISTORY
```

---

## 5. Critical ABAP Generation Rules

### 5.1 REPORT Rule

Generated source must contain exactly one program declaration.

Allowed:

```abap
REPORT zmy_report.
```

Forbidden:

```abap
REPORT zmy_report.
REPORT zmy_report2.
```

Auto-fix rule:

- keep only the first valid `REPORT` statement
- remove duplicate `REPORT`, `PROGRAM`, or `FUNCTION-POOL` statements

---

### 5.2 Full Runnable REPORT Rule

The AI must always return a complete runnable ABAP REPORT.

Forbidden outputs:

- code fragments only
- method body only
- class only without executable entry point
- markdown explanation
- JSON response
- pseudo code

Required:

```abap
REPORT z....

START-OF-SELECTION.
  ...
```

---

### 5.3 Open SQL Rule

Default rule:

- do not use `SELECT *`
- use explicit field lists
- use `@` only for ABAP variables
- do not use `@` before SQL literals

Wrong:

```abap
WHERE mtart = @'FERT'
```

Correct:

```abap
WHERE mtart = 'FERT'
```

Correct host variable:

```abap
WHERE mtart = @lv_mtart
```

---

### 5.4 Exception: All Fields Request

If the user explicitly asks for all fields, such as:

```text
전체 필드
전부 보여줘
모든 필드
all fields
```

then `SELECT *` is allowed only for that specific request.

Recommended rule:

```abap
DATA lt_mara TYPE TABLE OF mara.

SELECT *
  FROM mara
  INTO TABLE @lt_mara
  UP TO 100 ROWS.
```

When all fields are requested:

- prefer the real DDIC table type
- do not manually enumerate hundreds of fields
- do not create a fragile local `TYPES` structure

---

### 5.5 Partial Field SELECT Rule

If only some fields are selected, create a local structure that exactly matches the selected fields.

Correct:

```abap
TYPES:
  BEGIN OF ty_mara,
    matnr TYPE mara-matnr,
    mtart TYPE mara-mtart,
    matkl TYPE mara-matkl,
  END OF ty_mara.

DATA lt_mara TYPE TABLE OF ty_mara.

SELECT matnr,
       mtart,
       matkl
  FROM mara
  INTO TABLE @lt_mara
  UP TO 100 ROWS.
```

Forbidden:

```abap
DATA lt_mara TYPE TABLE OF mara.

SELECT matnr,
       mtart
  FROM mara
  INTO TABLE @lt_mara.
```

---

### 5.6 Elementary DDIC Type Initialization Rule

Wrong:

```abap
DATA(lv_mtart) = VALUE mara-mtart( 'FERT' ).
```

Correct:

```abap
DATA lv_mtart TYPE mara-mtart VALUE 'FERT'.
```

Auto-fix should detect and repair invalid elementary `VALUE ddic-type(...)` patterns.

---

### 5.7 SALV Rule

Only use `CL_SALV_TABLE=>FACTORY` for ALV output.

Wrong:

```abap
CREATE OBJECT lo_alv.
lo_alv = NEW cl_salv_table( ).
```

Correct:

```abap
DATA lo_alv TYPE REF TO cl_salv_table.

cl_salv_table=>factory(
  IMPORTING
    r_salv_table = lo_alv
  CHANGING
    t_table      = lt_data ).

lo_alv->display( ).
```

Forbidden:

- `REUSE_ALV_GRID_DISPLAY`
- direct `NEW cl_salv_table( )`
- `CREATE OBJECT lo_alv`

---

## 6. DDIC Metadata Injection

ZAICODING should detect the main SAP table from the user prompt and read real DDIC fields before calling OpenAI.

Recommended DDIC read:

```abap
SELECT fieldname
  FROM dd03l
 WHERE tabname  = @iv_tabname
   AND as4local = 'A'
   AND as4vers  = '0000'
 ORDER BY position
  INTO TABLE @rt_fields.
```

Prompt augmentation example:

```text
Confirmed DDIC fields for MARA are:
MATNR, ERSDA, ERNAM, LAEDA, AENAM, MTART, MATKL, MEINS, ...

Use only these confirmed fields.
Never invent DDIC fields.
If a required field is not confirmed, redesign the logic instead of inventing a field.
```

Purpose:

- prevent invalid components
- reduce hallucinated fields
- improve generation stability
- support field-safe Open SQL generation

---

## 7. Main Table Detection Rules

ZAICODING should map common user phrases to representative SAP tables.

| User keyword | Main table |
|---|---|
| 자재, material, MARA | `MARA` |
| 자재내역, material text, MAKT | `MAKT` |
| 고객, customer, KNA1 | `KNA1` |
| 벤더, 공급업체, vendor, LFA1 | `LFA1` |
| 판매오더, sales order, VBAK | `VBAK` |
| 판매오더 품목, sales item, VBAP | `VBAP` |
| 납품, delivery, LIKP | `LIKP` |
| 납품품목, LIPS | `LIPS` |
| 구매오더, purchase order, EKKO | `EKKO` |
| 구매오더 품목, EKPO | `EKPO` |
| 재고, storage location stock, MARD | `MARD` |
| 자재문서, material document, MSEG | `MSEG` |
| 함수 모듈, 펑션 모듈, function module | `TFDIR` |
| 트랜잭션, TCODE | `TSTC` |

---

## 8. Repository Analysis Safety Rules

For repository analysis programs, the AI must not invent repository fields.

Allowed repository tables should be used only with confirmed fields.

Recommended tables:

| Purpose | Table |
|---|---|
| Transaction start program | `TSTC` |
| Transaction text | `TSTCT` |
| Program attributes | `TRDIR` |
| Function module directory | `TFDIR` |
| Function module include relationship | `ENLFDIR` |
| Include hierarchy | `D010INC` |
| Dynpro header | `D020S` |
| Dynpro field list | `D021S` |

---

## 9. TFDIR Misuse Protection

`TFDIR` is a DDIC table name, not a field name.

Correct fields:

```text
TFDIR-FUNCNAME
TFDIR-PNAME
```

Forbidden patterns:

```abap
WITH KEY tfdir = ...
ls_data-tfdir
WHERE tfdir = ...
```

If a generated source uses `TFDIR` as a field name, reject or repair the source.

---

## 10. DNUM Hallucination Protection

`DNUM` must never be used unless confirmed in the actual DDIC table.

If generated code contains `DNUM` without confirmed DDIC support:

- treat it as hallucination
- reject the generated source
- regenerate or redesign the logic

---

## 11. FM → Program → TCODE Static Analysis Strategy

For prompts such as:

```text
Function Module을 호출하는 TCODE 찾아줘
내가 입력한 펑션 모듈이 연결된 TCODE 찾아줘
```

Recommended strategy:

```text
1. Select function module from TFDIR-FUNCNAME
2. Read function group main/include program from TFDIR-PNAME or related repository info
3. Read TCODE start programs from TSTC-PGMNA
4. Expand includes recursively using D010INC
5. Read source with READ REPORT
6. Search static CALL FUNCTION '...' lines
7. Display TCODE, text, start program, include, line number, source line in ALV
```

Scope rule:

- static `CALL FUNCTION 'FM_NAME'` only
- dynamic function calls are out of scope unless explicitly requested

Recommended recursion depth:

```text
max depth = 8
```

---

## 12. Fixed Base Prompt Strategy

ZAICODING should not rely only on the user prompt.

Always prepend a fixed base prompt before the user request.

Recommended structure:

```text
[ZAICODING Fixed Base Prompt]
[DDIC Metadata, if detected]
[Special Task Rules, if repository analysis]
[User Prompt]
```

Base prompt must include:

```text
You are an expert ABAP developer for SAP S/4HANA 2022 ABAP 7.56.
Generate only one complete runnable ABAP REPORT.
Do not output markdown.
Do not output explanation.
Use Clean ABAP style.
Use explicit Open SQL fields unless the user explicitly requests all fields.
Use only confirmed DDIC fields when metadata is provided.
Never invent DDIC or repository fields.
Use CL_SALV_TABLE=>FACTORY for ALV.
Return only ABAP code between ABAP_START and ABAP_END.
Do not include ABAP_START or ABAP_END inside the final SE38 source.
```

---

## 13. ABAP Extraction Rule

OpenAI should return ABAP between markers:

```text
ABAP_START
REPORT z...
...
ABAP_END
```

Extractor rule:

- extract only content between `ABAP_START` and `ABAP_END`
- remove the markers before `INSERT REPORT`
- if markers are missing, try to find the first `REPORT` statement and extract ABAP source from there
- remove markdown fences such as ```abap
- remove explanation text before and after ABAP source

Important:

```text
ABAP_START and ABAP_END are response extraction markers only.
They must not be inserted into the generated SE38 source.
```

---

## 14. Auto-Fix Engine Rules

The repair engine should automatically fix known unstable patterns.

| Issue | Repair |
|---|---|
| duplicate `REPORT` | keep only first one |
| `@'FERT'` | `'FERT'` |
| `VALUE mara-mtart( 'FERT' )` | `DATA lv_mtart TYPE mara-mtart VALUE 'FERT'` |
| `CREATE OBJECT lo_alv` | replace with SALV factory pattern where possible |
| `NEW cl_salv_table( )` | replace with SALV factory pattern where possible |
| `ATA:` | `DATA:` |
| `TART-OF-SELECTION.` | `START-OF-SELECTION.` |
| `DNUM` hallucination | reject or remove if safe |
| `TFDIR` as field name | reject or redesign |
| markdown fences | remove |
| `ABAP_START` / `ABAP_END` in final source | remove |

---

## 15. Syntax Check and Activation Rule

Recommended validation sequence:

```text
1. Run local source cleanup
2. INSERT REPORT
3. GENERATE REPORT
4. If success: display source or open SE38
5. If failure: show compile error and generated source
6. Optional: send error back to AI repair prompt
```

Final judgment:

```text
GENERATE REPORT is the final activation validation.
```

---

## 16. Recommended Success Behavior

If generated code compiles successfully, ZAICODING may support two modes.

### Mode A: SE38 Auto Launch

```text
Compile success → open SE38 with generated program
```

### Mode B: Source Viewer + Download

```text
Compile success → show generated source on screen
               → provide download button
               → default file name = generated program name
```

Recommended for current ZAICODING direction:

```text
Use Mode B as the default.
Do not jump to SE38 automatically after success.
Show the generated ABAP source and provide download.
```

---

## 17. Prompt Input Recommendation

For complex generation, one-line prompt input is not enough.

Recommended screen design:

```text
Screen 0100
Custom Control: CC_PROMPT
CL_GUI_TEXTEDIT for long prompt entry
```

Alternative simple design:

```text
Prompt line 1
Prompt line 2
...
Prompt line 10
```

Merge rule:

```text
Merge non-empty prompt lines with newline.
Use merged prompt as the final user request.
Save merged prompt in generated source header as comment.
```

---

## 18. Prompt History Recommendation

ZAICODING should save successful prompts.

Recommended fields:

```text
timestamp
program name
user prompt
model
status
compile message
source preview
```

Recommended functions:

- save successful prompt
- show recent prompt list
- reload selected prompt
- reuse prompt for regeneration
- optionally show failed prompts for learning

---

## 19. Generated Source Header Rule

Generated ABAP should include the original user prompt as a comment at the top.

Example:

```abap
REPORT zai_260503_1201.

*---------------------------------------------------------------------*
* Generated by ZAICODING
* User Prompt:
* 고객마스터 10개를 ALV로 보여줘
*---------------------------------------------------------------------*
```

Do not put API keys or secrets in generated source comments.

---

## 20. OpenAI Responses API Setup

### SM59

Recommended destination:

```text
Destination name: ZOPENAI
Host: api.openai.com
Path prefix: /v1/responses
Protocol: HTTPS
```

### STRUST

Required:

```text
Import and trust the required certificate chain for api.openai.com.
```

### HTTP Header

Required headers:

```text
Authorization: Bearer <API_KEY>
Content-Type: application/json; charset=utf-8
```

### Encoding

Recommended:

- send JSON as UTF-8
- avoid BOM
- inspect HTTP status and response body on failure

---

## 21. JSON Parsing Recommendation

Recommended next upgrade:

```text
Use /UI2/CL_JSON for structured parsing of Responses API JSON.
```

Avoid fragile parsing when possible.

Fallback extraction may still be kept for emergency cases.

---

## 22. Recommended Repair Prompt

When `GENERATE REPORT` fails, send a repair request to the model.

Recommended repair prompt structure:

```text
The following ABAP source failed to compile in SAP S/4HANA 2022 ABAP 7.56.

Compile error:
<error text>

Rules:
- Return one complete runnable ABAP REPORT only.
- Do not use markdown.
- Do not explain.
- Keep exactly one REPORT statement.
- Use only confirmed DDIC fields.
- Use CL_SALV_TABLE=>FACTORY for ALV.
- Do not include ABAP_START or ABAP_END in the final SE38 source.

Source:
<generated source>
```

---

## 23. Practical Prompt Templates

### 23.1 Customer Master

```text
고객마스터 10개를 조회해서 KUNNR, NAME1, LAND1을 ALV로 보여줘.
ABAP 7.56 기준으로 만들고 CL_SALV_TABLE=>FACTORY를 사용해줘.
```

### 23.2 Material Master by Material Type

```text
자재유형 HAWA인 자재 10개를 MATNR, MTART, MATKL, MEINS 기준으로 ALV 표시해줘.
```

### 23.3 All Material Fields

```text
MARA 전체 필드를 100건만 ALV로 보여줘.
전체 필드 요청이므로 실제 DDIC 타입을 사용해줘.
```

### 23.4 Purchase Order Amount Ranking

```text
구매조직 1000 기준 구매오더를 금액 순으로 ALV 표시해줘.
구매오더 번호, 벤더, 회사코드, 구매조직, 통화, 금액을 보여줘.
```

### 23.5 Function Module to TCODE

```text
Function Module 이름을 select-options로 입력받아서,
그 Function Module을 CALL FUNCTION으로 직접 호출하는 TCODE를 찾아주는 ABAP 리포트를 만들어줘.
TSTC, TSTCT, TFDIR, D010INC, READ REPORT 기준으로 구현해줘.
결과는 TCODE, TCODE 설명, 시작프로그램, 발견된 INCLUDE, 라인번호, 소스라인을 ALV로 보여줘.
동적 호출은 제외해줘.
```

---

## 24. Troubleshooting Checklist

### Duplicate REPORT Error

Symptom:

```text
Each ABAP program can contain only one REPORT, PROGRAM, or FUNCTION-POOL statement.
```

Fix:

```text
Remove duplicate REPORT/PROGRAM/FUNCTION-POOL statements.
```

---

### Invalid Host Literal

Wrong:

```abap
WHERE mtart = @'FERT'
```

Fix:

```abap
WHERE mtart = 'FERT'
```

---

### Invalid DDIC Field

Symptom:

```text
No component exists with the name ...
```

Fix:

```text
Check DD03L.
Use only confirmed DDIC fields.
Do not invent fields.
```

---

### SALV Creation Error

Symptom:

```text
An instance of CL_SALV_TABLE cannot be created outside the class.
```

Fix:

```abap
cl_salv_table=>factory(
  IMPORTING r_salv_table = lo_alv
  CHANGING  t_table      = lt_data ).
```

---

### ABAP_START / ABAP_END Appears in SE38

Fix:

```text
Remove ABAP_START and ABAP_END before INSERT REPORT.
They are extraction markers only.
```

---

### DNUM Appears

Fix:

```text
Treat as hallucination unless confirmed by DDIC.
Reject or regenerate.
```

---

### TFDIR Used as Field

Fix:

```text
Use TFDIR-FUNCNAME and TFDIR-PNAME only when confirmed.
Do not use TFDIR as a component name.
```

---

## 25. Recommended Next Upgrade Priority

1. **Source Viewer + Download Button** after successful compile
2. **Prompt History Save / Reload**
3. **Structured Responses API parsing with `/UI2/CL_JSON`**
4. **Generator → Validator → Repair double-pass flow**
5. **DDIC metadata injection for detected main table**
6. **Repository-analysis prompt templates**
7. **Failure learning log** for repeated compile errors

---

## 26. Final Operating Principle

ZAICODING should follow this principle:

```text
AI generates.
ZAICODING verifies.
ZAICODING repairs.
GENERATE REPORT decides.
```

Generation quality is important, but production stability comes from:

```text
Fixed Base Prompt
+ DDIC Metadata
+ Auto-Fix Engine
+ GENERATE REPORT
+ Repair Loop
```

---

## Maintainer

Chimoo Lee
