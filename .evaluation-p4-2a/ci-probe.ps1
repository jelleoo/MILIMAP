$ErrorActionPreference='Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
$here=$PSScriptRoot
Set-Location $here
$out=Join-Path $here 'evidence'
New-Item -ItemType Directory -Force -Path $out | Out-Null
dotnet --info | Out-File (Join-Path $out 'runtime.txt') -Encoding utf8
dotnet restore (Join-Path $here 'PdfPigProbe.csproj') --source https://api.nuget.org/v3/index.json
if($LASTEXITCODE -ne 0){throw 'Restore failed'}
dotnet build (Join-Path $here 'PdfPigProbe.csproj') --no-restore
if($LASTEXITCODE -ne 0){throw 'Build failed'}
dotnet list (Join-Path $here 'PdfPigProbe.csproj') package --include-transitive | Out-File (Join-Path $out 'packages.txt') -Encoding utf8
foreach($control in Get-ChildItem (Join-Path $here 'controls') -Filter '*.pdf' | Sort-Object Name){
    $native=Join-Path $out ($control.BaseName+'-native.json')
    dotnet (Join-Path $here 'bin/Debug/net8.0/PdfPigProbe.dll') $control.FullName 'Business A' | Out-File $native -Encoding utf8
    $exit=$LASTEXITCODE
    $e=Get-Content -Raw $native | ConvertFrom-Json
    if($e.PdfPigVersion -cne '0.1.16'){throw 'Wrong version'}
    if($control.BaseName -ceq 'truncated'){if($exit -eq 0 -or $e.OpenStatus -cne 'FAILED'){throw 'Malformed gate failed'}}
    elseif($control.BaseName -ceq 'encrypted'){if($exit -eq 0 -or $e.Encrypted -ne $true -or $e.OpenStatus -cne 'UNSUPPORTED'){throw 'Encrypted gate failed'}}
    else {
        if($exit -ne 0 -or $e.OpenStatus -cne 'COMPLETE'){throw 'Native open gate failed'}
        $grid=Join-Path $out ($control.BaseName+'-grid.json')
        python (Join-Path $here 'grid-probe.py') $native $grid 'Business A'
        if($LASTEXITCODE -ne 0){throw 'Grid probe failed'}
        $g=Get-Content -Raw $grid | ConvertFrom-Json
        if($control.BaseName -cin @('grid','multipage')){if($g.ClosedCellCount -ne 6 -or $g.ExpectedBusinessContainment -cne 'EXACTLY_ONE_CELL'){throw 'Synthetic grid containment failed'}}
        if($control.BaseName -cin @('image-only','native-no-grid') -and $g.GridCandidateCount -ne 0){throw 'Unsupported control falsely grid-positive'}
        if($control.BaseName -ceq 'image-only' -and ($e.Pages[0].LetterCount -ne 0 -or $e.Pages[0].ImageCount -ne 1)){throw 'Image-only detection failed'}
        if($control.BaseName -ceq 'multipage' -and $e.Pages.Count -ne 2){throw 'Page boundary failed'}
    }
}
Get-FileHash (Join-Path $here 'Program.cs'),(Join-Path $here 'PdfPigProbe.csproj'),(Join-Path $here 'grid-probe.py'),(Join-Path $here 'obj/project.assets.json') | Select-Object Path,Hash | ConvertTo-Json | Out-File (Join-Path $out 'source-assets-hashes.json') -Encoding utf8
Write-Host 'All evaluation gates PASS; parser-open status is not adapter approval.'
