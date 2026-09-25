# Phase 2 A2.1 Source Inventory and DDC Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to execute this plan task-by-task. Preserve the user's Native/inline preference when reconfirmed at plan review. Steps use checkbox syntax for tracking.

**Goal:** 실제 공식 자원의 조회·구조·완전성 근거를 기록하고, 확보한 동두천(DDC) 원문을 변경 없이 A1에 넣어 재사용 가능 여부와 필요한 최소 후속 변경을 판정한다.

**Architecture:** 기존 A1의 snapshot, rowless preparation cache, locator, scoped binding/extraction/validation/evaluation을 읽기 전용으로 실행한다. 네 출처의 조사와 DDC 적합성 평가가 첫 독립 산출물이다. 원문을 모르는 상태에서 전용 adapter를 만들지 않으며 원문/적합성 gate 실패는 차단 또는 차이 보고서로 남긴다.

**Tech Stack:** 기존 PowerShell 7 스크립트, Git, 승인된 실행 환경의 공개 HTTP 조회 수단. 새 라이브러리·provider·인증·DB 없음.

**Spec:** `docs/superpowers/specs/2026-09-25-phase2-a2-source-inventory-ddc-pilot-design.md`, reviewed version `d7d4c1edff44f2c8623d4b679be08d08d507907c`.

**Status:** PROPOSED PLAN — 실행 계획 사용자 검토 대기. 2026-09-25 사용자의 진행 승인은 설계서 검토 후 이 계획 작성까지다. 설계서 본문의 이전 PROPOSED 표시는 작성 시점 상태이며 승인 checkpoint는 Issue #62와 PR #63에 기록한다. 새 계획 실행·병합·후속 adapter 구현은 아직 승인되지 않았다.

