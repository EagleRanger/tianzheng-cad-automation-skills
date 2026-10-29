. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/single_background_input_v3/base_contract_v1.ps1')
function Get-CadBBackgroundOverlayV3 {
 [pscustomobject][ordered]@{owner_max_count=2;target_owner_id='B';lookup_intent='ReadExistingBFileDocumentAndSendFixedBackgroundRead';file_moniker_create_max=1;is_running_max=1;get_object_max=1;get_object_only_after_raw_s_ok=$true;enum_running_allowed=$false;moniker_binding_activation_allowed=$false;custom_key_lookup_allowed=$false;A_business_read_or_send_allowed=$false;existing_owner_set_exact_required=$true;prior_B_read_pass_required=$true;strict_binding_max_count=3;hold_acquired_document_until_worker_exit=$true}
}
function Get-CadBBackgroundCapsV3 {
 $caps=Get-CadSingleBackgroundCapsV1
 foreach($p in (Get-CadBBackgroundOverlayV3).PSObject.Properties){$caps|Add-Member NoteProperty $p.Name $p.Value -Force}
 $caps
}
function Assert-CadSingleBackgroundScopeV3($Scope,[string]$Root,[string]$RunDirectory){
 if($Scope.schema_version-ne1-or$Scope.candidate_version-ne3-or$Scope.implementation_version-ne3-or$Scope.profile_id-cne'CAD-SINGLE-BACKGROUND-INPUT-V1'-or$Scope.intent-cne'ExecuteSingleBackgroundReadProbe'-or$Scope.phase-cne'SINGLE_BACKGROUND_READ_ONLY'-or$Scope.lookup_intent-cne'ReadExistingBFileDocumentAndSendFixedBackgroundRead'-or$Scope.run_id-cne'20261028_b_direct_document_background_probe_76'){throw 'B_BACKGROUND_SCOPE_IDENTITY'}
 if(($Scope.capability_bounds|ConvertTo-Json -Depth 8 -Compress)-cne((Get-CadBBackgroundCapsV3)|ConvertTo-Json -Depth 8 -Compress)){throw 'B_BACKGROUND_CAPABILITY_DRIFT'}
 if((@($Scope.owners.id)-join',')-cne'A,B'-or(@($Scope.sequence)-join',')-cne'B'-or$Scope.lookup_target_path-cne$Scope.owners[1].document_full_path){throw 'B_BACKGROUND_OWNER_PLAN'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root;$identity.sequence=@('B')
 $owner=$identity.by_id['B'];$run=Assert-CadPreparationPathV1 $RunDirectory $Root
 if($run-ine(Join-Path $Root ('runs/'+$Scope.run_id))-or$owner.window_handle-gt[uint32]::MaxValue){throw 'B_BACKGROUND_RUN_OR_HWND_BOUND'}
 $rp=Assert-CadPreparationPathV1 $Scope.prior_B_read.return_path $Root;$sp=Assert-CadPreparationPathV1 $Scope.prior_B_read.scope_path $Root
 if($rp-ine(Join-Path $Root 'runs/20261028_b_native_document_read_75/execution_return.json')-or$Scope.prior_B_read.return_sha256-cne'7A438C8A59EBB6BD9674973C038A70F86FA16E64DCA6F9C4D34578AA8EDB48D5'-or(Get-FileHash $rp).Hash-cne$Scope.prior_B_read.return_sha256-or$sp-ine(Join-Path $Root 'reports/cad_multi_window_interface_research/read_session_v8/scope_example.json')-or$Scope.prior_B_read.scope_sha256-cne'C2CBE172733A9902B3F97F2A14105F71B48D1285488E1100931F4229792E34C5'-or(Get-FileHash $sp).Hash-cne$Scope.prior_B_read.scope_sha256){throw 'B_BACKGROUND_PRIOR_BINDING'}

 foreach($pair in @(@('controller','runs/20261028_b_native_document_read_75/controller_receipt.json','5E64F4359B6A9E2ECCE18BF7B907015BA0DDE8D0DC25D64155053A99AEB9AB93'),@('worker','runs/20261028_b_native_document_read_75/read_session_worker_receipt.json','3C6B13CBF988A71939F629210CC5BDD18AD700434EE30F1BE36B6582E50851CC'))){
  $path=Assert-CadPreparationPathV1 $Scope.prior_B_read.($pair[0]+'_path') $Root
  if($path-ine(Join-Path $Root $pair[1])-or$Scope.prior_B_read.($pair[0]+'_sha256')-cne$pair[2]-or(Get-FileHash $path).Hash-cne$pair[2]){throw 'B_BACKGROUND_PRIOR_FILE_PROVENANCE'}
 }

 $r=Read-CadPreparationScopeV1 $rp;$s=Read-CadPreparationScopeV1 $sp;$c=$r.controller_report;$w=$c.worker_receipt
 if($r.controller_report_sha256-cne$Scope.prior_B_read.controller_sha256-or$r.controller_report_path-cne'runs/20261028_b_native_document_read_75/controller_receipt.json'){throw 'B_BACKGROUND_PRIOR_CONTROLLER_POINTER'}
 if($r.run_id-cne$s.run_id-or$r.writer.thread_id-cne'RECEIVER_ID_REQUIRED'-or-not$r.execution_control_released-or$c.status-cne'PASS_B_READ_PROBE_ONLY'-or$c.protected_hashes_after-cne'UNCHANGED'-or$c.helper_phase.root_exit_code-ne0-or$c.helper_phase.job_active_after-ne0-or-not$c.helper_phase.output_complete-or$c.helper_phase.reason-or$w.status-cne'PASS_B_READ_PROBE_ONLY'-or@($w.getter_events).Count-ne6-or@($w.binding_events).Count-ne12-or@($w.rows).Count-ne1){throw 'B_BACKGROUND_PRIOR_READ_NOT_PASSED'}
 if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($s.owners|ConvertTo-Json -Depth 8 -Compress)-or$Scope.source_path-cne$s.source_path-or$Scope.source_sha256-cne$s.source_sha256-or$w.rows[0].owner-cne'B'-or$w.rows[0].values.FullName-cne$owner.document_full_path-or$w.rows[0].values.CMDACTIVE-ne0-or$w.rows[0].values.CMDNAMES-cne''-or$w.rows[0].values.DBMOD-ne0){throw 'B_BACKGROUND_PRIOR_OWNER_OR_STATE'}
 if($Scope.timeout_seconds-ne15-or$Scope.sample_interval_ms-ne20-or$Scope.observation_settle_ms-ne200){throw 'B_BACKGROUND_TIME_BOUNDS'}
 $ops=@($Scope.operations)
 if($ops.Count-ne1-or$ops[0].id-cne'B1'-or$ops[0].owner-cne'B'-or$ops[0].nonce-cnotmatch'^[a-f0-9]{32}$'-or$ops[0].duration_ms-ne0-or(Assert-CadPreparationPathV1 $ops[0].signal_path $Root)-ine(Join-Path $run 'signals/B1.log')){throw 'B_BACKGROUND_FIXED_OPERATION'}
 foreach($p in $Scope.PSObject.Properties){if($p.Name-match'(?i)^(command_text|payload|expression|allow_|fixture|offline_)'){throw 'B_BACKGROUND_EXTRA_EFFECT_FIELD'}}
 if(@($Scope.protected_files).Count-ne1-or$Scope.protected_files[0].path-cne$Scope.source_path-or$Scope.protected_files[0].sha256-cne$Scope.source_sha256-or$Scope.old_run72_effect-cne'UNKNOWN_NOT_RECLASSIFIED'-or$Scope.old_text_clear_or_enter_allowed-isnot[bool]-or$Scope.old_text_clear_or_enter_allowed){throw 'B_BACKGROUND_PRESERVATION_BOUNDARY'}
 $v=[pscustomobject]@{run_id=$Scope.run_id;run=$run;identity=$identity;owner=$owner;operation=$ops[0];timeout_seconds=15}
 Assert-CadSingleBackgroundProtectionV1 $Scope $v $Root;$v
}
function Assert-CadSingleBackgroundStageV3($Scope,[string]$Root,[string]$ScopeSha256,[ValidateSet('Candidate','Execute')][string]$Stage){
 $run=Join-Path $Root ('runs/'+$Scope.run_id)
 if($Stage-ceq'Candidate'){if(Test-Path $run){if(@(Get-ChildItem -LiteralPath $run -Force).Count){throw 'B_BACKGROUND_ALREADY_PUBLISHED'}};return}
 $h=Read-CadPreparationScopeV1 (Join-Path $run 'execution_handoff.json');$claim=Read-CadPreparationScopeV1 (Join-Path $run 'execution_controller_claim.json');$current=Read-CadPreparationScopeV1 (Join-Path $Root 'config/current_execution_handoff.json')
 if($h.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.single_background_input.scope_sha256-cne$ScopeSha256-or$h.program.scope_sha256-cne$ScopeSha256-or$claim.run_id-cne$Scope.run_id-or$claim.handoff_id-cne$h.handoff_id-or-not$claim.controller_attempt_reserved-or$current.status-cne'READY'-or$current.run_id-cne$Scope.run_id-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $run 'execution_handoff.json')).Hash){throw 'B_BACKGROUND_CURRENT_READY_CLAIM'}
}
