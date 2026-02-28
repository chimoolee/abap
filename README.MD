# ABAP AI Code Generation Framework (SAP S/4HANA 2022 / ABAP 7.56)

Maintained by: Chimoo Lee – SAP S/4HANA Logistics & ABAP Consultant  
Target: SAP S/4HANA 2022, ABAP 7.56  
API: OpenAI Responses API (/v1/responses)

---

## 1. Overview

This repository defines the **official AI-driven ABAP generation standard** for SAP S/4HANA 2022 systems.

It provides:
- OpenAI API integration from ABAP (SM59 HTTP destination)
- JSON response parsing and **ABAP_START ~ ABAP_END** extraction
- **Enterprise double-pass** validation (Generator → Validator/Repair)
- Automatic syntax checking
- TEST / CREATE execution modes
- Clean ABAP 7.56 coding standards
- HTTP/Proxy diagnostics

(Existing baseline summary derived from current README content.) :contentReference[oaicite:1]{index=1}

---

## 2. System Architecture

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
TEST: Display only / CREATE: INSERT REPORT (+ GENERATE REPORT optional)

---

## 3. Prerequisites

### 3.1 SM59 Destination (Required)
Create an HTTP destination (example: `ZOPENAI`)
- Host: `api.openai.com`
- Service: `443`
- Path Prefix: `/v1/responses`
- SSL: Enabled (STRUST must be OK)

### 3.2 SSL / Certificates (STRUST)
Ensure SSL trust chain is installed properly for outbound HTTPS.

### 3.3 Proxy/Firewall
Corporate environments may require proxy authentication.
- Capture and display diagnostic headers for troubleshooting:
  - HTTP status code
  - `WWW-Authenticate`
  - `Proxy-Authenticate`
  - response body prefix

---

## 4. Output Contract (MUST)

AI output must be returned **only** within markers:

**No markdown, no code fences, no extra commentary outside markers.**

---

## 5. Coding Standards (Clean ABAP / ABAP 7.56)

### 5.1 Naming
- Reports: `ZAI_*`
- Classes: `ZCL_*`
- Internal table: `lt_*`
- Work area/structure: `ls_*`
- Variables: `lv_*`
- Constants: `gc_*`

### 5.2 Open SQL
- Never use `SELECT *`
- Use explicit field lists and `@` host variables
- Avoid CASE/arithmetic in SQL; calculate in ABAP
- Use only fields that exist; do not guess
- If selecting from MAKT: filter `SPRAS = @sy-langu`

### 5.3 Error handling
- Wrap risky parts with `TRY...CATCH cx_root`
- Provide meaningful messages

### 5.4 ALV
Prefer `CL_SALV_TABLE=>FACTORY` (avoid obsolete ALV frameworks)

---

## 6. Enterprise Prompt Rules (Single Source of Truth)

This section is the **canonical prompt rule text** used by ABAP `build_system_rules`,
`build_marker_wrapper_rules`, `build_validator_rules`, `build_validator_user_prompt`.

> NOTE: For enterprise stability, the ABAP program reads these rules from an ABAP source
> (include/report) that mirrors this section. See section 7.

### 6.1 Generator Rules (Pass 1)
- You are a strict SAP ABAP 7.56 code generator for S/4HANA 2022.
- Generate COMPLETE runnable REPORT program only.
- Do NOT use markdown, backticks, or code fences.
- Return output EXACTLY between markers ABAP_START and ABAP_END.
- FIRST line must be ABAP_START; LAST line must be ABAP_END.
- Output NOTHING outside markers.
- Inside markers: ABAP code + ABAP comments only.
- Do not output lists/bullets/headings like "IT:" or "Note:".
- Exactly one REPORT statement. No INCLUDE/FUNCTION-POOL/MODULE-POOL.
- Use one local final class lcl_app with class-method run.
- START-OF-SELECTION must call lcl_app=>run.
- Follow Clean ABAP.
- Meaningful names (lt_, ls_, lv_, lo_), avoid unused variables.
- Never SELECT *; explicit fields + @ in Open SQL.
- Avoid CASE/arithmetic in SQL; calculate in ABAP.
- Use only existing fields, do not guess.
- For MAKT: SPRAS=@sy-langu.
- No generic types in RETURNING parameters; avoid TYPE ANY.
- Wrap risky parts in TRY...CATCH cx_root, MESSAGE TYPE E.
- Use CL_SALV_TABLE=>FACTORY, avoid REUSE_ALV_*.
- If unclear: assumptions as ABAP comments inside markers.

### 6.2 Marker Wrapper Rules
- You are a strict ABAP wrapper.
- Return EXACTLY the same content but wrapped with markers.
- First line MUST be ABAP_START; last line MUST be ABAP_END.
- Output NOTHING outside markers.
- Do NOT add explanations; do NOT change the code.
- Do NOT use markdown/backticks.

### 6.3 Validator Rules (Pass 2)
- You are an enterprise ABAP 7.56 validator and fixer for S/4HANA 2022.
- Input may contain non-ABAP text.
- Return ONLY a COMPLETE runnable ABAP REPORT.
- No markdown/backticks/explanations.
- Output MUST be wrapped with ABAP_START/ABAP_END.
- Inside markers: ABAP code + ABAP comments only.
- Remove English prose/analysis.
- Exactly one REPORT. No INCLUDE/FUNCTION-POOL/MODULE-POOL.
- Use local final class lcl_app with run; START-OF-SELECTION calls it.
- Never SELECT *; explicit fields + @.
- Use CL_SALV_TABLE=>FACTORY.
- Prefer minimal changes; ensure compile & runnable.

### 6.4 Validator User Prompt Template
Fix the draft and output ONLY final ABAP between ABAP_START and ABAP_END. Remove any non-ABAP text.

---

## 7. How ABAP Loads These Rules (Enterprise stable)

Recommended approach (no internet dependency):
1) Store section 6 as ABAP text in a dedicated ABAP include/report (single source inside SAP)
2) ABAP `build_system_rules*` reads that ABAP source using `READ REPORT`
3) Extract lines between markers and build final prompt string

(See code patch in the project.)

---

## 8. Troubleshooting

### 8.1 Proxy auth popup / 407
Disable SAP logon popup and print diagnostic headers.

### 8.2 SSL errors
Check STRUST chain and outbound HTTPS policy.

### 8.3 Model returns non-ABAP text
Use validator pass + “REPORT must exist” gate. Do not save garbage programs.

---

## 9. License
Personal Research & Educational Use
