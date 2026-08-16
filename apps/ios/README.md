# iOS 앱

향후 SwiftUI 기반 iOS 클라이언트가 들어갈 영역입니다. 현재는 Android MVP 검증이 우선이므로 실행 코드는 없습니다.

구현 시 원칙:

- `packages/contracts`의 공용 API 계약 사용
- 위치·지도·검색·상세 흐름을 Android와 동일하게 유지
- 플랫폼별 UI 관례와 접근성은 네이티브 방식으로 구현
- API 키는 `.xcconfig`와 CI secret으로 주입
