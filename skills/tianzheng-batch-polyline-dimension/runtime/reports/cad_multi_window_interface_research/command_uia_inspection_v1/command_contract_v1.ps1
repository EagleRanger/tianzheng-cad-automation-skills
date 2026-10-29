. (Join-Path $PSScriptRoot 'native_anchor_v1.ps1')
. (Join-Path $PSScriptRoot '../lifecycle_v1/preparation_contract_v1.ps1')
. (Join-Path $PSScriptRoot '../v3/cad_multi_owner_preflight_contract_v3.ps1')
function Get-CadCommandUiaInspectionCapsV1 {
 '{"serial_executor_required":true,"original_global_guard_unchanged":true,"existing_owners_only":true,"owner_max_count":2,"target_owner_id":"B","helper_max_count":1,"worker_apartment":"MTA","soft_timeout_seconds":2,"worker_timeout_seconds":15,"drain_timeout_seconds":3,"outer_timeout_seconds_max":30,"stream_max_chars":32768,"tree_max_controls":32,"tree_max_depth":8,"text_max_chars_per_control":4096,"total_text_max_chars":16384,"stage_max_bytes":1048576,"job_memory_limit_bytes":536870912,"job_active_process_limit":1,"job_before_uia_required":true,"job_contains_cad":false,"job_bounds_external_provider":false,"fresh_native_chain_required":true,"uia_from_handle_max":1,"uia_raw_view_subtree_only":true,"uia_read_only_patterns":true,"uia_transport_com_only":true,"uia_allowed":true,"cad_com_allowed":false,"nativeom_allowed":false,"rot_allowed":false,"desktop_scan_allowed":false,"find_all_allowed":false,"events_allowed":false,"password_text_allowed":false,"native_idle_verified":false,"send_authorized":false,"activate_allowed":false,"focus_change_allowed":false,"input_allowed":false,"command_allowed":false,"load_allowed":false,"launch_allowed":false,"save_allowed":false,"close_allowed":false,"kill_cad_allowed":false,"register_allowed":false,"retry_allowed":false,"global_configuration_change_allowed":false}' | ConvertFrom-Json
}
function Assert-CadCommandUiaInspectionScopeV1($Scope,[string]$Root){
 if($Scope.schema_version-ne1-or$Scope.candidate_version-ne1-or$Scope.profile_id-cne'CAD-EXACT-B-COMMAND-UIA-READ-V1'-or$Scope.intent-cne'InspectExistingBCommandUia'-or$Scope.phase-cne'INSPECT_EXISTING_B_COMMAND_UIA_ONLY'-or$Scope.run_id-cne'20261013_multi_owner_b_command_uia_inspection_31'-or(@($Scope.sequence)-join',')-cne'B'){throw 'INSPECTION_SCOPE_IDENTITY'}
 $caps=Get-CadCommandUiaInspectionCapsV1
 if(@($Scope.capability_bounds.PSObject.Properties).Count-ne@($caps.PSObject.Properties).Count){throw 'INSPECTION_CAPABILITY_EXTRA'}
 foreach($p in $caps.PSObject.Properties){$a=$Scope.capability_bounds.PSObject.Properties[$p.Name];if($null-eq$a-or$a.Value.GetType()-ne$p.Value.GetType()-or($a.Value|ConvertTo-Json -Compress)-cne($p.Value|ConvertTo-Json -Compress)){throw ('INSPECTION_CAPABILITY:'+ $p.Name)}}
 foreach($p in $Scope.PSObject.Properties){if($p.Name-like'allow_*'){throw 'INSPECTION_UNKNOWN_RIGHT'}}
 $prior=Assert-CadPreparationPathV1 $Scope.prior_return_path $Root
 if($prior-ine(Join-Path $Root 'runs/20261013_multi_owner_b_foreign_branch_inspection_30/execution_return.json')-or$Scope.prior_return_sha256-cne'AD2297D3BE18DE5A84FE0BF59BE17BB1CC6A3EE7D7EFE66DB22C92B9C1B084CA'-or(Get-FileHash $prior).Hash-cne$Scope.prior_return_sha256){throw 'INSPECTION_PRIOR_RETURN'}
 $priorScope=Assert-CadPreparationPathV1 $Scope.prior_scope_path $Root
 if($priorScope-ine(Join-Path $Root 'reports/cad_multi_window_interface_research/input_inspection_v6/scope_example.json')-or$Scope.prior_scope_sha256-cne'4C5A5176CA2DDB61A752628192199FA0B5731708A453032813CB3AE8BF6BAB1A'-or(Get-FileHash $priorScope).Hash-cne$Scope.prior_scope_sha256){throw 'INSPECTION_PRIOR_SCOPE'}
 $previous=Read-CadPreparationScopeV1 $priorScope
 if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($previous.owners|ConvertTo-Json -Depth 8 -Compress)-or$Scope.source_path-cne$previous.source_path-or$Scope.source_sha256-cne$previous.source_sha256){throw 'INSPECTION_OWNER_PROVENANCE'}

 $anchorPath=Assert-CadPreparationPathV1 $Scope.anchor_evidence_path $Root
 if($anchorPath-ine(Join-Path $Root 'runs/20261013_multi_owner_b_foreign_branch_inspection_30/input_inspection_raw.jsonl')-or$Scope.anchor_evidence_sha256-cne'B631E550C0B850846BA1DC4EECEE83658FAC94B88BEDC5465459E584CAED6A3D'-or(Get-Item $anchorPath).Length-gt1048576-or(Get-FileHash $anchorPath).Hash-cne$Scope.anchor_evidence_sha256){throw 'UIA_ANCHOR_EVIDENCE_HASH'}
 $anchorRows=@(Get-Content -LiteralPath $anchorPath|ForEach-Object {$_|ConvertFrom-Json -DateKind String})
 $anchor=Get-CadCommandNativeAnchorV1 $anchorRows $Scope.owners[1] $Scope.anchor_evidence_sha256
 if(($anchor|ConvertTo-Json -Depth 12 -Compress)-cne($Scope.native_anchor|ConvertTo-Json -Depth 12 -Compress)){throw 'UIA_ANCHOR_EVIDENCE_MISMATCH'}
 # The frozen validator is reused only for identity metadata, never its getters.
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
 $identity.sequence=@('B')
 $run=Assert-CadPreparationPathV1 (Join-Path $Root ('runs/'+$Scope.run_id)) $Root
 $source=Assert-CadPreparationPathV1 $Scope.source_path $Root
 $v=[pscustomobject]@{run=$run;source=$source;identity=$identity;owners=$identity.owners}
 Assert-CadCommandUiaInspectionProtectionV1 $Scope $v $Root
 $v
}
function Assert-CadCommandUiaInspectionProtectionV1($Scope,$Validated,[string]$Root){
 foreach($owner in $Validated.owners){$null=Assert-CadPreparationPathV1 $owner.document_full_path $Root}
 Assert-CadMultiOwnerProtectedHashesV1 $Validated.identity
 if((& (Join-Path $Root 'scripts/get_shared_file_sha256_v1.ps1') -Path $Validated.source)-cne$Scope.source_sha256){throw 'INSPECTION_SOURCE_HASH'}
}
function Assert-CadCommandUiaInspectionDependenciesV1([string]$Root){
 $m=Read-CadPreparationScopeV1 (Join-Path $PSScriptRoot 'candidate_manifest.json')
 if($m.id-cne'CAD-EXACT-B-COMMAND-UIA-READ-V1'-or$m.intent-cne'InspectExistingBCommandUia'-or$m.implementation_version-ne1-or$m.status-cne'SEALED_PRIVATE_VALIDATION_ONLY'){throw 'INSPECTION_MANIFEST'}
 foreach($f in $m.files){$p=Assert-CadPreparationPathV1 (Join-Path $Root $f.path) $Root;if((Get-FileHash $p).Hash-cne$f.sha256){throw ('INSPECTION_DEPENDENCY:'+ $f.path)}}
}
function Assert-CadCommandUiaInspectionStageV1($Scope,[string]$Root,[string]$ScopeSha256,[ValidateSet('Candidate','Ready','Execute')][string]$Stage){
 $run=Join-Path $Root ('runs/'+$Scope.run_id);$entries=@()
 if(Test-Path -LiteralPath $run){$entries=@(Get-ChildItem -LiteralPath $run -Force)}
 if(@($entries|Where-Object {$_.PSIsContainer-or($_.Attributes-band[IO.FileAttributes]::ReparsePoint)-or$_.Name-cnotin@('execution_handoff.json','execution_controller_claim.json')}).Count){throw 'INSPECTION_OLD_OR_UNKNOWN_RUN_ENTRY'}
 if($Stage-ceq'Candidate'){if($entries.Count){throw 'INSPECTION_ALREADY_PUBLISHED'};return}
 $h=Read-CadPreparationScopeV1 (Join-Path $run 'execution_handoff.json')
 $manifestSha=(Get-FileHash (Join-Path $PSScriptRoot 'candidate_manifest.json')).Hash
 if($h.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$h.loop_id-cne'auto-CAD-project-loop'-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.command_routing.route_id-cne'shared_annotation_interface_read'){throw 'INSPECTION_READY_IDENTITY'}
 $p=$h.existing_b_command_uia_read
 if($p.profile_id-cne$Scope.profile_id-or$p.intent-cne$Scope.intent-or$p.scope_sha256-cne$ScopeSha256-or$p.manifest_sha256-cne$manifestSha-or$h.program.scope_sha256-cne$ScopeSha256-or$h.program.manifest_sha256-cne$manifestSha-or$h.governance.workflow_id-cne$Scope.profile_id){throw 'INSPECTION_READY_BINDING'}
 if($Stage-ceq'Execute'){
  $claim=Read-CadPreparationScopeV1 (Join-Path $run 'execution_controller_claim.json')
  if($claim.run_id-cne$Scope.run_id-or$claim.handoff_id-cne$h.handoff_id-or$claim.controller_attempt_reserved-isnot[bool]-or-not$claim.controller_attempt_reserved-or[string]::IsNullOrWhiteSpace($claim.started_at)){throw 'INSPECTION_ENVELOPE_CLAIM'}
  $current=Read-CadPreparationScopeV1 (Join-Path $Root 'config/current_execution_handoff.json')
  if($current.status-cne'READY'-or$current.run_id-cne$Scope.run_id-or$current.immutable_handoff_path-cne('runs/'+$Scope.run_id+'/execution_handoff.json')-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $run 'execution_handoff.json')).Hash){throw 'INSPECTION_NOT_CURRENT_READY'}
 }
}
function Assert-CadCommandUiaExternalRuntimeV1 {
 $fingerprints=Read-CadPreparationScopeV1 (Join-Path $PSScriptRoot 'external_runtime_fingerprints.json')
 foreach($f in $fingerprints.files){if((Get-FileHash -LiteralPath $f.path).Hash-cne$f.sha256){throw ('UIA_RUNTIME_CHANGED:'+ $f.path)}}
}
