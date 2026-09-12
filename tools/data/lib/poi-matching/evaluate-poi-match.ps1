Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'poi-verification-contracts.ps1')

function ConvertTo-PoiMatchText {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Normalize([Text.NormalizationForm]::FormKC).Trim().ToLowerInvariant()
}

function ConvertTo-PoiMatchCompactText {
    param([AllowNull()]$Value)
    return ((ConvertTo-PoiMatchText $Value) -replace '[\s,().·&]', '')
}

function Get-PoiMatchProvince {
    param([AllowNull()]$AddressOrProvince)
    $text = ConvertTo-PoiMatchText $AddressOrProvince
    if (-not $text) { return '' }
    $token = @($text -split '[\s,]+' | Where-Object { $_ })[0]
    $aliases = @{
        '서울'='서울특별시'; '서울시'='서울특별시'; '서울특별시'='서울특별시'
        '부산'='부산광역시'; '부산시'='부산광역시'; '부산광역시'='부산광역시'
        '대구'='대구광역시'; '대구시'='대구광역시'; '대구광역시'='대구광역시'
        '인천'='인천광역시'; '인천시'='인천광역시'; '인천광역시'='인천광역시'
        '광주'='광주광역시'; '광주시'='광주광역시'; '광주광역시'='광주광역시'
        '대전'='대전광역시'; '대전시'='대전광역시'; '대전광역시'='대전광역시'
        '울산'='울산광역시'; '울산시'='울산광역시'; '울산광역시'='울산광역시'
        '세종'='세종특별자치시'; '세종시'='세종특별자치시'; '세종특별자치시'='세종특별자치시'
        '경기'='경기도'; '경기도'='경기도'
        '강원'='강원특별자치도'; '강원도'='강원특별자치도'; '강원특별자치도'='강원특별자치도'
        '충북'='충청북도'; '충청북도'='충청북도'; '충남'='충청남도'; '충청남도'='충청남도'
        '전북'='전북특별자치도'; '전라북도'='전북특별자치도'; '전북특별자치도'='전북특별자치도'
        '전남'='전라남도'; '전라남도'='전라남도'; '경북'='경상북도'; '경상북도'='경상북도'
        '경남'='경상남도'; '경상남도'='경상남도'
        '제주'='제주특별자치도'; '제주도'='제주특별자치도'; '제주특별자치도'='제주특별자치도'
    }
    if ($aliases.ContainsKey($token)) { return $aliases[$token] }
    return ''
}

function Get-PoiMatchAddressTokens {
    param([AllowNull()]$Address)
    return @((ConvertTo-PoiMatchText $Address) -split '[\s,]+' | Where-Object { $_ })
}

function Test-PoiMatchToken {
    param([string[]]$Tokens, [AllowNull()]$Value)
    $wanted = ConvertTo-PoiMatchText $Value
    if (-not $wanted) { return $null }
    return [bool](@($Tokens | Where-Object { $_ -ceq $wanted }).Count -gt 0)
}

function Get-PoiMatchAdministrativeToken {
    param([string[]]$Tokens, [ValidateSet('City','District')][string]$Kind)
    foreach ($token in $Tokens) {
        if (Get-PoiMatchProvince $token) { continue }
        if ($Kind -eq 'City' -and $token -match '(?:특별자치시|시|군)$') { return $token }
        if ($Kind -eq 'District' -and $token -match '(?:구|군)$') { return $token }
    }
    return ''
}

function Test-PoiMatchRoadToken {
    param([AllowNull()]$Address, [AllowNull()]$RoadName)
    $addressText = ConvertTo-PoiMatchText $Address
    $road = ConvertTo-PoiMatchText $RoadName
    if (-not $addressText -or -not $road) { return $null }
    $pattern = '(?<![가-힣a-z0-9])' + [regex]::Escape($road) + '(?=$|[\s,]|\d)'
    return [bool]($addressText -match $pattern)
}

function Get-PoiMatchRoadBuilding {
    param([AllowNull()]$RoadAddress, [AllowNull()]$RoadName)
    $addressText = ConvertTo-PoiMatchText $RoadAddress
    $road = ConvertTo-PoiMatchText $RoadName
    if (-not $addressText -or -not $road) { return $null }
    $pattern = '(?<![가-힣a-z0-9])' + [regex]::Escape($road) + '(?=$|[\s,]|\d)[\s,]+(?<main>\d+)(?:\s*-\s*(?<sub>\d+))?'
    $match = [regex]::Match($addressText, $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $match.Success) { return $null }
    $main = $match.Groups['main'].Value
    $sub = $match.Groups['sub'].Value
    return $(if ($sub) { "$main-$sub" } else { $main })
}

