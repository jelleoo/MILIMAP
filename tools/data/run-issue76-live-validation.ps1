$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')

$sampleIds = @(2,4,5,22,74,75,118,119,139,280,337,338)
$smokeIds = @(4,118,139)
$canonicalPath = Join-Path $PSScriptRoot '..\..\data\canonical\capital-area-military-benefits.csv'
$allRows = @(Import-Csv -LiteralPath $canonicalPath)

function Get-Issue76Row {
    param([Parameter(Mandatory)][int]$SourceRowNumber)
    $index = $SourceRowNumber - 2
    if ($index -lt 0 -or $index -ge $allRows.Count) { throw "Source row $SourceRowNumber is outside canonical data" }
    return $allRows[$index]
}

$client = [Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(45)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 MILIMAP-Phase2-Validation/1.0')
$requestInvoker = {
    param($Uri)
    $response = $client.GetAsync($Uri).GetAwaiter().GetResult()
    $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    $text = ''
    try { $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch { $text = '' }
    $contentType = if ($null -ne $response.Content.Headers.ContentType) { [string]$response.Content.Headers.ContentType } else { '' }
    [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        ContentType = $contentType
        Text = $text
        Bytes = [byte[]]$bytes
    }
}.GetNewClosure()

function Convert-Issue76Run {
    param([Parameter(Mandatory)]$Run, [Parameter(Mandatory)][int[]]$SourceRowNumbers, [Parameter(Mandatory)][double]$ElapsedSeconds)
    $rows = @()
    foreach ($id in $SourceRowNumbers) {
        $result = @($Run.Results | Where-Object SourceRowNumber -eq $id)[0]
        $review = @($Run.Rows | Where-Object SourceRowNumber -eq $id)[0]
        $diag = @($Run.EvidenceDiagnostics | Where-Object SourceRowNumber -eq $id)[0]
        $canonical = Get-Issue76Row -SourceRowNumber $id
        $greenPacket = $null
        if ($null -ne $result -and $result.ReviewClass -ceq 'GREEN') {
            $greenPacket = [pscustomobject][ordered]@{
                AuditStatus = 'PENDING_HUMAN_AUDIT'
                BusinessName = [string]$canonical.'업소명'
                SourceUrl = [string]$canonical.'출처URL'
                BenefitState = [string]$result.BenefitState
                ReviewClass = [string]$result.ReviewClass
                ReasonCodes = @($result.ReasonCodes)
                ClaimResults = @($result.ClaimResults)
                Evidence = @($result.Evidence)
                BindingEvidence = $(if ($null -ne $diag) { @($diag.BindingEvidence) } else { @() })
                ValidatedClaims = $(if ($null -ne $diag) { @($diag.ValidatedClaims) } else { @() })
                Slices = $(if ($null -ne $diag) { @($diag.Slices) } else { @() })
            }
        }
        $rows += [pscustomobject][ordered]@{
            SourceRowNumber = $id
            BusinessName = [string]$canonical.'업소명'
            SourceType = [string]$canonical.'출처유형'
            SourceUrl = [string]$canonical.'출처URL'
            BenefitState = $(if ($null -ne $result) { [string]$result.BenefitState } else { '' })
            ReviewClass = $(if ($null -ne $result) { [string]$result.ReviewClass } else { '' })
            ReasonCodes = $(if ($null -ne $result) { @($result.ReasonCodes) } else { @() })
            ProductionAction = $(if ($null -ne $result) { [string]$result.ProductionAction } else { '' })
            TotalExternalRequests = $(if ($null -ne $review) { [int]$review.TotalExternalRequests } else { 0 })
            FetchStatus = $(if ($null -ne $diag) { [string]$diag.FetchStatus } else { '' })
            SourceFormat = $(if ($null -ne $diag) { [string]$diag.SourceFormat } else { '' })
            AdapterId = $(if ($null -ne $diag) { [string]$diag.AdapterId } else { '' })
            AdapterStatus = $(if ($null -ne $diag) { [string]$diag.AdapterStatus } else { '' })
            LocationOperationalStatus = $(if ($null -ne $diag) { [string]$diag.LocationOperationalStatus } else { '' })
            LocationStatus = $(if ($null -ne $diag) { [string]$diag.LocationStatus } else { '' })
            OfficialityStatus = $(if ($null -ne $diag) { [string]$diag.OfficialityStatus } else { '' })
            BusinessBindingStatus = $(if ($null -ne $diag) { [string]$diag.BusinessBindingStatus } else { '' })
            ExtractionStatus = $(if ($null -ne $diag) { [string]$diag.ExtractionStatus } else { '' })
            DiagnosticReasonCodes = $(if ($null -ne $diag) { @($diag.ReasonCodes) } else { @() })
            ValidatedClaimTypes = $(if ($null -ne $diag) { @($diag.ValidatedClaims | ForEach-Object { [string]$_.ClaimType }) } else { @() })
            GreenAuditPacket = $greenPacket
        }
    }
    [pscustomobject][ordered]@{
        ElapsedSeconds = [math]::Round($ElapsedSeconds,2)
        Rows = $rows
        Summary = $Run.Summary
        PreparationSummary = $Run.PreparationSummary
    }
}

function Invoke-Issue76Set {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][int[]]$Ids)
    $selected = @($Ids | ForEach-Object { Get-Issue76Row -SourceRowNumber $_ })
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $run = Invoke-Phase2BenefitShadowMode -Rows $selected -SourceRowNumbers $Ids -UseScopedEvidence -RequestInvoker $requestInvoker -OperationalLiveRun
        $watch.Stop()
        $projection = Convert-Issue76Run -Run $run -SourceRowNumbers $Ids -ElapsedSeconds $watch.Elapsed.TotalSeconds
        return [pscustomobject][ordered]@{ Name=$Name; Status='COMPLETE'; Data=$projection; Error='' }
    } catch {
        $watch.Stop()
        return [pscustomobject][ordered]@{ Name=$Name; Status='EXCEPTION'; Data=$null; Error=$_.Exception.Message; ElapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2) }
    }
}

