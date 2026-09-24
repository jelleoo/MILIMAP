$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-location/test-support.ps1')
$path = Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1'
if (-not (Test-Path -LiteralPath $path)) { throw 'Scoped evidence contracts are missing' }
$before = Get-BenefitVerificationContractDefinition | ConvertTo-Json -Depth 8 -Compress
. $path
Assert-ScopeEqual (Get-BenefitVerificationContractDefinition | ConvertTo-Json -Depth 8 -Compress) $before 'New contracts must not extend existing global enums'

$fixtureData = Import-PowerShellDataFile -LiteralPath $script:ScopeTestFixturePath
Assert-ScopeEqual $fixtureData.FixtureKind 'SYNTHETIC_ALGORITHM_ONLY' 'Fixture must not impersonate real evidence'
Assert-ScopeEqual $fixtureData.Status 'TEST_ONLY' 'Fixture status must be explicit'
Assert-ScopeEqual (Get-BenefitEvidenceTextHash -Text 'abc') 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' 'Hash must be SHA-256 of UTF-8 text'
Assert-ScopeEqual (ConvertFrom-ScopeHtmlText -Text 'A &amp; B &lt;5 &gt;3<br><b>C</b>') 'A & B <5 >3 C' 'Decode entities after removing real markup'
$map = Get-BenefitScopedHeaderMap
Assert-ScopeEqual $map['업소명'] 'BusinessName' 'Known header mapping'
$map['업소명'] = 'Invented'
Assert-ScopeEqual (Get-BenefitScopedHeaderMap)['업소명'] 'BusinessName' 'Returned header map must not mutate later calls'

$rowHtml = '<tr><td>Sample A</td></tr>'
$html = '<table>' + $rowHtml + '</table>'
$d = New-ScopeTestDocument -Html $html
$params = @{SourceUrl=$d.Url; SourceFormat='HTML'; Text=$d.Text; ObservedAt=$d.ObservedAt}
$s = New-BenefitSourceSnapshot @params
Assert-ScopeEqual $s.Text $d.Text 'Snapshot preserves exact text'
Assert-ScopeEqual $s.ContractType 'BenefitSourceSnapshot' 'Snapshot has a local contract type'
Assert-ScopeEqual $s.SnapshotId (New-BenefitSourceSnapshot @params).SnapshotId 'Snapshot identity is deterministic'
$changedTime = $params.Clone(); $changedTime.ObservedAt='2026-09-25T00:00:00Z'
Assert-ScopeTrue ($s.SnapshotId -cne (New-BenefitSourceSnapshot @changedTime).SnapshotId) 'New observation time has a new snapshot identity'
$spaced = $params.Clone(); $spaced.Text="  $html `n"
Assert-ScopeEqual (New-BenefitSourceSnapshot @spaced).Text $spaced.Text 'Do not trim snapshot after hashing'
foreach ($bad in @(
    @{SourceUrl=''}, @{SourceUrl='/relative'}, @{SourceUrl='file:///tmp/source'},
    @{Text=''}, @{Text='   '}, @{SourceFormat='INVENTED'},
    @{ObservedAt=''}, @{ObservedAt='2026-09-24'}, @{ObservedAt='not-a-date'}
)) {
    $p = $params.Clone()
    foreach ($key in $bad.Keys) { $p[$key] = $bad[$key] }
    Assert-ScopeThrows { New-BenefitSourceSnapshot @p } 'Reject invalid snapshot URL, format, text, or timestamp'
}

