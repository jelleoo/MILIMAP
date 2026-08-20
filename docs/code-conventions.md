# 코드 규칙

## 기본 원칙

- 한 Issue와 한 브랜치에는 하나의 목적만 담습니다.
- 현재 사용자 동작을 바꾸는 변경과 구조 정리는 별도 Issue와 PR로 분리합니다.
- 요청하지 않은 대규모 리팩터링, dependency 추가와 파일 이동을 하지 않습니다.
- 팀에서 확정되지 않은 구조는 임의로 도입하지 않고 `Pending`으로 남깁니다.
- 저장소의 `.editorconfig`와 기존 파일의 줄바꿈 및 들여쓰기를 유지합니다.

## 적용 범위

- 이 규칙은 새로 작성하는 코드부터 적용합니다.
- 기존 코드를 컨벤션에 맞추기 위한 일괄 리팩터링이나 대규모 파일 이동을 하지 않습니다.
- 기존 코드는 해당 기능을 실제로 수정할 때 동작 안정성을 유지하며 점진적으로 정리합니다.

## Kotlin과 Compose

- Kotlin 공식 스타일을 기본으로 하며 4칸 들여쓰기, `val` 우선과 명시적인 Boolean 이름(`is`, `has`, `can`)을 사용합니다.
- 사용하지 않는 import를 제거하고 wildcard import는 피하되, 관련 없는 파일에 formatting이나 import 정리만 적용하지 않습니다.
- 클래스와 Composable은 `PascalCase`, 함수와 프로퍼티는 `camelCase`, 상수는 `UPPER_SNAKE_CASE`를 사용합니다.
- Composable은 화면 표시와 사용자 이벤트 전달에 집중하고 데이터 저장소에 직접 접근하지 않습니다.
- 화면 상태는 화면별 `UiState`로 표현하고 하나의 거대한 상태 모델에 모으지 않습니다. 비동기 작업과 오류 상태를 숨기지 않습니다.
- Compose는 상태를 아래로 전달하고(State down) 사용자 이벤트를 위로 전달합니다(Event up). UI에만 필요한 임시 상태는 가장 가까운 Composable에 둡니다.
- 공개 API와 복잡한 정책에는 이유를 설명하는 주석을 사용하되 코드 동작을 그대로 반복하는 주석은 피합니다.
- 사용자에게 표시하는 문자열은 하드코딩을 확대하지 말고 Android 리소스 사용을 검토합니다.

## ViewModel, Repository와 Coroutine

- ViewModel은 화면별 `UiState`와 사용자 이벤트를 관리하고 mutable 상태를 외부에 직접 노출하지 않습니다.
- ViewModel과 UI는 DAO, 네트워크와 위치정보 구현에 직접 접근하지 않습니다. Repository가 여러 DataSource를 조정하고 구체적인 접근은 Local·Remote·Location DataSource가 담당합니다.
- Blocking 가능 작업은 이를 수행하는 DataSource 또는 Repository에서 적절한 dispatcher를 사용해 main-safe하게 만듭니다. `viewModelScope.launch`만으로 백그라운드 실행이 보장된다고 가정하지 않습니다.
- `GlobalScope`를 사용하지 않으며 새로운 coroutine 구조나 library를 개인 판단으로 도입하지 않습니다.

## 아키텍처 변경

현재 Android MVP에는 `AppController`와 `SQLiteOpenHelper` 중심 코드가 존재합니다. 이 구조를 새 기능의 기본 패턴으로 확대하지 않습니다.

새 구조의 기본 의존 방향은 다음을 검토 대상으로 사용합니다.

```text
UI
→ ViewModel / 화면별 UiState
→ Repository
→ Local / Remote / Location DataSource
```

Room, DI 프레임워크, 모듈 분리, 인증 또는 서버 전환은 전용 Issue와 승인된 ADR 없이 도입하지 않습니다.

## 오류와 데이터

- 오류를 빈 결과나 성공 상태로 바꾸어 숨기지 않습니다.
- 사용자 메시지와 진단용 오류를 구분하고 로그에 비밀정보와 전체 인증 URL을 출력하지 않습니다.
- 혜택 데이터의 필수 신뢰성 필드는 `docs/data-policy.md`를 따릅니다.
- 출처가 없거나 확인되지 않은 값을 편의를 위해 추측하지 않습니다.

## 테스트

- 버그 수정에는 가능한 경우 실패를 재현하는 테스트를 먼저 추가합니다.
- Repository, ViewModel과 데이터 변환은 Android UI 밖에서 검증 가능한 구조를 우선합니다.
- DB schema 변경에는 Migration과 해당 검증을 함께 계획합니다.
- 실행한 테스트만 PR에 기록하며 실행하지 못한 테스트와 이유를 명시합니다.

Android 변경의 기본 검증 명령은 다음과 같습니다.

```text
cd apps/android
./gradlew lintDebug testDebugUnitTest assembleDebug
```

Windows에서는 `./gradlew` 대신 `.\gradlew.bat`을 사용합니다.

## Dependency

- 새 dependency는 Issue 범위에 필요한 최소한으로 추가합니다.
- 도입 이유, 대안, 라이선스, 앱 크기와 유지보수 영향을 PR에 기록합니다.
- dependency와 Gradle, JDK, SDK 버전 변경은 기능 변경과 분리합니다.
