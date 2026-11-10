param([Parameter(Mandatory)][string]$RunId,[Parameter(Mandatory)][string]$SourceRelativePath,[Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$SourceSha256,[Parameter(Mandatory)][string]$TianzhengSys)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'channel_contract_v11.ps1');$root=Resolve-FixedV3Root (Join-Path $PSScriptRoot '../../..')
if($RunId-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'FIXED_V3_RUN_ID'}
$run=Join-Path $root ('runs/'+$RunId);if(Test-Path -LiteralPath $run){throw 'FIXED_V3_FRESH_RUN_REQUIRED'}
$source=$SourceRelativePath;$sourcePath=Resolve-FixedV3Path $root $source;$sourceHash=(Get-FileHash -LiteralPath $sourcePath).Hash
if($sourceHash-cne$SourceSha256){throw 'FIXED_V3_SOURCE_HASH'}
$routeProfile=Get-FixedV3Profile $root;$module=Join-Path $PSScriptRoot 'bin/CadChannelV11.dll';$moduleHash=(Get-FileHash -LiteralPath $module).Hash
$machineSys=[IO.Path]::GetFullPath($TianzhengSys);$machineArx=@(foreach($name in @('tch_kernal.arx','tch_utility.arx','tch_pipewire.arx','tch_pipebase.arx','tch_initstart.arx','tch_common.arx','tch3_kernal.arx')){$p=Join-Path $machineSys $name;@{path=$p;sha256=(Get-FileHash -LiteralPath $p).Hash}})
$paths=@('config/parallel_receiver.json','scripts/restore_cad_manual_dialogs_after_exit.ps1','scripts/common/CadOperationGuard.psm1','scripts/assert_cad_independent_project_jobs_v3.ps1','scripts/assert_cad_canonical_open_consistency.ps1','reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll')
foreach($leaf in @('FixedTaskProtocol.cs','ChannelProtocolV11.cs','ChannelModuleV11.cs','bin/CadChannelV11.dll','channel_contract_v11.ps1','invoke_channel_v11.ps1','launch_channel_v11.ps1','publish_channel_request_v11.ps1','OwnStartupJobV4.cs','bin/OwnStartupJobV4.dll','startup_tip_worker_v4.ps1','build_channel_v11.ps1','build_channel_draft_v11.ps1','test_channel_v11.ps1','ChannelProtocolTestsV11.cs','receive_channel_result_v11.ps1')){$paths+=$script:FixedV3Prefix+$leaf}
$dependencies=@($paths|Sort-Object -Unique|ForEach-Object{@{path=(Join-Path $root $_);sha256=(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash}})
$null=New-Item -ItemType Directory -Path $run
$hostPlans=@();$boundData=@();$expires=[DateTimeOffset]::UtcNow.AddMinutes(30).ToString('o')
foreach($id in @('A','B')){
 $session=Join-Path $run ('hosts/'+$id);$null=New-Item -ItemType Directory -Path (Join-Path $session 'tasks') -Force
 $caseRoot=Join-Path $session 'AB';$work=Join-Path $caseRoot 'work.dwg';$data=Join-Path $caseRoot 'data';$null=New-Item -ItemType Directory -Path (Join-Path $data 'reports') -Force;[IO.File]::Copy($sourcePath,$work,$false)
 $caseInputs=@(@{id='AB';work=$work;sha256=$sourceHash;data_run=$data;checkpoint=(Join-Path $caseRoot 'write_checkpoint.dwg')});$boundData+=$work
 $boot=@{schema_version=10;validation_mode='PARALLEL_NATIVE_WRITE_ONLY';source_thread_id=$(if($id-ceq'A'){'RECEIVER_SOURCE_A'}else{'RECEIVER_SOURCE_B'});operations=@('KNOWN_WRITE_BATCH');run_id=$RunId;owner=$id;root=$root;session_dir=$session;module_sha256=$moduleHash;expires_utc=$expires;source=$sourcePath;source_sha256=$sourceHash;cases=$caseInputs;dependencies=$dependencies;machine_sys=$machineSys;machine_arx=$machineArx}
 $bootPath=Join-Path $session 'boot.json';Write-FixedV3NewJson $bootPath $boot;$boundData+=$bootPath
 $hostPlans+=@{id=$id;session_dir=$session;boot_path=$bootPath;boot_sha256=(Get-FileHash -LiteralPath $bootPath).Hash}
}
$scope=@{schema_version=3;implementation_version=3;profile_id=$routeProfile.profile_id;route='shared_annotation_interface_read';intent=$routeProfile.intent;phase=$routeProfile.phase;run_id=$RunId;source=@{path=$source;sha256=$sourceHash};validation_mode='PARALLEL_NATIVE_WRITE_ONLY';source_thread_id='RECEIVER_SOURCE_A';case_ids=@('AB');requests=@(foreach($id in @('A','B')){@{owner=$id;sequence=1;source_thread_id=$(if($id-ceq'A'){'RECEIVER_SOURCE_A'}else{'RECEIVER_SOURCE_B'});request_id=('AB_'+$id+'_SEQUENCE_1');nonce=[guid]::NewGuid().ToString('N');operation='KNOWN_WRITE_BATCH'}});hosts=$hostPlans;capability_bounds=$routeProfile.candidate_capability_bounds}
$scopePath=Join-Path $run 'scope.json';Write-FixedV3NewJson $scopePath $scope
$files=@($dependencies|ForEach-Object{@{path=[IO.Path]::GetRelativePath($root,$_.path).Replace('\','/');sha256=$_.sha256}})
foreach($p in @($sourcePath)+$boundData){$files+=@{path=[IO.Path]::GetRelativePath($root,$p).Replace('\','/');sha256=(Get-FileHash -LiteralPath $p).Hash}}
$manifest=@{profile_id=$scope.profile_id;files=@($files|Sort-Object path -Unique)};$manifestPath=Join-Path $run 'manifest.json';Write-FixedV3NewJson $manifestPath $manifest
$null=Assert-CadIndependentProjectScopeV3 $scope $root;Assert-CadIndependentProjectManifestV3 $manifest $root
$draft=Get-Content -LiteralPath (Join-Path $root 'templates/channel_handoff.draft.json') -Raw|ConvertFrom-Json -AsHashtable -DateKind String
foreach($key in @('background_native_read','single_background_native_read','shared_annotation_interface_read','interface_read_profile','return_delivery','immutable_handoff_path','immutable_handoff_sha256','development_workflow')){$draft.Remove($key)}
$program=[ordered]@{controller=($script:FixedV3Prefix+'invoke_channel_v11.ps1');scope=('runs/'+$RunId+'/scope.json');manifest=('runs/'+$RunId+'/manifest.json');regression=($script:FixedV3Prefix+'test_channel_v11.ps1')}
foreach($key in @($program.Keys)){$program[$key+'_sha256']=(Get-FileHash -LiteralPath (Join-Path $root $program[$key])).Hash}
$index=0;foreach($f in $manifest.files){$program['bound_'+$index]=$f.path;$program['bound_'+$index+'_sha256']=$f.sha256;$index++}
$draft.schema_version=3;$draft.status='DRAFT';$draft.run_id=$RunId;$draft.handoff_id='HO-CAD-FIXED-V3-'+$RunId;$draft.issued_at=[DateTimeOffset]::Now.ToString('o');$draft.program=$program
$draft.issuer=@{lane='shared_interface_research';thread_id='RECEIVER_SOURCE_A'};$draft.target=@{lane='execution_run';thread_id='RECEIVER_SOURCE_B'}
$draft.owner=@{process_id=0;window_handle=0;drawing=(Join-Path $hostPlans[0].session_dir 'AB/work.dwg');process_start_time_utc=$null;launch_permitted=$true;binding_policy='NEW_PRIVATE_RESEARCH_HOST_NATIVE_READY_ONLY__ALL_PREEXISTING_EXCLUDED'}
if(-not$draft.ContainsKey('canonical_open')){$draft.canonical_open=@{}};if(-not$draft.ContainsKey('launch_policy')){$draft.launch_policy=@{}}
$draft.canonical_open.profile_id=$scope.profile_id;$draft.canonical_open.component_id='CAD-SCOPED-PRIVATE-LAUNCH-V3';$draft.canonical_open.entrypoint=$script:FixedV3Prefix+'launch_channel_v11.ps1';$draft.canonical_open.transport='ISOLATED_PRIVATE_DESKTOP_CREATEPROCESS_FIXED_BOOT';$draft.canonical_open.launch_permitted_for_this_handoff=$true
$draft.canonical_open.open_result_semantics='new_native_PID_start_HWND_document_and_module_hash_or_fail__all_preexisting_hosts_excluded'
$draft.launch_policy.launch_permitted_for_this_handoff=$true;$draft.launch_policy.open_result_semantics=$draft.canonical_open.open_result_semantics;$draft.launch_policy.invocation='scoped_private_desktop_fixed_module_profile_only'
foreach($flag in @('inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open','standalone_close_allowed')){$draft.launch_policy[$flag]=$false}
$draft.command_routing=@{route_id='shared_annotation_interface_read';originating_research_thread_id=$draft.issuer.thread_id;detail_return_thread_id=$draft.issuer.thread_id;milestone_thread_id='RECEIVER_COORDINATOR'}
$draft.independent_project_jobs=@{validation_mode='PARALLEL_NATIVE_WRITE_ONLY';profile_id=$scope.profile_id;intent=$scope.intent;implementation_version=3;scope_path=$scopePath;scope_sha256=$program.scope_sha256;manifest_path=$program.manifest;manifest_sha256=$program.manifest_sha256}
$draft.workflow_mode='REAL_TWO_ORIGIN_PARALLEL_NATIVE_WRITE'
$draft.governance=@{workflow_id=$scope.profile_id;delivery_class='LIMITED_EXPERIMENT';formal_completion_claimed=$false;whole_drawing_acceptance_claimed=$false;visual_review_scope='LOCAL_CALIBRATION_OR_DIAGNOSTIC_ONLY';acceptance_mode='ordinary_test'}
$draft.reasoning.objective='A/B两个真实来源共同释放各一条固定写入任务，两个独立后台CAD在各自隔离DWG写入1024条原生LINE，并各自保存、独立重开核验且原来源收到结果；检查真实写入时间交叠。'
$draft.reasoning.user_authority='RECEIVER_MUST_RECORD_CURRENT_EXPLICIT_AUTHORIZATION_BEFORE_READY'
$draft.reasoning.settled='本包仅复用已验双来源固定通道；接收方本轮实机状态尚未验证。'
$draft.reasoning.open_space='双宿主写入阶段是否实际交叠、各自DWG原生LINE集合是否保存重开一致、两真实来源是否分别读回待实测。'
$draft.reasoning.reuse_admission.mode='NEW_AFTER_RECALL_GAP';$draft.reasoning.reuse_admission.reused_component_ids=@();$draft.reasoning.reuse_admission.why_no_active_component_applies='复用已验私有固定入口与双来源归路；既有只读通道没有原生写入与独立保存重开证据，本轮限隔离副本扩展。'
$draft.reasoning.reuse_admission.delta_scope='保留已验双来源exact-slot队列；增加一条固定1024 LINE原生写入、双host ready同步、独立保存重开核验与写入时段证据，不授生产控制。'
$draft.reasoning.reuse_admission.interface_contract=@{producer_semantics='EXACT_OWNER_SOURCE_BOUND_REQUEST';consumer_semantics='NATIVE_COMPLETION_RETURN_TO_SAME_REAL_ORIGIN';adapter_rule='VERSIONED_EXPLICIT_ADAPTER';controller_recalculation_count=0}
$draft.reasoning.reuse_admission.regression=@{path=$program.regression;sha256=$program.regression_sha256}
$draft.acceptance=@{retry_count=0;aesthetic_gate=$false;native_entry_required=$true;independent_saved_native_readback_required=$true;two_chat_control_claimed=$true;real_fault_isolation_claimed=$false;write_batch_overlap_required=$true}
$draft.action=@{controller_template=($program.controller+" -ReadyHandoffPath '"+(Join-Path $root 'config/current_execution_handoff.json')+"'");controller_call_max=1;send_max_count=0;native_task_max_count=2;plugin_load_max=2;always_load_click_max=0;save_copy_max=2;foreground_input_max=0;startup_tip_close_max=2}
$draft.forbidden=@('all preexisting CAD hosts','production deliverables','source overwrite','external COM business SendCommand','keyboard mouse focus activation','arbitrary payload','unknown resend','old run replay')
$draft.reporting=@{source_thread_id=$draft.issuer.thread_id;run_directory=('runs/'+$RunId);controller_receipt=('runs/'+$RunId+'/controller_receipt.json');next_gate='核两真实来源各自提交与读回、精确宿主、原生写入批次交集、两个保存DWG的独立重开回读与资源收口。'}
$draft.terminal_policy=@{next='本轮结束停止；所有专属宿主保护关闭并核实际退出，恢复手动打开设置；各原来源独立收到自身回执。';return_after='ONE_ISOLATED_FIXED_MODULE_TRIAL_OR_FIRST_DECISIVE_FAILURE'}
$draft.stop_conditions=@('本owner未知不重发，安全同伴在本次有界任务内结算','后台启动受阻无前台回退','原件变动、共享租约或自有助手未结算停止新动作')
$draft.rollback='只保留隔离工作副本与证据，不删除对象、不改原件、不关闭既有宿主。'
$draftPath=Join-Path $run 'candidate.draft.json';Write-FixedV3NewJson $draftPath $draft
& (Join-Path $PSScriptRoot 'invoke_channel_v11.ps1') -ReadyHandoffPath $draftPath -PreflightOnly
[pscustomobject]@{status='PRIVATE_DRAFT_NO_READY_NO_CAD';draft=$draftPath;scope=$scopePath;manifest=$manifestPath;dependency_count=$manifest.files.Count;CAD_calls=0}




