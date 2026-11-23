Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'poi-verification-contracts.ps1')

$script:WarningOrder=@('NAME_EMPTY','NAME_NORMALIZATION_UNCERTAIN','BRANCH_UNCERTAIN','ADDRESS_EMPTY','ADDRESS_PARSE_PARTIAL','ADDRESS_PARSE_FAILED','BUILDING_NUMBER_UNCERTAIN','FLOOR_UNIT_UNCERTAIN')
$script:Provinces=@('서울특별시','부산광역시','대구광역시','인천광역시','광주광역시','대전광역시','울산광역시','세종특별자치시','경기도','강원특별자치도','충청북도','충청남도','전북특별자치도','전라남도','경상북도','경상남도','제주특별자치도')

function ConvertTo-IdentityComparisonText { param([AllowNull()]$Value) if ($null -eq $Value) { return '' }; return (([string]$Value).Normalize([Text.NormalizationForm]::FormKC).Trim().ToLowerInvariant() -replace '[\s,().·&-]', '') }
function Get-OrderedWarnings { param([string[]]$Warnings) return @($script:WarningOrder | Where-Object { $Warnings -contains $_ }) }
function Test-AdministrativeDongToken {
 param([string]$Token)
 if ($Token -notmatch '^[가-힣]+동$') { return $false }
 return $Token -notin @('상가동','판매동','관리동','주차동','본관동','별관동','신관동','구관동','복지동','업무동','사무동','기숙사동')
}
function Get-NormalizedNameParts {
 param([AllowNull()]$OriginalName,[AllowNull()][string[]]$LocalityHints=@())
 $original=ConvertTo-PoiText $OriginalName; $warnings=@(); $base=$original; $branch=''; $normal=ConvertTo-IdentityComparisonText $original
 if (-not $original) { $warnings+='NAME_EMPTY' } elseif (-not $normal) { $warnings+='NAME_NORMALIZATION_UNCERTAIN' }
 $m=[regex]::Match($original,'^(?<base>.+?)\s*\((?<branch>[^()]+점)\)\s*$')
 if ($m.Success) { $candidate=$m.Groups['branch'].Value.Trim(); if ($candidate -notin @('전문점','음식점','상점','매장')) { $base=$m.Groups['base'].Value.Trim(); $branch=$candidate } }
 else {
  $m=[regex]::Match($original,'^(?<base>.+?)\s+(?<branch>본점|직영점|\d+호점)\s*$')
  if ($m.Success) { $base=$m.Groups['base'].Value.Trim(); $branch=$m.Groups['branch'].Value.Trim() }
  else {
   $m=[regex]::Match($original,'^(?<base>.+?)\s+(?<branch>[가-힣A-Za-z0-9]+점)\s*$')
   if ($m.Success) {
    $candidate=$m.Groups['branch'].Value; $stem=$candidate.Substring(0,$candidate.Length-1)
    $hintParts=@($LocalityHints|ForEach-Object { ([string]$_ -replace '(시|구|군|동|읍|면)$','') }|Where-Object{$_})
    $hints=@(); for($i=0;$i -lt $hintParts.Count;$i++) { $hints+=($hintParts[$i..($hintParts.Count-1)] -join '') }
    if ($stem -in $hints) { $base=$m.Groups['base'].Value.Trim(); $branch=$candidate } elseif ($candidate -notin @('전문점','음식점','상점','매장')) { $warnings+='BRANCH_UNCERTAIN' }
   }
  }
 }
 [pscustomobject][ordered]@{NormalizedName=$normal;BaseName=$base;BranchName=$branch;Warnings=(Get-OrderedWarnings $warnings)}
}
function Get-AdministrativeAddressParts {
 param([AllowNull()]$Address)
 $text=ConvertTo-PoiText $Address; $province='';$city='';$district='';$dong=''
 foreach($p in $script:Provinces){if($text -match ('(^|[\s,])'+[regex]::Escape($p)+'(?=$|[\s,])')){$province=$p;break}}
 foreach($rawToken in ($text -split '[\s,()]+'|Where-Object{$_})) {
  $t=$rawToken
  if ($t -in $script:Provinces) { continue }
  foreach ($p in $script:Provinces) {
   if ($t.StartsWith($p, [StringComparison]::Ordinal)) {
    $rest=$t.Substring($p.Length)
    if ($rest -match '^[가-힣]+(시|구|군)$') {
     if (-not $province) { $province=$p }
     $t=$rest
     break
    }
   }
  }
  if(-not $city -and $t -match '시$'){ $city=$t;continue }
  if(-not $district -and $t -match '(구|군)$'){ $district=$t;continue }
  if(-not $dong -and (($t -match '(읍|면)$') -or (Test-AdministrativeDongToken $t))){ $dong=$t }
 }
 [pscustomobject][ordered]@{Province=$province;City=$city;District=$district;Dong=$dong}
}
function Get-NormalizedAddressParts {
 param([string]$RoadAddress,[string]$LotAddress,[string]$MetadataProvince,[string]$MetadataArea)
 $road=ConvertTo-PoiText $RoadAddress;$lot=ConvertTo-PoiText $LotAddress;$preferred=if($road){$road}else{$lot};$warnings=@();$roadName='';$main='';$sub='';$floor='';$unit='';$partial=$false;$ambiguous=$false
 if(-not $preferred){return [pscustomobject][ordered]@{PreferredAddress='';Province='';City='';District='';Dong='';RoadName='';BuildingMain='';BuildingSub='';Floor='';Unit='';AddressParseStatus='UNPARSED';Warnings=@('ADDRESS_EMPTY')}}
 $parsed=Get-AdministrativeAddressParts $preferred;$meta=Get-AdministrativeAddressParts "$MetadataProvince $MetadataArea"
 foreach($key in @('Province','City','District','Dong')) { $pv=[string]$parsed.$key;$mv=[string]$meta.$key;if($pv -and $mv -and $pv -ne $mv){$parsed.$key='';$partial=$true}elseif(-not $pv -and $mv){$parsed.$key=$mv} }
 if($road){
  $roadText=$road.Trim()
  $hadProvince=$false
  $strippedProvince=''
  foreach($p in $script:Provinces){
   if($roadText -match ('^(?:'+([regex]::Escape($p))+')\s*')){$roadText=$roadText.Substring($matches[0].Length);$hadProvince=$true;$strippedProvince=$p;break}
  }
  if(-not $hadProvince -and $roadText -match '^서울시\s*'){$roadText=$roadText.Substring($matches[0].Length);$hadProvince=$true;$strippedProvince='서울특별시'}
  $effectiveProvince=if($parsed.Province){$parsed.Province}else{$strippedProvince}
  $metroProvinces=@('서울특별시','인천광역시','부산광역시','대구광역시','광주광역시','대전광역시','울산광역시','세종특별자치시')
  $isMetroProvince=($effectiveProvince -in $metroProvinces)
  $guCities=@('수원시','성남시','안양시','부천시','고양시','용인시','안산시','화성시')
  $expectGluedGu=$isMetroProvince
  $hadCity=$false
  if($parsed.City -and $roadText -match ('^(?:'+([regex]::Escape($parsed.City))+')\s*')){
   $roadText=$roadText.Substring($matches[0].Length)
   $hadCity=$true
   if($parsed.City -in $guCities){$expectGluedGu=$true}
  }elseif(-not $isMetroProvince -and $roadText -match '^[가-힣]+(?:광역시|특별시|특별자치시|시)\s+'){
   $matchedCity=($matches[0]).Trim()
   $roadText=$roadText.Substring($matches[0].Length)
   $hadCity=$true
   if($matchedCity -in $guCities){$expectGluedGu=$true}
  }elseif($hadProvince -and -not $isMetroProvince -and $roadText -match '^(?:시흥시|구리시|[^구시]{2,4}시)(?=[가-힣A-Za-z0-9]+(?:구|군|읍|면|로|길))'){
   $matchedCity=$matches[0]
   $roadText=$roadText.Substring($matchedCity.Length)
   $hadCity=$true
   if($matchedCity -in $guCities){$expectGluedGu=$true}
  }
  if($parsed.District -and $roadText -match ('^(?:'+([regex]::Escape($parsed.District))+')\s*')){
   $roadText=$roadText.Substring($matches[0].Length)
  }elseif($roadText -match '^[가-힣]+(?:구|군)\s+'){
   $roadText=$roadText.Substring($matches[0].Length)
  }elseif($expectGluedGu -and $roadText -match '^(?:구로구|[^구군시]{1,4}구)(?=[가-힣A-Za-z0-9]+(?:읍|면|로|길))'){
   $roadText=$roadText.Substring($matches[0].Length)
  }elseif(($expectGluedGu -or $hadProvince) -and -not $hadCity -and $effectiveProvince -ne '서울특별시' -and $roadText -match '^(?:군위군|[^구군시]{2,4}군)(?=[가-힣A-Za-z0-9]+(?:읍|면|로|길))'){
   $roadText=$roadText.Substring($matches[0].Length)
  }
  if($parsed.Dong -and $parsed.Dong -match '(?:읍|면)$' -and $roadText -match ('^(?:'+([regex]::Escape($parsed.Dong))+')\s*')){
   $roadText=$roadText.Substring($matches[0].Length)
  }elseif($roadText -match '^[가-힣]+(?:읍|면)\s+'){
   $roadText=$roadText.Substring($matches[0].Length)
  }elseif($hadProvince -and $effectiveProvince -ne '서울특별시' -and $roadText -match '^[^구군시읍면]{1,4}(?:읍|면)(?=[가-힣A-Za-z0-9]+(?:로|길))'){
   $roadText=$roadText.Substring($matches[0].Length)
  }
  if($roadText -match '^[가-힣]+동\s+'){
   $roadText=$roadText.Substring($matches[0].Length)
  }
  $rm=[regex]::Match($roadText,'(?<road>[가-힣A-Za-z0-9]+(?:번안길|번길|길|로))\s*(?:지하\s*)?(?<tail>\d+(?:\s*-\s*\d+)?)(?=$|[\s,()]|[A-Za-z]+동|상가\d*동)')
  if($rm.Success){$roadName=$rm.Groups['road'].Value;$tail=$rm.Groups['tail'].Value;if($tail -match '^\d+\s*-\s*\d+$'){$parts=$tail -split '\s*-\s*';$main=$parts[0];$sub=$parts[1]}else{$main=$tail}}
  else { $roadOnly=[regex]::Match($roadText,'(?<road>[가-힣A-Za-z0-9]+(?:번안길|번길|길|로))');if($roadOnly.Success){$roadName=$roadOnly.Groups['road'].Value;$partial=$true} }
  if($road -match '(?:번길|길|로)\d+\s*-\s*\d+층'){$main='';$sub='';$ambiguous=$true;$warnings+='BUILDING_NUMBER_UNCERTAIN';$warnings+='FLOOR_UNIT_UNCERTAIN'}
  $floors=[regex]::Matches($road,'(?<![가-힣A-Za-z0-9])((?:지하\s*|B\s*)?\d+)\s*층',[Text.RegularExpressions.RegexOptions]::IgnoreCase);$units=[regex]::Matches($road,'(?<![가-힣A-Za-z0-9-])([A-Za-z]\s*-\s*\d+|\d+)\s*호')
  if($road -match '[~]|\d+호\s*,\s*\d+호|\d+\s*-\s*\d+\s*호|(?<![A-Za-z0-9])[A-Za-z]\s*\d+\s*호' -or $floors.Count -gt 1 -or $units.Count -gt 1){$ambiguous=$true;$warnings+='FLOOR_UNIT_UNCERTAIN'}else{if($floors.Count -eq 1){$floor=($floors[0].Groups[1].Value -replace '\s+','')};if($units.Count -eq 1){$unit=($units[0].Groups[1].Value -replace '\s+','').ToUpperInvariant()}}
 }
 if($ambiguous){$floor='';$unit='';$partial=$true};if(-not $roadName -or -not $main){$partial=$true};if(-not (@($parsed.Province,$parsed.City,$parsed.District,$parsed.Dong)|Where-Object{$_})){$partial=$true};if($partial){$warnings+='ADDRESS_PARSE_PARTIAL'}
 $has=@($parsed.Province,$parsed.City,$parsed.District,$parsed.Dong,$roadName)|Where-Object{$_};$status=if(-not $has){$warnings+='ADDRESS_PARSE_FAILED';'UNPARSED'}elseif($partial){'PARTIAL'}else{'COMPLETE'}
 [pscustomobject][ordered]@{PreferredAddress=$preferred;Province=$parsed.Province;City=$parsed.City;District=$parsed.District;Dong=$parsed.Dong;RoadName=$roadName;BuildingMain=$main;BuildingSub=$sub;Floor=$floor;Unit=$unit;AddressParseStatus=$status;Warnings=(Get-OrderedWarnings $warnings)}
}
function ConvertTo-NormalizedBusiness { param([Parameter(Mandatory)]$Row,[Parameter(Mandatory)][int]$SourceRowNumber)
 $address=Get-NormalizedAddressParts ([string]$Row.소재지도로명주소) ([string]$Row.소재지지번주소) ([string]$Row.시도) ([string]$Row.시군구);$name=Get-NormalizedNameParts ([string]$Row.업소명) @($address.Province,$address.City,$address.District,$address.Dong);$warnings=Get-OrderedWarnings (@($name.Warnings)+@($address.Warnings))
 $out=New-NormalizedBusiness -SourceRowNumber $SourceRowNumber -OriginalName ([string]$Row.업소명) -NormalizedName $name.NormalizedName -BaseName $name.BaseName -BranchName $name.BranchName -OriginalRoadAddress ([string]$Row.소재지도로명주소) -OriginalLotAddress ([string]$Row.소재지지번주소) -PreferredAddress $address.PreferredAddress -Province $address.Province -City $address.City -District $address.District -Dong $address.Dong -RoadName $address.RoadName -BuildingMain $address.BuildingMain -BuildingSub $address.BuildingSub -Floor $address.Floor -Unit $address.Unit -AddressParseStatus $address.AddressParseStatus -NormalizationWarnings $warnings;Assert-NormalizedBusiness $out;return $out }
