ABAP AI Code Generation Framework

SAP S/4HANA 2022 / ABAP 7.56

Maintained by: Chimoo Lee – SAP S/4HANA Logistics & ABAP Consultant
Target: SAP S/4HANA 2022 / ABAP 7.56
API: OpenAI Responses API (/v1/responses)

1. Overview

This repository defines the official AI-driven ABAP generation standard for SAP S/4HANA 2022 systems.

It provides:

OpenAI API integration from ABAP (SM59 HTTP destination)

JSON response parsing and ABAP_START ~ ABAP_END extraction

Enterprise double-pass validation (Generator → Validator / Repair)

Automatic syntax checking

TEST / CREATE execution modes

Clean ABAP 7.56 coding standards

HTTP / Proxy diagnostics

Metadata-assisted AI generation

Enterprise class-based architecture

2. System Architecture
User Prompt
     ↓
ABAP Generator Report (ZAI_*)
     ↓
OpenAI Responses API (HTTPS)
     ↓
JSON Response
     ↓
Extract ABAP_START ~ ABAP_END
     ↓
(Option) Validator pass (repair)
     ↓
Syntax Check
     ↓
TEST: Display only
CREATE: INSERT REPORT (+ GENERATE REPORT optional)
2.1 ABAP Service Class Architecture (Enterprise Design)

To ensure maintainability, scalability, and enterprise-grade stability,
the AI generator must be structured using service classes instead of procedural FORM logic.

The generator report (ZAI_*) should act only as an orchestrator, while the main logic is delegated to specialized classes.

Architecture
ZAI_MAIN (REPORT)
   │
   ├─ ZCL_ZAI_PROMPT_ANALYZER
   ├─ ZCL_ZAI_METADATA_READER
   ├─ ZCL_ZAI_OPENAI_CLIENT
   ├─ ZCL_ZAI_CODE_EXTRACTOR
   ├─ ZCL_ZAI_SYNTAX_CHECKER
   ├─ ZCL_ZAI_REPAIR_ENGINE
   └─ ZCL_ZAI_PROGRAM_BUILDER
Responsibilities
Class	Responsibility
ZCL_ZAI_PROMPT_ANALYZER	Converts natural language prompt into structured ABAP task description
ZCL_ZAI_METADATA_READER	Reads SAP metadata (DD02L/DD03L/TADIR/TRDIR) to improve AI accuracy
ZCL_ZAI_OPENAI_CLIENT	Handles OpenAI Responses API communication
ZCL_ZAI_CODE_EXTRACTOR	Extracts ABAP source between ABAP_START and ABAP_END
ZCL_ZAI_SYNTAX_CHECKER	Executes SYNTAX-CHECK on generated code
ZCL_ZAI_REPAIR_ENGINE	Sends syntax errors back to AI for automatic correction
ZCL_ZAI_PROGRAM_BUILDER	Creates final program via INSERT REPORT
2.2 Execution Flow (Enterprise Pipeline)
User Prompt
   │
   ▼
Prompt Analyzer
   │
   ▼
Metadata Reader
   │
   ▼
OpenAI Client
   │
   ▼
Code Extractor
   │
   ▼
Syntax Checker
   │
   ▼
Repair Engine (optional loop)
   │
   ▼
Program Builder
   │
   ▼
TEST / CREATE Mode
2.3 Syntax Repair Loop

To achieve enterprise stability, generated code must pass through an automatic syntax repair loop.

Example flow:

AI Generated Code
      │
      ▼
SYNTAX-CHECK
      │
   OK │ ERROR
      ▼
Repair Engine → OpenAI Validator
      │
      ▼
Re-check Syntax

Recommended configuration:

MAX_REPAIR_ATTEMPTS = 3

If syntax errors remain after the final attempt, the program must not be saved.

2.4 Program Creation

Final ABAP programs should be created using standard SAP mechanisms.

Preferred approach:

INSERT REPORT lv_prog FROM lt_source.

Optional activation:

GENERATE REPORT lv_prog.
2.5 Metadata Injection (Accuracy Booster)

Before generating code, the framework should query SAP dictionary metadata.

Example:

SELECT fieldname
FROM dd03l
WHERE tabname = 'VBAK'.

This information is injected into the AI prompt to prevent:

invalid field references

non-existent tables

incorrect Open SQL usage

Metadata injection significantly improves generation accuracy.

3. Prerequisites
3.1 SM59 Destination (Required)

Create an HTTP destination (example: ZOPENAI)

Host

api.openai.com

Service

443

Path Prefix

/v1/responses

SSL

Enabled

STRUST must contain a valid certificate chain.

3.2 SSL / Certificates (STRUST)

Ensure the SSL trust chain is installed properly for outbound HTTPS communication.

3.3 Proxy / Firewall

Corporate environments may require proxy authentication.

Capture and display diagnostic headers for troubleshooting.

Example diagnostics:

