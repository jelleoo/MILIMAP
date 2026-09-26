$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/history/history-contracts.ps1')
. (Join-Path $PSScriptRoot 'lib/history/history-fingerprints.ps1')

function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){throw $Message} }
function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){throw ($Message + [Environment]::NewLine + 'expected: ' + $Expected + [Environment]::NewLine + 'actual:   ' + $Actual)} }
function Assert-NotEqual { param($Actual,$Expected,[string]$Message); if($Actual -ceq $Expected){throw $Message} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); $threw=$false; try{& $Action}catch{$threw=$true}; if(-not $threw){throw $Message} }

$left = [pscustomobject][ordered]@{ B=2; A=1; Nested=[pscustomobject][ordered]@{ Z='z'; Y='y' } }
$right = [pscustomobject][ordered]@{ Nested=[pscustomobject][ordered]@{ Y='y'; Z='z' }; A=1; B=2 }
Assert-Equal (ConvertTo-HistoryCanonicalJson $left) (ConvertTo-HistoryCanonicalJson $right) 'Property construction order must not affect canonical JSON'

$ordered1 = [pscustomobject][ordered]@{ Values=@('b','a') }
$ordered2 = [pscustomobject][ordered]@{ Values=@('a','b') }
Assert-NotEqual (ConvertTo-HistoryCanonicalJson $ordered1) (ConvertTo-HistoryCanonicalJson $ordered2) 'Array order is significant by default'
Assert-Equal (ConvertTo-HistoryCanonicalJson $ordered1 -OrderInsensitivePaths @('Values')) (ConvertTo-HistoryCanonicalJson $ordered2 -OrderInsensitivePaths @('Values')) 'Declared order-insensitive array must canonicalize'

$nullJson = ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{ Value=$null })
$emptyJson = ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{ Value='' })
$arrayJson = ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{ Value=@() })
Assert-NotEqual $nullJson $emptyJson 'Null and empty string must differ'
Assert-NotEqual $nullJson $arrayJson 'Null and empty array must differ'
Assert-NotEqual $emptyJson $arrayJson 'Empty string and empty array must differ'

$originalCulture = [Globalization.CultureInfo]::CurrentCulture
try {
    [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('ko-KR')
    $ko = ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{ Coordinate=37.5012345 })
    [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $fr = ConvertTo-HistoryCanonicalJson ([pscustomobject][ordered]@{ Coordinate=37.5012345 })
    Assert-Equal $ko $fr 'Numeric serialization must be culture invariant'
} finally {
    [Globalization.CultureInfo]::CurrentCulture = $originalCulture
}

$projection = [pscustomobject][ordered]@{ BusinessId='biz-0123456789abcdef0123456789abcdef'; Value='x' }
$fp1 = Get-HistoryFingerprint -Projection $projection -SchemaVersion 1
$fp2 = Get-HistoryFingerprint -Projection $projection -SchemaVersion 2
Assert-True ($fp1 -cmatch '^[0-9a-f]{64}$') 'Fingerprint must be lowercase SHA-256'
Assert-NotEqual $fp1 $fp2 'Schema version must participate in fingerprint'

$set = New-HistoryFingerprintSet -InputProjection @{A=1} -EvidenceProjection @{B=2} -SemanticProjection @{C=3} -ExecutionProjection @{D=4}
foreach($name in @('InputFingerprint','EvidenceFingerprint','SemanticFingerprint','ExecutionFingerprint')){
    Assert-True ([string]$set.$name -cmatch '^[0-9a-f]{64}$') "$name must be emitted"
}

function New-TestObservation {
    param([string]$Input='1',[string]$Evidence='2',[string]$Semantic='3',[string]$Execution='4')
    New-HistoryObservation -ObservationId ('obs-' + [Guid]::NewGuid().ToString('N')) -RunId 'run-test' -BusinessId 'biz-0123456789abcdef0123456789abcdef' -Domain 'LOCATION' -ObservedAt '2026-09-26T00:00:00Z' -OperationalStatus 'COMPLETE' -Comparable $true -InputFingerprint ($Input*64) -EvidenceFingerprint ($Evidence*64) -SemanticFingerprint ($Semantic*64) -ExecutionFingerprint ($Execution*64)
}
$base = New-TestObservation
Assert-Equal ((Get-HistoryDeltaDimensions -Previous $base -Current (New-TestObservation -Input 'a')) -join ',') 'INPUT' 'Input change must map to INPUT delta'
Assert-Equal ((Get-HistoryDeltaDimensions -Previous $base -Current (New-TestObservation -Evidence 'a')) -join ',') 'EVIDENCE' 'Evidence change must map to EVIDENCE delta'
Assert-Equal ((Get-HistoryDeltaDimensions -Previous $base -Current (New-TestObservation -Semantic 'a')) -join ',') 'SEMANTIC' 'Semantic change must map to SEMANTIC delta'
Assert-Equal ((Get-HistoryDeltaDimensions -Previous $base -Current (New-TestObservation -Execution 'a')) -join ',') 'EXECUTION' 'Execution change must map to EXECUTION delta'
Assert-Equal @((Get-HistoryDeltaDimensions -Previous $base -Current $base)).Count 0 'Identical fingerprints have no deltas'

Assert-Throws { ConvertTo-HistoryCanonicalJson ([IO.FileInfo]::new('x')) } 'Opaque unsupported types must fail closed'

Write-Host 'History fingerprint tests passed.'
