param(
 [Parameter(Mandatory)][string]$AutoCadSdkDirectory,
 [string]$PythonPath=$env:CAD_PYTHON,
 [string]$FrameworkDirectory=(Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'),
 [switch]$ReuseExistingVerifiedModules
)
# Builds this package's own seven modules only. No NETLOAD, CAD, fixture EXE,
# external publishing, owner registration, READY or COM. The existing bounded
# compiler retains its original Job memory/process/deadline/drain constraints.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion.Major-lt7){throw 'POWERSHELL_7_REQUIRED'}
if([string]::IsNullOrWhiteSpace($PythonPath)){$PythonPath=(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'common/CadPublicBuildTrust.ps1')
$map=Get-Content (Join-Path $root 'config/public_module_builds.json') -Raw|ConvertFrom-Json
$sdk=[IO.Path]::GetFullPath($AutoCadSdkDirectory)
$framework=[IO.Path]::GetFullPath($FrameworkDirectory)
$compiler=Join-Path $framework 'csc.exe';$resource=Join-Path $framework 'cvtres.exe';$console=Join-Path $env:WINDIR 'System32/conhost.exe'
function BoundPublicFile([string]$Path){$p=[IO.Path]::GetFullPath($Path);if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "BUILD_INPUT_MISSING:$p"};[ordered]@{path=$p;sha256=(Get-FileHash -LiteralPath $p).Hash}}
$compilerRecord=BoundPublicFile $compiler;$resourceRecord=BoundPublicFile $resource;$consoleRecord=BoundPublicFile $console
foreach($tool in @($compilerRecord,$resourceRecord,$consoleRecord)){if((Get-AuthenticodeSignature -LiteralPath $tool.path).Status-ne'Valid'){throw 'BUILD_TOOL_SIGNATURE_NOT_VALID'}}
$scriptRelative='reports/cad_multi_window_interface_research/command_uia_inspection_v1/job_build_v2'
$parent=Resolve-CadPublicLocalFile -Root $root -RelativePath ($scriptRelative+'/invoke_job_compile_v2.ps1')
$worker=Resolve-CadPublicLocalFile -Root $root -RelativePath ($scriptRelative+'/bounded_job_compile_v2.py')
$workerHash=(Get-FileHash -LiteralPath $worker).Hash;$pythonRecord=BoundPublicFile $PythonPath
$buildId='local_'+[Guid]::NewGuid().ToString('N');$buildRoot=Join-Path $root ('build/c/'+$buildId.Substring(6,8))
New-Item -ItemType Directory -Path $buildRoot|Out-Null
$modules=[Collections.Generic.List[object]]::new();$oldSpec=$env:CAD_JOB_COMPILE_SPEC_PATH;$oldPin=$env:CAD_JOB_COMPILE_SPEC_SHA256;$oldPython=$env:CAD_PYTHON
try{
 $env:CAD_PYTHON=$pythonRecord.path
 $moduleIndex=0
 foreach($module in $map.modules){
  $moduleIndex++;$dir=Join-Path $buildRoot ([string]$moduleIndex);New-Item -ItemType Directory -Path $dir|Out-Null
  $destination=[IO.Path]::GetFullPath((Join-Path $root $module.output))
  if(-not$destination.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetExtension($destination)-ine'.dll'){throw 'BUILD_OUTPUT_UNSAFE'}
  if(Test-Path -LiteralPath $destination){
   if(-not$ReuseExistingVerifiedModules){throw 'BUILD_OUTPUT_ALREADY_EXISTS_NO_OVERWRITE'}
   $existingHash=(Get-FileHash -LiteralPath $destination).Hash;$verified=$false
   foreach($oldReceipt in Get-ChildItem -LiteralPath (Join-Path $root 'build') -Recurse -File -Filter 'parent_receipt.json'){
    $previous=Get-Content -LiteralPath $oldReceipt.FullName -Raw|ConvertFrom-Json
    if($previous.status-cne'PASS_BOUNDARY_COMPILE_ONLY'-or$previous.source_sha256-cne$workerHash-or-not$previous.subtree_cleanup_known-or$previous.cad_calls-ne0-or$previous.worker_result.generated_module_loaded-or$previous.worker_result.candidate_destination-ine$destination-or$previous.worker_result.module_sha256-cne$existingHash){continue}
    $oldSpecPath=Join-Path (Split-Path -Parent (Split-Path -Parent $oldReceipt.DirectoryName)) 'job_compile_spec.json'
    $oldSpec=Get-Content -LiteralPath $oldSpecPath -Raw|ConvertFrom-Json
    $expectedSources=@($module.sources|ForEach-Object {(Resolve-CadPublicLocalFile -Root $root -RelativePath $_)})
    if(($expectedSources-join'|')-cne(@($oldSpec.sources.path)-join'|')){continue}
    foreach($inputRecord in @($oldSpec.sources)+@($oldSpec.references)+@($oldSpec.compiler)) {if((Get-FileHash -LiteralPath $inputRecord.path).Hash-cne$inputRecord.sha256){throw 'EXISTING_BUILD_INPUT_CHANGED'}}
    $verified=$true;break
   }
   if(-not$verified){throw 'EXISTING_BUILD_HAS_NO_MATCHING_SETTLED_COMPILE_EVIDENCE'}
   $lispFunctions=if($module.PSObject.Properties.Name-contains'lisp_functions'){@($module.lisp_functions)}else{@()}
   $modules.Add([ordered]@{id=$module.id;path=$module.output;sha256=$existingHash;sources=@($module.sources|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash}});native_commands=$module.commands;lisp_functions=$lispFunctions;loaded=$false;reused_settled_build=$true})
   continue
  }
  New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force|Out-Null
  $sources=@($module.sources|ForEach-Object {BoundPublicFile (Resolve-CadPublicLocalFile -Root $root -RelativePath $_)})
  $references=@($module.references|ForEach-Object {$p=if($_-match'^WPF/'){Join-Path $framework $_}elseif($_-in@('acmgd.dll','acdbmgd.dll','accoremgd.dll')){Join-Path $sdk $_}else{Join-Path $framework $_};BoundPublicFile $p})
  $identity=Join-Path $dir 'build_identity.json'
  [IO.File]::WriteAllText($identity,(@{kind='RECEIVER_BUILD_IDENTITY_NOT_CAD_AUTHORITY';module_id=$module.id;source_files=$sources}|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
  $spec=[ordered]@{schema_version=1;profile_id='CAD-COMMAND-UIA-OFFLINE-JOB-COMPILATION-V2';workflow_profile='CAD-EXACT-B-COMMAND-UIA-READ-V1';payload_protocol='OWN_HELPER_ATOMIC_JOB_ONLY';run_id=$buildId;nonce=[Guid]::NewGuid().ToString('N');compiler=$compilerRecord;references=$references;sources=$sources;request=(BoundPublicFile $identity);output_leaf=[IO.Path]::GetFileName($destination);candidate_destination=$destination;limits=@{process_mib=128;job_mib=192;active_limit=3;timeout_seconds=20};load_generated_module=$false;run_fixture_exe=$false;compiler_switches=@('/noconfig','/nostdlib+');resource_helper=$resourceRecord;console_host=$consoleRecord;bootstrap_limits=@{process_mib=256;job_mib=384;active_limit=4}}
  $env:CAD_JOB_COMPILE_SPEC_PATH=Join-Path $dir 'job_compile_spec.json'
  [IO.File]::WriteAllText($env:CAD_JOB_COMPILE_SPEC_PATH,($spec|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
  $env:CAD_JOB_COMPILE_SPEC_SHA256=(Get-FileHash -LiteralPath $env:CAD_JOB_COMPILE_SPEC_PATH).Hash
  $receipt=& $parent -Mode compile -SourceSha256 $workerHash -PythonSha256 $pythonRecord.sha256
  if($receipt.status-cne'PASS_BOUNDARY_COMPILE_ONLY'-or-not(Test-Path -LiteralPath $destination)){throw 'BOUNDED_PUBLIC_BUILD_NOT_PROVEN'}
  $lispFunctions=if($module.PSObject.Properties.Name-contains'lisp_functions'){@($module.lisp_functions)}else{@()}
  $modules.Add([ordered]@{id=$module.id;path=$module.output;sha256=(Get-FileHash -LiteralPath $destination).Hash;sources=@($module.sources|ForEach-Object {@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash}});native_commands=$module.commands;lisp_functions=$lispFunctions;loaded=$false})
 }
 $manifest=Join-Path $root 'config/receiver_build_manifest.json'
 if(Test-Path -LiteralPath $manifest){throw 'BUILD_MANIFEST_EXISTS_NO_OVERWRITE'}
 [IO.File]::WriteAllText($manifest,(@{schema_version=1;kind='RECEIVER_LOCAL_BUILD_ONLY';cad_loaded=$false;module_registration_verified=$false;modules=@($modules)}|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
 [pscustomobject]@{status='BUILD_ONLY_NO_CAD_LOAD_OR_BUSINESS_ACCEPTANCE';manifest_relative='config/receiver_build_manifest.json';pin_sha256=(Get-FileHash -LiteralPath $manifest).Hash;pin_environment_variable='CAD_BUILD_MANIFEST_SHA256';module_count=$modules.Count}
}finally{$env:CAD_JOB_COMPILE_SPEC_PATH=$oldSpec;$env:CAD_JOB_COMPILE_SPEC_SHA256=$oldPin;$env:CAD_PYTHON=$oldPython}
