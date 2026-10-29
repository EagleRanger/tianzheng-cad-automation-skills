# Failed-suffix adapter only; frozen V1/business/transport kernels stay intact.
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/batch_contract.ps1')
function Write-CadBatchJsonAtomicV2([string]$Path,$Data) {
 if(Test-Path -LiteralPath $Path){throw 'BATCH_ATOMIC_DESTINATION_EXISTS'}
 $part=$Path+'.'+[guid]::NewGuid().ToString('N')+'.part'
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Data|ConvertTo-Json -Depth 80))
 $stream=[IO.File]::Open($part,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
 # Same-directory rename publishes only complete bytes; no overwrite or retry.
 [IO.File]::Move($part,$Path)
}
function Read-CadBatchControlV2([string]$Path,[string[]]$RequiredFields) {
 if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
 try{
  $info=Get-Item -LiteralPath $Path;if($info.Length-le0-or$info.Length-gt8192){return $null}
  $value=Read-CadProbeControlFileV1 $Path
  if($null-eq$value-or$value-isnot[pscustomobject]){return $null}
  foreach($name in $RequiredFields){if($null-eq$value.PSObject.Properties[$name]){return $null}}
  $value
 }catch{return $null}
}
function Assert-CadRepresentativeSuffixPrefixV2([string]$Root) {
 $run=Join-Path $Root 'runs/20261028_ab_representative_command_batch_v4'
 if((Get-FileHash (Join-Path $run 'execution_return.json')).Hash-cne'6DCE7E8E1F60367AF51BD40C9594471AFF07A7EBCAE4F89799ACE746C3C915FF'-or(Get-FileHash (Join-Path $run 'controller_receipt.json')).Hash-cne'AFB1F859A208E4335A2666BEBF606D593434BF95889637F6830D4416C4D20CB6'){throw 'SUFFIX_PREFIX_RETURN_CHANGED'}
 $formal=Get-Content (Join-Path $run 'execution_return.json') -Raw|ConvertFrom-Json -DateKind String
 $controller=Get-Content (Join-Path $run 'controller_receipt.json') -Raw|ConvertFrom-Json -DateKind String
 $prior=Get-Content (Join-Path $run 'scope.json') -Raw|ConvertFrom-Json -DateKind String
 if(-not$formal.execution_control_released-or$controller.function_pass_count-ne2-or$controller.cleanup_errors.Count-or$controller.pairs.Count-ne7-or$controller.pairs[0].status-cnotlike'PASS_FUNCTION*'-or$controller.pairs[1].status-cnotlike'PASS_FUNCTION*'){throw 'SUFFIX_PREFIX_NOT_SETTLED'}
 foreach($owner in @('A','B')){
  $id=$owner+'03';$w=Get-Content (Join-Path $run ('worker_'+$id+'.json')) -Raw|ConvertFrom-Json -DateKind String
  if($w.status-cne'BLOCKED_BEFORE_SEND'-or$w.post_call_count-ne0-or$w.send_call_returned-or$w.operation_id-cne$id-or$w.run_id-cne$prior.run_id-or(Test-Path (Join-Path $run ('release_'+$id+'.json')))-or(Test-Path (Join-Path $run ('send_reservation_'+$id+'.json')))-or(Test-Path (Join-Path $run ('exact_b_send_'+$id+'.json')))){throw 'SUFFIX_FAILED_PAIR_NOT_PROVEN_UNSENT'}
 }
 $mapping=Get-Content (Join-Path $run 'reports/mapping_audit.json') -Raw|ConvertFrom-Json -DateKind String
 $map=@(Import-Csv (Join-Path $run 'reports/typed_source_mapping.tsv') -Delimiter ([char]9))
 if($mapping.status-cne'PASS'-or$mapping.unique_native_handle_count-ne2-or$map.Count-ne2-or(@($map.SEGMENT_TYPE|Sort-Object)-join',')-cne'ARC,LINE'-or@($map|Where-Object STATUS -CNE PASS).Count){throw 'SUFFIX_GENERATED_PAIR_MAPPING_UNPROVEN'}
 $a=Get-Content (Join-Path $run 'worker_A02.json') -Raw|ConvertFrom-Json -DateKind String
 $b=Get-Content (Join-Path $run 'worker_B02.json') -Raw|ConvertFrom-Json -DateKind String
 if($a.status-cne'PASS'-or$b.status-cne'PASS'-or$b.after.model_count-$b.before.model_count-ne2){throw 'SUFFIX_GENERATION_EFFECT_UNPROVEN'}
 [pscustomobject]@{run=$run;scope=$prior;A_model_count=$a.after.model_count;B_model_count=$b.after.model_count;frozen_new_handles=@($map.NATIVE_HANDLE|Sort-Object);accepted_pairs=2;accepted_sends=4;accepted_positive_intersections=1;accepted_overlap_ms=16}
}
function Get-CadSuffixDataLeavesV2 {
 @('model_before.tsv','grips_before.tsv','grips_generated.tsv','source_geometry_before.tsv','source_geometry_before_summary.tsv','selected_geometry.tsv','selected_source_full_geometry.tsv','selection_ledger.tsv','typed_source_mapping.tsv','new_native_handles.txt','generation_summary.tsv','generation_details.tsv','generation_details_utf8.tsv','mapping_audit.json','selection_receipt.json')
}
function Assert-CadRepresentativeCommandBatchScopeV2($Scope,[string]$Root) {
 if($Scope.schema_version-ne1-or$Scope.implementation_version-ne2-or$Scope.profile_id-cne'CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1'-or$Scope.route-cne'shared_annotation_interface_read'-or$Scope.intent-cne'ExecuteRepresentativeNativeCommandPairs'-or$Scope.phase-cne'AB_REPRESENTATIVE_COMMAND_BATCH'-or$Scope.resume_from_pair-ne3-or$Scope.resume_through_pair-ne7-or$Scope.resume_source_run_id-cne'20261028_ab_representative_command_batch_v4'){throw 'SUFFIX_SCOPE_IDENTITY'}
 if($Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'-or$scope.run_id-ceq$Scope.resume_source_run_id){throw 'SUFFIX_NEW_RUN_REQUIRED'}
 if(($Scope.capability_bounds|ConvertTo-Json -Compress)-cne((Get-CadRepresentativeBatchCapsV1)|ConvertTo-Json -Compress)){throw 'SUFFIX_CAPS_EXPANSION'}
 $prefix=Assert-CadRepresentativeSuffixPrefixV2 $Root
 if(($Scope.owners|ConvertTo-Json -Depth 10 -Compress)-cne($prefix.scope.owners|ConvertTo-Json -Depth 10 -Compress)-or$Scope.resume_baseline_A_model_count-ne$prefix.A_model_count-or$Scope.resume_baseline_B_model_count-ne$prefix.B_model_count-or(@($Scope.frozen_new_handles|Sort-Object)-join',')-cne($prefix.frozen_new_handles-join',')){throw 'SUFFIX_OWNER_OR_OBJECT_BASELINE_CHANGED'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
 $run=Resolve-CadExactBProjectPathV1 $Root ('runs/'+$Scope.run_id);$ops=@($Scope.operations)
 $leaves=@(Get-CadSuffixDataLeavesV2)
 if(@($Scope.resume_copied_files).Count-ne$leaves.Count){throw 'SUFFIX_COPY_SET'}
 foreach($leaf in $leaves){
  $copy=@($Scope.resume_copied_files|Where-Object leaf -CEQ $leaf)
  if($copy.Count-ne1){throw 'SUFFIX_COPY_SET'};$copy=$copy[0]
  $from=Join-Path $prefix.run ('reports/'+$leaf);$to=Join-Path $run ('reports/'+$leaf)
  if($copy.source_path-ine$from-or$copy.copy_path-ine$to-or$copy.sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash $from).Hash-cne$copy.sha256-or(Get-FileHash $to).Hash-cne$copy.sha256){throw 'SUFFIX_COPIED_BASELINE_CHANGED'}
 }
 if($ops.Count-ne10){throw 'SUFFIX_EXACT_TEN_OPERATIONS'};$nonces=@{}
 foreach($plan in @(Get-CadRepresentativeBatchPlanV1|Where-Object pair -GE 3)){
  foreach($owner in @('A','B')){
   $id=$owner+('{0:00}'-f$plan.pair);$found=@($ops|Where-Object id -CEQ $id)
   if($found.Count-ne1){throw 'SUFFIX_OPERATION_SET'};$op=$found[0]
   if($op.owner-cne$owner-or$op.pair-ne$plan.pair-or$op.nonce-cnotmatch'^[a-f0-9]{32}$'-or$nonces.ContainsKey($op.nonce)){throw 'SUFFIX_OWNER_OR_NONCE'};$nonces[$op.nonce]=$true
   if($op.signal_path-ine(Join-Path $run ('signals/'+$id+'.log'))){throw 'SUFFIX_OUTPUT_PATH'}
   if($owner-ceq'A'){
    if($op.kind-cne'READ'-or$op.duration_ms-ne0-or$op.action-cne'V285_CXANNOTATIONCONTROLREADV1'){throw 'SUFFIX_A_READ_ONLY'}
    foreach($entry in @(@('native_report',('reports/annotation_control_read_'+$id+'.tsv')),@('stage_signal_path',('signals/'+$id+'_phase.log')),@('load_context_path',('signals/'+$id+'_context.log')),@('registration_path',('reports/reader_availability_'+$id+'.log')))){if($op.($entry[0])-ine(Join-Path $run $entry[1])){throw 'SUFFIX_OUTPUT_PATH'}}
   }elseif($op.stage-cne$plan.stage-or$op.action-cne$plan.action-or$op.expected_model_delta-ne0-or$op.bundle_path-cne'reference/project-orchestration/reports/dimension_background_reproduction_v7/native_stages.lsp'-or$op.bundle_sha256-cne'543BF0BC999ADA031DE2F96FBCE22E28E6808501F88ED240647A45A52FFDDA18'){throw 'SUFFIX_B_FIXED_STAGE'}
  }
 }
 foreach($name in @($Scope.PSObject.Properties.Name)){if($name-match'(?i)payload|command_text|expression|allow_'){throw 'SUFFIX_EXTRA_EFFECT_FIELD'}}
 [pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;operations=$ops;accepted_prefix=$prefix}
}
function Assert-CadRepresentativeBatchManifestV2($Manifest,[string]$Root) {
 Assert-CadRepresentativeBatchManifestV1 $Manifest $Root
 $paths=@($Manifest.files.path)
 foreach($leaf in @('batch_contract.ps1','command_worker_v1.ps1','invoke_batch.ps1','process_batch.py')){if(('reports/cad_multi_window_interface_research/representative_command_batch_v2/'+$leaf)-cnotin$paths){throw 'SUFFIX_REQUIRED_CODE_UNBOUND'}}
}
function Assert-CadRepresentativeBatchAdmissionV2([string]$Root) {
 # Same original profile and maximum caps, not a new write/command authority.
 Assert-CadRepresentativeBatchAdmissionV1 $Root
 $p=(Get-Content (Join-Path $Root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String).routes.shared_annotation_interface_read.optional_command_profiles.'CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1'
 if(2-notin@($p.admitted_implementation_versions)-or$p.candidate_contract_abi_v2-cne'Assert-CadRepresentativeCommandBatchScopeV2($Scope,$Root)'-or$p.suffix_v2.first_pair-ne3-or$p.suffix_v2.last_pair-ne7-or$p.suffix_v2.send_max_count-ne10-or$p.suffix_v2.prefix_replay_allowed){throw 'SUFFIX_SHARED_ADMISSION_MISMATCH'}
}
function Assert-CadRepresentativeBatchDraftV2($Draft,$Scope,[string]$Root) {
 $controller='reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v2/invoke_batch.ps1'
 $expected=$controller+" -ReadyHandoffPath '"+(Join-Path $Root 'config/current_execution_handoff.json')+"'"
 if($Draft.governance.workflow_id-cne$Scope.profile_id-or$Draft.action.controller_template-cne$expected-or$Draft.action.send_max_count-ne10-or$Draft.acceptance.send_max_count-ne10-or$Draft.acceptance.A_read_max_count-ne5-or$Draft.acceptance.B_stage_max_count-ne5-or$Draft.acceptance.aesthetic_gate-or(@($Draft.acceptance.allowed_commanded_grips)-join',')-cne'0,1'-or$Draft.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$Draft.target.thread_id-cne'RECEIVER_ID_REQUIRED'){throw 'SUFFIX_DRAFT_MISMATCH'}
 if($Draft.execution_envelope.sha256-cne(Get-FileHash (Join-Path $Root $Draft.execution_envelope.entry)).Hash){throw 'SUFFIX_ENVELOPE_CHANGED'}
}
function Assert-CadRepresentativeBatchReadyV2($Scope,[string]$Root,[string]$ScopeHash,[string]$ManifestHash) {
 Assert-CadRepresentativeBatchAdmissionV2 $Root
 $run=Join-Path $Root ('runs/'+$Scope.run_id)
 $h=Get-Content (Join-Path $run 'execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
 $current=Get-Content (Join-Path $Root 'config/current_execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
 $claim=Get-Content (Join-Path $run 'execution_controller_claim.json') -Raw|ConvertFrom-Json -DateKind String
 if($h.status-cne'READY'-or$current.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$current.run_id-cne$Scope.run_id-or$h.representative_command_batch.implementation_version-ne2-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.program.scope_sha256-cne$ScopeHash-or$h.program.manifest_sha256-cne$ManifestHash-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $run 'execution_handoff.json')).Hash-or$claim.run_id-cne$Scope.run_id-or$claim.handoff_id-cne$h.handoff_id-or-not$claim.controller_attempt_reserved){throw 'SUFFIX_READY_OR_CLAIM'}
}
