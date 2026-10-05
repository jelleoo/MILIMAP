Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'testdata/benefit-evidence-pdf/test-support.ps1')
$project=Join-Path $PSScriptRoot 'pdf-native/Milimap.PdfNative.csproj'
if(-not (Test-Path $project)){throw 'Missing isolated PdfPig helper project'}
$dotnet=(Get-Command dotnet -ErrorAction Stop).Source
$null=& $dotnet restore $project --locked-mode
if($LASTEXITCODE -ne 0){throw 'Locked helper restore failed'}
$null=& $dotnet build $project -c Release --no-restore
if($LASTEXITCODE -ne 0){throw 'Helper build failed'}
$dll=Join-Path $PSScriptRoot 'pdf-native/bin/Release/net8.0/Milimap.PdfNative.dll'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-pdf-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
try {
    $raw=& $dotnet $dll inspect --input (Join-Path $scratch 'missing.pdf')
    Assert-PdfEqual $LASTEXITCODE 1 'Missing input must fail'
    $missing=($raw -join "`n") | ConvertFrom-Json
    Assert-PdfEqual $missing.OpenStatus 'FAILED' 'Missing file structured status'
    Assert-PdfEqual $missing.Diagnostics[0].Code 'FILE_NOT_FOUND' 'Missing file diagnostic'
    $bytes=New-PdfTestBytes;$file=Join-Path $scratch 'minimal.pdf';[IO.File]::WriteAllBytes($file,$bytes)
    $first=((& $dotnet $dll inspect --input $file) -join "`n")
    Assert-PdfEqual $LASTEXITCODE 0 'Native input opens'
    $second=((& $dotnet $dll inspect --input $file) -join "`n")
    Assert-PdfEqual $LASTEXITCODE 0 'Repeated native input opens'
    Assert-PdfEqual $first $second 'Deterministic primitive projection'
    $p=$first | ConvertFrom-Json
    Assert-PdfEqual $p.SchemaVersion 1 'Projection schema'
    Assert-PdfEqual $p.ParserId 'PDFPIG' 'Parser identity'
    Assert-PdfEqual $p.ParserVersion '0.1.16' 'Exact parser pin'
    Assert-PdfEqual $p.OpenStatus 'COMPLETE' 'Native parse status'
    Assert-PdfEqual $p.Pages.Count 1 'Physical page count'
    Assert-PdfEqual ($p.Pages[0].Letters.Text -join '') 'Synthetic native control' 'Native text'
    if($first -match 'UglyToad|PdfPig\.'){throw 'Parser CLR types leaked through JSON'}
    $lock=Get-Content (Join-Path $PSScriptRoot 'pdf-native/packages.lock.json') -Raw | ConvertFrom-Json
    Assert-PdfEqual $lock.dependencies.'net8.0'.PdfPig.resolved '0.1.16' 'Locked resolved version'
    Assert-PdfEqual $lock.dependencies.'net8.0'.PdfPig.requested '[0.1.16, 0.1.16]' 'Exact dependency range'
} finally {[IO.Directory]::Delete($scratch,$true)}
. (Join-Path $PSScriptRoot 'lib/benefit-evidence/pdf-native-runtime.ps1')
$bytes=New-PdfTestBytes
$runtime=Invoke-BenefitPdfNativeProjection -Bytes $bytes
Assert-PdfEqual $runtime.Status 'COMPLETE' 'Real isolated runtime success'
Assert-PdfEqual $runtime.Projection.FileSha256 (Get-BenefitEvidenceByteHash $bytes) 'Byte/hash identity'
$originalCommand=(Get-Item Function:Get-InternalBenefitPdfNativeCommand).ScriptBlock
$script:PdfFaultMode='schema'
try {
    function Get-InternalBenefitPdfNativeCommand {
        param([string]$InputFile)
        [pscustomobject]@{FileName=(Get-Command pwsh).Source;Arguments=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'testdata/benefit-evidence-pdf/fault-helper.ps1'),'-Mode',$script:PdfFaultMode,'-InputFile',$InputFile)}
    }
    foreach($case in @(@('schema','PDF_PROJECTION_INVALID'),@('parser','PDF_PROJECTION_INVALID'),@('version','PDF_PROJECTION_INVALID'),@('hash','PDF_PROJECTION_INVALID'),@('json','PDF_PROJECTION_INVALID'),@('crash','PDF_PROCESS_FAILED'),@('timeout','PDF_PROCESS_TIMEOUT'),@('output','PDF_OUTPUT_LIMIT'))){
        $script:PdfFaultMode=$case[0]
        $before=@(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'milimap-pdf-native-*').Count
        $timeout=if($case[0] -ceq 'timeout'){100}else{5000}
        $r=Invoke-BenefitPdfNativeProjection -Bytes $bytes -TimeoutMilliseconds $timeout -MaxOutputBytes 4096
        Assert-PdfEqual $r.Status 'FAILED' "$($case[0]) fail closed"
        Assert-PdfEqual $r.Projection $null "$($case[0]) discards projection"
        Assert-PdfEqual $r.Diagnostics[0].Code $case[1] "$($case[0]) diagnostic"
        Assert-PdfEqual (@(Get-ChildItem ([IO.Path]::GetTempPath()) -Directory -Filter 'milimap-pdf-native-*').Count) $before "$($case[0]) temporary cleanup"
    }
} finally {Set-Item Function:Get-InternalBenefitPdfNativeCommand $originalCommand}
Write-Host 'PDF native helper/runtime boundary tests passed.'
$oversized=[byte[]]::new(10485761)
[Text.Encoding]::ASCII.GetBytes('%PDF-1.4').CopyTo($oversized,0)
$r=Invoke-BenefitPdfNativeProjection -Bytes $oversized
Assert-PdfEqual $r.Diagnostics[0].Code 'PDF_SOURCE_LIMIT' 'Oversized source rejected before parser open'
foreach($case in @(
    @('pages',(New-PdfTestBytes -PageCount 33),'PDF_PAGE_LIMIT'),
    @('letters',(New-PdfTestBytes -Content ('BT /F1 12 Tf 20 100 Td (a) Tj ET '*20001)),'PDF_LETTER_LIMIT'),
    @('paths',(New-PdfTestBytes -Content (('20 20 m 30 20 l S '+"`n")*2049)),'PDF_PATH_LIMIT')
)) {
    $r=Invoke-BenefitPdfNativeProjection -Bytes $case[1]
    Assert-PdfEqual $r.Status FAILED "$($case[0]) quota fails closed"
    Assert-PdfEqual $r.Projection $null "$($case[0]) leaves no physical evidence"
    Assert-PdfEqual $r.Diagnostics[0].Code $case[2] "$($case[0]) explicit quota"
}
$deep=New-PdfTestBytes -Content (('['*300)+'1'+(']'*300)+' unknownOperator')
$r=Invoke-BenefitPdfNativeProjection -Bytes $deep
Assert-PdfEqual $r.Status FAILED 'Deep malformed input fails closed'
Assert-PdfEqual $r.Projection $null 'Deep malformed input yields no evidence'
Write-Host 'PDF resource limits tests passed.'
