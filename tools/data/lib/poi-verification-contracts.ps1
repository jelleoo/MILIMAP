Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PoiContractDefinition = [ordered]@{
    ContractVersion = 1
    AddressParseStatus = @('COMPLETE','PARTIAL','UNPARSED')
    QueryAttemptStatus = @('SUCCESS','FAILED','SKIPPED')
    DiscoveryStatus = @('COMPLETE','PARTIAL','FAILED')
    EvaluationStatus = @('COMPLETE','INCOMPLETE')
    Classification = @('GREEN','YELLOW','RED')
    Provider = @('NAVER_API_HUB_LOCAL')
    ProductionAction = @('NONE')
    Warning = @(
        'NAME_EMPTY','NAME_NORMALIZATION_UNCERTAIN','BRANCH_UNCERTAIN','ADDRESS_EMPTY',
        'ADDRESS_PARSE_PARTIAL','ADDRESS_PARSE_FAILED','BUILDING_NUMBER_UNCERTAIN','FLOOR_UNIT_UNCERTAIN'
    )
    Reason = @(
        'NAME_EXACT','NAME_COMPATIBLE','ADDRESS_EXACT','LOCALITY_MATCH','ROAD_NAME_MATCH',
        'BUILDING_NUMBER_MATCH','BRANCH_MATCH','FLOOR_UNIT_MATCH','REPEATED_DISCOVERY',
        'SINGLE_STRONG_CANDIDATE','MULTIPLE_PLAUSIBLE_CANDIDATES','INSUFFICIENT_IDENTITY_EVIDENCE',
        'NO_CANDIDATE','DISCOVERY_PARTIAL_FAILURE','DISCOVERY_FAILED'
    )
    Conflict = @(
        'PROVINCE_CONFLICT','CITY_DISTRICT_CONFLICT','BUILDING_NUMBER_CONFLICT','BRANCH_CONFLICT',
        'FLOOR_UNIT_CONFLICT','INVALID_COORDINATE_PAIR'
    )
    QueryStrategy = @(
        'NAME_FULL_ADDRESS','NAME_ROAD_BUILDING','NAME_LOCALITY_ROAD','BASE_NAME_BUILDING','BASE_NAME_LOCALITY'
    )
}

function Get-PoiVerificationContractDefinition {
    return [pscustomobject]$script:PoiContractDefinition
}

function ConvertTo-PoiText {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function ConvertTo-PoiArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Assert-PoiRequiredProperties {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Properties)
    foreach ($name in $Properties) {
        if ($null -eq $Object.PSObject.Properties[$name]) {
            throw "Missing required property: $name"
        }
    }
}

function Assert-PoiContractTypeAndVersion {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string]$ExpectedType)
    Assert-PoiRequiredProperties $Object @('ContractType','ContractVersion')
    if ([string]$Object.ContractType -ne $ExpectedType) { throw "Unexpected ContractType: $($Object.ContractType)" }
    if ([int]$Object.ContractVersion -ne 1) { throw "Unsupported ContractVersion: $($Object.ContractVersion)" }
}

function Assert-PoiAllowedCode {
    param([Parameter(Mandatory)][string]$Category, [Parameter(Mandatory)][string]$Value)
    if (-not $script:PoiContractDefinition.Contains($Category)) { throw "Unknown code category: $Category" }
    $allowed = @($script:PoiContractDefinition[$Category])
    if ($allowed -notcontains $Value) { throw "Invalid $Category code: $Value" }
}

function Assert-PoiCoordinatePair {
    param([AllowNull()]$Latitude, [AllowNull()]$Longitude)
    if ($null -eq $Latitude -and $null -eq $Longitude) { return }
    if ($null -eq $Latitude -or $null -eq $Longitude) { throw 'Latitude and longitude must both be present or both be absent' }
    if ($Latitude -isnot [double] -or $Longitude -isnot [double]) { throw 'Latitude and longitude must use double/null contract values' }
    if ($Latitude -lt 33.0 -or $Latitude -gt 39.5 -or $Longitude -lt 124.0 -or $Longitude -gt 132.0) {
        throw 'Coordinate pair is outside the approved Korea safety range'
    }
}

