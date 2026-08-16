# 데이터 도구

`convert-benefits.ps1`은 수도권 CSV를 Android 앱의 초기 JSON 자산으로 변환합니다. 입력과 출력 경로를 반드시 인자로 받으므로 저장소 루트에서 다음처럼 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\data\convert-benefits.ps1 `
  -SourceCsv ".\data\seed\capital-area-military-benefits-20260815.csv" `
  -DestinationJson ".\apps\android\app\src\main\assets\benefits.seed.json"
```
