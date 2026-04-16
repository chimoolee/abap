[README.md](https://github.com/user-attachments/files/26774116/README.md)
# ABAP AI Code Generation Framework (ZAICODING Integrated Edition)

## Overview
This repository defines a **production-ready AI-driven ABAP code generation framework** for SAP S/4HANA 2022 (ABAP 7.56).

It combines:
- Enterprise ABAP AI architecture
- ZAICODING practical implementation
- OpenAI Responses API integration
- Automatic correction & stabilization engine
- DDIC-aware prompt augmentation
- FM → Program → TCODE static-analysis prompt guidance
- Practical prompt templates for real-world SAP repository analysis

---

## ⚙️ Key Features
- Natural language → ABAP REPORT
- Model: `gpt-5.4`
- Temperature configurable (default `0.2`)
- Auto program naming: `ZAI_YYMMDD_HHMM`
- `INSERT REPORT` + `GENERATE REPORT`
- Auto correction engine (critical)
- DDIC metadata injection
- Main table detection from user prompt
- SE38 auto launch on success

---

## Architecture
User Prompt  
↓  
ZAI Generator  
↓  
OpenAI API  
↓  
ABAP Extraction (`ABAP_START` ~ `ABAP_END`)  
↓  
Auto Fix Engine  
↓  
Program Build  
↓  
Activation / SE38

---

## Enterprise Architecture
`ZAI_MAIN (REPORT)`  
├─ `ZCL_ZAI_PROMPT_ANALYZER`  
├─ `ZCL_ZAI_METADATA_READER`  
├─ `ZCL_ZAI_OPENAI_CLIENT`  
├─ `ZCL_ZAI_CODE_EXTRACTOR`  
├─ `ZCL_ZAI_SYNTAX_CHECKER`  
├─ `ZCL_ZAI_REPAIR_ENGINE`  
└─ `ZCL_ZAI_PROGRAM_BUILDER`

---

## Core Rules (VERY IMPORTANT)

### 1. REPORT Rule
- Only **ONE** `REPORT` statement allowed
- Duplicate `REPORT` automatically removed

### 2. Open SQL Rule
- ❌ `SELECT *` 금지
- ✅ Explicit field only
- ✅ `@` only for variables

❌ Wrong:
```abap
WHERE mtart = @'FERT'
```

✅ Correct:
```abap
WHERE mtart = 'FERT'
```

### 3. Elementary Type Rule (CRITICAL)
❌ Wrong:
```abap
DATA(lv_mtart) = VALUE mara-mtart( 'FERT' ).
```

✅ Correct:
```abap
DATA lv_mtart TYPE mara-mtart VALUE 'FERT'.
```

### 4. SALV Rule
❌ Wrong:
```abap
NEW cl_salv_table( )
CREATE OBJECT lo_alv.
```

✅ Correct:
```abap
DATA lo_alv TYPE REF TO cl_salv_table.
cl_salv_table=>factory(
  IMPORTING r_salv_table = lo_alv
  CHANGING  t_table      = lt_data ).
```

### 5. Partial SELECT Rule
When selecting only a subset of fields:
- define a local `TYPES` structure matching the selected fields exactly
- do **not** select partial fields into a full DDIC table type such as `KNA1`

---

## Auto Correction Engine
Automatically fixes:

| Issue | Fix |
|---|---|
| `@'FERT'` | `'FERT'` |
| `VALUE mara-mtart(...)` | `TYPE ... VALUE ...` |
| Duplicate `REPORT` | remove |
| Damaged keywords | repair |
| SALV misuse | `CL_SALV_TABLE=>FACTORY` |
| `DNUM` hallucination | remove / filter |
| `TFDIR` field misuse | normalize toward confirmed field usage |

---

## Execution Flow
1. Prompt 입력
2. OpenAI 호출
3. ABAP 추출
4. 자동 보정
5. 프로그램 생성

### ✔ 성공
→ SE38 자동 호출

### ❌ 실패
→ 오류 + 저장된 소스 표시

---

## Example Prompt
`플랜트 1000 기준 자재 조회 ALV 만들어줘`

---

## ⚠️ Important Notes
- API Key 교체 필수
- 생성 코드 반드시 검증
- `ABAP_START` / `ABAP_END` 는 **SE38 소스에 넣으면 안 됨**
- `ABAP_START` / `ABAP_END` 는 **응답 추출용 마커일 뿐**, 실제 프로그램 소스에 포함하면 안 됨
- 위 내용은 Troubleshooting 시에도 반복해서 확인할 것

---

## Enterprise Rules
- Exactly one `REPORT`
- No markdown
- No explanation text
- Clean ABAP only
- Explicit fields only
- `CL_SALV_TABLE=>FACTORY` only
- Invented DDIC fields forbidden
- Repository hallucination forbidden

---

## Advanced Rules (Stability)
- `CS` / `CP` predicate → safer alternatives when needed
- `SELECT-OPTIONS` → DDIC 변수 사용
- Z/Y namespace only scan when custom-only scope is required
- recursion depth limit = 8 for static custom-code scanners
- hotspot ALV navigation 권장
- `CONCATENATE` numeric → 문자 변환 필수

---

## Technical Setup

### SM59
- Host: `api.openai.com`
- Path: `/v1/responses`
- SSL 필수

### STRUST
- 인증서 체인 필요

---

## ZAICODING Improvement Update
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

then ZAICODING may allow the model to use the **real DDIC full table type** and `SELECT *` for that specific request.

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
- 자재 / `MARA` → `MARA`
- 고객 / `KNA1` → `KNA1`
- 벤더 / 공급업체 / `LFA1` → `LFA1`
- 판매오더 / `VBAK` → `VBAK`
- `VBAP` → `VBAP`
- `MSEG` → `MSEG`
- `MARD` → `MARD`
- 함수 모듈 / 펑션 모듈 / `FUNCTION MODULE` / `TFDIR` → `TFDIR`
- 트랜잭션 / `TCODE` / `TSTC` → `TSTC`

This helps drive DDIC metadata lookup and improves prompt precision.

### 4. Existing Auto-Fix Rules Retained
The current stabilization rules remain active:
- duplicate `REPORT` removal
- invalid host literal fix `@'FERT'` → `'FERT'`
- elementary DDIC initialization fix `VALUE mara-mtart( 'FERT' )` → `TYPE mara-mtart VALUE 'FERT'`
- SALV misuse fix `NEW cl_salv_table( )` / `CREATE OBJECT lo_alv` → `CL_SALV_TABLE=>FACTORY`
- damaged keyword repair such as `ATA:` → `DATA:` and `TART-OF-SELECTION.` → `START-OF-SELECTION.`

### 5. Repository Safety Rules Added
Additional rules were added to reduce repository-analysis hallucinations:
- Never invent DDIC fields.
- Never invent repository fields.
- Never use `DNUM` unless it is explicitly confirmed in the actual DDIC table.
- Never use `TFDIR` as if it were a field name.
- Do not confuse DDIC table names with internal table names.
- If a requested field is not confirmed in DDIC, redesign the logic instead of inventing it.
- When building local `TYPES`, explicitly declare every referenced component before use.

### 6. TFDIR Misuse Protection
Because `TFDIR` is a DDIC table name and not a field name, ZAICODING now applies stronger prompt guidance and normalization rules.

Recommended repository-safe usage:
- `TFDIR-FUNCNAME`
- `TFDIR-PNAME`

Forbidden patterns:
- using `TFDIR` as a structure component without explicit local declaration
- using `WITH KEY tfdir = ...`
- referencing `-tfdir` as if it were a real component of a line structure

### 7. FM → Program → TCODE Static Analysis Guidance
For requests such as:
- "내가 지정하는 펑션 모듈이 최종적으로 연결되어 있는 TCODE 찾아내기"
- "Function Module을 호출하는 TCODE 찾아줘"

ZAICODING should prefer the following static-analysis strategy:
1. Start from `TFDIR` using confirmed fields such as `FUNCNAME` and `PNAME`
2. Read transaction start programs from `TSTC-PGMNA`
3. Expand includes recursively with `D010INC`
4. Read source via `READ REPORT`
5. Search for static `CALL FUNCTION '...'` statements only
6. Treat dynamic calls as excluded or explicitly document them as out of scope

### 8. Prompt Hardening Rules
Additional practical prompt rules recommended for ZAICODING:
- Use only confirmed DDIC fields when metadata is provided.
- If all fields are requested, prefer the true DDIC table type and `SELECT *`.
- If only partial fields are requested, use explicit field lists and local `TYPES`.
- Use English literals for generated message text and ALV headers for higher encoding stability.
- For repository analysis, prefer `TSTC`, `TSTCT`, `TRDIR`, `TFDIR`, `D010INC`, `ENLFDIR`, `D020S`, and `D021S` only when actual field names are confirmed.

### 9. Fixed Base Prompt Strategy
Instead of relying on ad-hoc user wording only, ZAICODING can prepend a **fixed base prompt** before the user request.

Recommended design:
- keep a hardcoded base instruction inside ZAICODING
- always prepend it before the user prompt
- append user prompt at the end
- conditionally strengthen the prompt when keywords such as `FUNCTION MODULE`, `TCODE`, `펑션 모듈`, `함수 모듈`, or `트랜잭션` appear

This improves consistency and reduces unstable generations.

### 10. Multi-Line Prompt Input Recommendation
For practical use, a single short one-line prompt is often not enough for complex static-analysis tasks. ZAICODING should support **multi-line prompt entry**, for example 10 lines.

Recommended practical design:
- prompt line 1 ~ prompt line 10 on screen 0100
- merge non-empty lines into one final prompt separated by newline
- preserve the final merged text for prompt logging in the generated source header

This makes it easier to describe:
- scope
- exclusions
- desired output columns
- repository tables to prefer
- special safety rules

### 11. Practical Prompt Templates (Examples)
Recommended user prompt examples for FM → TCODE analysis:

```text
내가 입력하는 펑션 모듈을 정적으로 호출하는 TCODE를 찾아줘. select-options로 함수모듈명을 여러 개 입력할 수 있게 해주고, 결과는 TCODE, TCODE 설명, 시작프로그램, 발견된 소스 프로그램 또는 INCLUDE, 라인번호, 소스라인을 ALV로 보여줘.
```

```text
Function Module 이름을 select-options로 입력받아서, 그 Function Module을 CALL FUNCTION으로 직접 호출하는 TCODE를 찾아주는 ABAP 리포트를 만들어줘. TSTC, TSTCT, TFDIR, D010INC, READ REPORT 기준으로 구현해줘.
```

```text
Function Module -> Program -> TCODE 연결을 정적으로 분석하는 ABAP 리포트를 만들어줘. 시작은 TFDIR에서 FUNCNAME, PNAME을 읽고, TCODE는 TSTC-PGMNA를 기준으로 찾고, include는 D010INC로 재귀 탐색해줘.
```

### 12. Practical Outcome
These improvements specifically target failures such as:
- hallucinated DDIC fields like invalid MARA components
- over-enumerated field lists for full-table display requests
- `DNUM` hallucinations
- `TFDIR` field misuse
- unstable code generation for repository-analysis prompts

With these changes, ZAICODING becomes more reliable for both:
- full-table browse style reports
- partial-field ALV report generation
- FM → Program → TCODE static-analysis reports

### 13. Recommended Next Step
For maximum stability, the next upgrade should be:
- structured Responses API parsing via `/UI2/CL_JSON`
- optional double-pass validation (Generator → Validator / Repair)
- prompt template selection helper on screen 0100
- recent-prompt save / reload feature

---

## Troubleshooting
- If generated code contains `ABAP_START` or `ABAP_END`, remove them before pasting into SE38.
- If `DNUM` appears in a generated local structure or query without confirmed DDIC support, treat it as hallucination and reject the source.
- If `TFDIR` is used as a field name, treat it as invalid and redesign around confirmed fields like `FUNCNAME` and `PNAME`.
- If the user asks for all fields, prefer the real DDIC type instead of a huge hand-written local structure.

---

## Maintainer
Chimoo Lee