function Get-PoiMatchBranchSuffix {
    param([AllowNull()]$CandidateName, [AllowNull()]$BaseName)
    $candidate = ConvertTo-PoiMatchCompactText $CandidateName
    $base = ConvertTo-PoiMatchCompactText $BaseName
    if (-not $candidate -or -not $base -or -not $candidate.StartsWith($base, [StringComparison]::Ordinal)) { return $null }
    if ($candidate.Length -eq $base.Length) { return '' }
    return $candidate.Substring($base.Length)
}

function Get-PoiMatchFloorUnit {
    param([AllowNull()]$RoadAddress)
    $text = ConvertTo-PoiMatchText $RoadAddress
    $floor = ''
    $unit = ''
    if ($text) {
        $floorMatch = [regex]::Match($text, '(?<![가-힣a-z0-9])(?<value>(?:지하\s*|b\s*)?\d+)\s*층', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        $unitMatch = [regex]::Match($text, '(?<![가-힣a-z0-9])(?<value>\d+)\s*호', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if ($floorMatch.Success) { $floor = ($floorMatch.Groups['value'].Value -replace '\s+', '') }
        if ($unitMatch.Success) { $unit = $unitMatch.Groups['value'].Value }
    }
    return [pscustomobject]@{ Floor=$floor; Unit=$unit }
}

function Test-PoiMatchRepeatedDiscovery {
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)]$DiscoveryBatch)
    $successfulAttempts = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($attempt in @($DiscoveryBatch.QueryAttempts | Where-Object { $_.Status -eq 'SUCCESS' })) {
        $key = '{0}|{1}|{2}' -f [int]$attempt.QueryOrder, [string]$attempt.StrategyCode, [string]$attempt.Query
        [void]$successfulAttempts.Add($key)
    }
    $matchedAttempts = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($discovery in @($Candidate.DiscoveredBy)) {
        $key = '{0}|{1}|{2}' -f [int]$discovery.QueryOrder, [string]$discovery.StrategyCode, [string]$discovery.Query
        if ($successfulAttempts.Contains($key)) { [void]$matchedAttempts.Add($key) }
    }
    return $matchedAttempts.Count -ge 2
}

function Add-PoiMatchEvidence {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Evidence,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$ReasonSet,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$ConflictSet,
        [string]$Code, [string]$CandidateKey, [AllowNull()][string]$CanonicalValue,
        [AllowNull()][string]$CandidateValue, [bool]$Matched
    )
    $Evidence.Add((New-PoiMatchEvidence -EvidenceCode $Code -CandidateKey $CandidateKey -CanonicalValue $CanonicalValue -CandidateValue $CandidateValue -Matched $Matched))
    if ($Matched) { [void]$ReasonSet.Add($Code) } else { [void]$ConflictSet.Add($Code) }
}