**Pinned code baseline:** `dev@71b8e28518b95429cf878e0d8b3baf2b2ba2ebde` (A1 closeout, PR #61). 실행 시 최신 dev와 대조한다.

## Global Constraints

다음 문장은 승인 설계서의 제약을 그대로 적용한다.

- 원본 `BenefitSourceDocument`와 snapshot text는 변경하지 않는다. caption/header/cell은 원본 절대 위치로 검증한다.
- `SourceRowNumber`는 canonical의 원본 행 번호다. HTML physical row index와 구분하고, source-level cache에 넣지 않는다.
- qualification과 business binding, 선택된 slice, claim과 state는 공유 캐시에 넣지 않는다.
- header를 다른 글자로 덮어써 validator를 통과시키거나, 정규화한 mini-document를 원본처럼 사용하지 않는다.
- 페이지 전체의 할인 안내, 한시 행사, 표 밖 공통 조건을 모든 행에 자동으로 붙이지 않는다. 이번 DDC pilot은 기존 detail-only 계약을 유지한다.
- 원문 확보가 계속 막히면 조사 산출물만 마무리하고 DDC 구현은 보류한다. 접근 실패가 새로운 provider·인증·라이브러리 도입을 자동 승인하지 않는다.

추가 실행 경계:

- `data/canonical/**`, `data/seed/**`, `apps/**`, 현재 `tools/data/**`, runtime 계약, workflow를 수정하지 않는다. A2.1 실행의 커밋 산출물은 아래 두 Markdown 보고서뿐이다.
- 과거 비교 판정이나 parser 출력으로 expected truth를 만들지 않는다. 합성/파생 fixture와 원문 capture를 구분한다.
- 최초 대상은 아래 일곱 exact entry resource다. 다른 host/detail/attachment/검색/API는 자동 추적하지 않는다.
- `ProductionAction=NONE`, legacy 호출, currentness/lifecycle 판정을 유지한다. LLM/PDF/XLSX/HWP/OCR/SNS/검색 provider는 비대상이다.
- 조사 완료, DDC snapshot 적합성, DDC 전체 지원, A2 전체, Phase 2 완료를 구분한다. 미지원 대상을 지워 완료율을 높이지 않는다.
- 미실행 명령을 통과로 적지 않으며 사용자의 PC에서 중복 수동 테스트를 기본 요구하지 않는다.

## Review Focus

1. 리다이렉트·접근 차단·웹 캐시를 새 원문으로 취급하지 않는다. Task 1에서 직접 2xx, 실제 URL, 시점, complete body가 없으면 raw gate를 닫는다.
2. 인코딩·압축·BOM·줄바꿈이 hash/span을 바꾸지 않게 한다. Task 2에서 byte/text hash와 동일 string round-trip, UTF-16 offset을 검증한다.
3. 다른 표·동명 업체·공통 프로그램을 잘라 단일 일치를 만들지 않는다. Task 2의 독립 oracle과 Task 3의 원문 전체 입력/정확한 reference 대조로 확인한다.
4. replay를 live 재검증으로 오인하지 않는다. Task 3에서 capture ObservedAt을 사용하고 replay 시간·invoker 횟수를 따로 기록한다.
5. 원문·오라클·환경이 없는데 성공으로 보고하지 않는다. Task 4에서 차단/실패를 남기고 distinct positive 없는 재사용 성공을 거부한다.

---

## Delivery boundary and file map

### 현재 계획 작성 PR #63

이 계획을 추가한다. 기존 설계서와 `docs/ai-development.md`를 포함한 문서 PR이며 Issue #62가 세 경로를 예약한다. 제품 구현과 원문 획득은 이번 계획 작성 단계에서 수행하지 않는다.

### 계획 승인 후 A2.1 실행

문서 PR #63이 dev에 병합되었거나 사용자가 승인한 별도 기준선이 확정된 뒤 새 실행 Issue/브랜치를 만든다. 제안 브랜치: `codex/phase2-a2-1-source-inventory-ddc-reuse`. 다음 두 경로만 예약한다.

| 파일 | 책임 |
| --- | --- |
| `docs/handover/2026-09-25-phase2-a2-source-inventory.md` | 일곱 자원의 직접 관측/미관측, 응답·완전성·첨부/상세 의존성과 접근 실패 |
| `docs/handover/2026-09-25-phase2-a2-ddc-reuse-assessment.md` | 원문/오라클 근거, A1 probe, 재사용/차이/차단 판정, 다음 범위 |

body/header/capture metadata/독립 oracle/probe/log는 OS 임시 폴더에 둔다. 이는 일회성 조사 자료이지 새 runtime storage/schema가 아니다. cookie/token·불필요한 개인정보·원문 전체를 자동 커밋하지 않는다. 승인된 보관 위치와 hash를 보고하고 보관 적합성 또는 재접근이 불명확하면 제한을 명시한다.

DDC snapshot을 CI fixture로 넣거나 adapter를 고치려면 실제 구조와 보관 조건을 확인한 별도 계획에서 test/fixture/production 경로를 예약한다. 이번 계획에는 알 수 없는 parser 수정 작업을 넣지 않는다.

## Preflight — 실행 승인 후 Task 1에 포함

문제는 실제 구조 없이 support를 주장하는 것이다. 범위는 공개 entry 조사와 DDC read-only replay다. 비대상은 production/data 변경이다. 검증은 capture hash, 독립 oracle, 기존 A1 probe/회귀와 문서 diff다. 위험은 접근 실패, 위치 손상, scope 축소, replay와 live audit 혼동이다.

- [ ] PR #61/#63, Issue #62와 새 실행 Issue, `AGENTS.md`, `docs/current-work.md`, `docs/ai-development.md`, `docs/team-workflow.md`, spec/plan을 읽는다. current-work가 오래됐으면 실제 병합 코드와 해당 Issue/PR을 우선한다.
- [ ] 격리 clone/worktree와 브랜치/dirty/untracked/예약 충돌을 확인한다. 남의 파일을 reset/stash/덮어쓰기하지 않는다.
- [ ] 다음을 실행하고 실제 결과를 기록한다. pwsh가 없으면 읽기 조사만 가능하고 probe는 NOT_RUN이다. 테스트를 위해 CI에 live-network workflow를 추가하지 않는다.

```powershell
$ErrorActionPreference = 'Stop'
git fetch origin dev
if ($LASTEXITCODE -ne 0) { throw 'Cannot establish latest dev' }
git branch --show-current
git status --short
$codeBase = (git rev-parse origin/dev).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot pin origin/dev' }
Get-Command pwsh -ErrorAction Stop | Select-Object Source
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
if ($LASTEXITCODE -ne 0) { throw 'PowerShell runtime unavailable' }
$repoRoot = (git rev-parse --show-toplevel).Trim()
$captureRoot = Join-Path ([IO.Path]::GetTempPath()) ('milimap-a2-1-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($captureRoot) | Out-Null
$canonicalPath = Join-Path $repoRoot 'data/canonical/capital-area-military-benefits.csv'
$canonicalHash = (Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash.ToLowerInvariant()
@("CodeBase=$codeBase", "CanonicalSha256=$canonicalHash") |
    Set-Content -LiteralPath (Join-Path $captureRoot 'baseline.txt') -Encoding utf8
```

Expected: 실제 SHA/환경/hash가 남거나 BLOCKED_ENVIRONMENT가 기록된다. 이후 코드 블록은 같은 작업 변수들을 사용하며 재개 시 ledger에서 경로/SHA를 복구한다. 성공한 선행 gate 없이 다음 블록을 실행하지 않는다.

## Task 1: Seven-resource capability inventory and bounded capture

**Files:** Create `docs/handover/2026-09-25-phase2-a2-source-inventory.md`.

**Interfaces:** Consumes pinned code/canonical and 아래 exact URLs. Produces 일곱 resource records와 성공 시 DDC capture. 다음 task는 summary가 아니라 원문을 소비한다.

- [ ] **Step 1: 고정 조사 목록을 기록한다.** 이것은 기존 코드의 entry URL이며 현재 혜택을 확인한 목록이 아니다.

| ID | Family | Exact URL |
| --- | --- | --- |
| DDC-1 | DDC | `https://www.ddc.go.kr/ddc/contents.do?key=1570` |
| PAJU-1001 | Paju | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001` |
| PAJU-1002 | Paju | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1002` |
| PAJU-1004 | Paju | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1004` |
| MMA-1 | MMA | `https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357` |
| YANGJU-LEGACY | Yangju | `https://www.yangju.go.kr/www/selectBbsNttView.do?bbsNo=13&key=202&nttNo=198019` |
| YANGJU-ALTERNATE | Yangju | `https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761` |

- [ ] **Step 2: 공개 조회 환경에서 자원당 한 번 캡처한다.** 이미 사용 가능한 curl을 쓰는 아래 명령은 one-shot 조사이며 runtime RequestInvoker 교체가 아니다. 로그인·proxy·TLS 검증 해제·자동 redirect·retry를 추가하지 않는다. 도구/네트워크 부재는 환경 제한으로 기록한다.

```powershell
$curl = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue
if ($null -eq $curl) { $curl = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue }
if ($null -eq $curl) { throw 'Capture tool unavailable; record BLOCKED_ENVIRONMENT' }
$entries = [ordered]@{
    'DDC-1'='https://www.ddc.go.kr/ddc/contents.do?key=1570'
    'PAJU-1001'='https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001'
    'PAJU-1002'='https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1002'
    'PAJU-1004'='https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1004'
    'MMA-1'='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'
    'YANGJU-LEGACY'='https://www.yangju.go.kr/www/selectBbsNttView.do?bbsNo=13&key=202&nttNo=198019'
    'YANGJU-ALTERNATE'='https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761'
}
foreach ($id in $entries.Keys) {
    $dir = Join-Path $captureRoot $id
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $startedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $transport = & $curl.Source --silent --show-error --proto '=https' `
        --connect-timeout 10 --max-time 30 --max-filesize 8388608 `
        --dump-header (Join-Path $dir 'headers.private.txt') `
        --output (Join-Path $dir 'body.bin') `
        --write-out '%{http_code}\n%{url_effective}\n%{content_type}' `
        --url $entries[$id] 2> (Join-Path $dir 'transport-error.private.txt')
    $exitCode = $LASTEXITCODE
    [ordered]@{
        ResourceId=$id; RequestedUrl=$entries[$id]; Method='GET'
        StartedAt=$startedAt; CompletedAt=[DateTimeOffset]::UtcNow.ToString('o')
        CurlExitCode=$exitCode; Transport=@($transport)
        AutomaticRedirects=$false; CaptureMethod='direct-curl-one-shot'
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'transport.private.json') -Encoding utf8
}
```

Expected: 일곱 자원의 시도 기록. `CurlExitCode=0`만으로 성공이라고 하지 않는다. 실제 2xx, URL, complete body, content type을 확인한다. 3xx는 redirect 미조회이며 HTTP 오류·timeout·크기 초과·도구 오류·부분 다운로드는 raw gate 실패다. Location은 관계만 기록하고 자동 추적하지 않는다. 다른 자원 조회가 필요하면 bounded 범위를 별도 확인한다.

- [ ] **Step 3: inventory를 작성한다.** 각 자원에 조회 시각/방법, 실제 HTTP 관찰, 형식/encoding/hash/보관 위치, caption/header와 업체/혜택 근거 위치, pagination/detail/attachment 관계, 현재성 근거 위치, 보관 적합성을 기록한다. 미관측은 이유와 함께 미확인으로 둔다. cached/rendered 웹 텍스트는 별도 관찰 종류이며 raw capture 성공으로 바꾸지 않는다.
- [ ] **Step 4: completeness를 자원별로 기록한다.** 하나의 응답을 읽은 것과 사이트 전체를 읽은 것을 구분한다. 모든 일곱 entry를 남기며 외부 상세 지도, 검색/API, 한시/상시 첨부의 내용을 추정하지 않는다.
- [ ] **Step 5: 보고서만 커밋한다.**

```powershell
git add -- docs/handover/2026-09-25-phase2-a2-source-inventory.md
git diff --cached --stat
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Inventory documentation whitespace check failed' }
git commit -m 'docs: inventory official source entry capabilities'
```

Acceptance: 일곱 자원이 모두 결과/미확인 범위를 갖는다. DDC capture 실패는 유효한 조사 결과지만 DDC 지원 성공이 아니다. 실패 시 Task 2/3를 실행한 척하지 않고 사유를 Task 4에 넘긴다.

## Task 2: Pin DDC text and independent source expectations

**Files:** Start `docs/handover/2026-09-25-phase2-a2-ddc-reuse-assessment.md`. Private files: `$captureRoot/DDC-1`.

**Interfaces:** Consumes complete raw DDC body/metadata. Produces unmodified decoded text, original observation time, byte/text hashes, independent `expected.psd1`. 이 PSD1은 local test input이며 runtime schema가 아니다.

- [ ] **Step 1: capture gate를 검증한다.** complete 직접 2xx HTML만 받는다. redirect/차단/다른 형식/빈 body/로그인 요구는 BLOCKED_CAPTURE 또는 UNSUPPORTED_INPUT이다.
- [ ] **Step 2: encoding과 content encoding을 확인한다.** 알 수 없는 charset·압축·HTTP/meta 충돌이면 임의 UTF-8 해석 없이 BLOCKED_DECODE로 기록한다. 기존 승인 decoder로 lossless text가 확보된 경우만 진행한다. 다음 코드는 **HTTP에서 UTF-8과 압축 없음이 확인된 응답**에 한정한다.

```powershell
$ddcDir = Join-Path $captureRoot 'DDC-1'
$transport = Get-Content -Raw -LiteralPath (Join-Path $ddcDir 'transport.private.json') | ConvertFrom-Json
if ($transport.CurlExitCode -ne 0 -or @($transport.Transport).Count -ne 3) { throw 'Incomplete capture metadata' }
$httpStatus = [int]$transport.Transport[0]
$retrievedUrl = [string]$transport.Transport[1]
$contentType = [string]$transport.Transport[2]
if ($httpStatus -lt 200 -or $httpStatus -ge 300 -or $retrievedUrl -cne $entries['DDC-1']) { throw 'Direct successful source identity required' }
if ($contentType -notmatch '^(text/html|application/xhtml\+xml)(;|$)') { throw 'HTML media type required' }
$rawBytes = [IO.File]::ReadAllBytes((Join-Path $ddcDir 'body.bin'))
$decoder = [Text.UTF8Encoding]::new($false, $true)
$text = $decoder.GetString($rawBytes)
if ([string]::IsNullOrWhiteSpace($text)) { throw 'Empty capture; no source support claim' }
$sourceTextPath = Join-Path $ddcDir 'source.txt'
[IO.File]::WriteAllText($sourceTextPath, $text, [Text.UTF8Encoding]::new($false))
$reread = $decoder.GetString([IO.File]::ReadAllBytes($sourceTextPath))
if ($reread -cne $text) { throw 'Decoded source changed during storage' }
. ./tools/data/lib/benefit-evidence-location-contracts.ps1
$textHash = Get-BenefitEvidenceTextHash -Text $text
$byteHash = (Get-FileHash -LiteralPath (Join-Path $ddcDir 'body.bin') -Algorithm SHA256).Hash.ToLowerInvariant()
$observedAt = [string]$transport.CompletedAt
Assert-ScopeTimestamp $observedAt
@("ByteSha256=$byteHash", "TextSha256=$textHash", "ObservedAt=$observedAt", "ContentType=$contentType", 'Encoding=UTF-8') |
    Set-Content -LiteralPath (Join-Path $ddcDir 'decoded-evidence.txt') -Encoding utf8
