Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$libraryRoot = Join-Path $PSScriptRoot 'lib'
. (Join-Path $libraryRoot 'benefit-verification-contracts.ps1')
. (Join-Path $libraryRoot 'identity/normalize-business.ps1')
. (Join-Path $libraryRoot 'benefit-source/discover-official-benefit-sources.ps1')
. (Join-Path $libraryRoot 'benefit-source/qualify-official-benefit-source.ps1')
. (Join-Path $libraryRoot 'benefit-source/bind-benefit-source.ps1')
. (Join-Path $libraryRoot 'benefit-evidence/extract-benefit-evidence.ps1')
. (Join-Path $libraryRoot 'benefit-evidence/validate-benefit-evidence.ps1')
. (Join-Path $libraryRoot 'benefit-verification/compare-benefit-claims.ps1')
. (Join-Path $libraryRoot 'benefit-verification/evaluate-benefit-state.ps1')

function Get-Phase2BenefitRowValue {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)][string]$Name)
    if ($Row.PSObject.Properties.Name -contains $Name) { return [string]$Row.$Name }
    return ''
}

function ConvertTo-Phase2CanonicalBenefitRecord {
    param([Parameter(Mandatory)]$Row, [Parameter(Mandatory)][int]$SourceRowNumber)
    $params = @{
        SourceRowNumber=$SourceRowNumber
        BusinessName=(Get-Phase2BenefitRowValue -Row $Row -Name '업소명')
        BenefitDescription=(Get-Phase2BenefitRowValue -Row $Row -Name '할인정보')
        EligibleTarget=(Get-Phase2BenefitRowValue -Row $Row -Name '적용대상')
        UsageCondition=(Get-Phase2BenefitRowValue -Row $Row -Name '이용조건')
        VerificationMethod=(Get-Phase2BenefitRowValue -Row $Row -Name '인증방법')
        ExistingSourceType=(Get-Phase2BenefitRowValue -Row $Row -Name '출처유형')
        ExistingSourceUrl=(Get-Phase2BenefitRowValue -Row $Row -Name '출처URL')
        ExistingVerifiedOn=(Get-Phase2BenefitRowValue -Row $Row -Name '최근확인일')
    }
    $benefit = New-CanonicalBenefitRecord @params
    Assert-CanonicalBenefitRecord $benefit
    return $benefit
}

function Add-Phase2UniqueReasonCodes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Target, [AllowNull()][object[]]$ReasonCodes=@())
    foreach ($reason in @($ReasonCodes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        Assert-BenefitAllowedCode 'ReasonCode' ([string]$reason)
        if ($Target -notcontains [string]$reason) { $Target.Add([string]$reason) }
    }
}

function Get-Phase2ExtractionStatus {
    param([AllowNull()][object[]]$SourceRecords=@())
    $statuses = @($SourceRecords | ForEach-Object { [string]$_.Extraction.Status })
    if ($statuses.Count -eq 0) { return 'FAILED' }
    if (@($statuses | Where-Object { $_ -eq 'COMPLETE' }).Count -gt 0) { return 'COMPLETE' }
    if (@($statuses | Where-Object { $_ -eq 'PARTIAL' }).Count -gt 0) { return 'PARTIAL' }
    return 'FAILED'
}