function New-PoiQueryAttempt {
    param(
        [string]$StrategyCode='', [string]$Query='', [int]$QueryOrder=0,
        [string]$Status='SUCCESS', [int]$ResultCount=0, [string]$ErrorCode=''
    )
    return [pscustomobject][ordered]@{
        StrategyCode = ConvertTo-PoiText $StrategyCode
        Query = ConvertTo-PoiText $Query
        QueryOrder = $QueryOrder
        Status = ConvertTo-PoiText $Status
        ResultCount = $ResultCount
        ErrorCode = ConvertTo-PoiText $ErrorCode
    }
}

function Assert-PoiQueryAttempt {
    param([Parameter(Mandatory)]$Object)
    Assert-PoiRequiredProperties $Object @('StrategyCode','Query','QueryOrder','Status','ResultCount','ErrorCode')
    Assert-PoiAllowedCode 'QueryStrategy' ([string]$Object.StrategyCode)
    Assert-PoiAllowedCode 'QueryAttemptStatus' ([string]$Object.Status)
    if ([string]::IsNullOrWhiteSpace([string]$Object.Query)) { throw 'Query must not be empty' }
    if ([int]$Object.QueryOrder -lt 1) { throw 'QueryOrder must be 1-based' }
    if ([int]$Object.ResultCount -lt 0) { throw 'ResultCount must be nonnegative' }
    if ([string]$Object.Status -in @('FAILED','SKIPPED') -and [int]$Object.ResultCount -ne 0) { throw 'Failed/skipped query attempts cannot report results' }
}

function New-PoiDiscoveryEvidence {
    param([string]$StrategyCode='', [string]$Query='', [int]$QueryOrder=0, [int]$ResultPosition=0, [int]$ResultCount=0)
    return [pscustomobject][ordered]@{
        StrategyCode = ConvertTo-PoiText $StrategyCode
        Query = ConvertTo-PoiText $Query
        QueryOrder = $QueryOrder
        ResultPosition = $ResultPosition
        ResultCount = $ResultCount
    }
}

function Assert-PoiDiscoveryEvidence {
    param([Parameter(Mandatory)]$Object)
    Assert-PoiRequiredProperties $Object @('StrategyCode','Query','QueryOrder','ResultPosition','ResultCount')
    Assert-PoiAllowedCode 'QueryStrategy' ([string]$Object.StrategyCode)
    if ([string]::IsNullOrWhiteSpace([string]$Object.Query)) { throw 'Discovery evidence query must not be empty' }
    if ([int]$Object.QueryOrder -lt 1) { throw 'QueryOrder must be 1-based' }
    if ([int]$Object.ResultPosition -lt 1) { throw 'ResultPosition must be 1-based' }
    if ([int]$Object.ResultCount -lt 0) { throw 'ResultCount must be nonnegative' }
    if ([int]$Object.ResultPosition -gt [int]$Object.ResultCount) { throw 'ResultPosition cannot exceed ResultCount' }
}

function New-PoiMatchEvidence {
    param(
        [string]$EvidenceCode='', [string]$CandidateKey='', [AllowNull()][string]$CanonicalValue='',
        [AllowNull()][string]$CandidateValue='', [AllowNull()]$Matched=$null
    )
    return [pscustomobject][ordered]@{
        EvidenceCode = ConvertTo-PoiText $EvidenceCode
        CandidateKey = ConvertTo-PoiText $CandidateKey
        CanonicalValue = ConvertTo-PoiText $CanonicalValue
        CandidateValue = ConvertTo-PoiText $CandidateValue
        Matched = $Matched
    }
}