function Get-PoiMatchCandidateEvaluation {
    param(
        [Parameter(Mandatory)]$Business, [Parameter(Mandatory)]$Candidate,
        [Parameter(Mandatory)]$DiscoveryBatch,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Evidence,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$ReasonSet,
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.HashSet[string]]$ConflictSet
    )
    $key = [string]$Candidate.CandidateKey
    $candidateAddresses = @($Candidate.RoadAddress, $Candidate.LotAddress |
        ForEach-Object { [string]$_ } | Where-Object { ConvertTo-PoiMatchText $_ })
    $candidateAddress = $candidateAddresses -join ' | '
    $tokens = @($candidateAddresses | ForEach-Object { Get-PoiMatchAddressTokens $_ })
    $candidateProvince = ''
    foreach ($address in $candidateAddresses) {
        $candidateProvince = Get-PoiMatchProvince $address
        if ($candidateProvince) { break }
    }
    $canonicalProvince = Get-PoiMatchProvince $Business.Province
    $hasConflict = $false

    if ($canonicalProvince) {
        foreach ($address in $candidateAddresses) {
            $actualProvince = Get-PoiMatchProvince $address
            if ($actualProvince -and $canonicalProvince -cne $actualProvince) {
                Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'PROVINCE_CONFLICT' $key ([string]$Business.Province) $actualProvince $false
                $hasConflict = $true
                break
            }
        }
    }

    foreach ($part in @(@{ Name='City'; Value=[string]$Business.City }, @{ Name='District'; Value=[string]$Business.District })) {
        $expected = ConvertTo-PoiMatchText $part.Value
        if (-not $expected) { continue }
        foreach ($address in $candidateAddresses) {
            $addressTokens = @(Get-PoiMatchAddressTokens $address)
            $actual = Get-PoiMatchAdministrativeToken $addressTokens $part.Name
            if ($actual -and $actual -cne $expected) {
                Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'CITY_DISTRICT_CONFLICT' $key $part.Value $actual $false
                $hasConflict = $true
                break
            }
        }
    }

    $canonicalAddresses = @($Business.PreferredAddress, $Business.OriginalRoadAddress, $Business.OriginalLotAddress |
        ForEach-Object { [string]$_ } | Where-Object { ConvertTo-PoiMatchText $_ } | Select-Object -Unique)
    $addressExact = $false
    $matchedCanonicalAddress = ''
    $matchedCandidateAddress = ''
    foreach ($canonicalAddress in $canonicalAddresses) {
        foreach ($address in $candidateAddresses) {
            if ((ConvertTo-PoiMatchCompactText $canonicalAddress) -ceq (ConvertTo-PoiMatchCompactText $address)) {
                $addressExact = $true; $matchedCanonicalAddress = $canonicalAddress; $matchedCandidateAddress = $address; break
            }
        }
        if ($addressExact) { break }
    }
    if ($addressExact) {
        Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'ADDRESS_EXACT' $key $matchedCanonicalAddress $matchedCandidateAddress $true
    }

    $suppliedLocality = @($Business.Province, $Business.City, $Business.District, $Business.Dong |
        ForEach-Object { [string]$_ } | Where-Object { ConvertTo-PoiMatchText $_ })
    $localityMatch = $false
    if ($suppliedLocality.Count -gt 0 -and $candidateAddress) {
        $localityMatch = $true
        foreach ($locality in $suppliedLocality) {
            if ((Get-PoiMatchProvince $locality)) {
                if (-not $candidateProvince -or (Get-PoiMatchProvince $locality) -cne $candidateProvince) { $localityMatch = $false; break }
            } elseif (-not [bool](Test-PoiMatchToken $tokens $locality)) { $localityMatch = $false; break }
        }
        if ($localityMatch) {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'LOCALITY_MATCH' $key ($suppliedLocality -join ' ') $candidateAddress $true
        }
    }

    $roadMatch = [bool](Test-PoiMatchRoadToken $Candidate.RoadAddress $Business.RoadName)
    if ($roadMatch) {
        Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'ROAD_NAME_MATCH' $key ([string]$Business.RoadName) ([string]$Candidate.RoadAddress) $true
    }

    $canonicalBuilding = ConvertTo-PoiMatchText $Business.BuildingMain
    if ($canonicalBuilding -and (ConvertTo-PoiMatchText $Business.BuildingSub)) { $canonicalBuilding += '-' + (ConvertTo-PoiMatchText $Business.BuildingSub) }
    $candidateBuilding = Get-PoiMatchRoadBuilding $Candidate.RoadAddress $Business.RoadName
    $buildingMatch = $false
    if ($canonicalBuilding -and $null -ne $candidateBuilding) {
        $buildingMatch = $canonicalBuilding -ceq $candidateBuilding
        if ($buildingMatch) {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'BUILDING_NUMBER_MATCH' $key $canonicalBuilding $candidateBuilding $true
        } else {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'BUILDING_NUMBER_CONFLICT' $key $canonicalBuilding $candidateBuilding $false
            $hasConflict = $true
        }
    }

    $canonicalName = ConvertTo-PoiMatchCompactText $(if (ConvertTo-PoiMatchText $Business.NormalizedName) { $Business.NormalizedName } else { $Business.OriginalName })
    $candidateName = ConvertTo-PoiMatchCompactText $(if (ConvertTo-PoiMatchText $Candidate.NormalizedName) { $Candidate.NormalizedName } else { $Candidate.OriginalName })
    $baseName = ConvertTo-PoiMatchCompactText $Business.BaseName
    $nameExact = $canonicalName -and $candidateName -and $canonicalName -ceq $candidateName
    $nameCompatible = $false
    if ($nameExact) {
        Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'NAME_EXACT' $key $canonicalName $candidateName $true
    } elseif ($baseName -and $candidateName -and ($candidateName -ceq $baseName -or $candidateName.StartsWith($baseName, [StringComparison]::Ordinal))) {
        $nameCompatible = $true
        Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'NAME_COMPATIBLE' $key $baseName $candidateName $true
    }

    $canonicalBranch = ConvertTo-PoiMatchCompactText $Business.BranchName
    $candidateBranch = Get-PoiMatchBranchSuffix $Candidate.OriginalName $Business.BaseName
    $branchMatch = $false
    if ($canonicalBranch -and $null -ne $candidateBranch -and $candidateBranch) {
        $branchMatch = $canonicalBranch -ceq $candidateBranch
        if ($branchMatch) {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'BRANCH_MATCH' $key $canonicalBranch $candidateBranch $true
        } else {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'BRANCH_CONFLICT' $key $canonicalBranch $candidateBranch $false
            $hasConflict = $true
        }
    }

    $candidateFloorUnit = Get-PoiMatchFloorUnit $Candidate.RoadAddress
    $floorUnitCompared = $false
    $floorUnitMatch = $true
    foreach ($part in @(@{ Canonical=(ConvertTo-PoiMatchCompactText $Business.Floor); Candidate=$candidateFloorUnit.Floor },
            @{ Canonical=(ConvertTo-PoiMatchCompactText $Business.Unit); Candidate=$candidateFloorUnit.Unit })) {
        if ($part.Canonical -and $part.Candidate) {
            $floorUnitCompared = $true
            if ($part.Canonical -cne $part.Candidate) { $floorUnitMatch = $false }
        }
    }
    if ($floorUnitCompared) {
        $canonicalFloorUnit = @((ConvertTo-PoiMatchCompactText $Business.Floor), (ConvertTo-PoiMatchCompactText $Business.Unit)) -join '/'
        $candidateFloorUnitText = @($candidateFloorUnit.Floor, $candidateFloorUnit.Unit) -join '/'
        if ($floorUnitMatch) {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'FLOOR_UNIT_MATCH' $key $canonicalFloorUnit $candidateFloorUnitText $true
        } else {
            Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'FLOOR_UNIT_CONFLICT' $key $canonicalFloorUnit $candidateFloorUnitText $false
            $hasConflict = $true
        }
    } else { $floorUnitMatch = $false }

    $repeated = Test-PoiMatchRepeatedDiscovery $Candidate $DiscoveryBatch
    if ($repeated) {
        Add-PoiMatchEvidence $Evidence $ReasonSet $ConflictSet 'REPEATED_DISCOVERY' $key '2+' ([string]@($Candidate.DiscoveredBy).Count) $true
    }

    $componentMatch = $buildingMatch -and $roadMatch -and $localityMatch
    $nameSignal = $nameExact -or $nameCompatible
    $branchOkay = -not $canonicalBranch -or $branchMatch
    return [pscustomobject][ordered]@{
        Candidate=$Candidate; HasConflict=$hasConflict; AddressExact=$addressExact; ComponentMatch=$componentMatch
        NameExact=$nameExact; NameCompatible=$nameCompatible; BranchMatch=$branchMatch
        FloorUnitMatch=$floorUnitMatch; RepeatedDiscovery=$repeated
        Plausible=($nameSignal -and ($addressExact -or $localityMatch -or $roadMatch))
        Strong=($nameSignal -and ($addressExact -or $componentMatch) -and $branchOkay)
    }
}

