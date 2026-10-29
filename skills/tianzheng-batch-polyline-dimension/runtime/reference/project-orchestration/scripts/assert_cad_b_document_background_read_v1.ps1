param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest;$Root=[IO.Path]::GetFullPath($Root)
function BDocPath([string]$Value){if([string]::IsNullOrWhiteSpace($Value)){throw 'BDOC_ADMISSION_EMPTY_PATH'};$p=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))};if(-not$p.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BDOC_ADMISSION_OUTSIDE_ROOT'};for($x=$p;$x.Length-gt$Root.Length;$x=Split-Path -Parent $x){if((Test-Path -LiteralPath $x)-and((Get-Item -LiteralPath $x).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'BDOC_ADMISSION_REPARSE'}};$p}
function BDocCaps($Actual,$Expected){if(@($Actual.PSObject.Properties).Count-ne@($Expected.PSObject.Properties).Count){throw 'BDOC_ADMISSION_CAP_FIELDS'};foreach($p in $Expected.PSObject.Properties){$a=$Actual.PSObject.Properties[$p.Name];if($null-eq$a-or$null-eq$a.Value-or$a.Value.GetType()-ne$p.Value.GetType()-or($a.Value|ConvertTo-Json -Depth 6 -Compress)-cne($p.Value|ConvertTo-Json -Depth 6 -Compress)){throw ('BDOC_ADMISSION_CAP:'+ $p.Name)}}}
$p=$Draft.b_document_bridge_background_read
if($Contract.profile_id-cne'CAD-B-DOCUMENT-BRIDGE-BACKGROUND-READ-V1'-or$p.profile_id-cne$Contract.profile_id-or$p.intent-cne$Contract.intent-or$p.phase-cne$Contract.phase-or$Draft.governance.workflow_id-cne$Contract.profile_id-or$Draft.command_routing.route_id-cne'shared_annotation_interface_read'-or$Draft.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$Draft.target.thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'BDOC_ADMISSION_ROUTE'}
$mp=BDocPath $Contract.manifest_path
if((BDocPath $p.manifest_path)-ine$mp-or$p.manifest_sha256-cne$Contract.manifest_sha256-or(Get-FileHash $mp).Hash-cne$Contract.manifest_sha256){throw 'BDOC_ADMISSION_MANIFEST_HASH'}
$m=Get-Content -Raw -LiteralPath $mp|ConvertFrom-Json -DateKind String
if($m.id-cne$Contract.profile_id-or$m.source_thread_id-cne'RECEIVER_ID_REQUIRED'-or$m.scope_field-cne'b_document_bridge_background_read'-or$m.status-cne'SEALED_PRIVATE_IMPLEMENTATION__RUNTIME_BINDING_AND_SHARED_ADMISSION_REQUIRED'-or$m.live_verified-isnot[bool]-or$m.live_verified-or$m.cad_calls-ne0-or$m.actual_rot_calls-ne0){throw 'BDOC_ADMISSION_MANIFEST_IDENTITY'}
BDocCaps $m.capability_bounds $Contract.capability_bounds
$bindings=@{};foreach($x in $Draft.program.PSObject.Properties){if($x.Name.EndsWith('_sha256')){$k=$x.Name.Substring(0,$x.Name.Length-7);$q=$Draft.program.PSObject.Properties[$k];if($null-eq$q){throw 'BDOC_ADMISSION_PAIR'};$path=BDocPath ([string]$q.Value);if($bindings.ContainsKey($path)-and$bindings[$path]-cne$x.Value){throw 'BDOC_ADMISSION_CONFLICT'};$bindings[$path]=[string]$x.Value}}
function BDocBound([string]$Value,[string]$Hash){$path=BDocPath $Value;if($Hash-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$Hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$Hash){throw ('BDOC_ADMISSION_REQUIRED_HASH:'+ $Value)}}
BDocBound $mp $p.manifest_sha256
foreach($f in @($m.files)+@($m.validation_dependencies)){BDocBound $f.path $f.sha256}
foreach($f in $Contract.frozen_dependencies){BDocBound $f.path $f.sha256;if(@($m.files|Where-Object{$_.path-ceq$f.path-and$_.sha256-ceq$f.sha256}).Count-ne1){throw 'BDOC_ADMISSION_FROZEN_DEPENDENCY'}}
if((BDocPath $Draft.program.controller)-ine(BDocPath $Contract.controller)-or(BDocPath $m.controller)-ine(BDocPath $Contract.controller)-or(BDocPath $m.scope_contract)-ine(BDocPath $Contract.scope_contract)){throw 'BDOC_ADMISSION_CONTROLLER'}
$scopePath=BDocPath $p.scope_path;BDocBound $scopePath $p.scope_sha256;$s=Get-Content -Raw $scopePath|ConvertFrom-Json -DateKind String
if($s.offline_only-isnot[bool]-or$s.offline_only-or$s.profile_id-cne$Contract.profile_id-or$s.run_id-cne$Draft.run_id-or$s.intent-cne$Contract.intent-or$s.phase-cne$Contract.phase){throw 'BDOC_ADMISSION_OFFLINE_OR_WRONG_SCOPE'}
BDocCaps $s.capability_bounds $Contract.capability_bounds
if($s.operation.id-cne'B1'-or$s.operation.owner-cne'B'-or($s.operation.duration_ms-isnot[int]-and$s.operation.duration_ms-isnot[long])-or$s.operation.duration_ms-ne0-or$s.operation.nonce-cne$s.nonce-or@($s.operation.PSObject.Properties).Count-ne5){throw 'BDOC_ADMISSION_FIXED_OPERATION'}
foreach($f in @('command','expression','expression_text','script','arbitrary_command','a_host','save_path')){if($null-ne$s.PSObject.Properties[$f]){throw 'BDOC_ADMISSION_ARBITRARY_PAYLOAD'}}
$artifactPath=BDocPath $p.artifact_manifest_path;BDocBound $artifactPath $p.artifact_manifest_sha256;$am=Get-Content -Raw $artifactPath|ConvertFrom-Json -DateKind String
if($am.status-cne'SEALED_RUNTIME_ARTIFACTS_NOT_READY'-or$am.run_id-cne$s.run_id-or$am.profile_id-cne$Contract.profile_id-or$am.source_thread_id-cne$m.source_thread_id-or$am.source_manifest_sha256-cne$p.manifest_sha256-or$am.scope_sha256-cne$p.scope_sha256-or(BDocPath $am.scope_path)-ine$scopePath-or$am.cad_calls-ne0-or$am.live_verified){throw 'BDOC_ADMISSION_RUNTIME_MANIFEST'}
foreach($f in $am.files){BDocBound $f.path $f.sha256};BDocBound $s.a_predecessor_path $s.a_predecessor_sha256
$run=Join-Path $Root ('runs/'+$s.run_id)
if((BDocPath $s.new_b_drawing_path)-ine(Join-Path $run 'drawings/background_B.dwg')-or$s.stage_directory-cne('C:\tmp\cad_owner_bridge\'+$s.run_id)-or(Test-Path $s.stage_directory)-or(Test-Path $s.new_b_drawing_path)){throw 'BDOC_ADMISSION_STAGE_OR_DRAWING_REUSE'}
if(Test-Path $run){foreach($e in Get-ChildItem $run -Force){if($e.PSIsContainer-or$e.Name-cnotin@('execution_handoff.json','execution_controller_claim.json')){throw 'BDOC_ADMISSION_RUN_REPLAY'}}}
foreach($k in @('canonical_open','launch_policy')){if($Draft.$k.launch_permitted_for_this_handoff-isnot[bool]-or-not$Draft.$k.launch_permitted_for_this_handoff){throw 'BDOC_ADMISSION_BOUND_START_REQUIRED'}}
if($Draft.canonical_open.transport-cne'TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_AND_BOUND_B_SCRIPT'-or(BDocPath $Draft.canonical_open.entrypoint)-ine(BDocPath $Contract.controller)-or$Draft.launch_policy.standalone_close_allowed-or$Draft.launch_policy.inline_startup_wrapper_allowed-or$Draft.launch_policy.alternate_transport_allowed){throw 'BDOC_ADMISSION_CANONICAL_TRANSPORT'}
$expectedCommand=$Contract.controller+" -RunDirectory '$run' -ScopePath '$scopePath' -ScopeSha256 '$($p.scope_sha256)'"
if($Draft.action.controller_template-cne$expectedCommand){throw 'BDOC_ADMISSION_THREE_LITERAL_ARGUMENTS'}
# Only after every independent binding/capability gate may private pure code run.
& {param($Entry,$Scope,$ProjectRoot,$Run);. $Entry;$null=Assert-BDocScopeV1 $Scope $ProjectRoot $Run} (BDocPath $Contract.scope_contract) $s $Root $run
[pscustomobject]@{status='PASS';profile_id=$Contract.profile_id;runtime_bound=$true;CAD_calls=0;source_manifest=$mp}