function Assert-PoiMatchEvidence {
    param([Parameter(Mandatory)]$Object)
    Assert-PoiRequiredProperties $Object @('EvidenceCode','CandidateKey','CanonicalValue','CandidateValue','Matched')
    $evidenceCode = [string]$Object.EvidenceCode
    if (($script:PoiContractDefinition.Reason -notcontains $evidenceCode) -and ($script:PoiContractDefinition.Conflict -notcontains $evidenceCode)) {
        throw "Invalid EvidenceCode: $evidenceCode"
    }
    if ($null -ne $Object.Matched -and $Object.Matched -isnot [bool]) { throw 'Matched must be boolean or null' }
}

function New-NormalizedBusiness {
    param(
        [int]$SourceRowNumber,
        [string]$OriginalName='', [string]$NormalizedName='', [string]$BaseName='', [string]$BranchName='',
        [string]$OriginalRoadAddress='', [string]$OriginalLotAddress='', [string]$PreferredAddress='',
        [string]$Province='', [string]$City='', [string]$District='', [string]$Dong='', [string]$RoadName='',
        [string]$BuildingMain='', [string]$BuildingSub='', [string]$Floor='', [string]$Unit='',
        [string]$AddressParseStatus='UNPARSED', [AllowNull()][object[]]$NormalizationWarnings=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='NormalizedBusiness'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        OriginalName=ConvertTo-PoiText $OriginalName; NormalizedName=ConvertTo-PoiText $NormalizedName
        BaseName=ConvertTo-PoiText $BaseName; BranchName=ConvertTo-PoiText $BranchName
        OriginalRoadAddress=ConvertTo-PoiText $OriginalRoadAddress; OriginalLotAddress=ConvertTo-PoiText $OriginalLotAddress
        PreferredAddress=ConvertTo-PoiText $PreferredAddress; Province=ConvertTo-PoiText $Province
        City=ConvertTo-PoiText $City; District=ConvertTo-PoiText $District; Dong=ConvertTo-PoiText $Dong
        RoadName=ConvertTo-PoiText $RoadName; BuildingMain=ConvertTo-PoiText $BuildingMain
        BuildingSub=ConvertTo-PoiText $BuildingSub; Floor=ConvertTo-PoiText $Floor; Unit=ConvertTo-PoiText $Unit
        AddressParseStatus=ConvertTo-PoiText $AddressParseStatus; NormalizationWarnings=@(ConvertTo-PoiArray $NormalizationWarnings)
    }
}

function Assert-NormalizedBusiness {
    param([Parameter(Mandatory)]$Object)
    $required = @('ContractType','ContractVersion','SourceRowNumber','OriginalName','NormalizedName','BaseName','BranchName','OriginalRoadAddress','OriginalLotAddress','PreferredAddress','Province','City','District','Dong','RoadName','BuildingMain','BuildingSub','Floor','Unit','AddressParseStatus','NormalizationWarnings')
    Assert-PoiRequiredProperties $Object $required
    Assert-PoiContractTypeAndVersion $Object 'NormalizedBusiness'
    if ([int]$Object.SourceRowNumber -le 1) { throw 'SourceRowNumber must be greater than 1' }
    Assert-PoiAllowedCode 'AddressParseStatus' ([string]$Object.AddressParseStatus)
    foreach ($warning in @($Object.NormalizationWarnings)) { Assert-PoiAllowedCode 'Warning' ([string]$warning) }
    $preferred = ([string]$Object.PreferredAddress).Trim()
    $road = ([string]$Object.OriginalRoadAddress).Trim()
    $lot = ([string]$Object.OriginalLotAddress).Trim()
    if ($preferred -notin @('', $road, $lot)) { throw 'PreferredAddress must be a preserved source address or empty' }
}

