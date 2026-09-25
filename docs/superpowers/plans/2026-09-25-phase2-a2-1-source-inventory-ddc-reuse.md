# Phase 2 A2.1 Source Inventory and DDC Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to execute this plan task-by-task. Use the user's existing Native/inline preference when reconfirmed at plan review. Steps use checkbox syntax for tracking.

**Goal:** 실제 공식 자원의 조회·구조·완전성 근거를 기록하고, 확보한 동두천(DDC) 원문을 변경 없이 A1에 넣어 재사용 가능 여부와 필요한 최소 후속 변경을 판정한다.

**Architecture:** 기존 A1의 source snapshot, rowless preparation cache, locator, scoped binding/extraction/validation을 읽기 전용으로 실행한다. 네 출처의 조사와 DDC 적합성 평가가 첫 독립 산출물이며, 원문 차이를 모르는 상태에서 전용 adapter나 공통 계약을 만들지 않는다. 원문 확보 또는 적합성 gate가 실패하면 근거 있는 차단/차이 보고서를 남기며 지원 완료로 계산하지 않는다.

**Tech Stack:** 현재 저장소의 PowerShell 7 스크립트, Git, 기존 실행 환경의 공개 HTTP 조회 수단. 새 라이브러리·provider·인증·DB 없음.

**Spec:** `docs/superpowers/specs/2026-09-25-phase2-a2-source-inventory-ddc-pilot-design.md`, reviewed version `d7d4c1edff44f2c8623d4b679be08d08d507907c`.

**Status:** PROPOSED PLAN — 실행 계획 사용자 검토 대기. 2026-09-25 사용자의 진행 승인은 설계서 검토 후 이 계획 작성까지다. 제품 구현, 원격 병합, 아직 없는 후속 adapter 계획을 승인한 것으로 확대하지 않는다. 설계서 본문의 이전 PROPOSED 표시는 작성 시점 상태이며, 승인 checkpoint는 Issue #62와 PR #63에 기록한다.