function Invoke-Phase2BenefitSourceCandidate {
    param(
        [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$Business,
        [string]$CanonicalPhone='',
        [AllowNull()][scriptblock]$RequestInvoker=$null,
        [AllowNull()][scriptblock]$UnstructuredExtractor=$null,
        [AllowNull()][scriptblock]$SpreadsheetExtractor=$null,
        [AllowNull()][scriptblock]$PdfTextExtractor=$null
    )
    $document = Get-BenefitSourceDocument -Candidate $Candidate -RequestInvoker $RequestInvoker
    $qualified = Get-QualifiedBenefitSource -Candidate $Candidate -Document $document -Business $Business
    $bound = Get-BenefitBusinessBinding -Source $qualified -Business $Business -CanonicalPhone $CanonicalPhone
    $extractParams = @{Source=$bound;Document=$document;UnstructuredExtractor=$UnstructuredExtractor;SpreadsheetExtractor=$SpreadsheetExtractor;PdfTextExtractor=$PdfTextExtractor}
    $extraction = Invoke-BenefitEvidenceExtraction @extractParams
    $validation = ConvertTo-ValidatedBenefitEvidence -Extraction $extraction -Document $document

    $reasons = [System.Collections.Generic.List[string]]::new()
    Add-Phase2UniqueReasonCodes -Target $reasons -ReasonCodes $Candidate.ReasonCodes
    Add-Phase2UniqueReasonCodes -Target $reasons -ReasonCodes $document.ReasonCodes
    Add-Phase2UniqueReasonCodes -Target $reasons -ReasonCodes $qualified.ReasonCodes
    Add-Phase2UniqueReasonCodes -Target $reasons -ReasonCodes $bound.ReasonCodes
    Add-Phase2UniqueReasonCodes -Target $reasons -ReasonCodes $extraction.ReasonCodes
    Add-Phase2UniqueReasonCodes -Target $reasons -ReasonCodes $validation.ReasonCodes

    return [pscustomobject][ordered]@{
        SourceRowNumber=$Candidate.SourceRowNumber
        Candidate=$Candidate
        Document=$document
        Qualified=$qualified
        Bound=$bound
        Extraction=$extraction
        Validation=$validation
        ReasonCodes=@($reasons)
    }
}

function ConvertTo-Phase2BenefitEvidenceDiagnostic {
    param([Parameter(Mandatory)]$SourceRecord)
    return [pscustomobject][ordered]@{
        SourceRowNumber=$SourceRecord.SourceRowNumber
        Url=$SourceRecord.Candidate.Url
        SourceKind=$SourceRecord.Candidate.SourceKind
        DiscoveryMethod=$SourceRecord.Candidate.DiscoveryMethod
        FetchStatus=$SourceRecord.Document.FetchStatus
        SourceFormat=$SourceRecord.Document.SourceFormat
        OfficialityStatus=$SourceRecord.Qualified.OfficialityStatus
        QualificationEvidence=@($SourceRecord.Qualified.QualificationEvidence)
        BusinessBindingStatus=$SourceRecord.Bound.BusinessBindingStatus
        BindingEvidence=@($SourceRecord.Bound.BindingEvidence)
        ExtractionStatus=$SourceRecord.Extraction.Status
        ValidatedClaims=@($SourceRecord.Validation.Claims)
        ReasonCodes=@($SourceRecord.ReasonCodes)
    }
}

function Get-Phase2BenefitEvaluation {
    param([Parameter(Mandatory)]$Benefit, [AllowNull()][object[]]$SourceRecords=@(), [Parameter(Mandatory)][string]$DiscoveryStatus)
    $records = @($SourceRecords)
    $validatedClaims = @($records | ForEach-Object { $_.Validation.Claims })
    $claimResults = @(Compare-BenefitClaims -Benefit $Benefit -ValidatedEvidence $validatedClaims)
    $operationalStatus = [pscustomobject][ordered]@{
        DiscoveryStatus=$DiscoveryStatus
        ExtractionStatus=(Get-Phase2ExtractionStatus -SourceRecords $records)
    }
    $evaluation = Invoke-BenefitStateEvaluation -Benefit $Benefit -Sources @($records | ForEach-Object { $_.Bound }) -ClaimResults $claimResults -OperationalStatus $operationalStatus
    return [pscustomobject][ordered]@{ClaimResults=$claimResults;OperationalStatus=$operationalStatus;Evaluation=$evaluation}
}

function ConvertTo-Phase2BenefitReviewRow {
    param([Parameter(Mandatory)]$Result)
    return [pscustomobject][ordered]@{
        SourceRowNumber=$Result.SourceRowNumber
        BusinessName=$Result.BusinessIdentity.OriginalName
        BenefitState=$Result.BenefitState
        ReviewClass=$Result.ReviewClass
        ReasonCodes=@($Result.ReasonCodes)
        ClaimResultCount=@($Result.ClaimResults).Count
        EvidenceCount=@($Result.Evidence).Count
        ProductionAction=$Result.ProductionAction
    }
}

function Invoke-Phase2BenefitShadowMode {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [int]$SourceRowNumberOffset=1,
        [AllowNull()][scriptblock]$RequestInvoker=$null,
        [AllowNull()][scriptblock]$DiscoveryInvoker=$null,
        [AllowNull()][scriptblock]$UnstructuredExtractor=$null,
        [AllowNull()][scriptblock]$SpreadsheetExtractor=$null,
        [AllowNull()][scriptblock]$PdfTextExtractor=$null,
        [hashtable]$GoldenExpectations=@{},
        [switch]$OperationalLiveRun
    )

    $results = [Collections.Generic.List[object]]::new()
    $reportRows = [Collections.Generic.List[object]]::new()
    $diagnostics = [Collections.Generic.List[object]]::new()
    $rowMetadata = [Collections.Generic.List[object]]::new()

    for ($index=0; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        $sourceRowNumber = $SourceRowNumberOffset + $index + 1
        $business = ConvertTo-NormalizedBusiness -Row $row -SourceRowNumber $sourceRowNumber
        Assert-NormalizedBusiness $business
        $benefit = ConvertTo-Phase2CanonicalBenefitRecord -Row $row -SourceRowNumber $sourceRowNumber
        if ($benefit.SourceRowNumber -ne $business.SourceRowNumber) { throw 'Benefit and Business SourceRowNumber chain mismatch' }

        $canonicalPhone = Get-Phase2BenefitRowValue -Row $row -Name '업소전화번호'
        $sourceRecords = [Collections.Generic.List[object]]::new()
        $seenUrls = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $externalCounter = [pscustomobject]@{Requests=0;Discoveries=0}

        $countingRequest = $null
        if ($null -ne $RequestInvoker) {
            $innerRequest = $RequestInvoker
            $counter = $externalCounter
            $countingRequest = { param($Uri); $counter.Requests++; & $innerRequest $Uri }.GetNewClosure()
        }
        $countingDiscovery = $null
        if ($null -ne $DiscoveryInvoker) {
            $innerDiscovery = $DiscoveryInvoker
            $counter2 = $externalCounter
            $countingDiscovery = { param($DiscoveryBenefit,$DiscoveryBusiness); $counter2.Discoveries++; & $innerDiscovery $DiscoveryBenefit $DiscoveryBusiness }.GetNewClosure()
        }

        $existingCandidate = Get-ExistingBenefitSourceCandidate -Benefit $benefit
        $existingSourceUsed = $false
        if ($null -ne $existingCandidate) {
            [void]$seenUrls.Add([string]$existingCandidate.Url)
            $existingSourceUsed = $true
            $processParams = @{Candidate=$existingCandidate;Business=$business;CanonicalPhone=$canonicalPhone;RequestInvoker=$countingRequest;UnstructuredExtractor=$UnstructuredExtractor;SpreadsheetExtractor=$SpreadsheetExtractor;PdfTextExtractor=$PdfTextExtractor}
            $sourceRecords.Add((Invoke-Phase2BenefitSourceCandidate @processParams))
        }

        $preliminary = Get-Phase2BenefitEvaluation -Benefit $benefit -SourceRecords $sourceRecords.ToArray() -DiscoveryStatus 'COMPLETE'
        $fallbackUsed = $preliminary.Evaluation.BenefitState -eq 'NEEDS_VERIFICATION'
        $discoveryStatus = 'COMPLETE'
        $discoveryReasons = @()

        if ($fallbackUsed) {
            $discovery = Invoke-OfficialBenefitSourceDiscovery -Benefit $benefit -Business $business -DiscoveryInvoker $countingDiscovery
            $discoveryStatus = [string]$discovery.Status
            $discoveryReasons = @($discovery.ReasonCodes)
            foreach ($candidate in @($discovery.Candidates)) {
                if (-not $seenUrls.Add([string]$candidate.Url)) { continue }
                $processParams = @{Candidate=$candidate;Business=$business;CanonicalPhone=$canonicalPhone;RequestInvoker=$countingRequest;UnstructuredExtractor=$UnstructuredExtractor;SpreadsheetExtractor=$SpreadsheetExtractor;PdfTextExtractor=$PdfTextExtractor}
                $sourceRecords.Add((Invoke-Phase2BenefitSourceCandidate @processParams))
            }
        }

        $final = Get-Phase2BenefitEvaluation -Benefit $benefit -SourceRecords $sourceRecords.ToArray() -DiscoveryStatus $discoveryStatus
        $allReasons = [System.Collections.Generic.List[string]]::new()
        Add-Phase2UniqueReasonCodes -Target $allReasons -ReasonCodes $final.Evaluation.ReasonCodes
        Add-Phase2UniqueReasonCodes -Target $allReasons -ReasonCodes $discoveryReasons
        foreach ($sourceRecord in $sourceRecords) { Add-Phase2UniqueReasonCodes -Target $allReasons -ReasonCodes $sourceRecord.ReasonCodes }

        $resultParams = @{
            SourceRowNumber=$sourceRowNumber
            BusinessIdentity=$business
            BenefitState=$final.Evaluation.BenefitState
            ReviewClass=$final.Evaluation.ReviewClass
            ReasonCodes=@($allReasons)
            ClaimResults=$final.ClaimResults
            Evidence=$final.Evaluation.Evidence
            Warnings=$final.Evaluation.Warnings
            ProductionAction='NONE'
        }
        $result = New-BenefitVerificationResult @resultParams
        Assert-BenefitVerificationResult $result

        $results.Add($result)
        $reportRows.Add((ConvertTo-Phase2BenefitReviewRow -Result $result))
        foreach ($sourceRecord in $sourceRecords) { $diagnostics.Add((ConvertTo-Phase2BenefitEvidenceDiagnostic -SourceRecord $sourceRecord)) }
        $rowMetadata.Add([pscustomobject][ordered]@{
            SourceRowNumber=$sourceRowNumber
            DiscoveryStatus=$discoveryStatus
            ExistingSourceUsed=$existingSourceUsed
            FallbackUsed=$fallbackUsed
            TotalExternalRequests=([int]$externalCounter.Requests + [int]$externalCounter.Discoveries)
            SourceRecords=$sourceRecords.ToArray()
        })
    }

    $rowsArray = $reportRows.ToArray()
    return [pscustomobject][ordered]@{
        Results=$results.ToArray()
        Rows=$rowsArray
        EvidenceDiagnostics=$diagnostics.ToArray()
        Summary=(Get-Phase2BenefitShadowSummary -Rows $rowsArray -RowMetadata $rowMetadata.ToArray() -GoldenExpectations $GoldenExpectations -OperationalLiveRun:$OperationalLiveRun)
    }
}