HTTP status code

WWW-Authenticate

Proxy-Authenticate

response body prefix

4. Output Contract (MUST)

AI output must be returned only within markers.

ABAP_START
<ABAP CODE>
ABAP_END

Rules:

No markdown

No code fences

No explanations

No text outside markers

5. Coding Standards (Clean ABAP / ABAP 7.56)
5.1 Naming
Object	Prefix
Reports	ZAI_*
Classes	ZCL_*
Internal tables	lt_*
Structures	ls_*
Variables	lv_*
Constants	gc_*
5.2 Open SQL

Rules:

Never use SELECT *

Use explicit field lists

Use @ host variables

Avoid CASE or arithmetic in SQL

Perform calculations in ABAP

Use only existing fields

Do not guess fields

MAKT rule:

SPRAS = @sy-langu
5.3 Error Handling

All risky logic must be wrapped with:

TRY.
  ...
CATCH cx_root INTO DATA(lx).
  MESSAGE lx->get_text( ) TYPE 'E'.
ENDTRY.
5.4 ALV

Preferred ALV framework:

CL_SALV_TABLE=>FACTORY

Avoid obsolete:

REUSE_ALV_*
6. Enterprise Prompt Rules (Single Source of Truth)

This section defines the canonical prompt rules used by:

build_system_rules

build_marker_wrapper_rules

build_validator_rules

build_validator_user_prompt

These rules ensure consistent AI generation behavior.

6.1 Generator Rules (Pass 1)

You are a strict SAP ABAP 7.56 code generator for S/4HANA 2022.

Generate COMPLETE runnable REPORT program only.

Do NOT use markdown, backticks, or code fences.

Return output EXACTLY between markers ABAP_START and ABAP_END.

FIRST line must be ABAP_START.

LAST line must be ABAP_END.

Output NOTHING outside markers.

Inside markers: ABAP code + ABAP comments only.

Exactly one REPORT statement.

No INCLUDE / FUNCTION-POOL / MODULE-POOL.

Use local final class lcl_app.

START-OF-SELECTION must call lcl_app=>run.

Follow Clean ABAP.

Never SELECT *.

Explicit fields with @ host variables.

Avoid CASE/arithmetic in SQL.

For MAKT use SPRAS = @sy-langu.

6.2 Marker Wrapper Rules

You are a strict ABAP wrapper.

Return EXACTLY the same content wrapped with markers.

Do NOT change the code.

Do NOT add explanations.

Output only between:

ABAP_START
ABAP_END
6.3 Validator Rules (Pass 2)

You are an enterprise ABAP validator for S/4HANA 2022.

Input may contain non-ABAP text.

Return ONLY a COMPLETE runnable ABAP REPORT.

Remove English explanation text.

Use CL_SALV_TABLE=>FACTORY.

Ensure the program compiles.

6.4 Validator User Prompt Template
Fix the draft and output ONLY final ABAP between ABAP_START and ABAP_END.
Remove any non-ABAP text.
7. How ABAP Loads These Rules (Enterprise Stable)

Recommended approach:

Store section 6 inside an ABAP include/report.

Use READ REPORT to load the text.

Extract rules between markers.

Build the final AI prompt dynamically.

This ensures:

No internet dependency

Version control inside SAP

Enterprise stability

8. Troubleshooting
Proxy Authentication (HTTP 407)

Disable SAP popup login and print diagnostic headers.

SSL Errors

Check:

STRUST certificate chain

outbound HTTPS policy

Model Returns Non-ABAP Text

Use the validator pass and enforce the rule:

REPORT must exist

If validation fails:

Do not save the generated program.

ABAP_START / ABAP_END Marker Misuse

ABAP_START and ABAP_END are extraction markers for AI output handling.
They are not valid ABAP statements and must never be pasted directly into SE38 source code.
When creating or activating a program in SE38, copy only the pure ABAP code between the markers.
The actual program source must begin with a valid REPORT statement.
If ABAP_START is pasted into SE38, typical errors include:

The statement "ABAP_START" is invalid.

The REPORT/PROGRAM statement is missing.

---

# Bulk PFCG Role Copy (CSV 기반)

## 개요
SAP S/4HANA 2022 환경에서  
**PFCG Role을 CSV 파일 기반으로 대량 복제**하기 위한 ABAP 리포트 프로그램이다.

- CSV 기반 (엑셀 보안 이슈 없음)
- 시뮬레이션 모드 제공
- SAP 표준 Function Module 사용

---

## 실행 환경
- SAP S/4HANA 2022
- SAP GUI (Frontend 필수)
- ABAP Classic Report

---

## 입력 파일 (CSV) 사양

### 파일 형식
- `.csv`
- UTF-8 인코딩 권장
- 구분자: `,` (콤마)

### 컬럼 정의 (필수)
```text
SOURCE_ROLE,TARGET_ROLE,ROLE_TEXT
