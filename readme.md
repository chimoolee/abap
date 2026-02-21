
# ABAP Master Prompt (for ABAP 7.56 · S/4HANA 2022)
Advanced ABAP Code Generation Rules for Copilot

This document defines unified rules for generating consistent, high‑quality ABAP code in an ABAP 7.56 (S/4HANA 2022) environment.

---

## 1. General Rules

- Default ABAP version: **7.56**
- All generated code must be **complete and executable**
- Use **modern ABAP syntax**:
  - `DATA(...)` inline declarations
  - `VALUE`, `NEW`, `COND`, `SWITCH`, `FILTER`, `REDUCE`
  - Table expressions (`itab[ key ]`)
- **Forbidden syntax**
  - `FORM/ENDFORM`
  - `TABLES`
  - Implicit field-symbols
  - Obsolete function modules
- Follow **Clean ABAP**:
  - Clear naming
  - Small methods
  - No redundant comments
  - Consistent formatting

---

## 2. ABAP 7.56 Syntax Rules

- Constructor operators must always include parentheses
- RETURNING parameters must use **fully typed** structures
- Only class-based exceptions (`CX_ROOT` hierarchy)
- SELECT must use `INTO @DATA(...)`
- LOOP must use `ASSIGNING` or `REFERENCE INTO`

---

## 3. SEGW OData Rules

- Provide **MPC_EXT** and **DPC_EXT**
- Use `/IWBEP/IF_MGW_APPL_SRV_RUNTIME`
- Implement:
  - `GET_ENTITYSET`
  - `GET_ENTITY`
  - `CREATE_ENTITY`
  - `UPDATE_ENTITY`
  - `DELETE_ENTITY`
- Use `copy_data_to_ref` for responses

---

## 4. RAP Rules

- Use CDS View Entity
- Use UUID keys (`sysuuid_x16()`)
- Provide:
  - CDS View Entity
  - Metadata Extension
  - Behavior Definition
  - Behavior Pool Class
- Use:
  - `READ ENTITIES`
  - `MODIFY ENTITIES`
- Include Determinations / Validations / Actions as needed

---

## 5. AMDP Rules

- Implement `IF_AMDP_MARKER_HDB`
- Methods must use:

- SQLScript must be HANA‑compatible
- No `SELECT *`
- RETURN must be a **table type**

---

## 6. ABAP Unit Test Rules

- Test class must include:
  - `FOR TESTING`
  - `RISK LEVEL HARMLESS`
  - `DURATION SHORT`
- Provide:
  - `SETUP`
  - `TEARDOWN` (optional)
  - Multiple `test_<scenario>` methods
- Only **one assertion per test method**
- Use test doubles or local helper classes for mocking

---

## 7. Output Format Rules

All responses must follow:

### 1) Short Explanation
- Purpose of the code  
- Key design decisions  
- Assumptions  

### 2) Full Code
- Complete, executable code  
- No missing parts  

---