function Invoke-Issue76Individual {
    param([Parameter(Mandatory)][int]$Id)
    $set = Invoke-Issue76Set -Name "ROW_$Id" -Ids @($Id)
    if ($set.Status -ceq 'COMPLETE') { return $set.Data.Rows[0] | Select-Object *, @{N='HarnessStatus';E={'COMPLETE'}}, @{N='HarnessError';E={''}}, @{N='ElapsedSeconds';E={$set.Data.ElapsedSeconds}} }
    $canonical = Get-Issue76Row -SourceRowNumber $Id
    return [pscustomobject][ordered]@{
        SourceRowNumber=$Id; BusinessName=[string]$canonical.'업소명'; SourceType=[string]$canonical.'출처유형'; SourceUrl=[string]$canonical.'출처URL'
        BenefitState=''; ReviewClass=''; ReasonCodes=@(); ProductionAction=''; TotalExternalRequests=0
        FetchStatus=''; SourceFormat=''; AdapterId=''; AdapterStatus=''; LocationOperationalStatus=''; LocationStatus=''
        OfficialityStatus=''; BusinessBindingStatus=''; ExtractionStatus=''; DiagnosticReasonCodes=@(); ValidatedClaimTypes=@()
        GreenAuditPacket=$null; HarnessStatus='EXCEPTION'; HarnessError=[string]$set.Error; ElapsedSeconds=[double]$set.ElapsedSeconds
    }
}

Write-Host 'ISSUE76_VALIDATION_START'
Write-Host ('ISSUE76_SAMPLE_IDS ' + ($sampleIds -join ','))

$smoke = Invoke-Issue76Set -Name 'SMOKE' -Ids $smokeIds
Write-Host ('ISSUE76_SMOKE ' + ($smoke | ConvertTo-Json -Depth 16 -Compress))

$individual = @()
foreach ($id in $sampleIds) {
    $item = Invoke-Issue76Individual -Id $id
    $individual += $item
    Write-Host ('ISSUE76_ROW ' + ($item | ConvertTo-Json -Depth 16 -Compress))
}

$groups = @(
    (Invoke-Issue76Set -Name 'MMA_SHARED' -Ids @(4,5)),
    (Invoke-Issue76Set -Name 'DDC_SHARED' -Ids @(118,119,139)),
    (Invoke-Issue76Set -Name 'YANGJU_SHARED' -Ids @(337,338))
)
foreach ($group in $groups) { Write-Host ('ISSUE76_GROUP ' + ($group | ConvertTo-Json -Depth 12 -Compress)) }

$batch = Invoke-Issue76Set -Name 'REPRESENTATIVE_12' -Ids $sampleIds
Write-Host ('ISSUE76_BATCH ' + ($batch | ConvertTo-Json -Depth 12 -Compress))

$final = [pscustomobject][ordered]@{
    Baseline = 'c4ab1c1701a7b4c1aa7a108b6a45f15e310871de'
    SampleIds = $sampleIds
    Smoke = $smoke
    IndividualRows = $individual
    ReuseGroups = $groups
    Batch = $batch
}

$outDir = Join-Path $env:RUNNER_TEMP 'issue76-validation'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir 'issue76-validation.json'
[IO.File]::WriteAllText($outPath, (($final | ConvertTo-Json -Depth 20) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
Write-Host "ISSUE76_ARTIFACT $outPath"
Write-Host 'ISSUE76_VALIDATION_END'
$client.Dispose()