$u = New-BenefitSourceContentUnit -Snapshot $s -UnitReference 'HTML_TABLE_1_ROW_1' -TableStart 0 -TableLength $html.Length -RawStart 7 -RawLength $rowHtml.Length -RawEvidenceText 'Sample A' -StructuredFields @{} -FieldReferences @{}
$o2 = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($u) -Diagnostics @()
$o3 = New-BenefitSourceObservation -SourceRowNumber 3 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion '1' -AdapterStatus COMPLETE -ContentUnits @($u) -Diagnostics @()
$slice = New-RelevantBenefitEvidenceSlice -Observation $o2 -Unit $u -IdentityEvidence @()
Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $d -SourceRowNumber 2
Assert-ScopeEqual $o3.SourceRowNumber 3 'Independent row wrapper'
Assert-ScopeTrue (-not ($s.PSObject.Properties.Name -contains 'SourceRowNumber')) 'Shared payload is rowless'
Assert-ScopeTrue ($o2.ContentUnits -is [array]) 'One unit remains an array'
Assert-ScopeTrue ($slice.IdentityEvidence -is [array]) 'Empty identity evidence remains an array'
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $d -SourceRowNumber 3 } 'Reject cross-row slice'
$changed = New-ScopeTestDocument -Html ($html -replace 'Sample A','Sample B')
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $changed -SourceRowNumber 2 } 'Same URL is not same content'
$wrongUrl = New-ScopeTestDocument -Html $html -Url 'https://city.example.go.kr/other'
Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $slice -Document $wrongUrl -SourceRowNumber 2 } 'Reject other source URL'
foreach ($invalid in @($null, [pscustomobject]@{ContractType='Other';ContractVersion=1}, [pscustomobject]@{ContractType='RelevantEvidenceSlice';ContractVersion=99})) {
    Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $invalid -Document $d -SourceRowNumber 2 } 'Reject incomplete, null, or unsupported contract'
}
foreach ($start in @(-1,999)) {
    Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $s -UnitReference 'HTML_TABLE_1_ROW_1' -TableStart 0 -TableLength $html.Length -RawStart $start -RawLength $rowHtml.Length -RawEvidenceText 'Sample A' -StructuredFields @{} -FieldReferences @{} } 'Reject invalid row bounds'
}
Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $s -UnitReference '' -TableStart 0 -TableLength $html.Length -RawStart 7 -RawLength $rowHtml.Length -RawEvidenceText 'Sample A' -StructuredFields @{} -FieldReferences @{} } 'Reference must not be empty'
Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $s -UnitReference 'HTML_TABLE_1_ROW_1' -TableStart 0 -TableLength $html.Length -RawStart 7 -RawLength $rowHtml.Length -RawEvidenceText 'fabricated' -StructuredFields @{} -FieldReferences @{} } 'Decoded text must match original row'
Assert-ScopeThrows { New-BenefitSourceObservation -SourceRowNumber 1 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion 1 -AdapterStatus COMPLETE -ContentUnits @($u) } 'Canonical row must exceed header row'
Assert-ScopeThrows { New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion 1 -AdapterStatus COMPLETE -ContentUnits @($u,$u) } 'Duplicate physical references must fail'
Assert-ScopeThrows { New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion 1 -AdapterStatus COMPLETE -ContentUnits @($null) } 'Null unit is not a usable unit'
$empty = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion 1 -AdapterStatus COMPLETE -ContentUnits @() -Diagnostics @()
Assert-ScopeEqual @($empty.ContentUnits).Count 0 'Empty complete observation is representable'
Assert-ScopeThrows { New-RelevantBenefitEvidenceSlice -Observation $empty -Unit $u } 'Slice requires exact observation membership'
$partial = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $s -AdapterId HTML_GENERIC -AdapterVersion 1 -AdapterStatus PARTIAL -ContentUnits @($u) -Diagnostics @([pscustomobject]@{Code='HTML_TABLE_PARTIAL';Stage='ADAPTER';EvidenceReference='HTML_TABLE_1';Detail='test'})
Assert-ScopeThrows { New-RelevantBenefitEvidenceSlice -Observation $partial -Unit $u } 'Incomplete preparation must not produce a usable slice'

