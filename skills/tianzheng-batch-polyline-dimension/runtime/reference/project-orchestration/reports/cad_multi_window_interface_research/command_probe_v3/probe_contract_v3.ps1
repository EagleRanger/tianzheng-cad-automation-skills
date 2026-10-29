. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/single_background_input_v3/background_contract_v3.ps1')

function Assert-CadProbeProofFileV3($Root,$Path,$Hash,$ExpectedRelative,$ExpectedHash) {
 $p=Assert-CadPreparationPathV1 $Path $Root
 if($p-ine(Join-Path $Root $ExpectedRelative)-or$Hash-cne$ExpectedHash-or(Get-FileHash -LiteralPath $p).Hash-cne$Hash){throw 'PROBE_V3_PREDECESSOR_PATH_OR_HASH'}
 Read-CadPreparationScopeV1 $p
}
function Assert-CadProbeScopeV3($Scope,[string]$Root,[string]$RunDirectory,[switch]$AllowStartedSiblingSignals) {
 if($Scope.schema_version-ne1-or$Scope.candidate_version-ne3-or$Scope.profile_id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'-or$Scope.intent-cne'ExecuteNonDbProbe'-or$Scope.lookup_intent-cne'ExactFileDocumentNonDbProbe'-or$Scope.phase-cnotin@('ALTERNATING','OVERLAP')){throw 'PROBE_V3_SCOPE_IDENTITY'}
 $run=Assert-CadPreparationPathV1 $RunDirectory $Root
 if($Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'-or$run-ine(Join-Path $Root ('runs/'+$Scope.run_id))){throw 'PROBE_V3_RUN_PATH'}
 if($Scope.worker_timeout_seconds-ne15-or$Scope.sample_interval_ms-ne20-or(@($Scope.owners.id)-join',')-cne'A,B'){throw 'PROBE_V3_BOUNDS'}
 $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
 $base=Assert-CadProbeProofFileV3 $Root $Scope.prior_B_background_scope_path $Scope.prior_B_background_scope_sha256 'reports/cad_multi_window_interface_research/single_background_input_v3/scope_example.json' '725E1CCFBCDEA6112D76834F4F2068CEBDF446343F33501D62110F2BB631F180'
 $null=Assert-CadSingleBackgroundScopeV3 $base $Root (Join-Path $Root ('runs/'+$base.run_id))
 if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($base.owners|ConvertTo-Json -Depth 8 -Compress)-or$Scope.source_path-cne$base.source_path-or$Scope.source_sha256-cne$base.source_sha256){throw 'PROBE_V3_CURRENT_OWNER_SET_CHANGED'}
 $a=Assert-CadProbeProofFileV3 $Root $Scope.prior_A_return_path $Scope.prior_A_return_sha256 'runs/20261023_rich_fixture_monitored_preparation_65/execution_return.json' 'C5ED559BB22074F6F81DC146B32F45A32F9DF90FF908AF36408009D13628D3F5'
 $b=Assert-CadProbeProofFileV3 $Root $Scope.prior_B_background_return_path $Scope.prior_B_background_return_sha256 'runs/20261028_b_direct_document_background_probe_76/execution_return.json' '6C5389E0296BE8CF8ACF961148CB7A0D04950C81224471B69595621A3883F0EC'
 if($a.terminal_state-cne'CONTROLLER_REPORTED_PASS_FRESH_A_ONLY_PREPARED_AND_STRICT_READ__EVIDENCE_REVIEW_REQUIRED'-or$a.controller_report.strict_a.status-cne'PASS_A_ONLY_STRICT_READ'-or-not$a.execution_control_released-or$b.terminal_state-cne'CONTROLLER_REPORTED_PASS_SINGLE_BACKGROUND_INPUT_SAMPLED__EVIDENCE_REVIEW_REQUIRED'-or$b.controller_report.status-cne'PASS_SINGLE_BACKGROUND_INPUT_SAMPLED'-or-not$b.execution_control_released){throw 'PROBE_V3_CURRENT_PREDECESSORS_NOT_PASS'}
 $sa=$a.controller_report.strict_a.strict_state;$oa=$identity.by_id.A
 if($sa.dbmod-ne0-or$sa.full_path-cne$oa.document_full_path-or$sa.hwnd-ne$oa.window_handle){throw 'PROBE_V3_A_NATIVE_IDENTITY'}
 foreach($f in @('process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){if([string]$a.controller_report.fresh_owner_a.$f-cne[string]$oa.$f){throw ('PROBE_V3_A_OWNER:'+ $f)}}
 $ops=@($Scope.operations);$wanted=if($Scope.phase-ceq'ALTERNATING'){'A,B,A'}else{'A,B'}
 if(($ops.owner-join',')-cne$wanted){throw 'PROBE_OPERATION_ORDER'}
 $ids=@{};$nonces=@{}
 foreach($op in $ops){
  if($op.id-cnotmatch'^[AB][1-9][0-9]{0,2}$'-or-not$op.id.StartsWith($op.owner,[StringComparison]::Ordinal)-or$ids.ContainsKey($op.id)-or$op.nonce-cnotmatch'^[a-f0-9]{32}$'-or$nonces.ContainsKey($op.nonce)){throw 'PROBE_OPERATION_ID_NONCE'}
  $ids[$op.id]=$true;$nonces[$op.nonce]=$true
  if(($op.duration_ms-isnot[int]-and$op.duration_ms-isnot[long])-or($Scope.phase-ceq'ALTERNATING'-and$op.duration_ms-ne0)-or($Scope.phase-ceq'OVERLAP'-and($op.duration_ms-lt3000-or$op.duration_ms-gt8000))){throw 'PROBE_DURATION'}
  $p=Assert-CadPreparationPathV1 $op.signal_path $Root
  if($p-ine(Join-Path $run ('signals/'+$op.id+'.log'))-or(-not$AllowStartedSiblingSignals-and(Test-Path -LiteralPath $p))){throw 'PROBE_SIGNAL_PATH_EXISTS_OR_UNSAFE'}
 }
 if($Scope.phase-ceq'OVERLAP'){
  $rp=Assert-CadPreparationPathV1 $Scope.prior_alternating_return_path $Root;$cp=Assert-CadPreparationPathV1 $Scope.prior_alternating_receipt_path $Root
  if($Scope.prior_alternating_return_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash $rp).Hash-cne$Scope.prior_alternating_return_sha256-or$Scope.prior_alternating_receipt_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash $cp).Hash-cne$Scope.prior_alternating_receipt_sha256){throw 'PROBE_PRIOR_ALTERNATING_HASH'}
  $ar=Read-CadPreparationScopeV1 $rp;$ac=Read-CadPreparationScopeV1 $cp
  if($rp-ine(Join-Path $Root ('runs/'+$ar.run_id+'/execution_return.json'))-or$cp-ine(Join-Path $Root ('runs/'+$ar.run_id+'/controller_receipt.json'))-or$ar.controller_report_sha256-cne$Scope.prior_alternating_receipt_sha256-or-not$ar.execution_control_released){throw 'PROBE_PRIOR_ALTERNATING_POINTER'}
  Assert-CadProbeAlternatingPredecessorV1 $ar $ac $Scope.owners
 }
 foreach($p in $Scope.PSObject.Properties){if($p.Name-match'(?i)^(command_text|payload|expression|allow_|fixture|offline_)'){throw 'PROBE_V3_EXTRA_EFFECT_FIELD'}}
 Assert-CadMultiOwnerProtectedHashesV1 $identity
 if((Get-FileHash -LiteralPath $Scope.source_path).Hash-cne$Scope.source_sha256){throw 'PROBE_V3_SOURCE_CHANGED'}
 [pscustomobject]@{run=$run;run_id=$Scope.run_id;phase=$Scope.phase;identity=$identity;operations=$ops;worker_timeout_seconds=15}
}
function Assert-CadProbeDependenciesV3([string]$Directory,[string]$Root) {
 $m=Read-CadPreparationScopeV1 (Join-Path $Directory 'candidate_manifest.json')
 if($m.id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'-or$m.candidate_version-ne3){throw 'PROBE_V3_MANIFEST_IDENTITY'}
 foreach($f in $m.files){$p=Assert-CadPreparationPathV1 (Join-Path $Root $f.path) $Root;if((Get-FileHash $p).Hash-cne$f.sha256){throw ('PROBE_DEPENDENCY_CHANGED:'+ $f.path)}}
}
function Assert-CadProbeReadyClaimV3($Scope,$Root,$ScopeHash) {
 $h=Read-CadPreparationScopeV1 (Join-Path $Root ('runs/'+$Scope.run_id+'/execution_handoff.json'))
 $c=Read-CadPreparationScopeV1 (Join-Path $Root ('runs/'+$Scope.run_id+'/execution_controller_claim.json'))
 $current=Read-CadPreparationScopeV1 (Join-Path $Root 'config/current_execution_handoff.json')
 if($h.status-cne'READY'-or$h.run_id-cne$Scope.run_id-or$h.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$h.multi_owner_non_db_probe.scope_sha256-cne$ScopeHash-or$h.program.scope_sha256-cne$ScopeHash-or$c.run_id-cne$Scope.run_id-or$c.handoff_id-cne$h.handoff_id-or-not$c.controller_attempt_reserved-or$current.status-cne'READY'-or$current.run_id-cne$Scope.run_id-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $Root ('runs/'+$Scope.run_id+'/execution_handoff.json'))).Hash){throw 'PROBE_V3_READY_CLAIM'}
}
