📘 ABAP Development Standard Guide
ABAP 7.56 · Clean ABAP · Code Generation Rules · /abap-strict Specification
이 문서는 ABAP 개발 시 반드시 따라야 하는 **표준 규칙(Standard)**을 정의한다.
특히 /abap-strict 명령으로 생성되는 모든 코드의 기준이 된다.
문서의 목적은 다음과 같다:
- ABAP 코드 품질의 일관성 유지
- 최신 ABAP 문법(7.56) 기반 개발
- Clean ABAP 스타일 준수
- 자동 코드 생성 시 표준화된 출력 확보
- 협업 시 공통 규칙 제공

1. 기본 원칙
- ABAP 7.56 문법을 기준으로 한다.
- Clean ABAP 스타일을 따른다.
- 생성되는 코드는 반드시 완전 실행 가능해야 한다.
- 불필요한 주석, 불필요한 공백, 불필요한 로직을 포함하지 않는다.
- 모든 코드는 Short explanation + Full code 구조로 제공한다.
- 코드 예시는 항상 클래스 기반 구조를 사용한다.
- SALV는 반드시 FACTORY 방식으로 생성한다.
- SELECT는 명확한 필드 목록을 사용하며 SELECT *는 금지한다.

2. 문법 규칙
2.1 Inline 문법
- Inline DATA 사용 가능:
DATA(x) = ...
- 단, 시스템이 지원하지 않는 경우 전통 선언 방식으로 자동 대체한다.
- Inline FIELD-SYMBOLS, VALUE, NEW, table expressions 적극 사용.
2.2 변수 선언
- 변수는 사용 직전에 선언한다.
- 타입은 명확하게 정의한다.
- 불필요한 글로벌 변수 금지.
2.3 메서드 구조
- 메서드는 단일 책임 원칙(SRP)을 따른다.
- 메서드 이름은 동사 기반으로 명확하게 작성한다.
- 파라미터는 IMPORTING / RETURNING 중심으로 구성한다.

3. 프로그램 구조 규칙
모든 프로그램은 아래 구조를 따른다:
Selection screen
↓
Validation
↓
Execution (select, logic)
↓
Output (ALV)


3.1 클래스 기반 구조 필수
- lcl_app 또는 목적에 맞는 클래스명 사용
- run() → select_xxx() → display_xxx() 흐름 유지
3.2 SALV 규칙
- SALV는 FACTORY 방식만 허용
cl_salv_table=>factory(
  IMPORTING r_salv_table = lo_alv
  CHANGING  t_table      = it_data ).
- NEW cl_salv_table 금지
- 컬럼 텍스트는 반드시 설정한다.

4. SELECT 규칙
- SELECT는 명확한 필드 목록을 사용한다.
- WHERE 조건은 반드시 파라미터 바인딩(@)을 사용한다.
- ORDER BY는 명확하게 지정한다.
- LIMIT(UP TO n ROWS) 사용 시 반드시 정렬 기준을 명시한다.

5. 오류 처리 규칙
- SALV 오류는 cx_salv_msg로 처리한다.
- SELECT 결과가 없으면 사용자에게 메시지로 안내한다.
- 예외는 반드시 TRY-CATCH로 처리한다.

6. 코드 스타일 규칙
- Clean ABAP 네이밍 규칙 준수
- 변수: lower_case_with_underscore
- 클래스: UpperCamelCase
- 메서드: lower_case_with_underscore
- 불필요한 주석 금지
- 의미 없는 공백 금지
- 가독성을 위한 적절한 줄바꿈 유지

7. /abap-strict 출력 템플릿
### Short explanation

(기능 요약 설명)

### Full code

(완전 실행 가능한 ABAP 코드)



8. 예제: 판매조직 선택 → 최근 고객 주문서 10개 조회
REPORT zsalesorg_recent_customer_po_10.

TYPES: BEGIN OF ty_vbak,
         vkorg TYPE vbak-vkorg,
         vbeln TYPE vbak-vbeln,
         bstnk TYPE vbak-bstnk,
         erdat TYPE vbak-erdat,
         erzet TYPE vbak-erzet,
       END OF ty_vbak.

TYPES ty_vbak_tab TYPE STANDARD TABLE OF ty_vbak WITH EMPTY KEY.

PARAMETERS p_vkorg TYPE vbak-vkorg OBLIGATORY.

CLASS lcl_app DEFINITION FINAL.
  PUBLIC SECTION.
    CLASS-METHODS run.
  PRIVATE SECTION.
    CLASS-METHODS:
      select_recent_po
        IMPORTING iv_vkorg TYPE vbak-vkorg
        RETURNING VALUE(rt_vbak) TYPE ty_vbak_tab,
      display_alv
        IMPORTING it_vbak TYPE ty_vbak_tab.
ENDCLASS.

CLASS lcl_app IMPLEMENTATION.

  METHOD run.
    DATA lt_vbak TYPE ty_vbak_tab.

    lt_vbak = select_recent_po( iv_vkorg = p_vkorg ).

    IF lt_vbak IS INITIAL.
      MESSAGE '최근 고객 주문서 번호가 없습니다.' TYPE 'S'.
      RETURN.
    ENDIF.

    display_alv( it_vbak = lt_vbak ).
  ENDMETHOD.

  METHOD select_recent_po.
    SELECT
      vkorg,
      vbeln,
      bstnk,
      erdat,
      erzet
      FROM vbak
      WHERE vkorg = @iv_vkorg
        AND bstnk IS NOT NULL
      ORDER BY erdat DESCENDING, erzet DESCENDING
      INTO TABLE @rt_vbak
      UP TO 10 ROWS.
  ENDMETHOD.

  METHOD display_alv.
    DATA lo_alv TYPE REF TO cl_salv_table.

    cl_salv_table=>factory(
      IMPORTING r_salv_table = lo_alv
      CHANGING  t_table      = it_vbak ).

    lo_alv->get_functions( )->set_all( abap_true ).

    lo_alv->get_columns( )->get_column( 'VKORG' )->set_short_text( '판매조직' ).
    lo_alv->get_columns( )->get_column( 'VBELN' )->set_short_text( '판매오더' ).
    lo_alv->get_columns( )->get_column( 'BSTNK' )->set_short_text( '고객주문서번호' ).
    lo_alv->get_columns( )->get_column( 'ERDAT' )->set_short_text( '생성일' ).
    lo_alv->get_columns( )->get_column( 'ERZET' )->set_short_text( '생성시간' ).

    lo_alv->display( ).
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  lcl_app=>run( ).



9. 버전 관리 규칙
- 모든 변경은 PR(Pull Request)로 관리한다.
- PR에는 변경 이유와 영향 범위를 명확히 작성한다.
- 코드 리뷰 시 이 문서를 기준으로 승인 여부를 판단한다.

10. 문서 유지보수
- ABAP 버전 업데이트 시 문서도 함께 업데이트한다.
- Clean ABAP 가이드 변경 시 반영한다.
- 새로운 패턴이 도입되면 예제와 규칙을 추가한다.

