Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'invoke-benefit-seed-release-cut.ps1') -LibraryOnly

function Assert-ReleaseCutEqual {
    param(
        $Actual,
        $Expected,
        [string]$Message
    )

    if ($Actual -cne $Expected) {
        throw "Assertion failed: $Message (expected='$Expected', actual='$Actual')"
    }
}

function Assert-ReleaseCutFailure {
    param(
        [scriptblock]$Operation,
        [string]$ExpectedError
    )

    try {
        [void](& $Operation)
    } catch {
        if ($_.Exception.Message -match $ExpectedError) {
            return
        }
        throw
    }
    throw "Expected release cut to fail with $ExpectedError"
}

function Get-ReleaseCutFileHash {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$committedManifest = Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $repoRoot 'apps/android/app/src/main/assets/benefits.seed.manifest.json') | ConvertFrom-Json

# 1. Default DryRun verification against committed v14 repository assets
$dryRun = Invoke-BenefitSeedReleaseCut
Assert-ReleaseCutEqual $dryRun.Mode 'DRY_RUN' 'Default execution mode must be DRY_RUN'
Assert-ReleaseCutEqual $dryRun.SeedVersion 14 'SeedVersion should default to committed manifest seedVersion 14'
Assert-ReleaseCutEqual $dryRun.CanonicalCount 1137 'Canonical row count must match 1137'
Assert-ReleaseCutEqual $dryRun.CandidateCount 1018 'Candidate count must match 1018'
Assert-ReleaseCutEqual $dryRun.TotalCount 1018 'Total release seed count must match 1018'
Assert-ReleaseCutEqual $dryRun.ExactPinCount 998 'Exact pin count must match 998'
Assert-ReleaseCutEqual $dryRun.UnconfirmedCoordinateCount 20 'Unconfirmed coordinate count must match 20'
Assert-ReleaseCutEqual $dryRun.PublicEvidenceCount 757 'PUBLIC_EVIDENCE count must match 757'
Assert-ReleaseCutEqual $dryRun.LocalGovCount 261 'LOCAL_GOV count must match 261'
Assert-ReleaseCutEqual $dryRun.SeedSha256 ([string]$committedManifest.seedSha256) 'DryRun seedSha256 must deterministically match committed manifest'