# Positive, source-backed fields exercise the same validation that rejects mutations.
$f = New-ScopeContractFixture
Assert-RelevantBenefitEvidenceSlice -Slice $f.Slice -Document $f.Document -SourceRowNumber 2
Assert-ScopeEqual $f.Slice.StructuredFields.BusinessName '테스트가게 A' 'Correct field comes from selected row'
Assert-ScopeEqual $f.Slice.StructuredFields.BenefitDescription '10% 할인' 'Correct benefit cell preserved'
Assert-ScopeEqual $f.Slice.EvidenceReference 'HTML_TABLE_1_ROW_2' 'Physical row reference must not be renumbered'
Assert-ScopeEqual @($f.Observation.ContentUnits).Count 2 'Multiple units remain available before location'
Assert-ScopeTrue ($f.Slice.RawEvidenceText -notmatch '테스트가게 B|30%') 'Unrelated business text is not in selected row'

$mutations = @(
    @{Name='wrong type'; Apply={param($x) $x.Slice.ContractType='Other'}},
    @{Name='wrong version'; Apply={param($x) $x.Slice.ContractVersion=2}},
    @{Name='wrong row'; Apply={param($x) $x.Slice.SourceRowNumber=3}},
    @{Name='wrong hash'; Apply={param($x) $x.Slice.ContentHash=('0'*64)}},
    @{Name='wrong observation time'; Apply={param($x) $x.Slice.ObservedAt='2026-09-25T00:00:00Z'}},
    @{Name='empty reference'; Apply={param($x) $x.Slice.EvidenceReference=''}},
    @{Name='whole document scope'; Apply={param($x) $x.Slice.ScopeType='FULL_DOCUMENT'}},
    @{Name='altered raw fragment'; Apply={param($x) $x.Slice.RawFragment='invented'}},
    @{Name='altered decoded text'; Apply={param($x) $x.Slice.RawEvidenceText='invented'}},
    @{Name='altered observed value'; Apply={param($x) $x.Slice.StructuredFields['BenefitDescription']='30% 할인'}},
    @{Name='missing field reference'; Apply={param($x) $x.Slice.FieldReferences.Remove('Phone')}},
    @{Name='wrong header meaning'; Apply={param($x) $x.Slice.FieldReferences.BenefitDescription.HeaderStart=$x.Slice.FieldReferences.Phone.HeaderStart; $x.Slice.FieldReferences.BenefitDescription.HeaderLength=$x.Slice.FieldReferences.Phone.HeaderLength}},
    @{Name='claimed header text'; Apply={param($x) $x.Slice.FieldReferences.BenefitDescription.OriginalHeader='대상'}},
    @{Name='another row cell'; Apply={param($x) $other=$x.Units[1].FieldReferences.BenefitDescription; $x.Slice.FieldReferences.BenefitDescription.CellStart=$other.CellStart; $x.Slice.FieldReferences.BenefitDescription.CellLength=$other.CellLength; $x.Slice.StructuredFields.BenefitDescription='30% 할인'}},
    @{Name='another field reference'; Apply={param($x) $x.Slice.FieldReferences.BenefitDescription.FieldReference=$x.Slice.FieldReferences.Phone.FieldReference}},
    @{Name='invented extra field'; Apply={param($x) $x.Slice.StructuredFields['Currentness']='CURRENT'}},
    @{Name='wrong document format'; Apply={param($x) $x.Document.SourceFormat='CSV'}},
    @{Name='failed fetch'; Apply={param($x) $x.Document.FetchStatus='FAILED'}}
)
foreach ($case in $mutations) {
    $x = New-ScopeContractFixture
    Assert-RelevantBenefitEvidenceSlice -Slice $x.Slice -Document $x.Document -SourceRowNumber 2
    & $case.Apply $x
    Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $x.Slice -Document $x.Document -SourceRowNumber 2 } ('Reject ' + $case.Name)
}

