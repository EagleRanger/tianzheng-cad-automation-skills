param([string]$OutputPath='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source=Join-Path $root 'src\CodexNativeDimensionSemanticInventoryV1.cs'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $root 'build\CodexNativeDimensionSemanticInventory_20260831_01.dll'}
$output=[IO.Path]::GetFullPath($OutputPath);$buildRoot=[IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('\')+'\'
if(-not$output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'SEMANTIC_INVENTORY_OUTPUT_OUTSIDE_BUILD'}
$csc=(Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe');$acad=$(if($env:CAD_AUTOCAD_SDK){[IO.Path]::GetFullPath($env:CAD_AUTOCAD_SDK)}else{throw 'CAD_AUTOCAD_SDK_REQUIRED'})
$references=@('acmgd.dll','acdbmgd.dll','accoremgd.dll')|ForEach-Object{Join-Path $acad $_}
foreach($path in @($source,$csc)+$references){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "SEMANTIC_INVENTORY_BUILD_INPUT_MISSING:$path"}}
$arguments=@('/nologo','/target:library','/optimize+',('/out:'+$output))+@($references|ForEach-Object{'/reference:'+$_})+@($source)
&$csc @arguments
if($LASTEXITCODE-ne0-or-not(Test-Path -LiteralPath $output -PathType Leaf)){throw 'SEMANTIC_INVENTORY_BUILD_FAILED'}
[pscustomobject]@{status='PASS';output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $output).Length;command='CXNATIVEDIMSEMANTICINVENTORYV1'}