# 2. Isolated temp -Apply packaging test and 3. Zero-Kakao coordinate guard test
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('milimap-release-cut-test-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($tempDir)
try {
    $canonicalCsv = Join-Path $tempDir 'canonical.csv'
    $ddcCsv = Join-Path $tempDir 'ddc.csv'
    $pajuCsv = Join-Path $tempDir 'paju.csv'
    $yangjuCsv = Join-Path $tempDir 'yangju.csv'
    $mmaCsv = Join-Path $tempDir 'mma.csv'
    $coordCsv = Join-Path $tempDir 'coord.csv'
    $manualJson = Join-Path $tempDir 'manual.json'
    $candOutCsv = Join-Path $tempDir 'out/candidates.csv'
    $destSeedJson = Join-Path $tempDir 'out/benefits.seed.json'
    $destManifestJson = Join-Path $tempDir 'out/benefits.seed.manifest.json'

    @(
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000001'; 업종명='음식'; 업소명='동두천테스트'; 시도='경기도'; 시군구='동두천시'; 소재지도로명주소='경기도 동두천시 평화로 10'; 소재지지번주소=''; 위도='37.9035'; 경도='127.0555'; 좌표출처='소상공인 상가정보(공공누리1유형)'; 좌표출처URL='https://apis.data.go.kr/B553077/api/open/sdsc2'; 좌표검증상태='확인 완료'; 할인정보='10% 할인'; 적용대상='현역병'; 이용조건='없음'; 인증방법='신분증'; 업소전화번호='031-860-0001'; 출처유형='지자체 공식 자료'; 출처URL='https://www.ddc.go.kr/ddc/contents.do?key=1570'; 최근확인일='2026-11-20'; 혜택상태='이용 가능'; 수집자='tester'; 비고='' },
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000002'; 업종명='음식'; 업소명='파주테스트'; 시도='경기도'; 시군구='파주시'; 소재지도로명주소='경기도 파주시 중앙로 20'; 소재지지번주소=''; 위도='37.7600'; 경도='126.7800'; 좌표출처='행정안전부 위치정보요약DB(2026-10)'; 좌표출처URL='https://business.juso.go.kr'; 좌표검증상태='재확인 필요'; 할인정보='10% 할인'; 적용대상='현역병'; 이용조건='없음'; 인증방법='휴가증'; 업소전화번호='031-940-0002'; 출처유형='지자체 공식 자료'; 출처URL='https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001'; 최근확인일='2026-11-22'; 혜택상태='이용 가능'; 수집자='tester'; 비고='' },
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000003'; 업종명='음식'; 업소명='양주테스트'; 시도='경기도'; 시군구='양주시'; 소재지도로명주소='경기도 양주시 부흥로 30'; 소재지지번주소=''; 위도='37.7850'; 경도='127.0450'; 좌표출처='소상공인 상가정보(공공누리1유형)'; 좌표출처URL='https://apis.data.go.kr/B553077/api/open/sdsc2'; 좌표검증상태='확인 완료'; 할인정보='10% 할인'; 적용대상='현역병'; 이용조건='없음'; 인증방법='신분증'; 업소전화번호='031-808-0003'; 출처유형='지자체 공식 자료'; 출처URL='https://www.yangju.go.kr/health/selectBbsNttView.do?key=2716&bbsNo=81&nttNo=206761'; 최근확인일='2026-11-22'; 혜택상태='이용 가능'; 수집자='tester'; 비고='' },
        [pscustomobject][ordered]@{ businessId='biz-00000000000000000000000000000004'; 업종명='병원'; 업소명='병무청테스트'; 시도='서울특별시'; 시군구='강남구'; 소재지도로명주소='서울특별시 강남구 테헤란로 40'; 소재지지번주소=''; 위도='37.5000'; 경도='127.0360'; 좌표출처='행정안전부 위치정보요약DB(2026-10)'; 좌표출처URL='https://business.juso.go.kr'; 좌표검증상태='확인 완료'; 할인정보='비급여 20% 할인'; 적용대상='동원훈련이수자'; 이용조건='없음'; 인증방법='이수증'; 업소전화번호='02-555-0004'; 출처유형='공공데이터'; 출처URL='https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'; 최근확인일='2026-11-23'; 혜택상태='이용 가능'; 수집자='tester'; 비고='' }
    ) | Export-Csv -LiteralPath $canonicalCsv -NoTypeInformation -Encoding utf8

    @([pscustomobject][ordered]@{ 정본CSV행번호='2'; 업소명='동두천테스트'; 소재지도로명주소='경기도 동두천시 평화로 10'; 공식할인정보='10% 할인'; 판정='현재 공식 목록 일치 후보'; 검토결정='승인(tester)'; 확인일='2026-11-20' }) | Export-Csv -LiteralPath $ddcCsv -NoTypeInformation -Encoding utf8
    @([pscustomobject][ordered]@{ 정본CSV행번호='3'; 업소명='파주테스트'; 소재지도로명주소='경기도 파주시 중앙로 20'; 공식출처URL='https://www.paju.go.kr/user/soldier/BD_discountStoreList.do?q_ctgCd=1001'; 판정='공식 참여업소 일치 후보'; 검토결정='승인(tester)'; 확인일='2026-11-22' }) | Export-Csv -LiteralPath $pajuCsv -NoTypeInformation -Encoding utf8
    @([pscustomobject][ordered]@{ 정본CSV행번호='4'; 업소명='양주테스트'; 소재지도로명주소='경기도 양주시 부흥로 30'; 공식메뉴='불고기'; 공식할인정보='10% 할인'; 판정='현재 공식 목록 일치 후보'; 검토결정='승인(tester)'; 확인일='2026-11-22' }) | Export-Csv -LiteralPath $yangjuCsv -NoTypeInformation -Encoding utf8
    @([pscustomobject][ordered]@{ 정본CSV행번호='5'; 업소명='병무청테스트'; 소재지도로명주소='서울특별시 강남구 테헤란로 40'; 공식할인정보='비급여 20% 할인'; 판정='현재 공식 목록 일치 후보'; 검토결정='승인(tester)'; 확인일='2026-11-23' }) | Export-Csv -LiteralPath $mmaCsv -NoTypeInformation -Encoding utf8

    @(
        [pscustomobject][ordered]@{ 정본CSV행번호='2'; 업소명='동두천테스트'; 소재지도로명주소='경기도 동두천시 평화로 10'; 감사판정='확인 후보'; 검토결정='최종 승인'; 정본반영여부='예' },
        [pscustomobject][ordered]@{ 정본CSV행번호='3'; 업소명='파주테스트'; 소재지도로명주소='경기도 파주시 중앙로 20'; 감사판정='보류'; 검토결정='보류'; 정본반영여부='아니오' },
        [pscustomobject][ordered]@{ 정본CSV행번호='4'; 업소명='양주테스트'; 소재지도로명주소='경기도 양주시 부흥로 30'; 감사판정='확인 후보'; 검토결정='최종 승인'; 정본반영여부='예' },
        [pscustomobject][ordered]@{ 정본CSV행번호='5'; 업소명='병무청테스트'; 소재지도로명주소='서울특별시 강남구 테헤란로 40'; 감사판정='확인 후보'; 검토결정='최종 승인'; 정본반영여부='예' }
    ) | Export-Csv -LiteralPath $coordCsv -NoTypeInformation -Encoding utf8

    [IO.File]::WriteAllText($manualJson, '{"items":[]}', [Text.UTF8Encoding]::new($false))

    $applyParams = @{
        CanonicalCsv = $canonicalCsv
        DdcComparisonCsv = $ddcCsv
        PajuComparisonCsv = $pajuCsv
        YangjuComparisonCsv = $yangjuCsv
        MmaComparisonCsv = $mmaCsv
        CoordinateReviewCsv = $coordCsv
        ManualSeedJson = $manualJson
        SeedVersion = 99
        CandidateOutputCsv = $candOutCsv
        DestinationSeedJson = $destSeedJson
        DestinationManifestPath = $destManifestJson
        Apply = $true
    }

    $applied = Invoke-BenefitSeedReleaseCut @applyParams

    Assert-ReleaseCutEqual $applied.Mode 'APPLY' 'Apply run must report APPLY mode'
    Assert-ReleaseCutEqual $applied.SeedVersion 99 'Apply run must stamp SeedVersion 99'
    Assert-ReleaseCutEqual $applied.TotalCount 4 'Apply run must package 4 release items'
    Assert-ReleaseCutEqual $applied.ExactPinCount 3 'Apply run must expose 3 exact pins'
    Assert-ReleaseCutEqual $applied.UnconfirmedCoordinateCount 1 'Apply run must leave 1 unconfirmed row as list-only'

    # Use non-default encodings and line endings so rollback must preserve the exact original bytes.
    $manifestText = [IO.File]::ReadAllText($destManifestJson).Replace([string][char]10, ([string][char]13 + [char]10))
    [IO.File]::WriteAllText($destManifestJson, $manifestText, [Text.UTF8Encoding]::new($true))
    $originalSeed = Get-ReleaseCutFileHash $destSeedJson
    $originalManifest = Get-ReleaseCutFileHash $destManifestJson
    $originalCandidates = Get-ReleaseCutFileHash $candOutCsv

    $repeated = Invoke-BenefitSeedReleaseCut @applyParams
    Assert-ReleaseCutEqual $repeated.SeedVersion 99 'An identical release can reuse the installed version'
    Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $destSeedJson) $originalSeed 'An identical release must preserve the seed bytes'
    Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $destManifestJson) $originalManifest 'An identical release must preserve the manifest bytes'

    $applyParams.SeedVersion = 98
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @applyParams } 'RELEASE_CUT_VERSION_NOT_NEWER'
    $applyParams.SeedVersion = 99

    $collisionParams = $applyParams.Clone()
    $collisionParams.CandidateOutputCsv = $canonicalCsv
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @collisionParams } 'RELEASE_CUT_PATH_COLLISION'
    $collisionParams.CandidateOutputCsv = Join-Path (Split-Path -Parent $destSeedJson) ('./' + (Split-Path -Leaf $destSeedJson))
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @collisionParams } 'RELEASE_CUT_PATH_COLLISION'
    $collisionParams.CandidateOutputCsv = Split-Path -Parent $destSeedJson
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @collisionParams } 'RELEASE_CUT_OUTPUT_NOT_FILE'

    [IO.File]::WriteAllText($manualJson, '{"items":[{"id":"manual-v100"}]}', [Text.UTF8Encoding]::new($false))
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @applyParams } 'RELEASE_CUT_VERSION_NOT_NEWER'
    [IO.File]::WriteAllText($manualJson, '{"items":[]}', [Text.UTF8Encoding]::new($false))
    $canonicalBefore = [IO.File]::ReadAllBytes($canonicalCsv)
    $canonicalRows = Import-Csv -LiteralPath $canonicalCsv -Encoding utf8
    $canonicalRows[0].비고 = 'Provenance-only fixture edit'
    $canonicalRows | Export-Csv -LiteralPath $canonicalCsv -NoTypeInformation -Encoding utf8
    $previewParams = $applyParams.Clone()
    $previewParams.Apply = $false
    $preview = Invoke-BenefitSeedReleaseCut @previewParams
    Assert-ReleaseCutEqual $preview.SeedSha256 $applied.SeedSha256 'The provenance change must leave the rendered seed unchanged'
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @applyParams } 'RELEASE_CUT_VERSION_NOT_NEWER'
    [IO.File]::WriteAllBytes($canonicalCsv, $canonicalBefore)

    $changedRows = Import-Csv -LiteralPath $ddcCsv -Encoding utf8
    $changedRows[0].공식할인정보 = '15% 할인'
    $changedRows | Export-Csv -LiteralPath $ddcCsv -NoTypeInformation -Encoding utf8
    Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @applyParams } 'RELEASE_CUT_VERSION_NOT_NEWER'
    Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $destSeedJson) $originalSeed 'The version and path gates must preserve the installed seed'
    Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $destManifestJson) $originalManifest 'The version and path gates must preserve the installed manifest'
    Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $candOutCsv) $originalCandidates 'The version and path gates must preserve the candidates'

    $applyParams.SeedVersion = 100
    foreach ($scenario in @('existing', 'missing-candidates', 'fresh')) {
        $failureParams = $applyParams.Clone()
        if ($scenario -eq 'missing-candidates') {
            [IO.File]::Delete($candOutCsv)
        } elseif ($scenario -eq 'fresh') {
            $freshOut = Join-Path $tempDir 'fresh'
            $failureParams.DestinationSeedJson = Join-Path $freshOut 'benefits.seed.json'
            $failureParams.DestinationManifestPath = Join-Path $freshOut 'benefits.seed.manifest.json'
            $failureParams.CandidateOutputCsv = Join-Path $freshOut 'candidates.csv'
        }
        & {
            # Let the real copies publish the seed and manifest, then fail the candidates copy.
            function Copy-Item {
                [CmdletBinding()]
                param([string]$LiteralPath, [string]$Destination)

                if ([IO.Path]::GetFileName($LiteralPath) -ceq 'candidates.csv') {
                    $installed = Get-Content -Raw -Encoding utf8 -LiteralPath $failureParams.DestinationManifestPath | ConvertFrom-Json
                    Assert-ReleaseCutEqual $installed.seedVersion 100 'The manifest must have been published before the injected failure'
                    if ((Get-ReleaseCutFileHash $failureParams.DestinationSeedJson) -ceq $originalSeed) {
                        throw 'The changed seed must have been published before the injected failure'
                    }
                    [IO.File]::WriteAllBytes($Destination, [byte[]]@(0, 255, 1))
                    $LiteralPath = Join-Path $tempDir 'injected-missing-source.csv'
                }
                [IO.File]::Copy($LiteralPath, $Destination, $true)
            }

            Assert-ReleaseCutFailure { Invoke-BenefitSeedReleaseCut @failureParams } 'injected-missing-source.csv'
        }
        $outputDir = Split-Path -Parent $failureParams.DestinationSeedJson
        if (Get-ChildItem -LiteralPath $outputDir -Force -Filter '.milimap-release-cut-*.tmp') {
            throw 'A late copy failure must remove temporary output files'
        }
        if ($scenario -eq 'fresh') {
            if (Get-ChildItem -LiteralPath $outputDir -Force) {
                throw 'A late copy failure must remove newly created seed, manifest, and candidates outputs'
            }
        } else {
            Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $destSeedJson) $originalSeed 'A late copy failure must restore the original seed bytes'
            Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $destManifestJson) $originalManifest 'A late copy failure must restore the original manifest bytes'
            if ($scenario -eq 'existing') {
                Assert-ReleaseCutEqual (Get-ReleaseCutFileHash $candOutCsv) $originalCandidates 'A partial copy must preserve the original candidates bytes'
            } elseif (Test-Path -LiteralPath $candOutCsv) {
                throw 'A late copy failure must leave absent candidates absent'
            }
        }
    }

    $upgraded = Invoke-BenefitSeedReleaseCut @applyParams
    Assert-ReleaseCutEqual $upgraded.SeedVersion 100 'A version bump must allow changed data to apply after rollback'
    if ($upgraded.SeedSha256 -ceq $applied.SeedSha256) {
        throw 'The changed official benefit must yield a changed seed payload'
    }

    # Re-applying against an existing destination seed must preserve finer-grained district overrides (via -DistrictReferenceJson).
    $seedItemsForRef = @(Get-Content -Raw -Encoding utf8 -LiteralPath $destSeedJson | ConvertFrom-Json)
    ($seedItemsForRef | Where-Object { $_.name -ceq '파주테스트' }).district = '금촌동'
    ($seedItemsForRef | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $destSeedJson -Encoding utf8
    $applyV101Params = $applyParams.Clone()
    $applyV101Params.SeedVersion = 101
    [void](Invoke-BenefitSeedReleaseCut @applyV101Params)
    $v101Items = @(Get-Content -Raw -Encoding utf8 -LiteralPath $destSeedJson | ConvertFrom-Json)
    Assert-ReleaseCutEqual ($v101Items | Where-Object { $_.name -ceq '파주테스트' }).district '금촌동' 'Release cut must preserve finer-grained district from existing destination seed'

    # 3. Zero-Kakao coordinate provenance guard
    $kakaoRows = Import-Csv -LiteralPath $canonicalCsv -Encoding utf8
    $kakaoRows[0].좌표출처 = '카카오맵'
    $kakaoCsv = Join-Path $tempDir 'canonical-kakao.csv'
    $kakaoRows | Export-Csv -LiteralPath $kakaoCsv -NoTypeInformation -Encoding utf8

    $threwKakao = $false
    try {
        [void](Invoke-BenefitSeedReleaseCut `
            -CanonicalCsv $kakaoCsv `
            -DdcComparisonCsv $ddcCsv `
            -PajuComparisonCsv $pajuCsv `
            -YangjuComparisonCsv $yangjuCsv `
            -MmaComparisonCsv $mmaCsv `
            -CoordinateReviewCsv $coordCsv `
            -ManualSeedJson $manualJson `
            -SeedVersion 100 `
            -DestinationSeedJson $destSeedJson `
            -DestinationManifestPath $destManifestJson)
    } catch {
        if ($_.Exception.Message -match 'RELEASE_CUT_KAKAO_COORDINATE_FORBIDDEN') {
            $threwKakao = $true
        } else {
            throw
        }
    }
    if (-not $threwKakao) {
        throw 'Expected RELEASE_CUT_KAKAO_COORDINATE_FORBIDDEN when canonical row uses Kakao coordinates'
    }
} finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

$cli = & (Join-Path $PSScriptRoot 'invoke-benefit-seed-release-cut.ps1')
Assert-ReleaseCutEqual $cli.Mode 'DRY_RUN' 'Bare script execution must report DRY_RUN'
Assert-ReleaseCutEqual $cli.SeedVersion 14 'Bare script execution must read the bundled manifest version'
Assert-ReleaseCutEqual $cli.SeedSha256 $dryRun.SeedSha256 'Bare script execution must stage the same seed as library mode'

Write-Output 'PASS: benefit seed release cut tests'
