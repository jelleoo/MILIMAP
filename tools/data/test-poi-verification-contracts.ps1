$ErrorActionPreference = 'Stop'

$libraryPath = Join-Path $PSScriptRoot 'lib\poi-verification-contracts.ps1'
. $libraryPath

function Assert-Equal {
    param(
        [AllowNull()]$Actual,
        [AllowNull()]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-NoThrow {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        & $Action
    } catch {
        throw "$Message ($($_.Exception.Message))"
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Message
    )

    $threw = $false
    try {
        & $Action
    } catch {
        $threw = $true
    }

    if (-not $threw) {
        throw $Message
    }
}

$definition = Get-PoiVerificationContractDefinition
Assert-Equal -Actual $definition.ContractVersion -Expected 1 -Message 'Contract version must be 1'
Assert-True -Condition ($definition.Classification -contains 'GREEN') -Message 'GREEN classification must be defined'
Assert-True -Condition ($definition.Provider -contains 'NAVER_API_HUB_LOCAL') -Message 'NAVER provider code must be defined'

$validContract = [pscustomobject]@{
    ContractType = 'NormalizedBusiness'
    ContractVersion = 1
}
Assert-NoThrow -Action { Assert-PoiContractTypeAndVersion -Object $validContract -ExpectedType 'NormalizedBusiness' } -Message 'Supported contract type/version must pass'
Assert-Throws -Action { Assert-PoiContractTypeAndVersion -Object ([pscustomobject]@{ ContractType = 'WrongType'; ContractVersion = 1 }) -ExpectedType 'NormalizedBusiness' } -Message 'Unexpected contract type must throw'
Assert-Throws -Action { Assert-PoiContractTypeAndVersion -Object ([pscustomobject]@{ ContractType = 'NormalizedBusiness'; ContractVersion = 2 }) -ExpectedType 'NormalizedBusiness' } -Message 'Unsupported contract version must throw'

$validCodes = @(
    @{ Category = 'AddressParseStatus'; Value = 'COMPLETE' },
    @{ Category = 'QueryAttemptStatus'; Value = 'SUCCESS' },
    @{ Category = 'DiscoveryStatus'; Value = 'PARTIAL' },
    @{ Category = 'EvaluationStatus'; Value = 'INCOMPLETE' },
    @{ Category = 'Classification'; Value = 'YELLOW' },
    @{ Category = 'Provider'; Value = 'NAVER_API_HUB_LOCAL' },
    @{ Category = 'ProductionAction'; Value = 'NONE' },
    @{ Category = 'Warning'; Value = 'BRANCH_UNCERTAIN' },
    @{ Category = 'Reason'; Value = 'NO_CANDIDATE' },
    @{ Category = 'Conflict'; Value = 'BUILDING_NUMBER_CONFLICT' },
    @{ Category = 'QueryStrategy'; Value = 'NAME_FULL_ADDRESS' }
)
foreach ($case in $validCodes) {
    Assert-NoThrow -Action { Assert-PoiAllowedCode -Category $case.Category -Value $case.Value } -Message "Valid code must pass: $($case.Category)/$($case.Value)"
}
Assert-Throws -Action { Assert-PoiAllowedCode -Category 'Classification' -Value 'BLUE' } -Message 'Invalid classification must throw'
Assert-Throws -Action { Assert-PoiAllowedCode -Category 'UnknownCategory' -Value 'ANY' } -Message 'Unknown code category must throw'

Assert-NoThrow -Action { Assert-PoiCoordinatePair -Latitude $null -Longitude $null } -Message 'Missing coordinate pair must pass'
Assert-NoThrow -Action { Assert-PoiCoordinatePair -Latitude ([double]37.5665) -Longitude ([double]126.9780) } -Message 'Valid Korea coordinate pair must pass'
Assert-Throws -Action { Assert-PoiCoordinatePair -Latitude ([double]37.5665) -Longitude $null } -Message 'Half coordinate pair must throw'
Assert-Throws -Action { Assert-PoiCoordinatePair -Latitude '37.5665' -Longitude '126.9780' } -Message 'Coordinate strings must not satisfy the double/null contract'
Assert-Throws -Action { Assert-PoiCoordinatePair -Latitude ([double]32.9) -Longitude ([double]126.9780) } -Message 'Out-of-range latitude must throw'
Assert-Throws -Action { Assert-PoiCoordinatePair -Latitude ([double]37.5665) -Longitude ([double]132.1) } -Message 'Out-of-range longitude must throw'

Write-Host 'POI contract primitive tests passed.'
