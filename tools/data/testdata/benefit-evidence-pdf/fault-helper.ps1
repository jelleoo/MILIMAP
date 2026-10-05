# Test-only process-boundary fault injector, never used in production dispatch.
param([string]$Mode,[string]$InputFile)
if($Mode -ceq 'timeout'){Start-Sleep -Seconds 10;exit 0}
if($Mode -ceq 'crash'){exit 9}
if($Mode -ceq 'json'){Write-Output '{invalid';exit 0}
if($Mode -ceq 'output'){Write-Output ('x'*131072);exit 0}
$hash=([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($InputFile)))).ToLowerInvariant()
$p=[ordered]@{SchemaVersion=1;ParserId='PDFPIG';ParserVersion='0.1.16';FileSha256=$hash;OpenStatus='COMPLETE';Encrypted=$false;Pages=@([ordered]@{PageNumber=1;RotationDegrees=0;Width=100;Height=100;Letters=@();Paths=@();ImageCount=0});Diagnostics=@()}
switch -CaseSensitive ($Mode){'schema'{$p.SchemaVersion=2};'parser'{$p.ParserId='OTHER'};'version'{$p.ParserVersion='0.1.17'};'hash'{$p.FileSha256='0'*64}}
$p | ConvertTo-Json -Depth 10 -Compress
exit 0