function Invoke-PoiMatchEvaluation {
    param([Parameter(Mandatory)]$Business, [Parameter(Mandatory)]$DiscoveryBatch)
    Assert-NormalizedBusiness $Business
    Assert-PoiDiscoveryBatch $DiscoveryBatch
    if ([int]$Business.SourceRowNumber -ne [int]$DiscoveryBatch.SourceRowNumber) { throw 'Business and discovery batch SourceRowNumber must match' }

    $evidence = [Collections.Generic.List[object]]::new()
    $reasonSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $conflictSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $evaluations = [Collections.Generic.List[object]]::new()
    foreach ($candidate in @($DiscoveryBatch.Candidates)) {
        $evaluations.Add((Get-PoiMatchCandidateEvaluation $Business $candidate $DiscoveryBatch $evidence $reasonSet $conflictSet))
    }
    $survivors = @($evaluations | Where-Object { -not $_.HasConflict })
    $comparer = [Collections.Generic.Comparer[object]]::Create([Comparison[object]]{
        param($left, $right)
        foreach ($field in @('AddressExact','ComponentMatch','NameExact','NameCompatible','BranchMatch','FloorUnitMatch','RepeatedDiscovery')) {
            $comparison = [int][bool]$right.$field - [int][bool]$left.$field
            if ($comparison -ne 0) { return $comparison }
        }
        return [StringComparer]::Ordinal.Compare([string]$left.Candidate.CandidateKey, [string]$right.Candidate.CandidateKey)
    })
    [Array]::Sort($survivors, $comparer)
    $rankedKeys = @($survivors | ForEach-Object { [string]$_.Candidate.CandidateKey })

    $evaluationStatus = 'COMPLETE'
    $classification = 'YELLOW'
    $selected = $null
    $outcomeReason = ''
    if ([string]$DiscoveryBatch.Status -eq 'PARTIAL') {
        $evaluationStatus = 'INCOMPLETE'; $outcomeReason = 'DISCOVERY_PARTIAL_FAILURE'
    } elseif ([string]$DiscoveryBatch.Status -eq 'FAILED') {
        $evaluationStatus = 'INCOMPLETE'; $outcomeReason = 'DISCOVERY_FAILED'
    } elseif (@($DiscoveryBatch.Candidates).Count -eq 0) {
        $classification = 'RED'; $outcomeReason = 'NO_CANDIDATE'
    } elseif ($survivors.Count -eq 0) {
        $classification = 'RED'
    } else {
        $strong = @($survivors | Where-Object { $_.Strong })
        $plausible = @($survivors | Where-Object { $_.Plausible })
        if ($strong.Count -eq 1 -and $plausible.Count -eq 1) {
            $classification = 'GREEN'; $outcomeReason = 'SINGLE_STRONG_CANDIDATE'; $selected = $strong[0].Candidate
        } elseif ($plausible.Count -gt 1) {
            $outcomeReason = 'MULTIPLE_PLAUSIBLE_CANDIDATES'
        } else {
            $outcomeReason = 'INSUFFICIENT_IDENTITY_EVIDENCE'
        }
    }
    if ($outcomeReason) { [void]$reasonSet.Add($outcomeReason) }

    $reasonOrder = @('NAME_EXACT','NAME_COMPATIBLE','ADDRESS_EXACT','LOCALITY_MATCH','ROAD_NAME_MATCH','BUILDING_NUMBER_MATCH','BRANCH_MATCH','FLOOR_UNIT_MATCH','REPEATED_DISCOVERY','SINGLE_STRONG_CANDIDATE','MULTIPLE_PLAUSIBLE_CANDIDATES','INSUFFICIENT_IDENTITY_EVIDENCE','NO_CANDIDATE','DISCOVERY_PARTIAL_FAILURE','DISCOVERY_FAILED')
    $conflictOrder = @('PROVINCE_CONFLICT','CITY_DISTRICT_CONFLICT','BUILDING_NUMBER_CONFLICT','BRANCH_CONFLICT','FLOOR_UNIT_CONFLICT','INVALID_COORDINATE_PAIR')
    $reasons = @($reasonOrder | Where-Object { $reasonSet.Contains($_) })
    $conflicts = @($conflictOrder | Where-Object { $conflictSet.Contains($_) })
    $result = New-PoiMatchResult -SourceRowNumber $Business.SourceRowNumber -EvaluationStatus $evaluationStatus `
        -Classification $classification -SelectedCandidate $selected -RankedCandidateKeys $rankedKeys `
        -ReasonCodes $reasons -ConflictCodes $conflicts -Evidence $evidence.ToArray() `
        -EvaluatedCandidateCount @($DiscoveryBatch.Candidates).Count -SurvivingCandidateCount $survivors.Count -ProductionAction 'NONE'
    Assert-PoiMatchResult $result
    return $result
}
