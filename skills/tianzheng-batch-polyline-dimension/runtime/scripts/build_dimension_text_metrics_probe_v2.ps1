param([string]$OutputPath='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'src/CodexDimensionTextMetricsProbeV2.cs'
if(-not $OutputPath){$OutputPath=Join-Path $root 'build/CodexDimensionTextMetricsProbeV2.dll'}
$output=[IO.Path]::GetFullPath($OutputPath)
if(-not $output.StartsWith((Join-Path $root 'build/'),[StringComparison]::OrdinalIgnoreCase)){throw 'FACTORY_BUILD_PATH'}
if(Test-Path $output){throw 'FACTORY_BUILD_EXISTS'}
$refs=@('acmgd.dll','acdbmgd.dll','accoremgd.dll')|ForEach-Object {Join-Path 'C:/Program Files/Autodesk/AutoCAD 2021' $_}
& 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe' @('/nologo','/target:library','/optimize+',('/out:'+$output)) @($refs|ForEach-Object {'/reference:'+$_}) $source (Join-Path $root 'src/CodexDimensionTextGeometryRecipeV1.cs')
if($LASTEXITCODE -ne 0){throw 'FACTORY_COMPILE_FAILED'}
[pscustomobject]@{status='PASS_COMPILE_ONLY';path=$output;sha256=(Get-FileHash $output).Hash;cad_calls=0}


