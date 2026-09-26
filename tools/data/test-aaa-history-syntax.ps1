$ErrorActionPreference = 'Stop'

$target = Join-Path $PSScriptRoot 'lib/history/commit-history-run.ps1'
$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors)

if(@($errors).Count -gt 0){
    foreach($error in @($errors)){
        Write-Host ("PARSE_ERROR line={0} col={1} text={2} message={3}" -f $error.Extent.StartLineNumber,$error.Extent.StartColumnNumber,$error.Extent.Text,$error.Message)
    }
    throw 'History commit script has PowerShell parse errors'
}

Write-Host 'History commit script syntax passed.'
