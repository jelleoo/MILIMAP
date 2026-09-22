$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/identity/normalize-business.ps1')
function Assert-Equal { param($Actual,$Expected,[string]$Message); if ($Actual -cne $Expected) { throw "$Message (expected: $Expected, actual: $Actual)" } }
function Assert-True { param([bool]$Condition,[string]$Message); if (-not $Condition) { throw $Message } }

$name = Get-NormalizedNameParts -OriginalName ' 레드폴바버샵 강남신사점 ' -LocalityHints @('강남','신사')
Assert-Equal $name.NormalizedName '레드폴바버샵강남신사점' 'Comparison form is deterministic'
Assert-Equal $name.BaseName '레드폴바버샵' 'Base is source-like for B'
Assert-Equal $name.BranchName '강남신사점' 'Proved locality branch is retained'
$negative = Get-NormalizedNameParts -OriginalName '테스트 전문점'
Assert-Equal $negative.BranchName '' 'Generic type is not branch evidence'
$suwon=Get-AdministrativeAddressParts '경기도 수원시 권선구'; Assert-Equal $suwon.City '수원시' 'City parsing'; Assert-Equal $suwon.District '권선구' 'District parsing'
$gap=Get-AdministrativeAddressParts '경기도 가평군 가평읍'; Assert-Equal $gap.City '' 'County is not city'; Assert-Equal $gap.District '가평군' 'County district'; Assert-Equal $gap.Dong '가평읍' 'Eup dong'
$inHair=Get-NormalizedAddressParts '경기도 동두천시 삼육사로902, 2동 104호(생연동)' '' '경기도' '동두천시'; Assert-Equal $inHair.RoadName '삼육사로' 'No-space road'; Assert-Equal $inHair.BuildingMain '902' 'No-space building'; Assert-Equal $inHair.Unit '104' 'Unit'
$sculls=Get-NormalizedAddressParts '경기도 시흥시 서울대학로264번길 12, 208동 1층 B-112호' '' '경기도' '시흥시'; Assert-Equal $sculls.RoadName '서울대학로264번길' 'Numeric road'; Assert-Equal $sculls.BuildingMain '12' 'Building'; Assert-Equal $sculls.Floor '1' 'Floor'; Assert-Equal $sculls.Unit 'B-112' 'Alpha unit'
$bad=Get-NormalizedAddressParts '경기도 수원시 팔달구신풍로23번길63- 21층 (신풍동)' '' '경기도' '수원시'; Assert-Equal $bad.RoadName '신풍로23번길' 'Malformed road'; Assert-Equal $bad.BuildingMain '' 'No guessed building'; Assert-Equal $bad.Floor '' 'No guessed floor'; Assert-True ($bad.Warnings -contains 'BUILDING_NUMBER_UNCERTAIN') 'Building warning'
$row=[pscustomobject]@{업소명='레드폴바버샵 강남신사점';시도='서울특별시';시군구='강남구';소재지도로명주소='서울특별시 강남구 논현로151길 41, 2층 201호';소재지지번주소='서울특별시 강남구 신사동 561'};$business=ConvertTo-NormalizedBusiness $row 2;Assert-NormalizedBusiness $business;Assert-Equal $business.PreferredAddress $business.OriginalRoadAddress 'Preferred preserves road'
Write-Host 'Normalization tests passed.'
