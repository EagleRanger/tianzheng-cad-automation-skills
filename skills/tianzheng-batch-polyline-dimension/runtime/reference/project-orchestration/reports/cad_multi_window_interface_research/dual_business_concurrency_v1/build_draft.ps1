param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$OwnerEvidencePath,[Parameter(Mandatory)][string]$OwnerEvidenceSha256,[Parameter(Mandatory)][string]$AReferencePath,[Parameter(Mandatory)][string]$AReferenceSha256,[Parameter(Mandatory)][string]$BReferencePath,[Parameter(Mandatory)][string]$BReferenceSha256,[switch]$ScopeOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'));. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/dual_contract.ps1')
if($RunId-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'DUAL_RUN_ID'}
$run=Join-Path $root ('runs/'+$RunId);if(Test-Path $run){throw 'DUAL_FRESH_RUN_REQUIRED'}
$evidence=Read-CadExactBBoundJsonV1 (Resolve-CadExactBProjectPathV1 $root $OwnerEvidencePath) $OwnerEvidenceSha256
$refs=@{A=@{path=(Resolve-CadExactBProjectPathV1 $root $AReferencePath);sha256=$AReferenceSha256};B=@{path=(Resolve-CadExactBProjectPathV1 $root $BReferencePath);sha256=$BReferenceSha256}}
$ops=@(foreach($plan in @(Get-CadDualBusinessPlanV1)){foreach($owner in @('A','B')){$id=$owner+('{0:00}'-f$plan.pair);[pscustomobject][ordered]@{id=$id;owner=$owner;pair=$plan.pair;stage=$plan.stage;action=$plan.action;nonce=[guid]::NewGuid().ToString('N');expected_model_delta=$plan.delta;signal_path=(Join-Path $run ('signals/'+$id+'.log'));business_signal_path=(Join-Path $run ('signals/'+$id+'_business.log'));data_run=(Join-Path $run $owner);bundle_path=($script:DualRelative+'native_dual_stages.lsp');bundle_sha256=(Get-FileHash (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/native_dual_stages.lsp')).Hash}}})
$scope=[pscustomobject][ordered]@{schema_version=1;implementation_version=1;profile_id='CAD-AB-DUAL-BUSINESS-CONCURRENCY-V1';route='shared_annotation_interface_read';intent='ExecuteBothOwnerNativeGeneration';phase='AB_REAL_DUAL_NATIVE_GENERATION';run_id=$RunId;owners=$evidence.owners;owner_evidence=@{path=(Resolve-CadExactBProjectPathV1 $root $OwnerEvidencePath);sha256=$OwnerEvidenceSha256;receipts=$evidence.receipts};source=$evidence.source;references=$refs;capability_bounds=(Get-CadDualBusinessCapsV1);operations=$ops}
$null=Assert-CadDualBusinessScopeV1 $scope $root
if($ScopeOnly){$scope;return}
# Local file preparation only. No COM/native/process/window calls or READY.
foreach($dir in @('','signals','A','B','A/reports','B/reports')){$null=New-Item -ItemType Directory -Path (Join-Path $run $dir)}
Write-CadBatchJsonAtomicV2 (Join-Path $run 'scope.json') $scope
foreach($o in $scope.owners){
 $local=Join-Path $run $o.id
 # Mature compiler consults owners[1] only for expected-drawing. This explicit
 # one-owner data projection is never consumed by identity/permission guards.
 Write-CadBatchJsonAtomicV2 (Join-Path $local 'scope.json') @{owner_projection_only=$true;owners=@($null,$o)}
 [IO.File]::Copy($refs[$o.id].path,(Join-Path $local 'reports/reference_candidate.txt'),$false)
}
$deps=@{}
foreach($manifestPath in @('reports/cad_multi_window_interface_research/background_operation_reproduction_v8/candidate_manifest.json','runs/20261028_dimension_failed_line_recovery_v8b/manifest.json')){
 $old=Get-Content (Join-Path $root $manifestPath) -Raw|ConvertFrom-Json -DateKind String;$items=@($old.files)
 if($old.PSObject.Properties.Name-contains'validation_dependencies'){$items+=@($old.validation_dependencies)}
 foreach($f in $items){if((Get-FileHash (Join-Path $root $f.path)).Hash-cne$f.sha256){throw ('DUAL_FROZEN_REUSE_CHANGED:'+ $f.path)};$deps[$f.path]=$f.sha256};$deps[$manifestPath]=(Get-FileHash (Join-Path $root $manifestPath)).Hash
}
$extra=@($scope.owner_evidence.path,$AReferencePath,$BReferencePath)+@($scope.owner_evidence.receipts.path)+@($evidence.registration.A.path,$evidence.registration.B.path)
foreach($p in $extra){$path=Resolve-CadExactBProjectPathV1 $root $p;$rel=[IO.Path]::GetRelativePath($root,$path).Replace('\','/');$deps[$rel]=(Get-FileHash $path).Hash}
foreach($version in @('representative_command_batch_v1','representative_command_batch_v2','representative_command_batch_v3')){foreach($leaf in @('batch_contract.ps1','process_batch.py')){$rel='reports/cad_multi_window_interface_research/'+$version+'/'+$leaf;$deps[$rel]=(Get-FileHash (Join-Path $root $rel)).Hash}}
foreach($rel in @(Get-CadDualExtraDependenciesV1)){$deps[$rel]=(Get-FileHash (Join-Path $root $rel)).Hash}
foreach($f in Get-ChildItem $PSScriptRoot -File|Where-Object Extension -In @('.ps1','.py','.lsp')){$rel=$script:DualRelative+$f.Name;$deps[$rel]=(Get-FileHash $f.FullName).Hash}
foreach($o in $scope.owners){foreach($leaf in @('scope.json','reports/reference_candidate.txt')){$rel='runs/'+$RunId+'/'+$o.id+'/'+$leaf;$deps[$rel]=(Get-FileHash (Join-Path $root $rel)).Hash}}
$manifest=@{profile_id=$scope.profile_id;files=@($deps.Keys|Sort-Object|ForEach-Object{@{path=$_;sha256=$deps[$_]}})}
Write-CadBatchJsonAtomicV2 (Join-Path $run 'manifest.json') $manifest;Assert-CadDualManifestV1 $manifest $root
$seed=Get-Content (Join-Path $root 'runs/20261028_ab_native_annotation_read_81/execution_handoff.json') -Raw|ConvertFrom-Json -AsHashtable -DateKind String
foreach($key in @('background_native_read','single_background_native_read','shared_annotation_interface_read','interface_read_profile','return_delivery','immutable_handoff_path','immutable_handoff_sha256','development_workflow')){$seed.Remove($key)}
$program=[ordered]@{controller=($script:DualRelative+'invoke_dual.ps1');scope=('runs/'+$RunId+'/scope.json');manifest=('runs/'+$RunId+'/manifest.json');regression=($script:DualRelative+'test_contract.ps1')}
foreach($key in @($program.Keys)){$program[$key+'_sha256']=(Get-FileHash (Join-Path $root $program[$key])).Hash}
$i=0;foreach($f in $manifest.files){$program['bound_'+$i]=$f.path;$program['bound_'+$i+'_sha256']=$f.sha256;$i++}
$seed.schema_version=3;$seed.status='DRAFT';$seed.run_id=$RunId;$seed.handoff_id='HO-CAD-DUAL-BUSINESS-'+$RunId;$seed.issued_at=[DateTime]::Now.ToString('o');$seed.program=$program
$seed.issuer=@{lane='shared_interface_research';thread_id='RECEIVER_ID_REQUIRED'};$seed.target=@{lane='execution_run';thread_id='RECEIVER_ID_REQUIRED'}
$seed.command_routing=@{route_id='shared_annotation_interface_read';originating_research_thread_id=$seed.issuer.thread_id;detail_return_thread_id=$seed.issuer.thread_id;milestone_thread_id='RECEIVER_ID_REQUIRED'}
$seed.dual_business_concurrency=@{profile_id=$scope.profile_id;intent=$scope.intent;implementation_version=1;scope_path=(Join-Path $run 'scope.json');scope_sha256=$program.scope_sha256;manifest_path=$program.manifest;manifest_sha256=$program.manifest_sha256}
$seed.workflow_mode='TWO_OWNERS_REAL_NATIVE_ARC_LINE_GENERATION__NO_HOLD_NO_RETRY'
$seed.governance=@{workflow_id=$scope.profile_id;delivery_class='LIMITED_EXPERIMENT';formal_completion_claimed=$false;whole_drawing_acceptance_claimed=$false;visual_review_scope='NO_AESTHETIC_GATE';acceptance_mode='ordinary_test'}
$seed.reasoning.objective='两个真实新绑定实例各执行成熟ARC和LINE生成，分别验原生语义/源映射/旧对象保护，以真实GENERATE起止区间交集判断双业务并发。'
$seed.reasoning.user_authority='RECEIVER_CURRENT_AUTHORIZATION_REQUIRED__REFERENCE_SOURCE_IS_NOT_PERMISSION'
$seed.reasoning.settled='旧7组/14发送/16ms冻结；唯一控制者持原guard，双OwnJob；预先独立serial注册，本profile零NETLOAD，业务焦点仅观测。'
$seed.reasoning.open_space='真实生成交集待测，无交集如实结算，不重发、不延长native时间、不宣称两聊天控制。'
$seed.reasoning.reuse_admission.reused_component_ids=@('CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1')
$seed.reasoning.reuse_admission.delta_scope='仅owner参数/隔离输出/双写编排及原生区间适配；冻结几何生产者和DLL。'
$seed.reasoning.reuse_admission.interface_contract=@{producer_semantics='FROZEN_TYPED_ARC_LINE_PER_OWNER';consumer_semantics='INDEPENDENT_MAPPING_SEMANTICS_PROTECTION_AND_NATIVE_INTERVAL';adapter_rule='VERSIONED_EXPLICIT_OWNER_ADAPTER';controller_recalculation_count=0}
$seed.reasoning.reuse_admission.regression=@{path=$program.regression;sha256=$program.regression_sha256}
$seed.acceptance=@{scope='REAL_DUAL_BUSINESS_NOT_TWO_CHAT';send_max_count=6;per_owner_generation_max_count=1;per_owner_new_native_object_max_count=2;old_objects_unchanged_required=$true;native_ack_complete_required=$true;positive_GENERATE_native_intersection_required_for_concurrency=$true;allowed_commanded_grips=@();aesthetic_gate=$false;formal_reopen_claimed=$false;retry_count=0}
$seed.action=@{controller_template=($program.controller+" -ReadyHandoffPath '"+(Join-Path $root 'config/current_execution_handoff.json')+"'");controller_call_max=1;send_max_count=6;plugin_load_max=0;always_load_click_max=0;save_copy_max=0;foreground_input_max=0}
$seed.forbidden=@('original overwrite','old run replay','unknown resend','preexisting object mutation','arbitrary payload','global ROT fallback','NETLOAD or prompt click during business','activation or keyboard/mouse during business','two-chat control claim','new geometry or aesthetics')
$seed.reporting=@{source_thread_id=$seed.issuer.thread_id;run_directory=('runs/'+$RunId);controller_receipt=('runs/'+$RunId+'/controller_receipt.json');next_gate='分别核真实生成/映射/语义/保护和GENERATE原生交集；注册输入影响与业务零输入分列。'}
$seed.terminal_policy=@{next='回执直返来源；用户验收前不关CAD。';return_after='ONE_BOUNDED_DUAL_BUSINESS_OR_FAILURE'}
$seed.stop_conditions=@('owner/原租约/manifest/源保护漂移','未知发送不重发；已发双方独立结算，后续依赖步骤停止','两OwnJob各512MiB/active1/15秒，原3秒drain；清理未知不得PASS')
$seed.rollback='失败对象保留留证，不自动删对象、不重发、不覆盖原件，仅清理本批OwnJob。'
$path=Join-Path $run 'candidate.draft.json';Write-CadBatchJsonAtomicV2 $path $seed
& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/invoke_dual.ps1') -ReadyHandoffPath $path -PreflightOnly
@{status='PRIVATE_DRAFT_NO_READY_NO_CAD';draft=$path;scope_sha256=$program.scope_sha256;manifest_sha256=$program.manifest_sha256;cad_calls=0;ready_published=0}|ConvertTo-Json -Compress
