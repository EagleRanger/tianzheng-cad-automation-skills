# Import the frozen reader expressions/parsers before the verified AB identity
# contracts; single-owner aliases are not used as AB admission authority.
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/background_operation_reproduction_v7/native_read_contract_v7.ps1')
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/command_probe_v4/probe_contract_v4.ps1')
function Get-CadABNativeReadCapsV8 {
 [pscustomobject][ordered]@{serial_executor_required=$true;original_global_guard_unchanged=$true;native_ack_complete_required=$true;background_at_send_required=$true;conditional_load_only_if_unregistered=$true;exact_current_module_prompt_only=$true;owner_max_count=2;prepare_send_max_per_owner=1;business_read_send_max_per_owner=1;plugin_load_max_per_owner=1;exact_module_always_load_max_per_owner=1;helper_max_count=2;helper_timeout_seconds=15;drain_timeout_seconds=3;job_memory_limit_bytes=536870912;job_active_process_limit=1;foreground_sampling_ms=20;foreground_activation_allowed=$false;focus_allowed=$false;keyboard_allowed=$false;database_write_allowed=$false;launch_allowed=$false;save_close_kill_cad_allowed=$false;retry_allowed=$false;fallback_allowed=$false;global_security_setting_changes_allowed=$false;concurrency_allowed=$true;fixed_recipe='V285_CXANNOTATIONCONTROLREADV1'}
}
function Get-CadNativeOperationLensV8($Scope,$Operation) {
 $lens=$Scope|ConvertTo-Json -Depth 24|ConvertFrom-Json -DateKind String
 $lens.operations=@($Operation)
 foreach($name in @('native_report','stage_signal_path','load_context_path')){$lens|Add-Member NoteProperty $name $Operation.$name -Force}
 $lens
}
function Assert-CadBackgroundNativeReadScopeV8($Scope,[string]$Root,[string]$RunDirectory) {
 if($Scope.schema_version-ne1-or$Scope.implementation_version-ne8-or$Scope.profile_id-cne'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1'-or$Scope.intent-cne'ReadVerifiedNativePropertiesAndGrips'-or$Scope.phase-cne'AB_BACKGROUND_NATIVE_READ'-or$Scope.lookup_intent-cne'KnownAHeldApplicationAndBFileDocumentNativeRead'-or$Scope.operation_stage-cne'SERIAL_ENSURE_FIXED_READER_THEN_READ_FIXED_V285_AB'-or(@($Scope.workflow_steps)-join',')-cne'SERIAL_ENSURE_FIXED_READER,READ_FIXED_V285_AB_ONLY'){throw 'NATIVE8_SCOPE_IDENTITY'}
 if(($Scope.capability_bounds|ConvertTo-Json -Depth 8 -Compress)-cne((Get-CadABNativeReadCapsV8)|ConvertTo-Json -Depth 8 -Compress)){throw 'NATIVE8_CAPS'}
 $run=Assert-CadPreparationPathV1 $RunDirectory $Root
 if($Scope.run_id-cne'20261028_ab_native_annotation_read_81'-or$run-ine(Join-Path $Root ('runs/'+$Scope.run_id))-or$Scope.timeout_seconds-ne15-or$Scope.sample_interval_ms-ne20-or(@($Scope.sequence)-join',')-cne'A,B'){throw 'NATIVE8_RUN_OR_BUDGET'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
 $prior=Assert-CadProbeProofFileV3 $Root $Scope.prior_AB_return_path $Scope.prior_AB_return_sha256 'runs/20261028_ab_hybrid_document_overlap_80/execution_return.json' '6F5D3379620C71C99B64337BBA37261F968FD16AE6B79894CED9578E87A17E66'
 $priorScope=Assert-CadProbeProofFileV3 $Root $Scope.prior_AB_scope_path $Scope.prior_AB_scope_sha256 'reports/cad_multi_window_interface_research/command_probe_v4/scope_overlap.json' '1710ACE349329A3A8FF1F8D1E094FC902379F25B74B9391D2E2A1FE822FB9A83'
 $pc=Assert-CadProbeProofFileV3 $Root $Scope.prior_AB_controller_path $Scope.prior_AB_controller_sha256 'runs/20261028_ab_hybrid_document_overlap_80/controller_receipt.json' '71C9815D05B631E791CB2CD35D94B4D5CA0B893FFC24D1C15BD592AB8CCFEF94'
 if(-not$prior.execution_control_released-or$pc.status-cne'PASS_OVERLAPPING_NONDB_PROBE'-or$prior.controller_report_sha256-cne$Scope.prior_AB_controller_sha256-or($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($priorScope.owners|ConvertTo-Json -Depth 8 -Compress)-or$Scope.source_path-cne$priorScope.source_path-or$Scope.source_sha256-cne$priorScope.source_sha256){throw 'NATIVE8_PRIOR_OWNER_OR_PASS'}
 if($Scope.recipe_id-cne'V285_CXANNOTATIONCONTROLREADV1'-or$Scope.module_path-cne'reports/cad_annotation_read_interface_research/candidates/CodexAnnotationControlReadV1.dll'-or$Scope.module_sha256-cne'249C5FF7B349D5F830B6E5EA30C021DB3C715A1668F097A22C5F839417F12C8B'-or(Get-FileHash (Join-Path $Root $Scope.module_path)).Hash-cne$Scope.module_sha256-or$Scope.recipe_success_return-cne'runs/20261005_annotation_control_read_v285/execution_return.json'-or$Scope.recipe_success_sha256-cne'12CCB45EFED9B853EBC564668F95340402EA3754D91888905FA7E857B5EBC912'-or(Get-FileHash (Join-Path $Root $Scope.recipe_success_return)).Hash-cne$Scope.recipe_success_sha256){throw 'NATIVE8_FIXED_RECIPE'}
 $preps=@($Scope.preparation_operations);$reads=@($Scope.operations)
 if(($preps.id-join',')-cne'A9,B9'-or($reads.id-join',')-cne'A1,B1'-or($preps.owner-join',')-cne'A,B'-or($reads.owner-join',')-cne'A,B'){throw 'NATIVE8_OPERATION_PLAN'}
 $nonces=@{}
 foreach($op in @($preps)+@($reads)){
  if($op.nonce-cnotmatch'^[a-f0-9]{32}$'-or$nonces.ContainsKey($op.nonce)-or$op.duration_ms-ne0-or-not$op.id.StartsWith($op.owner,[StringComparison]::Ordinal)){throw 'NATIVE8_OPERATION_NONCE'};$nonces[$op.nonce]=$true
  $kind=if($op.id-in@('A9','B9')){'PREPARE'}else{'READ'}
  if($op.kind-cne$kind){throw 'NATIVE8_OPERATION_KIND'}
  foreach($p in @(@('signal_path',('signals/'+$op.id+'.log')),@('stage_signal_path',('signals/'+$op.id+'_phase.log')),@('load_context_path',('signals/'+$op.id+'_context.log')),@('registration_path',('reports/'+$(if($kind-ceq'PREPARE'){'module_registration_'}else{'reader_availability_'})+$op.id+'.log')),@('native_report',('reports/annotation_control_read_'+$op.id+'.tsv')))){if((Assert-CadPreparationPathV1 $op.($p[0]) $Root)-ine(Join-Path $run $p[1])){throw 'NATIVE8_OPERATION_OUTPUT_PATH'}}
 }
 foreach($p in $Scope.PSObject.Properties){if($p.Name-match'(?i)^(command_text|payload|expression|allow_|fixture|offline_)'){throw 'NATIVE8_EXTRA_EFFECT_FIELD'}}
 Assert-CadMultiOwnerProtectedHashesV1 $identity
 if((Get-FileHash $Scope.source_path).Hash-cne$Scope.source_sha256){throw 'NATIVE8_SOURCE_CHANGED'}
 [pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;operations=$reads;preparations=$preps;worker_timeout_seconds=15}
}
function Assert-CadNativeReadDependenciesV8($Root) {
 $m=Read-CadPreparationScopeV1 (Join-Path $PSScriptRoot 'candidate_manifest.json')
 if($m.id-cne'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1'-or$m.implementation_version-ne8){throw 'NATIVE8_MANIFEST'}
 foreach($f in $m.files){if((Get-FileHash (Join-Path $Root $f.path)).Hash-cne$f.sha256){throw ('NATIVE8_DEPENDENCY:'+ $f.path)}}
}
function Assert-CadNativeReadReadyClaimV8($Scope,$Root,$ScopeHash) {
 $rp=Join-Path $Root ('runs/'+$Scope.run_id);$h=Read-CadPreparationScopeV1 (Join-Path $rp 'execution_handoff.json');$c=Read-CadPreparationScopeV1 (Join-Path $rp 'execution_controller_claim.json');$current=Read-CadPreparationScopeV1 (Join-Path $Root 'config/current_execution_handoff.json')
 if($h.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$h.background_native_read.scope_sha256-cne$ScopeHash-or$h.program.scope_sha256-cne$ScopeHash-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$c.run_id-cne$Scope.run_id-or$c.handoff_id-cne$h.handoff_id-or-not$c.controller_attempt_reserved-or$current.status-cne'READY'-or$current.run_id-cne$Scope.run_id-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $rp 'execution_handoff.json')).Hash){throw 'NATIVE8_READY_CLAIM'}
}
# Prompt adapter uses the same real two-owner contract and then selects its
# explicitly bound preparation operation; old single-owner defaults stay frozen.
function Assert-CadSingleBackgroundDependenciesV1($Root){Assert-CadNativeReadDependenciesV8 $Root}
