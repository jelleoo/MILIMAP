Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/benefit-evidence-location-contracts.ps1')
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-hwpx/test-support.ps1')
$adapter=Join-Path $PSScriptRoot 'lib/benefit-evidence/convert-hwpx-source-observation.ps1'
if(Test-Path $adapter){. $adapter}
$valid=Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot)
Assert-HwpxEqual $valid.Status COMPLETE 'Valid package resolves trusted section'
Assert-HwpxEqual $valid.Sections.Count 1 'One spine member parsed'
Assert-HwpxEqual $valid.Sections[0].EntryName 'Contents/section0.xml' 'Exact package member retained'
Assert-HwpxEqual $valid.Sections[0].SectionOrdinal 1 'Spine ordinal starts at one'
$root="<o:package xmlns:o='http://www.idpf.org/2007/opf'><o:manifest><o:item id='s' href='section0.xml'/></o:manifest><o:spine><o:itemref idref='s'/></o:spine></o:package>"
Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes (New-HwpxTestBytes -RootXml $root))).Status COMPLETE 'Equivalent OPF prefixes accepted'
foreach($badRoot in @('<broken',($root.Replace('http://www.idpf.org/2007/opf','urn:wrong')),($root.Replace('section0.xml','../section0.xml')),($root.Replace('section0.xml','https://bad.example/section0.xml')),($root.Replace("<o:item id='s' href='section0.xml'/>","<o:item id='s' href='section0.xml'/><o:item id='s' href='section0.xml'/>")),($root.Replace("<o:itemref idref='s'/>","<o:itemref idref='s'/><o:itemref idref='s'/>")),($root.Replace('section0.xml','missing.xml')),($root.Replace("idref='s'","idref='missing'")),("<!DOCTYPE x [<!ENTITY ex SYSTEM 'file:///must-not-read'>]>"+$root))){
    Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes (New-HwpxTestBytes -RootXml $badRoot))).Status FAILED 'Untrusted manifest/spine fails closed'
}
foreach($badSection in @('<broken',"<!DOCTYPE x [<!ENTITY ex SYSTEM 'https://must-not-fetch.example'>]><x/>",'<s:sec xmlns:s="urn:wrong"/>')){
    $partial=Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes (New-HwpxTestBytes -Sections @('<hs:sec xmlns:hs="http://www.hancom.co.kr/hwpml/2011/section"/>',$badSection)))
    Assert-HwpxEqual $partial.Status PARTIAL 'Bad section is isolated'
    Assert-HwpxEqual $partial.Sections.Count 1 'Only safe section retained'
    Assert-HwpxEqual $partial.Diagnostics.Count 1 'Isolation diagnostic retained'
}
foreach($bytes in @((New-HwpxTestBytes -MissingRoot),(New-HwpxTestBytes -Mimetype wrong),(New-HwpxTestBytes -ExtraEntries @([pscustomobject]@{Name='../unsafe';Text='x'})),(New-HwpxTestBytes -ExtraEntries @([pscustomobject]@{Name='Contents/SECTION0.xml';Text='x'})),(New-HwpxTestBytes -ExtraEntries @(1..257|ForEach-Object{[pscustomobject]@{Name="extra/$_";Text='x'}})))){
    Assert-HwpxEqual (Read-InternalBenefitHwpxPackage -Snapshot (New-HwpxTestSnapshot -Bytes $bytes)).Status FAILED 'Unsafe or bounded-invalid ZIP rejected'
}
Write-Host 'HWPX package/XML tests passed.'