```

BOM·줄바꿈·주석·다른 표를 제거하지 않는다. byte hash와 A1 UTF-8 text hash를 구분한다. `RawStart/RawLength`는 .NET UTF-16 code-unit offset이며 바이트 offset이 아니다.

- [ ] **Step 3: parser 실행 전에 독립 oracle을 작성한다.** 원문 전체에서 실제 DDC 혜택 표/caption/header와 서로 다른 업체 두 행의 cell을 직접 대조한다. 두 positive를 확보하지 못하면 원문 적합성 성공을 선언하지 않는다. 동명 후보/모순을 제외하지 않으며 parser/locator 출력에서 기대값을 복사하지 않는다.

`expected.psd1`의 정확한 local 형식:

- Root: `EvidenceKind='DIRECT_CAPTURE_ORACLE'`, `AuthoringMethod='DIRECT_RAW_INSPECTION'`, `SourceUrl`, `ObservedAt`, `TextSha256`, `ByteSha256`, `CanonicalSha256`, `Cases` array.
- Case: `SourceRowNumber` (고정 canonical의 원본 CSV 행 번호), `UnitReference`, `RawStart`, `RawLength`, `Fields` dictionary.
- Fields key: 원문에 실제 존재하는 A1 필드명. Value object: `Value`, `OriginalHeader`, `FieldReference`, `HeaderStart`, `HeaderLength`, `CellStart`, `CellLength`.
- `FieldReference`는 원문 physical `HTML_TABLE_<n>_ROW_<n>/<FieldName>`이다. 실제 숫자/문자열은 이 task의 직접 관찰 산출물이며 계획이 미리 만들어 넣지 않는다.
- 두 distinct positive는 `BusinessName`과 `BenefitDescription`을 갖는다. 할인 문자열이 같아도 reference로 분리한다. canonical은 비교 대상일 뿐 source의 빈 필드를 채우는 증거가 아니다. 충돌 사례는 위험 사례로 기록하고 억지 positive로 만들지 않는다.

```powershell
$oracle = Import-PowerShellDataFile -LiteralPath (Join-Path $ddcDir 'expected.psd1')
if ($oracle.EvidenceKind -cne 'DIRECT_CAPTURE_ORACLE' -or $oracle.AuthoringMethod -cne 'DIRECT_RAW_INSPECTION') { throw 'Independent source oracle required' }
if ($oracle.TextSha256 -cne $textHash -or $oracle.ByteSha256 -cne $byteHash -or $oracle.CanonicalSha256 -cne $canonicalHash) { throw 'Oracle/input hash mismatch' }
if ($oracle.ObservedAt -cne $observedAt -or $oracle.SourceUrl -cne $entries['DDC-1']) { throw 'Oracle source identity mismatch' }
if (@($oracle.Cases).Count -lt 2) { throw 'Insufficient independent positive controls' }
if (@($oracle.Cases.SourceRowNumber | Select-Object -Unique).Count -ne @($oracle.Cases).Count -or @($oracle.Cases.UnitReference | Select-Object -Unique).Count -ne @($oracle.Cases).Count) { throw 'Controls must use distinct canonical and source rows' }
foreach ($case in $oracle.Cases) {
    if ($case.SourceRowNumber -le 1 -or $case.RawStart -lt 0 -or $case.RawLength -le 0 -or ($case.RawStart + $case.RawLength) -gt $text.Length) { throw 'Invalid independent row span' }
    foreach ($required in @('BusinessName','BenefitDescription')) {
        if (-not $case.Fields.ContainsKey($required)) { throw ('Missing positive field: ' + $required) }
    }
    foreach ($name in $case.Fields.Keys) {
        $field = $case.Fields[$name]
        $cell = $text.Substring([int]$field.CellStart, [int]$field.CellLength)
        $header = $text.Substring([int]$field.HeaderStart, [int]$field.HeaderLength)
        Write-Host $case.UnitReference $name $header $cell
    }
}
```

Expected: 原문에서가 아니라 **원문에서 직접 대조한** 독립 기대값과 hash가 연결된다. 이 출력은 위치 확인용이지 oracle 자동 생성기가 아니다.

- [ ] **Step 4: 보관 정책을 기록한다.** hash·수집 시각·source URL·oracle 작성자/방식·승인된 보관 위치 또는 제한을 보고서에 남긴다. 익명화/절단 자료는 새 파생 자료이며 원본 hash/offset을 승계하지 않는다. agent 원문 대조와 A3 human audit를 구분한다.

## Task 3: Read-only A1 probe and regression evidence

**Files:** Update DDC assessment report. 다음 probe는 private workspace에서만 실행하며 parser/contract를 수정하지 않는다.

**Interfaces:** Consumes Task 2's exact text/oracle/canonical. Uses existing observation, locator, qualification, scoped binding/extraction/validation and evaluation. Produces correct-source positive evidence 또는 구체적인 gap.

- [ ] **Step 1: 두 distinct positive를 실행한다.** 기존 동작이 맞으면 baseline PASS다. 가짜 RED를 만들지 않는다. 실패하면 exact input hash와 기대/실제 차이를 남기고 production을 고치지 않는다.

```powershell
. ./tools/data/testdata/benefit-evidence-location/test-support.ps1
. ./tools/data/invoke-phase2-benefit-shadow-mode.ps1
$canonicalRows = @(Import-Csv -LiteralPath $canonicalPath -Encoding utf8)
$failures = [Collections.Generic.List[string]]::new()
foreach ($case in $oracle.Cases) {
    try {
        $number = [int]$case.SourceRowNumber
        if ($number -gt ($canonicalRows.Count + 1)) { throw 'Oracle row outside pinned canonical input' }
        $row = $canonicalRows[$number - 2]
        Assert-ScopeEqual ([string]$row.'출처URL') $oracle.SourceUrl 'Canonical and captured resource must match'
        $business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber $number
        $document = New-BenefitSourceDocument -SourceRowNumber $number -Url $oracle.SourceUrl -SourceFormat HTML -FetchStatus COMPLETE -ContentType $contentType -Text $text -ObservedAt $oracle.ObservedAt
        $observation = ConvertTo-BenefitHtmlObservation -Document $document
        Assert-ScopeEqual $observation.AdapterStatus 'COMPLETE' 'Unmodified response must be supported'
        $location = Find-BenefitBusinessEvidence -Observation $observation -Business $business -CanonicalPhone ([string]$row.'업소전화번호')
        Assert-ScopeEqual $location.Status 'LOCATED' 'Independently matched business is located'
        $slice = $location.Slices[0]
        Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $document -SourceRowNumber $number
        Assert-ScopeEqual $slice.EvidenceReference $case.UnitReference 'Correct physical row'
        Assert-ScopeEqual $slice.RawStart $case.RawStart 'Original start'
        Assert-ScopeEqual $slice.RawLength $case.RawLength 'Original length'
        foreach ($name in $case.Fields.Keys) {
            $expected = $case.Fields[$name]
            Assert-ScopeEqual $slice.StructuredFields[$name] $expected.Value 'Independent exact source value'
            $actual = $slice.FieldReferences[$name]
            foreach ($key in @('OriginalHeader','FieldReference','HeaderStart','HeaderLength','CellStart','CellLength')) {
                Assert-ScopeEqual $actual.$key $expected[$key] ('Original field: ' + $key)
            }
        }
        $candidate = New-BenefitSourceCandidate -SourceRowNumber $number -Url $oracle.SourceUrl -SourceKind PUBLIC_OFFICIAL -SourceLabel 'DDC captured official source' -DiscoveryMethod 'OFFLINE_CAPTURE_REPLAY' -ObservedAt $oracle.ObservedAt
        $qualified = Get-QualifiedBenefitSource -Candidate $candidate -Document $document -Business $business
        Assert-ScopeEqual $qualified.OfficialityStatus 'VERIFIED_OFFICIAL' 'Qualification still required'
        $bound = Get-BenefitBusinessBinding -Source $qualified -Business $business -CanonicalPhone ([string]$row.'업소전화번호') -EvidenceSlice $slice
        Assert-ScopeEqual $bound.BusinessBindingStatus 'STRONG' 'Independent binding required'
        $extraction = Invoke-BenefitEvidenceExtraction -Source $bound -Document $document -EvidenceSlice $slice
        $validated = ConvertTo-ValidatedBenefitEvidence -Extraction $extraction -Document $document -EvidenceSlice $slice
        $claims = @($validated.Claims | Where-Object { $_.ClaimType -ceq 'BENEFIT_DESCRIPTION' -and $_.ValidationStatus -ceq 'VALIDATED' })
        Assert-ScopeEqual $claims.Count 1 'Own benefit cell, not whole-page claims'
        Assert-ScopeEqual $claims[0].Value $case.Fields.BenefitDescription.Value 'Own value'
        Assert-ScopeEqual $claims[0].EvidenceReference $case.Fields.BenefitDescription.FieldReference 'Own reference'
        Assert-ScopeEqual @($validated.Claims | Where-Object { $_.ClaimType -in @('BENEFIT_EXISTENCE','CURRENT_APPLICABILITY','VALID_FROM','VALID_UNTIL') }).Count 0 'No lifecycle inference'
        $record = [pscustomobject]@{ Candidate=$candidate; Document=$document; Qualified=$qualified; Bound=$bound; Extraction=$extraction; Validation=$validated }
        $benefit = ConvertTo-Phase2CanonicalBenefitRecord -Row $row -SourceRowNumber $number
        $evaluation = Get-Phase2BenefitEvaluation -Benefit $benefit -SourceRecords @($record) -DiscoveryStatus COMPLETE
        Assert-ScopeEqual $evaluation.Evaluation.BenefitState 'NEEDS_VERIFICATION' 'Detail-only capture does not resolve lifecycle'
        Assert-ScopeTrue ($evaluation.Evaluation.ReviewClass -cne 'GREEN') 'No unsupported approval'
        Write-Host ('PASS DDC direct-capture positive row ' + $number)
    } catch { $failures.Add(('Row ' + $case.SourceRowNumber + ': ' + $_.Exception.Message)) }
}
if ($failures.Count -gt 0) {
    $failures | Set-Content -LiteralPath (Join-Path $ddcDir 'compatibility-gap.txt') -Encoding utf8
    throw 'DDC gap demonstrated; no support-completion claim'
}
```

Expected: 모든 positive가 정확한 원문 row/cell을 유지하거나 gap이 재현된다. 예외, 잘못된 선택, 불완전 구조, canonical identity 모순을 구분한다. 실패한 case/표를 지워 통과시키지 않는다.

- [ ] **Step 2: 성공한 원문 slice의 변조를 거부하는지 확인한다.** 다음 입력은 test-only이며 실제 혜택 데이터 변경이 아니다. Step 1이 실패하면 성공한 positive처럼 다음 결과를 주장하지 않는다.

```powershell
$badSlice = Copy-ScopeContractData $slice
$badSlice.StructuredFields['BenefitDescription'] = '__SYNTHETIC_TAMPER_NOT_SOURCE__'
Assert-ScopeThrows {
    Assert-RelevantBenefitEvidenceSlice -Slice $badSlice -Document $document -SourceRowNumber $document.SourceRowNumber
} 'Changed value cannot certify itself'
$badUrlDocument = New-BenefitSourceDocument -SourceRowNumber $document.SourceRowNumber -Url 'https://city.example.go.kr/not-the-original' -SourceFormat HTML -FetchStatus COMPLETE -Text $text -ObservedAt $oracle.ObservedAt
Assert-ScopeThrows {
    Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $badUrlDocument -SourceRowNumber $document.SourceRowNumber
} 'Another URL cannot inherit source provenance'
```

Expected: 두 변조 모두 거부한다.

- [ ] **Step 3: 동일 capture의 parse reuse와 시각을 확인한다.** live fetch 없이 원래 시각을 가진 fresh document 두 개를 사용한다.

```powershell
$context = New-BenefitSourceRunContext
$observations = @()
foreach ($case in @($oracle.Cases | Select-Object -First 2)) {
    $doc = New-BenefitSourceDocument -SourceRowNumber $case.SourceRowNumber -Url $oracle.SourceUrl -SourceFormat HTML -FetchStatus COMPLETE -ContentType $contentType -Text $text -ObservedAt $oracle.ObservedAt
    $observations += Get-BenefitRunHtmlObservation -Context $context -Document $doc
}
Assert-ScopeEqual $context.Metrics.AdapterParseCount 1 'One parse of same captured snapshot'
Assert-ScopeEqual $context.Metrics.AdapterReuseCount 1 'One parse reuse'
Assert-ScopeEqual $context.Metrics.ExternalFetchCount 0 'Offline probe is not live fetch'
Assert-ScopeEqual $observations[0].ObservedAt $oracle.ObservedAt 'Original capture time'
Assert-ScopeTrue (-not [object]::ReferenceEquals($observations[0], $observations[1])) 'Independent wrappers'
Assert-ScopeEqual $observations[0].SourceRowNumber $oracle.Cases[0].SourceRowNumber 'First original row'
Assert-ScopeEqual $observations[1].SourceRowNumber $oracle.Cases[1].SourceRowNumber 'Second original row'
```

추가 runner replay에서 fake RequestInvoker를 사용하면 원문 capture 시각/replay 시각을 분리한다. runner의 새 ObservedAt은 live 재조회 증거가 아니며 ExternalFetchCount도 fake invoker 호출 수이지 network 횟수가 아니다. `-OperationalLiveRun`은 사용하지 않는다.

- [ ] **Step 4: 기존 안전 회귀를 실행한다.** 다른 업체 종료 문구, strong+name-only 대안, hard-number/floor/unit/phone, PARTIAL/UNSUPPORTED, 호출 호환성, reuse, protected export는 기존 assertions를 유지한다.

```powershell
$tests = @(
    'test-benefit-evidence-location-contracts.ps1', 'test-convert-html-source-observation.ps1',
    'test-find-business-evidence-slice.ps1', 'test-benefit-source-run-context.ps1',
    'test-bind-benefit-source.ps1', 'test-extract-benefit-evidence.ps1',
    'test-validate-benefit-evidence.ps1', 'test-phase2-scoped-html.ps1',
    'test-phase2-benefit-shadow-mode.ps1', 'test-phase1-poi-shadow-mode.ps1'
)
foreach ($name in $tests) {
    pwsh -NoProfile -File (Join-Path tools/data $name)
    if ($LASTEXITCODE -ne 0) { throw ('Existing regression failed: ' + $name) }
}
```

Expected: 기존 안전 계약 PASS. 합성 회귀만으로 DDC raw 적합성이나 population 정확도를 주장하지 않는다. 실행 불가는 NOT_RUN이며 exact-HEAD CI와 분리한다.

## Task 4: Decision, truthful closeout and next delivery gate

**Files:** Finalize both handover reports; no production changes.

**Interfaces:** Consumes inventory/capture/oracle/probe/test outputs. Produces 다음 작은 작업을 위한 검증 가능한 판정이지 자동 adapter 구현이 아니다.

- [ ] **Step 1: 다음 셋 중 DDC 결과를 결정한다.**

| Outcome | 필요한 근거 | 다음 작업 |
| --- | --- | --- |
| REUSE_VERIFIED_FOR_CAPTURE | 직접 capture, 독립 distinct positive 2개 이상, 원문 provenance, 안전 회귀, parse reuse | 검증한 snapshot 범위만 재사용 가능. 고정 fixture/CI 회귀는 보관 적합성·파일 예약 후 별도 계획. 불필요한 adapter 없음 |
| GAP_REPRODUCED | 동일 hash에서 실패, 기대/실제 차이, 영향 범위 | 차이만 다루는 A2.2 설계/계획. TDD RED→GREEN과 정확한 파일 예약 검토 후 수정 |
| BLOCKED_EVIDENCE_OR_ENVIRONMENT | capture/decode/oracle/runtime/보관 중 부족한 근거와 시도 기록 | 조사 완료와 DDC 구현 보류를 구분. source 변경/도구 도입은 별도 결정 |

이 분기는 조사 결과에 따른 gate다. 근거 없는 header alias/resolver/adapter 구현을 추가하지 않는다.

- [ ] **Step 2: 상태·수치를 대조한다.** 일곱 entry를 모두 유지하고 확보/미확보/미지원/미확인을 나눈다. DDC input hash, 독립 case 수, 정확한 row/cell 결과, 사유별 실패, offline network 0, 실행/NOT_RUN을 기록한다. 실제 human audit는 `NOT_RUN`이며 미측정 population precision/recall·false-GREEN/ENDED는 null이다.
- [ ] **Step 3: scope와 non-write를 확인한다.** `$codeBase`는 preflight SHA를 유지한다.

```powershell
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'Whitespace error' }
git diff --exit-code $codeBase -- data/canonical data/seed apps tools/data .github
if ($LASTEXITCODE -ne 0) { throw 'Non-documentation delta detected' }
$currentHash = (Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($currentHash -cne $canonicalHash) { throw 'Canonical input changed' }
git status --short --untracked-files=all
git diff --name-only $codeBase
```

Expected: non-documentation 변경 없음, canonical hash 동일. capture/credentials는 stage하지 않는다. remote diff만 확인했다면 local dirty/untracked까지 확인했다고 쓰지 않는다.

- [ ] **Step 4: 실행 검증을 마무리한다.** 환경이 갖춰지면 아래 전체 data suite 두 방식을 한 번씩 확인한다. 환경상 불가능하면 사유와 exact-HEAD CI를 분리하고 사용자 PC 중복 테스트를 강요하지 않는다. 이는 자동 live network 검증이 아니다.

```powershell
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object {
    pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw ('FAILED: ' + $_.Name) }
}
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & $_.FullName }
```

Expected: 수행한 전체 방식 PASS. baseline 실패를 숨기거나 문서 작업 때문이라고 단정하지 않는다.

- [ ] **Step 5: 보고서 커밋/PR 후 멈춘다.**

```powershell
git add -- docs/handover/2026-09-25-phase2-a2-source-inventory.md docs/handover/2026-09-25-phase2-a2-ddc-reuse-assessment.md
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged documentation check failed' }
git diff --cached --stat
git commit -m 'docs: record DDC reuse evidence and source capability limits'
```

최종 HEAD를 push하고 dev 대상 문서 PR을 만든다. 자동 CI가 실행되면 해당 HEAD만 보고한다. 자체 리뷰는 독립 reviewer/human audit가 아니다. 승인 없는 merge/A2.2 구현은 하지 않는다.

## Final report and progress

보고: 변경 파일, 자원별 확보 여부, DDC gate 결과, 실제 실행/미실행 명령과 이유, raw/derived/replay/human-audit 구분, input hash/보호 경로, PR/HEAD/CI, 남은 위험, 다음 작은 작업.

A1은 5/5 merged다. 이 A2.1은 네 task의 산출물 상태를 보고하되 raw gate 실패를 구현 성공으로 세지 않는다. A2 전체의 지원 범위/작업 수는 아직 미확정이므로 전체 퍼센트를 계산하지 않는다. A3와 Phase 2 전체는 이번 조사만으로 완료하지 않는다.

## Plan self-review and execution handoff

Spec 1–5절의 의도·조사·재사용은 Task 1, 원문/독립 검증은 Task 2–3, 공통 계약/실패/현재성은 Global Constraints와 Task 3, 출처 분리/완료/위험/A3 전달은 Task 4에 대응한다. 실제 원문 없는 adapter 설계는 산출물이 아니며 gap 확인 후 별도 승인 대상이다.

위 snippets는 **향후 실행 명령**이다. 이번 문서 작성에서 공개 source capture, pwsh probe, 테스트, human audit를 실행했다는 뜻이 아니다.

사용자가 계획과 기존 Native/inline 방식을 확인하면 `executing-plans`로 Task 1부터 시작한다. PR #63 병합 권한은 별도로 확인한다. 현재 단계에서는 제품 구현/병합을 하지 않는다.
