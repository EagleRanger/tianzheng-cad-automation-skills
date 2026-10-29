param([string]$OutputPath='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source=Join-Path $root 'src/CodexCadDocumentPreviewCaptureV1.cs'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path $root 'build/CodexCadDocumentPreviewCapture_20260831_01.dll'}
$output=[IO.Path]::GetFullPath($OutputPath)
$buildRoot=[IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('\')+'\'
if(-not$output.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'CAD_DOCUMENT_PREVIEW_OUTPUT_OUTSIDE_BUILD'}
$csc=(Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe')
$acad=$(if($env:CAD_AUTOCAD_SDK){[IO.Path]::GetFullPath($env:CAD_AUTOCAD_SDK)}else{throw 'CAD_AUTOCAD_SDK_REQUIRED'})
$wpf=(Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/WPF')
$references=@('acmgd.dll','acdbmgd.dll','accoremgd.dll')|ForEach-Object{Join-Path $acad $_}
$frameworkReferences=@('System.Drawing.dll',(Join-Path $wpf 'WindowsBase.dll'),(Join-Path $wpf 'PresentationCore.dll'))
foreach($path in @($source,$csc)+$references+@($frameworkReferences|Where-Object{[IO.Path]::IsPathRooted($_)})){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "CAD_DOCUMENT_PREVIEW_BUILD_INPUT_MISSING:$path"}}
$arguments=@('/nologo','/target:library','/optimize+',('/out:'+$output))+@($frameworkReferences|ForEach-Object{'/reference:'+$_})+@($references|ForEach-Object{'/reference:'+$_})+@($source)
&$csc @arguments
if($LASTEXITCODE-ne0-or-not(Test-Path -LiteralPath $output -PathType Leaf)){throw 'CAD_DOCUMENT_PREVIEW_BUILD_FAILED'}
[pscustomobject]@{status='PASS';output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $output).Length;command='CXCADDOCUMENTPREVIEWCAPTUREV1';backend='AUTOCAD_DOCUMENT_CAPTURE_PREVIEW_IMAGE';preview_scale=2.0;preview_capture_count=1;business_object_mutation_count=0;save_count=0;retry_count=0}