# A correct header from a different table must not validate a selected row.
$x = New-ScopeContractFixture
$combined = $x.Document.Text + $x.Document.Text
$two = New-BenefitSourceSnapshot -SourceUrl $x.Document.Url -SourceFormat HTML -Text $combined -ObservedAt $x.Document.ObservedAt
$refs = [ordered]@{}
foreach ($key in $x.Units[0].FieldReferences.Keys) { $refs[$key]=$x.Units[0].FieldReferences[$key] }
$refs.BenefitDescription.HeaderStart += $x.Document.Text.Length
$unit = $x.Units[0]
Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $two -UnitReference $unit.UnitReference -TableStart $unit.TableStart -TableLength $unit.TableLength -RawStart $unit.RawStart -RawLength $unit.RawLength -RawEvidenceText $unit.RawEvidenceText -StructuredFields $unit.StructuredFields -FieldReferences $refs } 'Cross-table header is not provenance'

# Nested mutable fields cannot leak between caller objects, observations or slices.
$x = New-ScopeContractFixture
$x.Units[0].StructuredFields['BusinessName']='mutated caller'
$x.Units[0].FieldReferences.BenefitDescription.CellStart=0
Assert-ScopeEqual $x.Observation.ContentUnits[0].StructuredFields.BusinessName '테스트가게 A' 'Observation must defensively copy fields'
Assert-RelevantBenefitEvidenceSlice -Slice $x.Slice -Document $x.Document -SourceRowNumber 2
$x.Observation.ContentUnits[0].StructuredFields['BusinessName']='mutated observation'
Assert-ScopeEqual $x.Slice.StructuredFields.BusinessName '테스트가게 A' 'Slice must defensively copy observed fields'
Assert-RelevantBenefitEvidenceSlice -Slice $x.Slice -Document $x.Document -SourceRowNumber 2

# Location status represents evidence preparation, never benefit lifecycle.
$x = New-ScopeContractFixture
$located = New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status LOCATED -Slices @($x.Slice) -CandidateReferences @($x.Slice.EvidenceReference) -Diagnostics @()
Assert-ScopeTrue ($located.Slices -is [array]) 'Single usable slice remains an array'
Assert-ScopeEqual @($located.Slices).Count 1 'LOCATED requires one slice'
foreach ($status in @('AMBIGUOUS','NOT_FOUND')) {
    $result = New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status $status -Slices @() -CandidateReferences @() -Diagnostics @()
    Assert-ScopeEqual @($result.Slices).Count 0 'Unresolved location has no usable slice'
    Assert-ScopeTrue (-not ($result.PSObject.Properties.Name -contains 'BenefitState')) 'Preparation status cannot invent benefit lifecycle'
}
foreach ($op in @('FAILED','PARTIAL','UNSUPPORTED')) {
    $result = New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus $op -Status $null -Slices @() -CandidateReferences @() -Diagnostics @()
    Assert-ScopeTrue ($null -eq $result.Status) 'Operational failure has no semantic absence status'
    Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus $op -Status NOT_FOUND -Slices @() } 'Incomplete processing cannot claim NOT_FOUND'
}
Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status LOCATED -Slices @() } 'LOCATED requires evidence'
Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status LOCATED -Slices @($x.Slice,$x.Slice) } 'A1 does not permit multi-row LOCATED'
Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 3 -OperationalStatus COMPLETE -Status LOCATED -Slices @($x.Slice) } 'Result row must match slice row'
Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status AMBIGUOUS -Slices @($x.Slice) } 'Ambiguity cannot expose usable slices'
Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status ENDED -Slices @() } 'Benefit state is not a location status'
Assert-ScopeThrows { New-BenefitEvidenceLocationResult -SourceRowNumber 2 -OperationalStatus COMPLETE -Status NOT_FOUND -Diagnostics @([pscustomobject]@{Code='incomplete'}) } 'Diagnostic shape must remain auditable'

