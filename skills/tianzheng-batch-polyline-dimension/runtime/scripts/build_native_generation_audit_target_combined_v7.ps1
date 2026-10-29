param([string]$OutputPath='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sources=@(
  'src/CodexNativeGenerationPlacementAuditV2.cs',
  'src/CodexNativeGenerationPlacementAuditV3.cs',
  'src/CodexNativeGenerationPlacementAuditV4.cs',
  'src/CodexNativeGenerationPlacementAuditV5.cs',
  'src/CodexNativePlacementTargetPointV1.cs',
  'src/CodexNativePlacementGrip0MoverV1.cs',
  'src/CodexNativePlacementTranslatorV1.cs',
  'src/CodexNativePlacementTranslatorV2.cs'
)|ForEach-Object{Join-Path $root $_}
if([string]::IsNullOrWhiteSpace($OutputPath)){
  $OutputPath=Join-Path $root 'build/CodexNativeGenerationAuditTarget_20260830_08.dll'
}
$output=[IO.Path]::GetFullPath($OutputPath)
$buildRoot=[IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('\')+'\'
if(-not$output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){
  throw 'COMBINED_NATIVE_DLL_V7_OUTPUT_OUTSIDE_BUILD'
}
$csc=(Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe')
$acad=$(if($env:CAD_AUTOCAD_SDK){[IO.Path]::GetFullPath($env:CAD_AUTOCAD_SDK)}else{throw 'CAD_AUTOCAD_SDK_REQUIRED'})
$references=@('acmgd.dll','acdbmgd.dll','accoremgd.dll')|ForEach-Object{Join-Path $acad $_}
foreach($path in @($csc)+$references+$sources){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){
    throw "COMBINED_NATIVE_DLL_V7_INPUT_MISSING:$path"
  }
}
$arguments=@('/nologo','/target:library','/optimize+',('/out:'+$output))+
  @($references|ForEach-Object{'/reference:'+$_})+$sources
& $csc @arguments
if($LASTEXITCODE-ne0-or-not(Test-Path -LiteralPath $output -PathType Leaf)){
  throw 'COMBINED_NATIVE_DLL_V7_BUILD_FAILED'
}
[pscustomobject]@{
  status='PASS';output=$output
  sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
  bytes=(Get-Item -LiteralPath $output).Length
  lisp_functions=@(
    'CXNATIVEPLACEMENTAUDITV2','CXNATIVEPLACEMENTAUDITV3',
    'CXNATIVEPLACEMENTAUDITV4','CXNATIVEPLACEMENTAUDITV5',
    'CXNATIVEPLACEMENTTARGETPOINTV1','CXNATIVEPLACEMENTMOVEGRIP0V1',
    'CXNATIVEPLACEMENTTRANSLATEV1','CXNATIVEPLACEMENTTRANSLATEV2')
}