function New-PoiCandidate {
    param(
        [string]$CandidateKey='', [string]$Provider='NAVER_API_HUB_LOCAL', [string]$OriginalName='', [string]$NormalizedName='',
        [string]$RoadAddress='', [string]$LotAddress='', [AllowNull()]$Latitude=$null, [AllowNull()]$Longitude=$null,
        [string]$Phone='', [string]$Category='', [string]$ProviderLink='', [AllowNull()][object[]]$DiscoveredBy=@()
    )
    return [pscustomobject][ordered]@{
        ContractType='PoiCandidate'; ContractVersion=1; CandidateKey=ConvertTo-PoiText $CandidateKey
        Provider=ConvertTo-PoiText $Provider; OriginalName=ConvertTo-PoiText $OriginalName; NormalizedName=ConvertTo-PoiText $NormalizedName
        RoadAddress=ConvertTo-PoiText $RoadAddress; LotAddress=ConvertTo-PoiText $LotAddress
        Latitude=$Latitude; Longitude=$Longitude; Phone=ConvertTo-PoiText $Phone; Category=ConvertTo-PoiText $Category
        ProviderLink=ConvertTo-PoiText $ProviderLink; DiscoveredBy=@(ConvertTo-PoiArray $DiscoveredBy)
    }
}

function Assert-PoiCandidate {
    param([Parameter(Mandatory)]$Object)
    $required = @('ContractType','ContractVersion','CandidateKey','Provider','OriginalName','NormalizedName','RoadAddress','LotAddress','Latitude','Longitude','Phone','Category','ProviderLink','DiscoveredBy')
    Assert-PoiRequiredProperties $Object $required
    Assert-PoiContractTypeAndVersion $Object 'PoiCandidate'
    if ([string]::IsNullOrWhiteSpace([string]$Object.CandidateKey)) { throw 'CandidateKey must not be empty' }
    Assert-PoiAllowedCode 'Provider' ([string]$Object.Provider)
    Assert-PoiCoordinatePair $Object.Latitude $Object.Longitude
    if (@($Object.DiscoveredBy).Count -lt 1) { throw 'PoiCandidate must preserve at least one discovery evidence record' }
    foreach ($evidence in @($Object.DiscoveredBy)) { Assert-PoiDiscoveryEvidence $evidence }
}

function New-PoiDiscoveryBatch {
    param([int]$SourceRowNumber, [string]$Status='FAILED', [AllowNull()][object[]]$Candidates=@(), [AllowNull()][object[]]$QueryAttempts=@())
    return [pscustomobject][ordered]@{
        ContractType='PoiDiscoveryBatch'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        Status=ConvertTo-PoiText $Status; Candidates=@(ConvertTo-PoiArray $Candidates); QueryAttempts=@(ConvertTo-PoiArray $QueryAttempts)
    }
}

function Assert-PoiDiscoveryBatch {
    param([Parameter(Mandatory)]$Object)
    Assert-PoiRequiredProperties $Object @('ContractType','ContractVersion','SourceRowNumber','Status','Candidates','QueryAttempts')
    Assert-PoiContractTypeAndVersion $Object 'PoiDiscoveryBatch'
    if ([int]$Object.SourceRowNumber -le 1) { throw 'SourceRowNumber must be greater than 1' }
    Assert-PoiAllowedCode 'DiscoveryStatus' ([string]$Object.Status)
    foreach ($candidate in @($Object.Candidates)) { Assert-PoiCandidate $candidate }
    foreach ($attempt in @($Object.QueryAttempts)) { Assert-PoiQueryAttempt $attempt }
    if ([string]$Object.Status -eq 'COMPLETE' -and @($Object.QueryAttempts | Where-Object { $_.Status -eq 'FAILED' }).Count -gt 0) {
        throw 'COMPLETE discovery cannot contain failed query attempts'
    }
}