function Get-Phase2BenefitShadowSummary {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][object[]]$RowMetadata,
        [hashtable]$GoldenExpectations=@{},
        [switch]$OperationalLiveRun
    )
    $allRows = @($Rows)
    $meta = @($RowMetadata)
    $sourceRecords = @($meta | ForEach-Object { $_.SourceRecords })
    $totalExternalRequests = [int](@($meta | Measure-Object -Property TotalExternalRequests -Sum).Sum)
    $falseGreen = @($allRows | Where-Object {
        $GoldenExpectations.ContainsKey([string]$_.SourceRowNumber) -and $_.ReviewClass -eq 'GREEN' -and [string]$GoldenExpectations[[string]$_.SourceRowNumber].ExpectedReviewClass -ne 'GREEN'
    }).Count

    return [pscustomobject][ordered]@{
        EvaluatedRows=$allRows.Count
        DiscoveryComplete=@($meta | Where-Object DiscoveryStatus -eq 'COMPLETE').Count
        DiscoveryPartial=@($meta | Where-Object DiscoveryStatus -eq 'PARTIAL').Count
        DiscoveryFailed=@($meta | Where-Object DiscoveryStatus -eq 'FAILED').Count
        QualifiedOfficialSourceRows=@($meta | Where-Object { @($_.SourceRecords | Where-Object { $_.Qualified.OfficialityStatus -eq 'VERIFIED_OFFICIAL' }).Count -gt 0 }).Count
        BindingStrong=@($sourceRecords | Where-Object { $_.Bound.BusinessBindingStatus -eq 'STRONG' }).Count
        BindingPlausible=@($sourceRecords | Where-Object { $_.Bound.BusinessBindingStatus -eq 'PLAUSIBLE' }).Count
        BindingAmbiguous=@($sourceRecords | Where-Object { $_.Bound.BusinessBindingStatus -eq 'AMBIGUOUS' }).Count
        BindingConflict=@($sourceRecords | Where-Object { $_.Bound.BusinessBindingStatus -eq 'CONFLICT' }).Count
        ExtractionComplete=@($sourceRecords | Where-Object { $_.Extraction.Status -eq 'COMPLETE' }).Count
        ExtractionPartial=@($sourceRecords | Where-Object { $_.Extraction.Status -eq 'PARTIAL' }).Count
        ExtractionFailed=@($sourceRecords | Where-Object { $_.Extraction.Status -eq 'FAILED' }).Count
        EvidenceValidationRejected=@($sourceRecords | ForEach-Object { $_.Validation.Claims } | Where-Object { $_.ValidationStatus -in @('INVALID','CONFLICT') }).Count
        Active=@($allRows | Where-Object BenefitState -eq 'ACTIVE').Count
        Changed=@($allRows | Where-Object BenefitState -eq 'CHANGED').Count
        Ended=@($allRows | Where-Object BenefitState -eq 'ENDED').Count
        NeedsVerification=@($allRows | Where-Object BenefitState -eq 'NEEDS_VERIFICATION').Count
        Green=@($allRows | Where-Object ReviewClass -eq 'GREEN').Count
        Yellow=@($allRows | Where-Object ReviewClass -eq 'YELLOW').Count
        Red=@($allRows | Where-Object ReviewClass -eq 'RED').Count
        FalseGreenCount=$falseGreen
        FastReviewCandidates=@($allRows | Where-Object ReviewClass -eq 'GREEN').Count
        DeepManualReviewRequired=@($allRows | Where-Object { $_.ReviewClass -in @('YELLOW','RED') }).Count
        AllRowsRequireFinalHumanApproval=$true
        ExistingSourceReuseCount=@($meta | Where-Object ExistingSourceUsed -eq $true).Count
        DiscoveryFallbackCount=@($meta | Where-Object FallbackUsed -eq $true).Count
        TotalExternalRequests=$totalExternalRequests
        AverageExternalRequests=$(if ($allRows.Count -eq 0) { [double]0 } else { [double]$totalExternalRequests / [double]$allRows.Count })
        OperationalLiveShadowRun=$(if ($OperationalLiveRun) { 'RUN' } else { 'NOT_RUN' })
    }
}

