$ErrorActionPreference='Stop'

. (Join-Path $PSScriptRoot 'invoke-phase2-benefit-shadow-mode.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-history-adapter.ps1')
. (Join-Path $PSScriptRoot 'lib/history/benefit-incremental-reuse.ps1')

function Assert-Equal { param($Actual,$Expected,[string]$Message); if($Actual -cne $Expected){ throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition,[string]$Message); if(-not $Condition){ throw $Message } }
function Assert-NotEqual { param($Actual,$Expected,[string]$Message); if($Actual -ceq $Expected){ throw $Message } }

$htmlCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefit' -SourceKind PUBLIC_OFFICIAL -SourceLabel 'fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
$htmlDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text '<html><body>10% 할인</body></html>' -ObservedAt '2026-09-26T00:00:00Z'
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $htmlCandidate -Document $htmlDocument) 'POST_FETCH' 'Official HTML supports POST_FETCH reuse'

$xlsxDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url 'https://city.example.go.kr/benefit.xlsx' -SourceFormat XLSX -FetchStatus COMPLETE -ContentType 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' -Text '' -Bytes ([byte[]](1,2,3,4)) -ObservedAt '2026-09-26T00:00:00Z'
$xlsxCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url $xlsxDocument.Url -SourceKind PUBLIC_OFFICIAL -SourceLabel 'fixture' -DiscoveryMethod TEST -ObservedAt '2026-09-26T00:00:00Z'
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $xlsxCandidate -Document $xlsxDocument) 'POST_FETCH' 'Official XLSX supports POST_FETCH reuse'

$mmaCandidate=New-BenefitSourceCandidate -SourceRowNumber 2 -Url 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357' -SourceKind PUBLIC_OFFICIAL -SourceLabel 'MMA' -DiscoveryMethod EXISTING_CANONICAL_URL -ObservedAt '2026-09-26T00:00:00Z'
$mmaDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $mmaCandidate.Url -SourceFormat JSONP -FetchStatus COMPLETE -ContentType 'application/javascript' -Text 'callback({});' -ObservedAt '2026-09-26T00:00:00Z'
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $mmaCandidate -Document $mmaDocument) 'NONE' 'MMA JSONP remains outside P3-4 reuse'

$failedDocument=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus FAILED -ContentType 'text/html' -Text '' -ObservedAt '2026-09-26T00:00:00Z' -ReasonCodes @('SOURCE_FETCH_FAILED')
Assert-Equal (Get-BenefitIncrementalCapability -Candidate $htmlCandidate -Document $failedDocument) 'NONE' 'Failed fetch cannot enter reuse capability'

$checkpoint1=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocument
$htmlDocumentLater=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text $htmlDocument.Text -ObservedAt '2026-09-27T00:00:00Z'
$checkpoint2=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocumentLater
Assert-Equal $checkpoint1.ContentHash $checkpoint2.ContentHash 'ObservedAt must not affect payload checkpoint'
Assert-Equal $checkpoint1.SourceUrl $checkpoint2.SourceUrl 'Checkpoint preserves stable source identity'
Assert-Equal $checkpoint1.SourceFormat $checkpoint2.SourceFormat 'Checkpoint preserves source format'

$htmlDocumentChanged=New-BenefitSourceDocument -SourceRowNumber 2 -Url $htmlCandidate.Url -SourceFormat HTML -FetchStatus COMPLETE -ContentType 'text/html' -Text '<html><body>20% 할인</body></html>' -ObservedAt '2026-09-27T00:00:00Z'
$checkpointChanged=New-BenefitIncrementalPayloadCheckpoint -Document $htmlDocumentChanged
Assert-NotEqual $checkpoint1.ContentHash $checkpointChanged.ContentHash 'Payload content change must change checkpoint'

$xlsxCheckpoint=New-BenefitIncrementalPayloadCheckpoint -Document $xlsxDocument
Assert-True ($xlsxCheckpoint.ContentHash -match '^[0-9a-f]{64}$') 'XLSX checkpoint uses stable payload hash'

Assert-True (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider { [pscustomobject]@{IsClean=$true} }) 'Injected clean repository state permits reuse'
Assert-True (-not (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider { [pscustomobject]@{IsClean=$false} })) 'Injected dirty repository state rejects reuse'
Assert-True (-not (Test-BenefitIncrementalRepositoryClean -RepositoryStateProvider { throw 'git unavailable' })) 'Repository-state failure is fail closed'

Write-Host 'Benefit incremental checkpoint tests passed.'
