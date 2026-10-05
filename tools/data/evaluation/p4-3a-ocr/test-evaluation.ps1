param([ValidateSet('Contract','ImageEligibility','GridOcr','Safety','All')][string]$Group='All',
    [string]$TesseractExecutable,[string]$KoreanModelPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($Group -in @('Safety','All')){
    throw 'NOT_RUN_CORE_ACCEPTANCE_GATE_FAILED: Task 4/5 are intentionally unimplemented; run Contract, ImageEligibility, and GridOcr separately. All cannot claim PASS.'
}
function Require($Condition,[string]$Message){ if(-not $Condition){throw $Message} }
if($Group -in @('Contract','All')){
    $project=Join-Path $PSScriptRoot 'Milimap.P4_3A.OcrEval.csproj'
    Require (Test-Path -LiteralPath $project) 'Missing evaluation-only PDF inspection project'
    & dotnet restore $project --locked-mode | Out-Host
    Require ($LASTEXITCODE -eq 0) 'Locked restore failed'
    & dotnet build $project -c Release --no-restore | Out-Host
    Require ($LASTEXITCODE -eq 0) 'Evaluation build failed'
    $dll=Join-Path $PSScriptRoot 'bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
    $absent=& dotnet $dll inspect --input (Join-Path $PSScriptRoot 'missing.pdf') --artifact-dir ([IO.Path]::GetTempPath()) | ConvertFrom-Json
    Require ($absent.Status -eq 'FAILED' -and $absent.OpenCount -eq 0) 'Missing PDF must fail without open'
    $pdf=Join-Path $PSScriptRoot '../../testdata/benefit-evidence-pdf/two-business.pdf'
    $valid=& dotnet $dll inspect --input $pdf --artifact-dir ([IO.Path]::GetTempPath()) | ConvertFrom-Json
    Require ($valid.SchemaVersion -eq 1 -and $valid.ProbeId -ceq 'MILIMAP_P4_3A_OCR_EVAL' -and $valid.PdfPigVersion -ceq '0.1.16') 'Inspection identity mismatch'
    Require ($valid.OpenCount -eq 1 -and $valid.Status -eq 'NATIVE_TEXT') 'Valid native PDF must open exactly once'
    . (Join-Path $PSScriptRoot 'invoke-tesseract-eval.ps1')
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('p43a-contract-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $model=Join-Path $scratch 'kor.traineddata'; [IO.File]::WriteAllBytes($model,[byte[]]@(1,2,3))
        $hash=(Get-FileHash $model -Algorithm SHA256).Hash.ToLowerInvariant()
        $missing=Invoke-TesseractEvaluation -Executable (Join-Path $scratch 'missing.exe') -ModelPath $model -ModelHash $hash -Inputs @()
        Require ($missing.Status -eq 'FAILED' -and $missing.Code -eq 'EXECUTABLE_MISSING' -and $missing.InvocationCount -eq 0) 'Missing engine must fail closed'
        $wrong=Invoke-TesseractEvaluation -Executable (Get-Command pwsh).Source -ModelPath $model -ModelHash $hash -Inputs @()
        Require ($wrong.Status -eq 'FAILED' -and $wrong.Code -eq 'ENGINE_VERSION_MISMATCH' -and $wrong.InvocationCount -eq 0) 'Wrong engine must fail before OCR'
        $missingModel=Invoke-TesseractEvaluation -Executable (Get-Command pwsh).Source -ModelPath (Join-Path $scratch 'absent') -ModelHash $hash -Inputs @()
        Require ($missingModel.Code -eq 'MODEL_MISSING') 'Missing model must reject'
        $wrongModel=Invoke-TesseractEvaluation -Executable (Get-Command pwsh).Source -ModelPath $model -ModelHash ('0'*64) -Inputs @()
        Require ($wrongModel.Code -eq 'MODEL_HASH_MISMATCH') 'Wrong model must reject'
    }finally{[IO.Directory]::Delete($scratch,$true)}
    Write-Host 'Contract PASS'
}
if($Group -in @('ImageEligibility','All')){
    $dll=Join-Path $PSScriptRoot 'bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
    $manifest=Get-Content (Join-Path $PSScriptRoot 'fixtures/manifest.json') -Raw | ConvertFrom-Json
    foreach($name in @('gray','rgb','multi-image','partial-image','one-bit','cmyk','undecodable','multipage')){
        $fixture=@($manifest.fixtures | Where-Object name -eq $name)[0]
        $pdf=Join-Path $PSScriptRoot ('fixtures/'+$name+'.pdf')
        Require ((Get-FileHash $pdf).Hash.ToLowerInvariant() -ceq $fixture.sha256) 'Fixture bytes changed'
        $scratch=Join-Path ([IO.Path]::GetTempPath()) ('p43a-image-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($scratch)
        try{
            $result=& dotnet $dll inspect --input $pdf --artifact-dir $scratch | ConvertFrom-Json
            Require ($result.OpenCount -eq 1) "$name must open once"
            Require ($result.PageReadCount -eq $result.Pages.Count -or $result.Status -in @('UNSUPPORTED','FAILED')) 'Eligible pages must not be parsed twice for image handoff'
            Require ($result.Status -ceq $fixture.expectedEligibility) "$name image eligibility: expected $($fixture.expectedEligibility), got $($result.Status)"
            if($fixture.expectedEligibility -eq 'ELIGIBLE'){
                Require ($result.Images.Count -eq $result.Pages.Count) "$name one image per page"
                foreach($image in $result.Images){
                    Require (Test-Path $image.ArtifactPath) 'Missing bounded pixel artifact'
                    Require ($image.PixelSha256 -eq (Get-FileHash $image.ArtifactPath).Hash.ToLowerInvariant()) 'Pixel artifact provenance mismatch'
                    Require ($image.PixelSha256 -ceq $fixture.expectedPixelHashes[$image.PageNumber-1]) 'Decoded pixels differ from independently authored source'
                    Require ($image.Width -eq 1600 -and $image.Height -eq 900) 'Wrong decoded dimensions'
                }
            }else{Require (@(Get-ChildItem $scratch -File).Count -eq 0) 'Rejected document leaked pixel artifact'}
        }finally{[IO.Directory]::Delete($scratch,$true)}
    }
    Write-Host 'ImageEligibility PASS'
}
if($Group -in @('GridOcr','All')){
    $runner=Join-Path $PSScriptRoot 'run-evaluation.ps1'
    Require (Test-Path $runner) 'Missing pixel-grid Korean OCR evaluation runner'
    . $runner
    Require ($TesseractExecutable -and $KoreanModelPath) 'GridOcr requires explicit external engine and official model paths; missing runtime is NOT_RUN, not PASS'
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('p43a-ocr-contract-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    try{
        $dll=Join-Path $PSScriptRoot 'bin/Release/net8.0/Milimap.P4_3A.OcrEval.dll'
        $inspect=& dotnet $dll inspect --input (Join-Path $PSScriptRoot 'fixtures/gray.pdf') --artifact-dir $scratch | ConvertFrom-Json
        $actual=Invoke-TesseractEvaluation -Executable $TesseractExecutable -ModelPath $KoreanModelPath -ModelHash '6b85e11d9bbf07863b97b3523b1b112844c43e713df8b66418a081fd1060b3b2' -Inputs @($inspect.Images[0].ArtifactPath)
        Require ($actual.Status -eq 'COMPLETE' -and $actual.EngineVersion -ceq '5.5.3' -and $actual.InvocationCount -eq 1 -and $actual.Words.Count -gt 0) 'Verified Windows release build must supply real OCR TSV, not be rejected or stubbed'
    }finally{[IO.Directory]::Delete($scratch,$true)}
    $cells=@([pscustomobject]@{Id=1;X0=0;Y0=0;X1=100;Y1=100},[pscustomobject]@{Id=2;X0=100;Y0=0;X1=200;Y1=100})
    $cross=Resolve-EvaluationOcrCells -Cells $cells -Words @([pscustomobject]@{Left=90;Top=10;Width=20;Height=20;Confidence=99;Text='cross';Page=1}) -Threshold 0
    Require ($cross.Status -eq 'PARTIAL' -and $cross.Accepted.Count -eq 0) 'Cross-cell box must not be assigned by centroid'
    $overlap=Resolve-EvaluationOcrCells -Cells $cells -Words @([pscustomobject]@{Left=10;Top=10;Width=20;Height=20;Confidence=99;Text='one';Page=1},[pscustomobject]@{Left=15;Top=10;Width=20;Height=20;Confidence=99;Text='two';Page=1}) -Threshold 0
    Require ($overlap.Status -eq 'PARTIAL' -and $overlap.Accepted.Count -eq 0) 'Overlapping OCR words must fail closed'
    $ordered=Resolve-EvaluationOcrCells -Cells $cells -Words @([pscustomobject]@{Left=10;Top=40;Width=20;Height=20;Confidence=99;Text='second';Page=1},[pscustomobject]@{Left=10;Top=10;Width=20;Height=20;Confidence=99;Text='first';Page=1}) -Threshold 0
    Require ($ordered.CellText[0].Text -ceq "first`nsecond") 'Within-cell multiline ordering must be physical, not TSV reading order'
    foreach($name in @('gray','rgb','borderless','broken','merged')){
        $result=Invoke-P43aGridProbe -PdfPath (Join-Path $PSScriptRoot ('fixtures/'+$name+'.pdf'))
        if($name -in @('gray','rgb')){Require ($result.Status -eq 'COMPLETE' -and $result.Cells.Count -eq 12) "$name must prove 12 independent closed cells"}
        else{Require ($result.Status -ne 'COMPLETE' -and $result.Cells.Count -eq 0) "$name must not infer grid"}
    }
    Write-Host 'GridOcr geometry PASS; actual OCR calibration is a separate measured gate, not a test constant.'
}
