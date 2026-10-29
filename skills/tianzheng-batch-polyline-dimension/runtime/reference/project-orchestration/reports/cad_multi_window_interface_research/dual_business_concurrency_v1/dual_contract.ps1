# Definition-only composition. No CAD, COM, process or window action on import.
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v2/batch_contract.ps1')
$script:DualRelative='reports/cad_multi_window_interface_research/dual_business_concurrency_v1/'
function Get-CadDualBusinessCapsV1 {
 [pscustomobject][ordered]@{serial_executor_required=$true;original_global_guard_unchanged=$true;owner_max_count=2;pair_count=3;send_max_count=6;per_owner_generation_max_count=1;per_owner_new_native_object_max_count=2;helper_max_simultaneous=2;helper_timeout_seconds=15;drain_timeout_seconds=3;job_memory_limit_bytes=536870912;job_active_process_limit=1;plugin_load_max_count=0;prompt_click_max_count=0;fixed_existing_lsp_load_only=$true;focus_policy='OBSERVE_ONLY';activation_allowed=$false;keyboard_mouse_allowed=$false;save_original_allowed=$false;launch_close_kill_cad_allowed=$false;retry_allowed=$false;fallback_allowed=$false;arbitrary_payload_allowed=$false;two_chat_control_allowed=$false;aesthetic_gate=$false;overall_timeout_seconds=120;artificial_native_hold_ms=0;commanded_grip_move_count=0}
}
function Get-CadDualBusinessPlanV1 {
 @(@{pair=1;stage='DISCOVER';action='TARGET_SEGMENT_GEOMETRY_INVENTORY';process='prepare';delta=0},@{pair=2;stage='GENERATE';action='TDIM_TYPED_SEGMENT_BATCH';process='after_generation';delta=2},@{pair=3;stage='POSTREAD';action='NATIVE_GENERATION_SEMANTICS_AND_PROTECTION';process='final';delta=0})
}
function Get-CadDualExtraDependenciesV1 {
 @('reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v9/read_settlement_v9.ps1')
}
function Assert-CadDualBusinessScopeV1($Scope,[string]$Root) {
 if($Scope.schema_version-ne1-or$Scope.implementation_version-ne1-or$Scope.profile_id-cne'CAD-AB-DUAL-BUSINESS-CONCURRENCY-V1'-or$Scope.route-cne'shared_annotation_interface_read'-or$Scope.intent-cne'ExecuteBothOwnerNativeGeneration'-or$Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'DUAL_SCOPE_IDENTITY'}
 if(($Scope.capability_bounds|ConvertTo-Json -Compress)-cne((Get-CadDualBusinessCapsV1)|ConvertTo-Json -Compress)){throw 'DUAL_CAPS'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
 if($identity.owners.Count-ne2-or$identity.owners[0].window_handle-eq$identity.owners[1].window_handle-or$identity.owners[0].protected_sha256-cne$identity.owners[1].protected_sha256){throw 'DUAL_DISTINCT_SAME_HASH_ISOLATED_OWNERS_REQUIRED'}
 $run=Resolve-CadExactBProjectPathV1 $Root ('runs/'+$Scope.run_id)
 $e=Read-CadExactBBoundJsonV1 $Scope.owner_evidence.path $Scope.owner_evidence.sha256
 if(($e.owners|ConvertTo-Json -Depth 15 -Compress)-cne($Scope.owners|ConvertTo-Json -Depth 15 -Compress)-or@($Scope.owner_evidence.receipts).Count-lt2){throw 'DUAL_OWNER_EVIDENCE'}
 foreach($f in $Scope.owner_evidence.receipts){$null=Read-CadExactBBoundJsonV1 (Resolve-CadExactBProjectPathV1 $Root $f.path) $f.sha256}
 foreach($o in $Scope.owners){
  $ref=$e.registration.($o.id);$r=Read-CadExactBBoundJsonV1 (Resolve-CadExactBProjectPathV1 $Root $ref.path) $ref.sha256
  if($r.status-cne'PASS_SERIAL_NATIVE_REGISTRATION'-or$r.owner_id-cne$o.id-or$r.process_id-ne$o.process_id-or$r.process_start_time_utc-cne$o.process_start_time_utc-or$r.window_handle-ne$o.window_handle-or$r.document_full_path-ine$o.document_full_path-or-not$r.native_registered-or$r.actual_generation_count-ne0-or$r.empty_task_admission_count-ne1-or(@($r.commands|Sort-Object)-join',')-cne'C:CXTDIMARCFULLBATCH,CXNATIVEGRIPINVENTORY,CXTDIMTEXTMETRICSV2'){throw 'DUAL_EXACT_SERIAL_REGISTRATION_REQUIRED'}
 }
 if($Scope.source.path-ine$e.source.path-or$Scope.source.sha256-cne$e.source.sha256){throw 'DUAL_SOURCE_EVIDENCE'}
 if($Scope.source.sha256-cne(& (Join-Path $Root 'scripts/get_shared_file_sha256_v1.ps1') -Path $Scope.source.path)){throw 'DUAL_SOURCE_HASH'}
 if(@($Scope.operations).Count-ne6){throw 'DUAL_EXACT_SIX_OPERATIONS'};$nonces=@{}
 foreach($plan in @(Get-CadDualBusinessPlanV1)){foreach($owner in @('A','B')){
  $id=$owner+('{0:00}'-f$plan.pair);$ops=@($Scope.operations|Where-Object id -CEQ $id);if($ops.Count-ne1){throw 'DUAL_OPERATION_SET'};$op=$ops[0]
  if($op.owner-cne$owner-or$op.pair-ne$plan.pair-or$op.stage-cne$plan.stage-or$op.action-cne$plan.action-or$op.expected_model_delta-ne$plan.delta-or$op.nonce-cnotmatch'^[a-f0-9]{32}$'-or$nonces.ContainsKey($op.nonce)){throw 'DUAL_OPERATION_IDENTITY'};$nonces[$op.nonce]=$true
  if($op.signal_path-ine(Join-Path $run ('signals/'+$id+'.log'))-or$op.business_signal_path-ine(Join-Path $run ('signals/'+$id+'_business.log'))-or$op.data_run-ine(Join-Path $run $owner)-or$op.bundle_path-cne($script:DualRelative+'native_dual_stages.lsp')-or$op.bundle_sha256-cne(Get-FileHash (Join-Path $Root $op.bundle_path)).Hash){throw 'DUAL_OPERATION_PATH_OR_BUNDLE'}
  foreach($name in @($op.PSObject.Properties.Name)){if($name-match'(?i)payload|command_text|expression|entry_function|module_path|load_paths'){throw 'DUAL_ARBITRARY_EXECUTABLE_FIELD'}}
 }}
 foreach($o in $Scope.owners){$r=$Scope.references.($o.id);if($r.sha256-cne(Get-FileHash $r.path).Hash-or[IO.File]::ReadAllText($r.path).Trim()-cnotmatch'^[0-9A-F]+$'){throw 'DUAL_REFERENCE_DATA'}}
 [pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;operations=@($Scope.operations)}
}
function Assert-CadDualManifestV1($Manifest,[string]$Root) {
 if($Manifest.profile_id-cne'CAD-AB-DUAL-BUSINESS-CONCURRENCY-V1'-or$Manifest.files.Count-lt20){throw 'DUAL_MANIFEST_IDENTITY'}
 $seen=@{};foreach($f in $Manifest.files){$path=Resolve-CadExactBProjectPathV1 $Root $f.path;if($seen.ContainsKey($f.path)-or(Get-FileHash $path).Hash-cne$f.sha256){throw ('DUAL_MANIFEST_CHANGED:'+ $f.path)};$seen[$f.path]=$true}
 foreach($leaf in @('dual_contract.ps1','build_draft.ps1','invoke_dual.ps1','command_worker_v1.ps1','process_dual.py','native_dual_stages.lsp','test_offline.py','test_contract.ps1')){if(-not$seen.ContainsKey($script:DualRelative+$leaf)){throw 'DUAL_UNBOUND_CANDIDATE'}}
 foreach($p in @('reference/project-orchestration/reports/dimension_background_reproduction_v7/native_stages.lsp','reference/project-orchestration/reports/dimension_background_reproduction_v8/process_artifacts.py','reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v2/batch_contract.ps1','reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v3/process_batch.py','scripts/tdimarc_native_full_batch.lsp')){if(-not$seen.ContainsKey($p)){throw ('DUAL_UNBOUND_FROZEN_KERNEL:'+ $p)}}
 foreach($p in @(Get-CadDualExtraDependenciesV1)){if(-not$seen.ContainsKey($p)){throw ('DUAL_UNBOUND_RUNTIME_DEPENDENCY:'+ $p)}}
}
function Assert-CadDualReadyV1($Scope,[string]$Root,[string]$ScopeHash,[string]$ManifestHash) {
 $p=(Get-Content (Join-Path $Root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String).routes.shared_annotation_interface_read.optional_command_profiles.PSObject.Properties[$Scope.profile_id]
 if($null-eq$p-or$p.Value.candidate_contract_abi-cne'Assert-CadDualBusinessScopeV1($Scope,$Root)'-or($p.Value.candidate_capability_bounds|ConvertTo-Json -Compress)-cne((Get-CadDualBusinessCapsV1)|ConvertTo-Json -Compress)){throw 'DUAL_SHARED_ADMISSION_REQUIRED'}
 $run=Join-Path $Root ('runs/'+$Scope.run_id);$h=Get-Content (Join-Path $run 'execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
 $current=Get-Content (Join-Path $Root 'config/current_execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
 $claim=Get-Content (Join-Path $run 'execution_controller_claim.json') -Raw|ConvertFrom-Json -DateKind String
 if((Test-Path (Join-Path $run 'execution_return.json'))-or$h.status-cne'READY'-or$current.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$current.run_id-cne$Scope.run_id-or$h.dual_business_concurrency.profile_id-cne$Scope.profile_id-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.program.scope_sha256-cne$ScopeHash-or$h.program.manifest_sha256-cne$ManifestHash-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $run 'execution_handoff.json')).Hash-or$claim.run_id-cne$Scope.run_id-or$claim.handoff_id-cne$h.handoff_id-or-not$claim.controller_attempt_reserved){throw 'DUAL_READY_OR_CLAIM'}
}
function Assert-CadDualProtectedFilesV1($Scope,$Identity,[string]$Root){Assert-CadMultiOwnerProtectedHashesV1 $Identity;if((& (Join-Path $Root 'scripts/get_shared_file_sha256_v1.ps1') -Path $Scope.source.path)-cne$Scope.source.sha256){throw 'DUAL_SOURCE_DISK_CHANGED'}}
function New-CadDualExpressionV1($Scope,$Op,$Owner,[string]$Root) {
 $values=[ordered]@{'cxbg:root'=$Root.Replace('\','/');'cxbg:run-path'=$Op.data_run.Replace('\','/');'cxbg:run-id'=$Scope.run_id;'cxbg:operation-id'=$Op.id;'cxbg:nonce'=$Op.nonce;'cxbg:signal-path'=$Op.signal_path.Replace('\','/');'cxbg:expected-drawing'=$Owner.document_full_path.Replace('\','/');'cxbg:stage'=$Op.stage;'cxdual:owner'=$Owner.id}
 $values['cxdual:business-signal-path']=$Op.business_signal_path.Replace('\','/')
 $assign=@(foreach($k in $values.Keys){$k+' '+(ConvertTo-CadExactBLispStringV2 $values[$k])})-join' '
 $entry=ConvertTo-CadExactBLispStringV2 ((Join-Path $Root $Op.bundle_path).Replace('\','/'));$drawing=ConvertTo-CadExactBLispStringV2 $Owner.document_full_path.Replace('\','/')
 '(progn (vl-load-com) (if (and (= (rem (+ (vla-get-HWND (vlax-get-acad-object)) 4294967296.0) 4294967296.0) '+[long]$Owner.window_handle+') (= (strcase (vl-string-translate "\\" "/" (vla-get-FullName (vla-get-ActiveDocument (vlax-get-acad-object))))) (strcase '+$drawing+'))) (progn (setq '+$assign+') (load '+$entry+') (cxdual:run)) (princ "DUAL_NATIVE_OWNER_CHANGED_NO_ACTION")) (princ))'+"`n"
}
function Read-CadDualNativeV1($Scope,$Op,[switch]$GeneratorBody) {
 $path=if($GeneratorBody){if($Op.stage-cne'GENERATE'){throw 'DUAL_BODY_ONLY_GENERATE'};$Op.business_signal_path}else{$Op.signal_path}
 if(-not(Test-Path $path)){return $null};$raw=[IO.File]::ReadAllText($path);if(-not$raw.EndsWith("`n")){return $null}
 $lines=@($raw-split'\r?\n'|Where-Object{$_});$typed=@($lines|Where-Object {$_-like'CX_MULTI_OWNER_PROBE_V1|*'});if($typed.Count-lt2){return $null};if($typed.Count-ne2-or$lines.Count-ne4){throw 'DUAL_SIGNAL_DUPLICATED'}
 $owner=@($Scope.owners|Where-Object id -CEQ $Op.owner)[0];$rows=@()
 foreach($l in $typed){$f=$l.Split('|');if($f.Count-ne10-or$f[1]-cne$Op.nonce-or$f[2]-cne$Scope.run_id-or$f[3]-cne$Op.id-or$f[4]-cne$Op.owner-or$f[5]-cne[string]$owner.window_handle){throw 'DUAL_SIGNAL_IDENTITY'};foreach($i in @(7,8,9)){if($f[$i]-cnotmatch'^\d+$'){throw 'DUAL_SIGNAL_NUMERIC'}};$rows+=@([pscustomobject]@{stage=$f[6];tick=[long]$f[7];dbmod=[int]$f[8];model_count=[int]$f[9]})}
 if(($rows.stage-join',')-cne'ACK,COMPLETE'){throw 'DUAL_SIGNAL_ORDER'};$duration=($rows[1].tick-$rows[0].tick+4294967296L)%4294967296L
 if($duration-gt15000-or$rows[1].model_count-$rows[0].model_count-ne$Op.expected_model_delta-or($Op.stage-cne'GENERATE'-and$rows[1].dbmod-ne$rows[0].dbmod)){throw 'DUAL_SIGNAL_EFFECT_OR_DEADLINE'}
 foreach($r in $rows){if(@($lines|Where-Object {$_-ceq('CX_CAD_SIGNAL_V1|CAD_COMMAND_'+$r.stage+'|'+$r.tick)}).Count-ne1){throw 'DUAL_OBSERVER_DISAGREEMENT'}}
 [pscustomobject]@{status='PASS';owner=$Op.owner;ack=$rows[0];complete=$rows[1];ack_tick=$rows[0].tick;complete_tick=$rows[1].tick;native_ms=$duration;interval_scope=$(if($GeneratorBody){'EXACT_MATURE_GENERATOR_BODY_ONLY'}else{'FIXED_NATIVE_STAGE_INCLUDING_READBACK'})}
}