function New-PoiMatchResult {
    param(
        [int]$SourceRowNumber, [string]$EvaluationStatus='INCOMPLETE', [string]$Classification='YELLOW',
        [AllowNull()]$SelectedCandidate=$null, [AllowNull()][object[]]$RankedCandidateKeys=@(),
        [AllowNull()][object[]]$ReasonCodes=@(), [AllowNull()][object[]]$ConflictCodes=@(), [AllowNull()][object[]]$Evidence=@(),
        [int]$EvaluatedCandidateCount=0, [int]$SurvivingCandidateCount=0, [string]$ProductionAction='NONE'
    )
    return [pscustomobject][ordered]@{
        ContractType='PoiMatchResult'; ContractVersion=1; SourceRowNumber=$SourceRowNumber
        EvaluationStatus=ConvertTo-PoiText $EvaluationStatus; Classification=ConvertTo-PoiText $Classification
        SelectedCandidate=$SelectedCandidate; RankedCandidateKeys=@(ConvertTo-PoiArray $RankedCandidateKeys)
        ReasonCodes=@(ConvertTo-PoiArray $ReasonCodes); ConflictCodes=@(ConvertTo-PoiArray $ConflictCodes)
        Evidence=@(ConvertTo-PoiArray $Evidence); EvaluatedCandidateCount=$EvaluatedCandidateCount
        SurvivingCandidateCount=$SurvivingCandidateCount; ProductionAction=ConvertTo-PoiText $ProductionAction
    }
}

function Assert-PoiMatchResult {
    param([Parameter(Mandatory)]$Object)
    $required = @('ContractType','ContractVersion','SourceRowNumber','EvaluationStatus','Classification','SelectedCandidate','RankedCandidateKeys','ReasonCodes','ConflictCodes','Evidence','EvaluatedCandidateCount','SurvivingCandidateCount','ProductionAction')
    Assert-PoiRequiredProperties $Object $required
    Assert-PoiContractTypeAndVersion $Object 'PoiMatchResult'
    if ([int]$Object.SourceRowNumber -le 1) { throw 'SourceRowNumber must be greater than 1' }
    Assert-PoiAllowedCode 'EvaluationStatus' ([string]$Object.EvaluationStatus)
    Assert-PoiAllowedCode 'Classification' ([string]$Object.Classification)
    Assert-PoiAllowedCode 'ProductionAction' ([string]$Object.ProductionAction)
    foreach ($reason in @($Object.ReasonCodes)) { Assert-PoiAllowedCode 'Reason' ([string]$reason) }
    foreach ($conflict in @($Object.ConflictCodes)) { Assert-PoiAllowedCode 'Conflict' ([string]$conflict) }
    foreach ($evidence in @($Object.Evidence)) { Assert-PoiMatchEvidence $evidence }
    if ($null -ne $Object.SelectedCandidate) { Assert-PoiCandidate $Object.SelectedCandidate }
    if ([int]$Object.EvaluatedCandidateCount -lt 0 -or [int]$Object.SurvivingCandidateCount -lt 0) { throw 'Candidate counts must be nonnegative' }
    if ([int]$Object.SurvivingCandidateCount -gt [int]$Object.EvaluatedCandidateCount) { throw 'SurvivingCandidateCount cannot exceed EvaluatedCandidateCount' }
    if ([string]$Object.EvaluationStatus -eq 'INCOMPLETE' -and [string]$Object.Classification -ne 'YELLOW') { throw 'INCOMPLETE evaluation must be YELLOW' }
    switch ([string]$Object.Classification) {
        'GREEN' {
            if ([string]$Object.EvaluationStatus -ne 'COMPLETE') { throw 'GREEN evaluation must be COMPLETE' }
            if ($null -eq $Object.SelectedCandidate) { throw 'GREEN requires a selected candidate' }
        }
        'RED' {
            if ([string]$Object.EvaluationStatus -ne 'COMPLETE') { throw 'RED evaluation must be COMPLETE' }
            if ($null -ne $Object.SelectedCandidate) { throw 'RED must not select a candidate' }
        }
    }
}
