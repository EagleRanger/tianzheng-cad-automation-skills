param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$Root=[IO.Path]::GetFullPath($Root)
function ArmPath([string]$Value){
 if([string]::IsNullOrWhiteSpace($Value)){throw 'ARM_ADMISSION_EMPTY_PATH'}
 $p=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
 if(-not$p.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'ARM_ADMISSION_OUTSIDE_ROOT'}
 for($x=$p;$x.Length-gt$Root.Length;$x=Split-Path -Parent $x){if((Test-Path -LiteralPath $x)-and((Get-Item -LiteralPath $x).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'ARM_ADMISSION_REPARSE'}}
 $p
}
function ArmCaps($Actual,$Expected){
 if(@($Actual.PSObject.Properties).Count-ne@($Expected.PSObject.Properties).Count){throw 'ARM_ADMISSION_CAP_FIELDS'}
 foreach($p in $Expected.PSObject.Properties){$a=$Actual.PSObject.Properties[$p.Name];if($null-eq$a-or$null-eq$a.Value-or$a.Value.GetType()-ne$p.Value.GetType()-or($a.Value|ConvertTo-Json -Depth 6 -Compress)-cne($p.Value|ConvertTo-Json -Depth 6 -Compress)){throw ('ARM_ADMISSION_CAP:'+ $p.Name)}}
}
$p=$Draft.existing_b_document_arm_background_read
if($Contract.profile_id-cne'CAD-EXISTING-B-DOCUMENT-ARM-BACKGROUND-READ-V1'-or$Contract.status-cne'admitted_bounded_existing_owner_recovery__live_unverified'-or$Contract.scope_field-cne'existing_b_document_arm_background_read'-or$p.profile_id-cne$Contract.profile_id-or$p.intent-cne$Contract.intent-or$p.phase-cne$Contract.phase-or$Draft.governance.workflow_id-cne$Contract.profile_id-or$Draft.command_routing.route_id-cne'shared_annotation_interface_read'-or$Draft.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$Draft.target.thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'ARM_ADMISSION_ROUTE'}
$mp=ArmPath $Contract.manifest_path
if((ArmPath $p.manifest_path)-ine$mp-or$p.manifest_sha256-cne$Contract.manifest_sha256-or(Get-FileHash $mp).Hash-cne$Contract.manifest_sha256){throw 'ARM_ADMISSION_MANIFEST_HASH'}
$m=Get-Content -Raw -LiteralPath $mp|ConvertFrom-Json -DateKind String
if($m.id-cne$Contract.profile_id-or$m.source_thread_id-cne$Draft.issuer.thread_id-or$m.scope_field-cne$Contract.scope_field-or$m.status-cne'PRIVATE_SEALED_CANDIDATE_NOT_SHARED_ADMITTED_OR_LIVE'-or$m.live_verified-isnot[bool]-or$m.live_verified-or$m.runtime_bound-isnot[bool]-or$m.runtime_bound-or$m.cad_calls-ne0){throw 'ARM_ADMISSION_MANIFEST_IDENTITY'}
ArmCaps $m.capability_bounds $Contract.capability_bounds
$bindings=@{}
foreach($x in $Draft.program.PSObject.Properties){if($x.Name.EndsWith('_sha256')){$k=$x.Name.Substring(0,$x.Name.Length-7);$q=$Draft.program.PSObject.Properties[$k];if($null-eq$q){throw 'ARM_ADMISSION_PAIR'};$path=ArmPath ([string]$q.Value);if($bindings.ContainsKey($path)-and$bindings[$path]-cne$x.Value){throw 'ARM_ADMISSION_CONFLICT'};$bindings[$path]=[string]$x.Value}}
function ArmBound([string]$Value,[string]$Hash){$path=ArmPath $Value;if($Hash-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$Hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$Hash){throw ('ARM_ADMISSION_REQUIRED_HASH:'+ $Value)}}
ArmBound $mp $p.manifest_sha256
foreach($f in @($m.files)+@($m.validation_dependencies)){ArmBound $f.path $f.sha256}
if((ArmPath $Draft.program.controller)-ine(ArmPath $Contract.controller)-or(ArmPath $m.controller)-ine(ArmPath $Contract.controller)-or(ArmPath $m.scope_contract)-ine(ArmPath $Contract.scope_contract)){throw 'ARM_ADMISSION_CONTROLLER'}
$scopePath=ArmPath $p.scope_path;ArmBound $scopePath $p.scope_sha256
if((ArmPath $Draft.program.scope)-ine$scopePath-or$Draft.program.scope_sha256-cne$p.scope_sha256-or(ArmPath $Draft.program.manifest)-ine$mp){throw 'ARM_ADMISSION_PROGRAM_SCOPE'}
$s=Get-Content -Raw -LiteralPath $scopePath|ConvertFrom-Json -DateKind String
if($s.offline_only-isnot[bool]-or$s.offline_only-or$s.profile_id-cne$Contract.profile_id-or$s.run_id-cne$Draft.run_id-or$s.intent-cne$Contract.intent-or$s.phase-cne$Contract.phase-or$s.mode-cne'EXISTING_B_ONLY'){throw 'ARM_ADMISSION_OFFLINE_OR_WRONG_SCOPE'}
ArmCaps $s.capability_bounds $Contract.capability_bounds
foreach($field in @('arbitrary_command','script','expression','expression_text','a_host','save_path','new_b_drawing_path')){if($null-ne$s.PSObject.Properties[$field]){throw 'ARM_ADMISSION_ARBITRARY_OR_NEW_DRAWING'}}
$artifactPath=ArmPath $p.artifact_manifest_path;ArmBound $artifactPath $p.artifact_manifest_sha256
$am=Get-Content -Raw -LiteralPath $artifactPath|ConvertFrom-Json -DateKind String
if($am.status-cne'SEALED_RUNTIME_ARTIFACTS_NOT_READY'-or$am.run_id-cne$s.run_id-or$am.profile_id-cne$Contract.profile_id-or$am.source_thread_id-cne$m.source_thread_id-or$am.source_manifest_sha256-cne$p.manifest_sha256-or$am.scope_sha256-cne$p.scope_sha256-or(ArmPath $am.scope_path)-ine$scopePath-or$am.cad_calls-ne0-or$am.live_verified-isnot[bool]-or$am.live_verified){throw 'ARM_ADMISSION_RUNTIME_MANIFEST'}
foreach($f in $am.files){ArmBound $f.path $f.sha256}
foreach($prefix in @('a','b','payload','settlement')){ArmBound $s.($prefix+'_predecessor_path') $s.($prefix+'_predecessor_sha256')}
$run=Join-Path $Root ('runs/'+$s.run_id)
if(Test-Path -LiteralPath $run){foreach($e in Get-ChildItem -LiteralPath $run -Force){if($e.PSIsContainer-or$e.Name-cnotin@('execution_handoff.json','execution_controller_claim.json')){throw 'ARM_ADMISSION_RUN_REPLAY'}}}
foreach($k in @('canonical_open','launch_policy')){if($Draft.$k.launch_permitted_for_this_handoff-isnot[bool]-or$Draft.$k.launch_permitted_for_this_handoff){throw 'ARM_ADMISSION_LAUNCH_FORBIDDEN'}}
if($Draft.canonical_open.profile_id-cne$Contract.profile_id-or$Draft.canonical_open.transport-cne$Contract.canonical_open_transport-or(ArmPath $Draft.canonical_open.entrypoint)-ine(ArmPath $Contract.controller)-or(ArmPath $Draft.canonical_open.inner_entrypoint)-ine(ArmPath $Contract.controller)){throw 'ARM_ADMISSION_CANONICAL_TRANSPORT'}
foreach($flag in @('standalone_close_allowed','inline_startup_wrapper_allowed','alternate_transport_allowed','bound_startup_script_only','timeout_may_reclassify_failed_open')){if($Draft.launch_policy.$flag-isnot[bool]-or$Draft.launch_policy.$flag){throw ('ARM_ADMISSION_LAUNCH_POLICY:'+ $flag)}}
if($Draft.owner.launch_permitted-isnot[bool]-or$Draft.owner.launch_permitted){throw 'ARM_ADMISSION_OWNER_LAUNCH'}
foreach($field in @('process_id','process_image_path','window_handle')){if([string]$Draft.owner.$field-cne[string]$s.existing_b.$field){throw ('ARM_ADMISSION_OWNER:'+ $field)}}
function ArmTicks($Value){if($Value-is[DateTime]){return $Value.ToUniversalTime().Ticks};if($Value-is[DateTimeOffset]){return $Value.UtcDateTime.Ticks};([DateTimeOffset]::Parse([string]$Value)).UtcDateTime.Ticks}
if((ArmTicks $Draft.owner.process_start_time_utc)-ne(ArmTicks $s.existing_b.process_start_time_utc)){throw 'ARM_ADMISSION_OWNER_START_TIME'}
if((ArmPath $Draft.owner.drawing)-ine(ArmPath $s.existing_b.document_full_path)){throw 'ARM_ADMISSION_OWNER_DRAWING'}
$expectedCommand=$Contract.controller+" -RunDirectory '$run' -ScopePath '$scopePath' -ScopeSha256 '$($p.scope_sha256)'"
if($Draft.action.controller_template-cne$expectedCommand){throw 'ARM_ADMISSION_THREE_LITERAL_ARGUMENTS'}
# Pure source contract runs only after independently checking its sealed file set.
& {param($Entry,$Scope,$ProjectRoot,$Run);. $Entry;$null=Assert-BDocScopeV1 $Scope $ProjectRoot $Run} (ArmPath $Contract.scope_contract) $s $Root $run
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;runtime_bound=$true;CAD_calls=0;source_manifest=$mp}