**Pinned code baseline:** `dev@71b8e28518b95429cf878e0d8b3baf2b2ba2ebde` (A1 closeout, PR #61). 계획 실행 시 최신 dev와 대조한다.

## Global Constraints

다음 문장은 승인 설계서의 제약을 그대로 적용한다.

- 원본 `BenefitSourceDocument`와 snapshot text는 변경하지 않는다. caption/header/cell은 원본 절대 위치로 검증한다.
- `SourceRowNumber`는 canonical의 원본 행 번호다. HTML physical row index와 구분하고, source-level cache에 넣지 않는다.
- qualification과 business binding, 선택된 slice, claim과 state는 공유 캐시에 넣지 않는다.
- header를 다른 글자로 덮어써 validator를 통과시키거나, 정규화한 mini-document를 원본처럼 사용하지 않는다.
- 페이지 전체의 할인 안내, 한시 행사, 표 밖 공통 조건을 모든 행에 자동으로 붙이지 않는다. 이번 DDC pilot은 기존 detail-only 계약을 유지한다.
- 원문 확보가 계속 막히면 조사 산출물만 마무리하고 DDC 구현은 보류한다. 접근 실패가 새로운 provider·인증·라이브러리 도입을 자동 승인하지 않는다.

추가 실행 경계:

- `data/canonical/**`, `data/seed/**`, `apps/**`, 현재 `tools/data/**`, runtime 계약 및 workflow를 수정하지 않는다. 이 A2.1 실행의 커밋 산출물은 아래 두 Markdown 보고서뿐이다.
- 기존 비교 도구의 historical 판정이나 parser 출력으로 expected truth를 만들지 않는다. 합성·파생 자료와 원문 capture를 구분한다.
- 최초 조사 대상은 아래 일곱 exact entry resource다. 다른 host/detail/attachment/검색/API는 자동으로 따라가지 않고 관계와 미조회 사유를 기록한다.
- `ProductionAction=NONE`, 기본 legacy 동작, currentness/lifecycle 판정은 변경하지 않는다. LLM/PDF/XLSX/HWP/OCR/SNS/검색 provider는 비대상이다.
- A2.1 완료는 조사·적합성 판정 산출물 완료다. DDC 지원 완료, A2 전체 완료, Phase 2 완료와 구분한다.
- 실행하지 않은 명령을 통과로 적지 않는다. 사용자의 PC에서 중복 수동 테스트를 기본 요구하지 않는다.

## Review Focus

1. 리다이렉트·접근 차단·오래된 웹 캐시를 새 원문으로 취급하지 않는다. Task 1에서 직접 2xx 응답/실제 URL/시점/바이트가 없으면 원문 gate를 닫는다.
2. 인코딩·압축·BOM·줄바꿈 변경이 원문 hash와 span을 바꾸지 않게 한다. Task 2에서 전송 바이트와 decoded text의 서로 다른 hash, .NET UTF-16 offset 기준을 검증한다.
3. 알려진 다른 표·동명 업체·공통 프로그램을 잘라내 단일 일치를 만들지 않는다. Task 2의 독립 oracle과 Task 3의 원문 전체 입력/정확한 cell reference 대조로 확인한다.
4. replay 조회 시각을 실시간 확인일로 잘못 기록하지 않는다. Task 3에서 원문 ObservedAt을 직접 문서 생성에 사용하고, runner replay의 새 시각·invoker 횟수는 별도로 표시한다.
5. 데이터·실행환경·오라클이 없는데 성공이나 100%를 보고하지 않는다. Task 4에서 접근 불가·미지원·차이를 분모와 보고서에 남기고, positive 근거 없는 재사용 성공을 거부한다.

---

## Delivery boundary and file map

### 이번 계획 작성 PR #63

- 이 계획 파일 추가.
- 기존 설계서와 `docs/ai-development.md`는 같은 문서 PR에 포함된 상태를 유지.
- Issue #62는 계획 경로까지 예약되었으며 제품 구현은 여전히 비대상.

### 계획 승인 후 A2.1 실행 Issue / branch

새 실행 Issue를 만들고 다음 두 경로만 예약한다. 기존 문서 PR #63이 dev에 병합되었거나 사용자가 승인한 별도 기준선이 확정된 뒤 실행 브랜치를 만든다. 미병합 설계 브랜치 위에서 조용히 구현하지 않는다.

| 파일 | 책임 |
| --- | --- |
| `docs/handover/2026-09-25-phase2-a2-source-inventory.md` | 일곱 자원의 직접 관측/미관측, 응답 형태, 완전성, 첨부·상세 의존성, 조회 실패 기록 |
| `docs/handover/2026-09-25-phase2-a2-ddc-reuse-assessment.md` | 원문·오라클 출처, A1 적합성 실행 결과, 재사용/차이/차단 판정, 후속 범위와 검증 한계 |

실행 브랜치 제안: `codex/phase2-a2-1-source-inventory-ddc-reuse`.

원문 body, 응답 header, capture metadata, canonical snapshot, 독립 oracle, probe 스크립트와 로그는 OS 임시 작업 폴더에 보관한다. 이것은 일회성 조사 자료이며 새 runtime storage/JSON 계약이 아니다. HTTP header/cookie/token·불필요한 개인정보·전체 원문을 GitHub에 자동 업로드하지 않는다. 재현에 필요한 자료의 승인된 보관 위치와 hash를 보고한다. 보관 적합성이 불명확하거나 접근 가능한 보관 위치가 없으면 보고서에 제한을 남긴다.

DDC snapshot 회귀를 CI에 넣거나 adapter를 고쳐야 한다면 실제 원문 차이와 보관 정책을 확인한 별도 계획/Issue에서 production/test/fixture 파일을 예약한다. 이 계획은 알 수 없는 parser 수정 파일을 미리 승인하지 않는다.

## Preflight — 실행 승인 후 Task 1에 포함

문제는 실제 구조를 모르는 상태에서 source support를 주장하는 것이다. 범위는 공개 entry inventory와 DDC read-only replay이며, production/data 변경은 없다. 검증은 capture hash·독립 원문 oracle·기존 A1 실행·기존 회귀와 최종 문서 diff다. 위험은 접근 실패, 인코딩/위치 손상, source scope 축소, 재생 결과를 live audit로 오인하는 것이다.

- [ ] 최신 GitHub의 PR #61/#63, Issue #62와 새 실행 Issue, `AGENTS.md`, `docs/current-work.md`, `docs/ai-development.md`, `docs/team-workflow.md`, spec과 plan을 확인한다. 과거 current-work 진행표가 A1 병합 기록보다 오래되면 병합된 코드를 우선하고 차이를 기록한다.
- [ ] 격리 clone/worktree의 브랜치·dirty/untracked 상태를 확인한다. 다른 작업의 파일은 덮어쓰거나 stash/reset하지 않는다. 보고서 경로와 다른 활성 Issue 예약이 겹치지 않는지 확인한다.
- [ ] 아래를 실행하고 로그에 실제 결과를 기록한다. pwsh가 없으면 설치했다고 가정하거나 CI에 live-network 테스트를 심지 않는다. 읽기 조사까지만 수행하고 executable probe를 NOT_RUN으로 남긴다.

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

Expected: 정상 환경에서는 실제 SHA/실행 위치/PowerShell 버전/hash가 남는다. 환경 실패는 BLOCKED_ENVIRONMENT이며 데이터 문제나 혜택 종료가 아니다. 계획 작성 시 이 명령들을 실행한 것으로 표시하지 않는다.

## Task 1: Seven-resource capability inventory and bounded capture

**Files:** Create `docs/handover/2026-09-25-phase2-a2-source-inventory.md`.

**Interfaces:** Consumes exact entry URLs below, pinned code and canonical hash. Produces resource records plus a DDC capture directory only when actual acquisition succeeds. Later tasks consume the capture, not a web summary.

- [ ] **Step 1: 고정 조사 목록을 기록한다.** 이 목록은 현재 코드의 entry URL이지 현재 혜택 유효성을 확인한 목록이 아니다.

| ID | Family | Exact entry URL |
| --- | --- | --- |
| DDC-1 | DDC | `https://www.ddc.go.kr/ddc/contents.do?key=1570` |
| PAJU-1001 | Paju | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001` |
| PAJU-1002 | Paju | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1002` |
| PAJU-1004 | Paju | `https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1004` |
| MMA-1 | MMA | `https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357` |
| YANGJU-LEGACY | Yangju | `https://www.yangju.go.kr/www/selectBbsNttView.do?bbsNo=13&key=202&nttNo=198019` |
| YANGJU-ALTERNATE | Yangju | `https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761` |

- [ ] **Step 2: 승인된 공개 조회 환경에서 자원당 한 번 캡처한다.** 이미 사용 가능한 curl 실행 파일의 아래 one-shot 명령을 사용할 수 있다. 이것은 수동 조사 명령이지 application RequestInvoker/provider의 교체 구현이 아니다. 로그인·proxy·인증서 검증 해제·자동 redirect·무제한 retry는 추가하지 않는다. curl이 없거나 네트워크가 차단되면 그 환경 제한을 기록한다.

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

Expected: 七つの試行ではなく **일곱 자원의 시도 기록**이 남는다. `CurlExitCode=0`만으로 성공이라고 하지 않는다. 실제 HTTP 2xx와 요청/실제 URL, 완전한 body, media type을 확인한다. 3xx는 redirect 미조회, HTTP 오류·timeout·크기 초과·도구 오류는 원문 gate 실패다. redirect Location은 조사 관계만 기록하고 이 실행에서 자동 추적하지 않는다. 향후 안전한 별도 요청이 필요하면 bounded 범위를 다시 확인한다. 부분 다운로드를 정상 원문으로 재사용하지 않는다.

- [ ] **Step 3: 원문과 header를 읽어 inventory를 채운다.** 자원마다 시각·방법·HTTP 관찰·형식/encoding·hash/보관 위치·caption/header·업체/혜택 근거 위치·pagination/detail/attachment 관계·현재성 근거 위치·보관 적합성을 기록한다. 실제 읽지 않은 항목은 미확인이라고 적고 이유를 함께 쓴다. 웹 도구의 cached/rendered 텍스트는 별도 관찰 종류로 남기며 raw capture 상태를 성공으로 바꾸지 않는다.
- [ ] **Step 4: completeness를 자원 단위로 판정한다.** 성공한 HTML 응답 하나와 사이트 전체 목록 완전성은 다르다. 일곱 entry를 모두 보고하고, 못 읽은 page/category/attachment를 제거하지 않는다. 파주의 외부 상세 지도, 병무청 검색/API, 양주 한시/상시 첨부는 관찰된 링크만 기록하고 내용을 추정하지 않는다.
- [ ] **Step 5: 보고서만 커밋한다.** 원문·쿠키·기술 로그나 실제 혜택 변경은 stage하지 않는다.

```powershell
git add -- docs/handover/2026-09-25-phase2-a2-source-inventory.md
git diff --cached --stat
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Inventory documentation whitespace check failed' }
git commit -m 'docs: inventory official source entry capabilities'
```

Task acceptance: 일곱 자원 모두 접근 결과와 미확인 범위를 갖는다. DDC capture 실패 시에도 inventory는 유효한 조사 결과지만 DDC 지원 성공은 아니다. Task 2/3의 실행 불가 사유를 Task 4에 넘긴다.

## Task 2: Pin DDC text and independent source expectations

**Files:** Start `docs/handover/2026-09-25-phase2-a2-ddc-reuse-assessment.md`; private capture/oracle under `$captureRoot/DDC-1`, not committed.

**Interfaces:** Consumes Task 1's complete DDC body and response metadata. Produces unmodified decoded `source.txt`, original observation timestamp, text/byte hashes, and an independently authored `expected.psd1` for Task 3. This PSD1 is test-only local input, not a public runtime schema.

- [ ] **Step 1: capture gate를 확인한다.** 직접 확보한 complete 2xx HTML인지 확인한다. 다른 format, redirect/차단, 빈 body, cookie/login requirement는 BLOCKED_CAPTURE 또는 UNSUPPORTED_INPUT으로 기록한다. 이후 A1 probe를 성공 실행했다고 쓰지 않는다.
- [ ] **Step 2: encoding과 content encoding을 직접 확인하고 text를 고정한다.** 전송 bytes hash와 UTF-8 text hash는 별개다. 압축 또는 charset 판독이 불명확하면 bytes를 임의 UTF-8로 해석하지 않고 BLOCKED_DECODE로 남긴다. 승인된 기존 decoder로 lossless text가 확보됐을 때만 진행한다. `<meta charset>`와 HTTP charset이 충돌하면 해석 근거를 기록하고 해결 전에는 probe하지 않는다.

아래는 **HTTP header에서 UTF-8, 압축 없음이 확인된 capture**의 완전한 처리 예다. 다른 인코딩 입력에는 이 예를 억지로 적용하지 않는다.

```powershell
$ddcDir = Join-Path $captureRoot 'DDC-1'
$rawBytes = [IO.File]::ReadAllBytes((Join-Path $ddcDir 'body.bin'))
$decoder = [Text.UTF8Encoding]::new($false, $true)
$text = $decoder.GetString($rawBytes)
if ([string]::IsNullOrWhiteSpace($text)) { throw 'DDC capture is empty; no source support claim' }
[IO.File]::WriteAllText((Join-Path $ddcDir 'source.txt'), $text, [Text.UTF8Encoding]::new($false))
. ./tools/data/lib/benefit-evidence-location-contracts.ps1
$textHash = Get-BenefitEvidenceTextHash -Text $text
$byteHash = (Get-FileHash -LiteralPath (Join-Path $ddcDir 'body.bin') -Algorithm SHA256).Hash.ToLowerInvariant()
$transport = Get-Content -Raw -LiteralPath (Join-Path $ddcDir 'transport.private.json') | ConvertFrom-Json
$observedAt = [string]$transport.CompletedAt
Assert-ScopeTimestamp $observedAt
@("ByteSha256=$byteHash", "TextSha256=$textHash", "ObservedAt=$observedAt", 'Encoding=UTF-8') |
    Set-Content -LiteralPath (Join-Path $ddcDir 'decoded-evidence.txt') -Encoding utf8
```

BOM・줄바꿈·주석·다른 표를 제거하지 않는다. 파일 읽기/쓰기 과정에서 source string이 동일한지 `ReadAllText` 후 ordinal equality와 text hash로 대조한다. `RawStart/RawLength` 등은 .NET string의 UTF-16 code-unit offset이며 raw bytes offset이 아니다.

- [ ] **Step 3: parser를 실행하기 전에 source oracle을 만든다.** 원문 전체에서 실제 DDC 혜택 표, caption/header, 최소 두 개의 서로 다른 업체 행과 각 할인 cell을 직접 대조한다. 두 positive 사례를 확보할 수 없으면 그 사실을 기록한다. 원문상 동명 후보·주소 모순은 제거하지 않는다. A1 parser/locator 결과에서 기대값을 복사하지 않는다.

`expected.psd1`의 정확한 local 형식:

- Root: `EvidenceKind` (`DIRECT_CAPTURE_ORACLE`), `SourceUrl`, `ObservedAt`, `TextSha256`, `ByteSha256`, `CanonicalSha256`, `AuthoringMethod` (`DIRECT_RAW_INSPECTION`), `Cases` (array).
- 각 case: `SourceRowNumber` (고정 canonical CSV의 실제 행 번호, 2 이상), `UnitReference`, `RawStart`, `RawLength`, `Fields` (dictionary).
- 각 Fields 항목의 key는 실제 원문에 있는 A1 필드명이다. 값은 `Value`, `OriginalHeader`, `FieldReference`, `HeaderStart`, `HeaderLength`, `CellStart`, `CellLength`를 갖는다.
- `FieldReference`는 직접 확인한 physical `HTML_TABLE_<n>_ROW_<n>/<FieldName>`이고 `RawStart/RawLength`는 원래 row span이다. 숫자·문자열의 실제 값은 이번 원문 조사 산출물이며 이 계획이 미리 만들지 않는다.
- 적어도 `BusinessName`과 `BenefitDescription` 필드를 갖는 두 positive case를 선정한다. 같은 할인 문자열이 반복돼도 reference가 다른지 검증한다.
- canonical 행은 입력 대상일 뿐 source의 빈 이름·주소·전화·할인 cell을 채우는 데이터로 쓰지 않는다. canonical과 source가 충돌하면 해당 위험 사례를 보고서에 남기고 긍정 기대값으로 바꾸지 않는다.

데이터 읽기 및 oracle 검사:

```powershell
$oracle = Import-PowerShellDataFile -LiteralPath (Join-Path $ddcDir 'expected.psd1')
if ($oracle.EvidenceKind -cne 'DIRECT_CAPTURE_ORACLE' -or $oracle.AuthoringMethod -cne 'DIRECT_RAW_INSPECTION') {
    throw 'Independent direct-source oracle required'
}
if ($oracle.TextSha256 -cne $textHash -or $oracle.ByteSha256 -cne $byteHash -or $oracle.CanonicalSha256 -cne $canonicalHash) {
    throw 'Oracle belongs to different source or canonical input'
}
if ($oracle.ObservedAt -cne $observedAt -or $oracle.SourceUrl -cne 'https://www.ddc.go.kr/ddc/contents.do?key=1570') {
    throw 'Oracle source identity mismatch'
}
if (@($oracle.Cases).Count -lt 2) { throw 'Insufficient independent positive controls; not a reuse success' }
foreach ($case in $oracle.Cases) {
    if ($case.SourceRowNumber -le 1 -or $case.RawStart -lt 0 -or $case.RawLength -le 0 -or ($case.RawStart + $case.RawLength) -gt $text.Length) {
        throw 'Invalid independently recorded row span'
    }
    foreach ($fieldName in $case.Fields.Keys) {
        $field = $case.Fields[$fieldName]
        $sourceCell = $text.Substring([int]$field.CellStart, [int]$field.CellLength)
        $sourceHeader = $text.Substring([int]$field.HeaderStart, [int]$field.HeaderLength)
        # This display is for raw cross-check, never automatic oracle generation.
        Write-Host $case.UnitReference $fieldName $sourceHeader $sourceCell
    }
}
```

- [ ] **Step 4: 보관 적합성을 판단한다.** 원문·오라클이 공개 재배포에 적합한지는 별도 확인한다. 원문 전체를 익명화/절단하면 새 파생 자료이고 원본 hash/span/support proof를 승계하지 못한다. 보고서에는 hash, 수집 시각, source URL, oracle 작성자/방식, 승인된 보관 위치 또는 보관 제한을 남긴다. A3의 human audit와 agent의 direct inspection을 구분한다.

Expected: 실제 원문과 독립 기대값이 연결되거나 명시적인 차단 결과가 생긴다. 예상값이 없다는 이유로 parser가 낸 값을 기대값으로 삼지 않는다.

## Task 3: Read-only A1 compatibility probe and regression evidence

**Files:** Update the DDC assessment report. Probe commands below run only in the private workspace. No production parser/contract edits.

**Interfaces:** Consumes Task 2's exact source text/oracle and original canonical rows. Uses `ConvertTo-BenefitHtmlObservation -Document`, `Find-BenefitBusinessEvidence -Observation -Business -CanonicalPhone`, `Get-QualifiedBenefitSource`, existing scoped binding/extraction/validation. Produces source-grounded positives, failure diagnostics and a reusable-input or demonstrated-gap decision.

- [ ] **Step 1: 먼저 두 원문 positive를 검증한다.** 아래 코드는 baseline 적합성 probe다. 현재 동작이 이미 맞으면 PASS를 baseline 증거로 기록하며 가짜 RED 이력을 만들지 않는다. 실패하면 메시지와 exact input hash를 차이 증거로 남기고 코드를 수정하지 않는다.

```powershell
. ./tools/data/testdata/benefit-evidence-location/test-support.ps1
. ./tools/data/lib/benefit-evidence/convert-html-source-observation.ps1
. ./tools/data/lib/benefit-evidence/find-business-evidence-slice.ps1
. ./tools/data/lib/benefit-source/qualify-official-benefit-source.ps1
. ./tools/data/lib/benefit-evidence/extract-benefit-evidence.ps1
. ./tools/data/lib/benefit-evidence/validate-benefit-evidence.ps1
$canonicalRows = @(Import-Csv -LiteralPath $canonicalPath -Encoding utf8)
$probeFailures = [Collections.Generic.List[string]]::new()
foreach ($case in $oracle.Cases) {
    try {
        $rowNumber = [int]$case.SourceRowNumber
        if ($rowNumber -gt ($canonicalRows.Count + 1)) { throw 'Oracle row outside pinned canonical input' }
        $row = $canonicalRows[$rowNumber - 2]
        Assert-ScopeEqual ([string]$row.'출처URL') $oracle.SourceUrl 'Canonical source URL must match the captured resource'
        $business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber $rowNumber
        $document = New-BenefitSourceDocument -SourceRowNumber $rowNumber -Url $oracle.SourceUrl -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text $text -ObservedAt $oracle.ObservedAt
        $observation = ConvertTo-BenefitHtmlObservation -Document $document
        Assert-ScopeEqual $observation.AdapterStatus 'COMPLETE' 'Full unmodified response must be supported'
        $location = Find-BenefitBusinessEvidence -Observation $observation -Business $business -CanonicalPhone ([string]$row.'업소전화번호')
        Assert-ScopeEqual $location.Status 'LOCATED' 'Independently matched business must be located'
        $slice = $location.Slices[0]
        Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $document -SourceRowNumber $rowNumber
        Assert-ScopeEqual $slice.EvidenceReference $case.UnitReference 'Do not select another physical row'
        Assert-ScopeEqual $slice.RawStart $case.RawStart 'Original row start survives'
        Assert-ScopeEqual $slice.RawLength $case.RawLength 'Original row length survives'
        foreach ($fieldName in $case.Fields.Keys) {
            $expected = $case.Fields[$fieldName]
            Assert-ScopeEqual $slice.StructuredFields[$fieldName] $expected.Value 'Exact independently inspected value survives'
            $actual = $slice.FieldReferences[$fieldName]
            foreach ($key in @('OriginalHeader','FieldReference','HeaderStart','HeaderLength','CellStart','CellLength')) {
                Assert-ScopeEqual $actual.$key $expected[$key] ('Original field provenance: ' + $key)
            }
        }
        $candidate = New-BenefitSourceCandidate -SourceRowNumber $rowNumber -Url $oracle.SourceUrl -SourceKind PUBLIC_OFFICIAL -SourceLabel 'DDC captured official source' -DiscoveryMethod 'OFFLINE_CAPTURE_REPLAY' -ObservedAt $oracle.ObservedAt
        $qualified = Get-QualifiedBenefitSource -Candidate $candidate -Document $document -Business $business
        Assert-ScopeEqual $qualified.OfficialityStatus 'VERIFIED_OFFICIAL' 'Existing qualification remains required'
        $bound = Get-BenefitBusinessBinding -Source $qualified -Business $business -CanonicalPhone ([string]$row.'업소전화번호') -EvidenceSlice $slice
        Assert-ScopeEqual $bound.BusinessBindingStatus 'STRONG' 'Selected evidence must independently bind'
        $extraction = Invoke-BenefitEvidenceExtraction -Source $bound -Document $document -EvidenceSlice $slice
        $validated = ConvertTo-ValidatedBenefitEvidence -Extraction $extraction -Document $document -EvidenceSlice $slice
        $benefitClaims = @($validated.Claims | Where-Object { $_.ClaimType -ceq 'BENEFIT_DESCRIPTION' -and $_.ValidationStatus -ceq 'VALIDATED' })
        Assert-ScopeEqual $benefitClaims.Count 1 'One selected benefit field, not the whole page'
        Assert-ScopeEqual $benefitClaims[0].Value $case.Fields.BenefitDescription.Value 'Own source value only'
        Assert-ScopeEqual $benefitClaims[0].EvidenceReference $case.Fields.BenefitDescription.FieldReference 'Own source cell only'
        Assert-ScopeEqual @($validated.Claims | Where-Object { $_.ClaimType -in @('BENEFIT_EXISTENCE','CURRENT_APPLICABILITY','VALID_FROM','VALID_UNTIL') }).Count 0 'No new lifecycle inference'
        Write-Host ('PASS DDC direct-capture positive row ' + $rowNumber)
    } catch {
        $probeFailures.Add(('Row ' + $case.SourceRowNumber + ': ' + $_.Exception.Message))
    }
}
if ($probeFailures.Count -gt 0) {
    $probeFailures | Set-Content -LiteralPath (Join-Path $ddcDir 'compatibility-gap.txt') -Encoding utf8
    throw 'DDC compatibility gap demonstrated; no source-support completion'
}
```

Expected: 양성 사례 모두 정확한 원문 row/cell을 유지하거나 구체적인 차이가 재현된다. 실행 예외, false selection, 구조 불완전성, canonical identity conflict를 서로 구분한다. 단일 case만 통과하고 나머지를 삭제하여 통과로 바꾸지 않는다.

- [ ] **Step 2: 원문 변조 거부를 별도로 확인한다.** Step 1에서 성공한 slice의 deep copy를 변경한 뒤 원본 문서로 거부되는지 확인한다. 이 변조 입력은 test-only이며 실제 DDC 혜택 주장으로 기록하지 않는다.

```powershell
$badSlice = Copy-ScopeContractData $slice
$badSlice.StructuredFields['BenefitDescription'] = '__SYNTHETIC_TAMPER_NOT_SOURCE__'
Assert-ScopeThrows {
    Assert-RelevantBenefitEvidenceSlice -Slice $badSlice -Document $document -SourceRowNumber $document.SourceRowNumber
} 'Changed value cannot certify itself with unchanged original provenance'
$badUrlDocument = New-BenefitSourceDocument -SourceRowNumber $document.SourceRowNumber -Url 'https://city.example.go.kr/not-the-original' -SourceFormat HTML -FetchStatus COMPLETE -Text $text -ObservedAt $oracle.ObservedAt
Assert-ScopeThrows {
    Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $badUrlDocument -SourceRowNumber $document.SourceRowNumber
} 'Same text at another URL cannot inherit captured provenance'
```

Expected: 두 변조를 거부한다. positive gate가 실패한 경우 이 코드를 성공한 원문 사례처럼 실행하지 않고 Task 4로 이동한다.

- [ ] **Step 3: 같은 capture의 parse reuse를 측정한다.** 원문 시각을 유지한 fresh document 두 개를 A1.4 context에 넣는다. 이 probe는 live fetch를 수행하지 않는다.

```powershell
. ./tools/data/lib/benefit-evidence/benefit-source-run-context.ps1
$context = New-BenefitSourceRunContext
$observations = @()
foreach ($case in @($oracle.Cases | Select-Object -First 2)) {
    $doc = New-BenefitSourceDocument -SourceRowNumber $case.SourceRowNumber -Url $oracle.SourceUrl -SourceFormat HTML -FetchStatus COMPLETE -Text $text -ObservedAt $oracle.ObservedAt
    $observations += Get-BenefitRunHtmlObservation -Context $context -Document $doc
}
Assert-ScopeEqual $context.Metrics.AdapterParseCount 1 'Same captured snapshot parses once'
Assert-ScopeEqual $context.Metrics.AdapterReuseCount 1 'Second row reuses parse template'
Assert-ScopeEqual $context.Metrics.ExternalFetchCount 0 'Offline probe must not claim a live fetch'
Assert-ScopeEqual $observations[0].ObservedAt $oracle.ObservedAt 'Original observation time remains original'
Assert-ScopeTrue (-not [object]::ReferenceEquals($observations[0], $observations[1])) 'Independent row wrappers'
```

runner의 fake RequestInvoker로 추가 replay를 수행한다면 원문 capture 시각과 replay 시각을 함께 적는다. runner가 새로 만드는 ObservedAt은 live 재조회 증거가 아니다. `ExternalFetchCount`도 fake invoker 호출 수이며 실제 network request 수로 보고하지 않는다. `-OperationalLiveRun`을 사용하지 않는다.

- [ ] **Step 4: 기존 안전 회귀를 실행한다.** 다른 업체의 종료 문구, strong+name-only 대안, hard-number/floor/unit/phone conflict, PARTIAL/UNSUPPORTED, positional/named 호출, fetch/parse reuse와 protected export는 기존 테스트를 보존한다.

```powershell
$tests = @(
    'test-benefit-evidence-location-contracts.ps1',
    'test-convert-html-source-observation.ps1',
    'test-find-business-evidence-slice.ps1',
    'test-benefit-source-run-context.ps1',
    'test-bind-benefit-source.ps1',
    'test-extract-benefit-evidence.ps1',
    'test-validate-benefit-evidence.ps1',
    'test-phase2-scoped-html.ps1',
    'test-phase2-benefit-shadow-mode.ps1',
    'test-phase1-poi-shadow-mode.ps1'
)
foreach ($name in $tests) {
    pwsh -NoProfile -File (Join-Path tools/data $name)
    if ($LASTEXITCODE -ne 0) { throw ('Existing regression failed: ' + $name) }
}
```

Expected: 기존 안전 계약을 유지한다. 이 합성 회귀 PASS만으로 DDC live source 지원이나 전체 source-family precision을 주장하지 않는다. 환경상 실행하지 못하면 NOT_RUN이며 실제 CI 결과와 구분한다.

## Task 4: Decision, truthful closeout and next delivery gate

**Files:** Finalize both handover reports; no production changes.

**Interfaces:** Consumes inventory, capture/expectation evidence and observed test outputs. Produces an auditable decision for the next small delivery, not an automatic adapter implementation.

- [ ] **Step 1: DDC 판정을 셋 중 하나로 확정한다.**

| Outcome | 필요한 근거 | 다음 작업 |
| --- | --- | --- |
| REUSE_VERIFIED_FOR_CAPTURE | 직접 캡처·독립 positive 2개 이상·정확한 원문 provenance·안전 회귀·parse reuse 측정 | snapshot 범위만 재사용 가능으로 기록. 재배포 가능한 고정 fixture/CI 회귀를 별도 파일 예약 후 계획. 필요 없는 adapter를 만들지 않음 |
| GAP_REPRODUCED | 동일 hash 원문에서 재현된 실패·기대/실제 차이·영향 범위 | 차이만 해결하는 A2.2 bounded 설계 또는 공통 계약 영향 설계. TDD RED→GREEN 계획과 정확한 파일 예약을 사용자에게 검토받음 |
| BLOCKED_EVIDENCE_OR_ENVIRONMENT | capture/decode/oracle/runtime/보관 제약 중 무엇이 부족한지와 시도 결과 | 조사 보고서를 완료하되 DDC 구현은 보류. 출처 변경이나 새 도구 도입은 별도 결정 |

이 분기는 조사 결과로 결정하는 gate이지 빈 구현 항목이 아니다. 근거 없는 `DDC_ADAPTER`·header alias·URL resolver 구현을 계획에 끼워 넣지 않는다.

- [ ] **Step 2: 보고서의 수치와 상태를 대조한다.** 일곱 entry 기록을 유지하고 원문 확보/미확보/미지원/미확인 개수를 나눈다. DDC에는 입력 hash, 원문 대조 case 수, 정확한 row/field 선택 수, 실패별 사유, replay의 network 0, 실제 실행/NOT_RUN 명령을 적는다. 사람 감사는 `NOT_RUN`이고 population precision/recall·false-GREEN/ENDED 수치는 측정하지 않았으면 null이다.
- [ ] **Step 3: scope와 non-write를 확인한다.** 다음 명령에서 `$codeBase`는 preflight에서 기록한 SHA를 계속 사용한다. 원격 dev가 움직였다고 과거 비교 기준을 바꾸지 않는다.

```powershell
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'Whitespace error' }
git diff --exit-code $codeBase -- data/canonical data/seed apps tools/data .github
if ($LASTEXITCODE -ne 0) { throw 'Non-documentation delta detected' }
$currentCanonicalHash = (Get-FileHash -LiteralPath $canonicalPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($currentCanonicalHash -cne $canonicalHash) { throw 'Canonical input changed during read-only assessment' }
git status --short --untracked-files=all
git diff --name-only $codeBase
```

Expected: 보호 경로·현재 production/test/workflow 변경 없음, canonical hash 동일. dirty/untracked capture가 저장소 안에 있거나 credentials가 포함되면 stage하지 않는다. GitHub remote diff만 확인했다면 local dirty/untracked 확인까지 했다고 쓰지 않는다.

- [ ] **Step 4: 실행 검증을 마무리한다.** 코드가 바뀌지 않은 문서 실행 PR에서 과도한 중복 로컬 테스트를 강요하지 않는다. 실제 환경에서 Task 3 검증이 가능하면 전체 data suite의 두 실행 방식을 한 번씩 확인하고 기록한다. 불가능하면 이유와 exact-HEAD CI 근거를 분리한다.

```powershell
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object {
    pwsh -NoProfile -File $_.FullName
    if ($LASTEXITCODE -ne 0) { throw ('FAILED: ' + $_.Name) }
}
Get-ChildItem -LiteralPath tools/data -Filter 'test-*.ps1' | Sort-Object Name | ForEach-Object { & $_.FullName }
```

Expected: 수행한 방식의 전체 suite PASS. baseline 실패는 이번 문서 작업 때문에 생겼다고 단정하지 않지만 누락하지 않고 보고한다. CI에 별도 live 원문 조회를 추가하지 않는다.

- [ ] **Step 5: 보고서 커밋과 PR을 만들고 멈춘다.**

```powershell
git add -- docs/handover/2026-09-25-phase2-a2-source-inventory.md docs/handover/2026-09-25-phase2-a2-ddc-reuse-assessment.md
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw 'Staged documentation check failed' }
git diff --cached --stat
git commit -m 'docs: record DDC reuse evidence and source capability limits'
```

최종 branch HEAD를 push하고 base dev 문서 PR을 생성한다. `verify-data`/`verify`가 실행되면 그 HEAD의 결과만 보고한다. author self-review는 독립 reviewer/human audit로 표시하지 않는다. 승인 전 자동 merge나 A2.2 adapter 구현은 없다.

## Final report contract and progress

보고 항목: 변경 파일 두 개, 조사한 자원과 원문 확보 여부, DDC 세 가지 gate 중 결과, 실행한 명령과 실제 결과, 미실행 명령과 이유, raw/derived/replay/human-audit 구분, 보호 경로와 input hash, PR/HEAD/CI, 남은 위험과 다음 작은 작업.

진행률은 다음 범위를 구분한다.

- A1: 완료 (5/5 merged).
- 이 A2.1 계획: 승인 후 네 task의 산출물 상태를 보고하되 raw gate 실패를 구현 성공으로 세지 않는다.
- A2 전체: 출처별 지원 범위와 후속 작업 수가 아직 확정되지 않았으므로 전체 퍼센트를 계산하지 않는다.
- A3/Phase 2 전체: 이번 조사·DDC replay만으로 완료 처리하지 않는다.

## Plan author self-review and handoff

설계 1–5절의 의도/조사/재사용 원칙은 Task 1, 원문 및 독립 검증 gate는 Task 2–3, 공통 계약/실패/현재성 경계는 Global Constraints와 Task 3, 출처별 분리/완료/위험/A3 전달은 Task 4에 대응한다. 실제 원문 없는 adapter 설계는 이번 계획의 산출물이 아니며, 차이 확인 후 별도 승인 대상으로 명시했다.

계획의 code snippets는 **향후 실행 명령**이다. 이번 문서 작성에서 curl 원문 캡처, PowerShell probe, 전체 테스트, human audit가 수행됐다는 뜻이 아니다.

사용자가 이 계획을 검토하고 기존 Native/inline 실행 방식으로 진행을 확인하면 `executing-plans`로 Task 1부터 시작한다. PR #63 병합 권한은 별도 확인하며, 현재 승인 없는 제품 구현/병합은 하지 않는다.
