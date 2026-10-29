# Private composition only. Imports define existing kernels, never operate CAD.
$batchRootV1=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
. (Join-Path $batchRootV1 'scripts/cad_exact_b_focus_independent_transport_v4.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v8/native_read_contract_v8.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v8/operation_adapter_v8.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/command_probe_v4/file_binding_v4.ps1')
. (Join-Path $batchRootV1 'reference/project-orchestration/reports/dimension_background_reproduction_v8/runtime_contract.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v9/read_settlement_v9.ps1')
. (Join-Path $batchRootV1 'scripts/cad_worker_receipt_settlement_v1.ps1')

function Get-CadRepresentativeBatchPlanV1 {
 @(
  @{pair=1;stage='DISCOVER';action='TARGET_SEGMENT_GEOMETRY_INVENTORY';category='native_read';process='prepare'},
  @{pair=2;stage='GENERATE';action='TDIM_TYPED_SEGMENT_BATCH';category='ARC_LINE_generation';process='after_generation'},
  @{pair=3;stage='METRICS';action='AUDIT_NATIVE_DIM_TEXT_BBOXES';category='new_object_text_read';process='adjust_plan'},
  @{pair=4;stage='LAYOUT';action='NET_GENERIC_GRIP_BATCH_MOVE';category='new_LINE_dual_grip_adjust';process='adjust_audit'},
  @{pair=5;stage='FINAL_METRICS';action='AUDIT_NATIVE_DIM_TEXT_BBOXES';category='native_semantic_readback';process='final'},
  @{pair=6;stage='VISUAL';action='DOCUMENT_PREVIEW';category='view_refresh_preview_call';process='preview'},
  @{pair=7;stage='CHECKPOINT';action='SAVE_COPY_CHECKPOINT';category='new_file_save';process='checkpoint'}
 )
}
function Get-CadRepresentativeBatchCapsV1 {
 [pscustomobject][ordered]@{serial_executor_required=$true;original_global_guard_unchanged=$true;owner_max_count=2;pair_count=7;send_max_count=14;A_read_max_count=7;B_stage_max_count=7;helper_max_simultaneous=2;helper_timeout_seconds=15;drain_timeout_seconds=3;job_memory_limit_bytes=536870912;job_active_process_limit=1;plugin_load_max_count=0;prompt_click_max_count=0;fixed_existing_B_lsp_load_only=$true;new_native_object_max_count=2;adjust_only_new_LINE=$true;adjusted_native_grips='0,1';test_delta_wcs='ONE_DRAWING_UNIT_ALONG_MATURE_LINE_AXIS';focus_policy='OBSERVE_ONLY';activation_allowed=$false;keyboard_mouse_allowed=$false;save_original_allowed=$false;launch_close_kill_cad_allowed=$false;retry_allowed=$false;fallback_allowed=$false;arbitrary_payload_allowed=$false;two_chat_control_allowed=$false;aesthetic_gate=$false;overall_timeout_seconds=180}
}
function Assert-CadRepresentativeCommandBatchScopeV1($Scope,[string]$Root) {
 if($Scope.schema_version-ne1-or$Scope.profile_id-cne'CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1'-or$Scope.route-cne'shared_annotation_interface_read'-or$Scope.intent-cne'ExecuteRepresentativeNativeCommandPairs'-or$Scope.phase-cne'AB_REPRESENTATIVE_COMMAND_BATCH'-or$Scope.implementation_version-ne1){throw 'BATCH_SCOPE_IDENTITY'}
 if($Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'BATCH_RUN_ID'}
 if(($Scope.capability_bounds|ConvertTo-Json -Compress)-cne((Get-CadRepresentativeBatchCapsV1)|ConvertTo-Json -Compress)){throw 'BATCH_CAPS'}
 $prior=Get-Content (Join-Path $Root 'runs/20261028_dimension_failed_line_recovery_v8b/scope.json') -Raw|ConvertFrom-Json -DateKind String
 if(($Scope.owners|ConvertTo-Json -Depth 10 -Compress)-cne($prior.owners|ConvertTo-Json -Depth 10 -Compress)){throw 'BATCH_OWNER_PROVENANCE'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
 $run=Resolve-CadExactBProjectPathV1 $Root ('runs/'+$Scope.run_id)
 $ops=@($Scope.operations);if($ops.Count-ne14){throw 'BATCH_OPERATION_COUNT'}
 $seen=@{}
 foreach($p in @(Get-CadRepresentativeBatchPlanV1)){
  foreach($ownerId in @('A','B')){
   $id=$ownerId+('{0:00}'-f$p.pair);$rows=@($ops|Where-Object id -CEQ $id)
   if($rows.Count-ne1){throw 'BATCH_OPERATION_ID'};$op=$rows[0]
   if($op.owner-cne$ownerId-or$op.pair-ne$p.pair-or$op.nonce-cnotmatch'^[a-f0-9]{32}$'-or$seen.ContainsKey($op.nonce)){throw 'BATCH_OPERATION_OWNER_OR_NONCE'};$seen[$op.nonce]=$true
   if($op.signal_path-ine(Join-Path $run ('signals/'+$id+'.log'))){throw 'BATCH_SIGNAL_PATH'}
   if($ownerId-ceq'A'){
    if($op.kind-cne'READ'-or$op.duration_ms-ne0-or$op.action-cne'V285_CXANNOTATIONCONTROLREADV1'){throw 'BATCH_A_READ_ONLY'}
    foreach($entry in @(@('native_report',('reports/annotation_control_read_'+$id+'.tsv')),@('stage_signal_path',('signals/'+$id+'_phase.log')),@('load_context_path',('signals/'+$id+'_context.log')),@('registration_path',('reports/reader_availability_'+$id+'.log')))){
     if($op.($entry[0])-ine(Join-Path $run $entry[1])){throw 'BATCH_A_OUTPUT_PATH'}
    }
   }else{
    if($op.stage-cne$p.stage-or$op.action-cne$p.action-or$op.expected_model_delta-ne$(if($p.stage-ceq'GENERATE'){2}else{0})-or$op.bundle_path-cne'reference/project-orchestration/reports/dimension_background_reproduction_v7/native_stages.lsp'-or$op.bundle_sha256-cne'543BF0BC999ADA031DE2F96FBCE22E28E6808501F88ED240647A45A52FFDDA18'){throw 'BATCH_B_FIXED_STAGE'}
   }
  }
 }
 foreach($name in @($Scope.PSObject.Properties.Name)){if($name-match'(?i)payload|command_text|expression|allow_'){throw 'BATCH_EXTRA_EFFECT_FIELD'}}
 [pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;operations=$ops}
}
function Assert-CadRepresentativeBatchManifestV1($Manifest,[string]$Root) {
 if($Manifest.profile_id-cne'CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1'-or$Manifest.files.Count-lt10){throw 'BATCH_MANIFEST_IDENTITY'}
 $seen=@{};foreach($f in $Manifest.files){if($seen.ContainsKey($f.path)){throw 'BATCH_DUPLICATE_DEPENDENCY'};$seen[$f.path]=$true;$path=Resolve-CadExactBProjectPathV1 $Root $f.path;if((Get-FileHash $path).Hash-cne$f.sha256){throw ('BATCH_DEPENDENCY_CHANGED:'+ $f.path)}}
 foreach($path in @('reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/batch_contract.ps1','reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/command_worker_v1.ps1','reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/invoke_batch.ps1','reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/process_batch.py','reference/project-orchestration/reports/dimension_background_reproduction_v7/native_stages.lsp')){if(-not$seen.ContainsKey($path)){throw ('BATCH_REQUIRED_DEPENDENCY:'+ $path)}}
}
function Assert-CadRepresentativeBatchAdmissionV1([string]$Root) {
 $routing=Get-Content (Join-Path $Root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String
 $profiles=$routing.routes.shared_annotation_interface_read.optional_command_profiles
 $prop=$profiles.PSObject.Properties['CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1']
 if($null-eq$prop){throw 'BATCH_SHARED_COMPOSITION_NOT_ADMITTED'};$p=$prop.Value
 if($p.candidate_source_thread_id-cne'RECEIVER_ID_REQUIRED'-or$p.candidate_contract_abi-cne'Assert-CadRepresentativeCommandBatchScopeV1($Scope,$Root)'-or($p.candidate_capability_bounds|ConvertTo-Json -Compress)-cne((Get-CadRepresentativeBatchCapsV1)|ConvertTo-Json -Compress)){throw 'BATCH_SHARED_ADMISSION_MISMATCH'}
}
function Assert-CadRepresentativeBatchDraftV1($Draft,$Scope,[string]$Root) {
 $controller='reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/invoke_batch.ps1'
 $expected=$controller+" -ReadyHandoffPath '"+(Join-Path $Root 'config/current_execution_handoff.json')+"'"
 if($Draft.governance.workflow_id-cne$Scope.profile_id-or$Draft.action.controller_template-cne$expected-or$Draft.action.send_max_count-ne14-or$Draft.acceptance.send_max_count-ne14-or$Draft.acceptance.aesthetic_gate-or$Draft.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$Draft.target.thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'BATCH_DRAFT_COMPOSITION_MISMATCH'}
 if($Draft.execution_envelope.sha256-cne(Get-FileHash (Join-Path $Root $Draft.execution_envelope.entry)).Hash){throw 'BATCH_TERMINAL_ENVELOPE_CHANGED'}
}
function Assert-CadRepresentativeBatchReadyV1($Scope,[string]$Root,[string]$ScopeHash,[string]$ManifestHash) {
 Assert-CadRepresentativeBatchAdmissionV1 $Root
 $run=Join-Path $Root ('runs/'+$Scope.run_id)
 $h=Get-Content (Join-Path $run 'execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
 $current=Get-Content (Join-Path $Root 'config/current_execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
 $claim=Get-Content (Join-Path $run 'execution_controller_claim.json') -Raw|ConvertFrom-Json -DateKind String
 if($h.status-cne'READY'-or$current.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$current.run_id-cne$Scope.run_id-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.program.scope_sha256-cne$ScopeHash-or$h.program.manifest_sha256-cne$ManifestHash-or$h.representative_command_batch.profile_id-cne$Scope.profile_id-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $run 'execution_handoff.json')).Hash-or$claim.run_id-cne$Scope.run_id-or$claim.handoff_id-cne$h.handoff_id-or-not$claim.controller_attempt_reserved){throw 'BATCH_READY_OR_CLAIM'}
}
function Get-CadBatchARecipeV1($Scope,$Operation,[string]$Root) {
 $path=Join-Path $Root 'reports/cad_multi_window_interface_research/background_operation_reproduction_v8/scope_example.json'
 if((Get-FileHash $path).Hash-cne'FB01EE6D1CE959B50A3E4BD5FCE52492E4B95B981C4C537374A22CBCC188E6A4'){throw 'BATCH_A_RECIPE_CHANGED'}
 $recipe=Get-Content $path -Raw|ConvertFrom-Json -DateKind String
 $recipe.run_id=$Scope.run_id;$recipe.owners=$Scope.owners;$recipe.operations=@($Operation)
 $recipe
}
function Assert-CadBatchProtectedFilesV1($Identity,[string]$Root) {
 Assert-CadMultiOwnerProtectedHashesV1 $Identity
 $prior=Get-Content (Join-Path $Root 'reports/cad_multi_window_interface_research/background_operation_reproduction_v8/scope_example.json') -Raw|ConvertFrom-Json -DateKind String
 $sourceHash=& (Join-Path $Root 'scripts/get_shared_file_sha256_v1.ps1') -Path $prior.source_path
 if($sourceHash-cne$prior.source_sha256){throw 'BATCH_ORIGINAL_SOURCE_CHANGED'}
}
function Read-CadBatchNativeV1($Scope,$Operation,[string]$Root) {
 if($Operation.owner-ceq'A'){
  Read-CadProbeEvidenceV1 $Operation.signal_path (Get-CadBatchARecipeV1 $Scope $Operation $Root) $Operation $Scope.owners[0]
 }else{
  $Scope|Add-Member NoteProperty absolute_run (Join-Path $Root ('runs/'+$Scope.run_id)) -Force
  Read-DimensionStageSignalV1 $Scope $Operation
 }
}
function Get-CadBatchPairOverlapV1($A,$B) {
 # Preserve the old >=100ms policy in its returned object. This new functional
 # batch also reports any strictly positive real intersection, with no hold.
 $raw=Measure-CadProbeOverlapV1 $A ([pscustomobject]@{ack_tick=$B.ack.tick;complete_tick=$B.complete.tick})
 [pscustomobject]@{native_intersection_ms=$raw.overlap_ms;positive_native_intersection=($raw.overlap_ms-gt0);legacy_100ms_proof=$raw.overlap_proven;artificial_hold_ms=0;clock=$raw.clock}
}
