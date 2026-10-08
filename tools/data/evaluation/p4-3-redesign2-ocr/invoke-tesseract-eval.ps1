Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Runtime only: historical acceptance/threshold code is deliberately not loaded.
. (Join-Path $PSScriptRoot '../p4-3a2-ocr/invoke-tesseract-eval.ps1')

function Invoke-P43R2TesseractEvaluation {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$ModelPath,
        [AllowEmptyCollection()][string[]]$Inputs=@(),[ValidateSet(3,4,6,11)][int]$Psm=11)
    $raw=Invoke-P43a2TesseractEvaluation -Executable $Executable -ModelPath $ModelPath -Inputs $Inputs -Psm $Psm
    return [pscustomobject]@{
        ProbeId='MILIMAP_P4_3_REDESIGN2_OCR_EVAL';SchemaVersion=1
        TrustModelVersion='STRUCTURAL_TRUST_V1';ConfidencePolicy='DIAGNOSTIC_ONLY_V1'
        Status=$raw.Status;Code=$raw.Code;EngineVersion=$raw.EngineVersion;EngineBuild=$raw.EngineBuild
        ModelSha256=$raw.ModelSha256;InvocationCount=$raw.InvocationCount;ElapsedMilliseconds=$raw.ElapsedMilliseconds
        Words=$raw.Words;Diagnostics=$raw.Diagnostics;ProductionAction='NONE'
    }
}
