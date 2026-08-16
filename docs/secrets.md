# 비밀정보 관리

## Git에 올리지 않는 값

- 공공데이터포털 서비스 키
- 네이버 클라우드 Secret
- 운영 DB 접속 정보
- Android/iOS 서명 키
- 사용자 개인정보가 포함된 운영 데이터

로컬 Android 키는 `apps/android/local.properties`에만 저장하며 이 파일은 Git에서 제외됩니다. 저장소에는 변수명만 포함된 `local.properties.example`만 커밋합니다.

GitHub Actions에서 비밀값이 필요해지면 Repository Settings의 Actions secrets에 등록하고 workflow에서 `${{ secrets.NAME }}`으로 참조합니다. Pull Request 로그에 키나 전체 요청 URL을 출력하지 않습니다.

## 현재 MVP의 제한

현재 Android MVP는 공공 API 서비스 키를 앱 빌드에 포함할 수 있는 구조입니다. 디버그 및 내부 검증에만 사용하고, 공개 배포 전에는 반드시 서버 프록시로 옮깁니다.
