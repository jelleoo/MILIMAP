Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-P43R3aPnmDescriptor {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha256)
    if(-not [IO.File]::Exists($Path)){throw 'SOURCE_IMAGE_MISSING'}
    if((Get-Item -LiteralPath $Path).Length -gt 32000032){throw 'PNM_INVALID'}
    [byte[]]$bytes=[IO.File]::ReadAllBytes($Path)
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$' -or $hash -cne $ExpectedSha256){throw 'SOURCE_PIXEL_HASH_MISMATCH'}
    # Only the historical helper's compact, LF-only header is supported.
    $prefix=[Text.Encoding]::ASCII.GetString($bytes,0,[Math]::Min(32,$bytes.Length))
    $match=[regex]::Match($prefix,'\A(P[56])\n([1-9][0-9]*) ([1-9][0-9]*)\n255\n')
    if(-not $match.Success){throw 'PNM_INVALID'}
    [long]$width=0;[long]$height=0
    if(-not [long]::TryParse($match.Groups[2].Value,[ref]$width) -or -not [long]::TryParse($match.Groups[3].Value,[ref]$height)){throw 'PNM_INVALID'}
    $components=if($match.Groups[1].Value -ceq 'P5'){1}else{3}
    if($width -gt 4096 -or $height -gt 4096 -or $width*$height -gt 8000000 -or $bytes.Length -ne $match.Length+$width*$height*$components){throw 'PNM_INVALID'}
    return [pscustomobject]@{Magic=$match.Groups[1].Value;Width=[int]$width;Height=[int]$height;Components=$components;HeaderLength=$match.Length;PixelByteLength=[int]($width*$height*$components);SourceSha256=$hash}
}

function Get-InternalP43R3aCropBytes {
    param([byte[]]$Source,[object]$Descriptor,[object]$Cell)
    $width=$Cell.X1-$Cell.X0;$height=$Cell.Y1-$Cell.Y0
    [byte[]]$header=[Text.Encoding]::ASCII.GetBytes("$($Descriptor.Magic)`n$width $height`n255`n")
    $stride=$width*$Descriptor.Components
    [byte[]]$result=[byte[]]::new($header.Length+$stride*$height)
    [Buffer]::BlockCopy($header,0,$result,0,$header.Length)
    for($y=0;$y -lt $height;$y++){
        $offset=$Descriptor.HeaderLength+(([int]$Cell.Y0+$y)*$Descriptor.Width+[int]$Cell.X0)*$Descriptor.Components
        [Buffer]::BlockCopy($Source,$offset,$result,$header.Length+$y*$stride,$stride)
    }
    return ,$result
}

function New-P43R3aCellCropSet {
    param([Parameter(Mandatory)][string]$ImagePath,[Parameter(Mandatory)][string]$ImageSha256,[Parameter(Mandatory)][object[]]$Cells,[Parameter(Mandatory)][string]$OutputDirectory)
    $result=[pscustomobject]@{Status='FAILED';Code=$null;Policy='PROVEN_CELL_CROP_V1';SourcePixelSha256=$ImageSha256;CropBuildCount=0;Crops=@();ProductionAction='NONE'}
    $created=[Collections.Generic.List[string]]::new()
    try{
        $descriptor=Get-P43R3aPnmDescriptor -Path $ImagePath -ExpectedSha256 $ImageSha256
        if($Cells.Count -ne 12){throw 'CROP_CELL_COUNT_MISMATCH'}
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $positions=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $validated=[Collections.Generic.List[object]]::new()
        foreach($cell in $Cells){
            $id=[string]$cell.CellId
            if($id -cnotmatch '^(?:[1-9]|1[0-2])$' -or -not $ids.Add($id)){throw 'CROP_CELL_ID_MISMATCH'}
            $numeric=[ordered]@{CellId=$id}
            foreach($field in @('Row','Column','X0','Y0','X1','Y1')){
                [int]$integer=0
                if(-not [int]::TryParse([string]$cell.$field,[ref]$integer)){throw 'CROP_RECTANGLE_INVALID'}
                $numeric[$field]=$integer
            }
            $cell=[pscustomobject]$numeric
            if(-not $positions.Add("$($cell.Row):$($cell.Column)")){throw 'CROP_CELL_POSITION_MISMATCH'}
            if($cell.Row -ne [int][Math]::Floor(([int]$id-1)/4)+1 -or $cell.Column -ne ([int]$id-1)%4+1){throw 'CROP_CELL_POSITION_MISMATCH'}
            if($cell.X0 -lt 0 -or $cell.Y0 -lt 0 -or $cell.X1 -le $cell.X0 -or $cell.Y1 -le $cell.Y0 -or $cell.X1 -gt $descriptor.Width -or $cell.Y1 -gt $descriptor.Height){throw 'CROP_RECTANGLE_INVALID'}
            $validated.Add($cell)
        }
        # Validate every cell before creating any output artifact.
        [byte[]]$source=[IO.File]::ReadAllBytes($ImagePath)
        if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($source)).ToLowerInvariant() -cne $ImageSha256){throw 'SOURCE_PIXEL_HASH_MISMATCH'}
        $ordered=@($validated | Sort-Object {[int]$_.CellId})
        $extension=if($descriptor.Components -eq 1){'pgm'}else{'ppm'}
        foreach($cell in $ordered){
            $path=Join-Path $OutputDirectory ('crop-{0:D2}-cell-{1}.{2}' -f [int]$cell.CellId,$cell.CellId,$extension)
            if([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)){throw 'CROP_ARTIFACT_ALREADY_EXISTS'}
        }
        [void][IO.Directory]::CreateDirectory($OutputDirectory)
        $crops=[Collections.Generic.List[object]]::new()
        foreach($cell in $ordered){
            $ordinal=[int]$cell.CellId
            $path=[IO.Path]::GetFullPath((Join-Path $OutputDirectory ('crop-{0:D2}-cell-{1}.{2}' -f $ordinal,$cell.CellId,$extension)))
            [byte[]]$bytes=Get-InternalP43R3aCropBytes -Source $source -Descriptor $descriptor -Cell $cell
            # CreateNew also prevents a file appearing after the preflight from being overwritten.
            $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $created.Add($path)
            try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
            $crops.Add([pscustomobject]@{Ordinal=$ordinal;CellId=[string]$cell.CellId;Row=[int]$cell.Row;Column=[int]$cell.Column;X0=[int]$cell.X0;Y0=[int]$cell.Y0;X1=[int]$cell.X1;Y1=[int]$cell.Y1;Width=[int]($cell.X1-$cell.X0);Height=[int]($cell.Y1-$cell.Y0);Components=$descriptor.Components;ArtifactPath=$path;CropSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()})
        }
        $result.Status='COMPLETE';$result.CropBuildCount=1;$result.Crops=$crops.ToArray()
    }catch{
        $result.Code=$_.Exception.Message
        foreach($path in $created){[IO.File]::Delete($path)}
    }
    return $result
}