# Regression: internally consistent names must still match actual source positions.
foreach ($wrongReference in @('HTML_TABLE_1_ROW_99','HTML_TABLE_99_ROW_2','HTML_TABLE_1_ROW_3')) {
    $x = New-ScopeContractFixture
    $x.Slice.EvidenceReference = $wrongReference
    foreach ($key in $x.Slice.FieldReferences.Keys) {
        $x.Slice.FieldReferences[$key].FieldReference = "$wrongReference/$key"
    }
    Assert-ScopeThrows { Assert-RelevantBenefitEvidenceSlice -Slice $x.Slice -Document $x.Document -SourceRowNumber 2 } "Physical reference must match original table and row: $wrongReference"
}

# Position checks operate on real elements, not HTML-looking text in opaque content.
foreach ($case in @(
    @{Prefix='<table><tr><td>earlier table</td></tr></table>'; Index=2},
    @{Prefix='<!-- <table><tr><td>ignored comment</td></tr></table> -->'; Index=1},
    @{Prefix='<script>const sample = "<table><tr><td>ignored script</td></tr></table>";</script>'; Index=1},
    @{Prefix='<div data-sample="<table><tr>not elements</tr></table>"></div>'; Index=1}
)) {
    $x = New-ScopeContractFixture
    $text = $case.Prefix + $x.Document.Text
    $document = New-ScopeTestDocument -Html $text
    $snapshot = New-BenefitSourceSnapshot -SourceUrl $document.Url -SourceFormat HTML -Text $text -ObservedAt $document.ObservedAt
    $sourceUnit = $x.Units[0]
    $offset = $case.Prefix.Length
    $reference = "HTML_TABLE_$($case.Index)_ROW_2"
    $fieldRefs = Copy-ScopeContractData $sourceUnit.FieldReferences
    foreach ($key in $fieldRefs.Keys) {
        $fieldRefs[$key].HeaderStart += $offset
        $fieldRefs[$key].CellStart += $offset
        $fieldRefs[$key].FieldReference = "$reference/$key"
    }
    $shifted = New-BenefitSourceContentUnit -Snapshot $snapshot -UnitReference $reference -TableStart $offset -TableLength $sourceUnit.TableLength -RawStart ($sourceUnit.RawStart+$offset) -RawLength $sourceUnit.RawLength -RawEvidenceText $sourceUnit.RawEvidenceText -StructuredFields $sourceUnit.StructuredFields -FieldReferences $fieldRefs
    $observation = New-BenefitSourceObservation -SourceRowNumber 2 -Snapshot $snapshot -AdapterId HTML_GENERIC -AdapterVersion 1 -AdapterStatus COMPLETE -ContentUnits @($shifted)
    $scoped = New-RelevantBenefitEvidenceSlice -Observation $observation -Unit $shifted
    Assert-RelevantBenefitEvidenceSlice -Slice $scoped -Document $document -SourceRowNumber 2
}
# A row written inside an HTML comment is not a real selected source element.
$fake = '<!-- <table><tr><td>comment only</td></tr></table> -->'
$fakeSnapshot = New-BenefitSourceSnapshot -SourceUrl $d.Url -SourceFormat HTML -Text $fake -ObservedAt $d.ObservedAt
$fakeTable = '<table><tr><td>comment only</td></tr></table>'
$fakeRow = '<tr><td>comment only</td></tr>'
Assert-ScopeThrows { New-BenefitSourceContentUnit -Snapshot $fakeSnapshot -UnitReference HTML_TABLE_1_ROW_1 -TableStart ($fake.IndexOf('<table>')) -TableLength $fakeTable.Length -RawStart ($fake.IndexOf('<tr>')) -RawLength $fakeRow.Length -RawEvidenceText 'comment only' -StructuredFields @{} -FieldReferences @{} } 'Comment text must not become a physical evidence row'
Assert-ScopeEqual (Get-BenefitVerificationContractDefinition | ConvertTo-Json -Depth 8 -Compress) $before 'Global contracts remain unchanged after use'
Write-Host 'Benefit evidence location contract tests passed.'
