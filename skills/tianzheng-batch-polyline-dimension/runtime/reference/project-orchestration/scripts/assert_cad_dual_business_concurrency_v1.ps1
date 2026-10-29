param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
function DualAdmissionPath([string]$Path){
 if([string]::IsNullOrWhiteSpace($Path)){throw 'DUAL_ADMISSION_EMPTY_PATH'}
 $p=if([IO.Path]::IsPathRooted($Path)){[IO.Path]::GetFullPath($Path)}else{[IO.Path]::GetFullPath((Join-Path $Root $Path))}
 if(-not$p.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'DUAL_ADMISSION_OUTSIDE_PROJECT'}
 for($x=$p;$x.Length-gt$Root.Length;$x=Split-Path -Parent $x){if((Test-Path -LiteralPath $x)-and((Get-Item -LiteralPath $x).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'DUAL_ADMISSION_REPARSE'}}
 $p
}
$profile=$Draft.dual_business_concurrency
if($Contract.profile_id-cne'CAD-AB-DUAL-BUSINESS-CONCURRENCY-V1'-or$profile.profile_id-cne$Contract.profile_id-or$profile.intent-cne'ExecuteBothOwnerNativeGeneration'-or$profile.implementation_version-ne1-or$Draft.governance.workflow_id-cne$profile.profile_id-or$Draft.command_routing.route_id-cne'shared_annotation_interface_read'-or$Draft.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$Draft.target.thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'DUAL_ADMISSION_AUTHORITY'}
if($Draft.schema_version-lt3-or$Draft.status-cnotin@('DRAFT','READY')){throw 'DUAL_ADMISSION_NOT_ACTIVE'}
$run=DualAdmissionPath ('runs/'+$Draft.run_id)
if(Test-Path (Join-Path $run 'execution_return.json')){throw 'DUAL_ADMISSION_TERMINAL_RUN'}
$bindings=@{}
foreach($p in $Draft.program.PSObject.Properties){if($p.Name.EndsWith('_sha256')){
 $name=$p.Name.Substring(0,$p.Name.Length-7);$pair=$Draft.program.PSObject.Properties[$name]
 if($null-eq$pair){throw 'DUAL_ADMISSION_HASH_PAIR'};$path=DualAdmissionPath ([string]$pair.Value)
 if([string]$p.Value-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$p.Value){throw ('DUAL_ADMISSION_BINDING:'+ $path)}
 if($bindings.ContainsKey($path)-and$bindings[$path]-cne$p.Value){throw 'DUAL_ADMISSION_BINDING_CONFLICT'}
 $bindings[$path]=[string]$p.Value
}}
$sp=DualAdmissionPath $profile.scope_path;$mp=DualAdmissionPath $profile.manifest_path
if($sp-ine(Join-Path $run 'scope.json')-or$mp-ine(Join-Path $run 'manifest.json')-or$bindings[$sp]-cne$profile.scope_sha256-or$bindings[$mp]-cne$profile.manifest_sha256){throw 'DUAL_ADMISSION_SCOPE_MANIFEST'}
$s=Get-Content $sp -Raw|ConvertFrom-Json -DateKind String;$m=Get-Content $mp -Raw|ConvertFrom-Json -DateKind String
if($s.profile_id-cne$profile.profile_id-or$s.run_id-cne$Draft.run_id-or$s.phase-cne'AB_REAL_DUAL_NATIVE_GENERATION'-or$m.profile_id-cne$s.profile_id){throw 'DUAL_ADMISSION_SCOPE_IDENTITY'}
if(($s.capability_bounds|ConvertTo-Json -Compress)-cne($Contract.candidate_capability_bounds|ConvertTo-Json -Compress)){throw 'DUAL_ADMISSION_CAPS'}
$closure=@{}
foreach($f in $m.files){$p=DualAdmissionPath $f.path;if($closure.ContainsKey($p)){throw 'DUAL_ADMISSION_DUPLICATE_CLOSURE'};if($bindings[$p]-cne$f.sha256){throw 'DUAL_ADMISSION_MANIFEST_UNBOUND'};$closure[$p]=$f.sha256}
$prefix='reports/cad_multi_window_interface_research/dual_business_concurrency_v1/'
foreach($leaf in @('dual_contract.ps1','invoke_dual.ps1','command_worker_v1.ps1','process_dual.py','native_dual_stages.lsp','test_contract.ps1')){if(-not$closure.ContainsKey((Join-Path $Root ($prefix+$leaf)))){throw 'DUAL_ADMISSION_REQUIRED_CODE'}}
$controller=$prefix+'invoke_dual.ps1';$expected=$controller+" -ReadyHandoffPath '"+(Join-Path $Root 'config/current_execution_handoff.json')+"'"
if($Contract.controller-cne$controller-or$Draft.program.controller-cne$controller-or$Draft.action.controller_template-cne$expected-or$Contract.candidate_contract_abi-cne'Assert-CadDualBusinessScopeV1($Scope,$Root)'){throw 'DUAL_ADMISSION_LITERAL_ENTRY'}
if($Draft.action.controller_call_max-ne1-or$Draft.action.send_max_count-ne6-or$Draft.action.plugin_load_max-ne0-or$Draft.action.always_load_click_max-ne0-or$Draft.action.save_copy_max-ne0-or$Draft.action.foreground_input_max-ne0-or$Draft.acceptance.aesthetic_gate-or$Draft.acceptance.formal_reopen_claimed-or$Draft.acceptance.retry_count-ne0-or@($Draft.acceptance.allowed_commanded_grips).Count-ne0){throw 'DUAL_ADMISSION_ACTION_SCOPE'}
if($Draft.canonical_open.launch_permitted_for_this_handoff-or$Draft.launch_policy.launch_permitted_for_this_handoff){throw 'DUAL_ADMISSION_NO_LIFECYCLE'}
& {param($Root,$Scope,$Manifest);. (Join-Path $Root 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/dual_contract.ps1');$null=Assert-CadDualBusinessScopeV1 $Scope $Root;Assert-CadDualManifestV1 $Manifest $Root} $Root $s $m
[pscustomobject]@{status='PASS';profile_id=$s.profile_id;operations=6;CAD_calls=0;live_verified=$false}