function ConvertTo-Phase2BenefitShadowCsvRow {
    param([Parameter(Mandatory)]$Row)
    $projected = [ordered]@{}
    foreach ($property in $Row.PSObject.Properties) {
        $value = $property.Value
        $projected[$property.Name] = if ($value -is [Collections.IEnumerable] -and $value -isnot [string]) { (@($value | ForEach-Object { [string]$_ }) -join '|') } else { $value }
    }
    return [pscustomobject]$projected
}

function Test-Phase2BenefitShadowPathWithinDirectory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Directory)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullDirectory = ([IO.Path]::GetFullPath($Directory)).TrimEnd($separators)
    $comparison = [StringComparison]::OrdinalIgnoreCase
    return $fullPath.Equals($fullDirectory, $comparison) -or $fullPath.StartsWith($fullDirectory + [IO.Path]::DirectorySeparatorChar, $comparison)
}

function Resolve-Phase2BenefitShadowExportPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Explicit output paths are required' }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    foreach ($protectedPath in @('data/canonical','data/seed','apps')) {
        if (Test-Phase2BenefitShadowPathWithinDirectory -Path $fullPath -Directory (Join-Path $repositoryRoot $protectedPath)) { throw 'Protected output path is not allowed' }
    }
    return $fullPath
}

function Export-Phase2BenefitShadowMode {
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][string]$RowReportCsv,
        [Parameter(Mandatory)][string]$SummaryJson,
        [Parameter(Mandatory)][string]$EvidenceDiagnosticJson
    )
    $resolvedRowReportCsv = Resolve-Phase2BenefitShadowExportPath $RowReportCsv
    $resolvedSummaryJson = Resolve-Phase2BenefitShadowExportPath $SummaryJson
    $resolvedEvidenceDiagnosticJson = Resolve-Phase2BenefitShadowExportPath $EvidenceDiagnosticJson
    foreach ($path in @($resolvedRowReportCsv,$resolvedSummaryJson,$resolvedEvidenceDiagnosticJson)) {
        $parent = Split-Path -Parent $path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    }
    @($Run.Rows | ForEach-Object { ConvertTo-Phase2BenefitShadowCsvRow $_ }) | Export-Csv -LiteralPath $resolvedRowReportCsv -NoTypeInformation -Encoding utf8
    [IO.File]::WriteAllText($resolvedSummaryJson, (($Run.Summary | ConvertTo-Json -Depth 10) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($resolvedEvidenceDiagnosticJson, ((@($Run.EvidenceDiagnostics) | ConvertTo-Json -Depth 14) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}
