param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
function ProbePath([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){throw 'NONDB_PROBE_PATH_EMPTY'}
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if(-not$path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'NONDB_PROBE_PATH_OUTSIDE_PROJECT'}
    $path
}
function ProbeHash([string]$Path) {(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
$aExpression=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-A-EXPRESSION-VALIDATION-V2'
if(-not$aExpression-and[string]$Contract.profile_id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'){throw 'NONDB_PROBE_CONTRACT_UNKNOWN'}
$scopeField=if($aExpression){'multi_owner_a_expression_validation'}else{'multi_owner_non_db_probe'}
$profile=$Draft.$scopeField
if([string]$profile.profile_id-cne[string]$Contract.profile_id){throw 'NONDB_PROBE_PROFILE_UNKNOWN'}
$fileDocumentProbe=$false
if($null-ne$profile.PSObject.Properties['candidate_version']-or$null-ne$profile.PSObject.Properties['lookup_intent']){
    if($aExpression-or$profile.lookup_intent-cnotin@('ExactFileDocumentNonDbProbe','KnownAApplicationAndExactBFileDocumentNonDbProbe')-or$null-eq$Contract.PSObject.Properties['candidate_lookup_variants']){throw 'NONDB_PROBE_CANDIDATE_VARIANT'}
    $variant=$Contract.candidate_lookup_variants.PSObject.Properties[[string]$profile.lookup_intent]
    if($null-eq$variant-or$profile.candidate_version-ne$variant.Value.candidate_version){throw 'NONDB_PROBE_CANDIDATE_NOT_ADMITTED'}
    $candidateVersion=[int]$variant.Value.candidate_version
    $scopeValidator='Assert-CadProbeScopeV'+$candidateVersion
    if($candidateVersion-notin@(3,4)-or$variant.Value.scope_validator-cne$scopeValidator){throw 'NONDB_PROBE_CANDIDATE_CONTRACT'}
    $candidateDirectory=ProbePath $variant.Value.candidate_directory
    if((ProbePath $profile.manifest_path)-ine(Join-Path $candidateDirectory 'candidate_manifest.json')){throw 'NONDB_PROBE_CANDIDATE_DIRECTORY'}
    # Only this explicit variant uses a source-sealed candidate; legacy V1 and
    # A-expression validation retain their fixed manifest and original checks.
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    $Contract.manifest_path=$profile.manifest_path
    $Contract.manifest_sha256=$profile.manifest_sha256
    $Contract.controller=[IO.Path]::GetRelativePath($Root,(Join-Path $candidateDirectory ('invoke_non_db_probe_v'+$candidateVersion+'.ps1'))).Replace('\','/')
    $Contract.scope_contract=[IO.Path]::GetRelativePath($Root,(Join-Path $candidateDirectory ('probe_contract_v'+$candidateVersion+'.ps1'))).Replace('\','/')
    $fileDocumentProbe=$true
}
foreach($field in @('multi_owner_a_only_preparation','multi_owner_test_preparation','multi_owner_read_preflight','multi_owner_non_db_probe','multi_owner_binding_diagnostic','multi_owner_focus_registration','multi_owner_nativeom_diagnostic','multi_owner_a_expression_validation','multi_owner_b_startup_bridge','multi_owner_b_startup_bridge_resume','multi_owner_b_startup_bridge_replacement')){if($field-cne$scopeField-and$null-ne$Draft.PSObject.Properties[$field]){throw 'NONDB_PROBE_MIXED_PROFILE'}}
$manifestPath=ProbePath $Contract.manifest_path
if((ProbePath $profile.manifest_path)-ine$manifestPath-or[string]$profile.manifest_sha256-cne[string]$Contract.manifest_sha256-or(ProbeHash $manifestPath)-cne[string]$Contract.manifest_sha256){throw 'NONDB_PROBE_MANIFEST_BINDING'}
$manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if($manifest.id-cne$profile.profile_id-or[string]$manifest.controller-cne[string]$Contract.controller-or[string]$manifest.scope_contract-cne[string]$Contract.scope_contract){throw 'NONDB_PROBE_MANIFEST_IDENTITY'}
if($fileDocumentProbe){
    if($manifest.candidate_version-ne$candidateVersion-or$manifest.lookup_intent-cne$profile.lookup_intent-or$manifest.source_thread_id-cne$variant.Value.source_thread_id){throw 'NONDB_PROBE_CANDIDATE_MANIFEST_IDENTITY'}
    if($manifest.status-cne'SEALED_PRIVATE_VALIDATION_ONLY'-or$manifest.scope_field-cne$scopeField-or$manifest.intent-cne'ExecuteNonDbProbe'-or$manifest.scope_assertion-cne$scopeValidator-or$manifest.fixed_expression_generator-cne'New-CadProbeExpressionV2'-or$manifest.helper_memory_limit_bytes-ne536870912-or$manifest.helper_process_limit-ne1-or$manifest.helper_max_concurrent-ne2){throw 'NONDB_PROBE_CANDIDATE_CAPABILITIES'}
    if($candidateVersion-eq4-and($manifest.A_enumerate_max_per_operation-ne1-or$manifest.A_hold_selected_application-isnot[bool]-or-not$manifest.A_hold_selected_application-or$manifest.A_strict_bind_max_per_operation-ne4-or$manifest.B_file_lookup_max_per_operation-ne1-or$manifest.B_strict_bind_max_per_operation-ne3-or$manifest.dynamic_fallback_allowed-isnot[bool]-or$manifest.dynamic_fallback_allowed)){throw 'NONDB_PROBE_CANDIDATE_OWNER_TRANSPORT'}
    foreach($path in @($manifestPath,(ProbePath $Contract.controller),(ProbePath $Contract.scope_contract))){
        for($ancestor=$path;$ancestor.Length-gt$Root.Length;$ancestor=Split-Path -Parent $ancestor){if((Test-Path -LiteralPath $ancestor)-and((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'NONDB_PROBE_CANDIDATE_REPARSE'}}
    }
}
$requiredFalse=if($aExpression){@('database_write_allowed','foreground_activation_allowed','input_injection_allowed','netload_allowed','launch_save_close_kill_cad_allowed','fallback_allowed','retry_allowed','live_verified','alternating_proven','concurrency_proven')}else{@('database_write_allowed','launch_allowed','save_close_kill_cad_allowed','foreground_activation_allowed','input_injection_allowed','netload_allowed','send_retry_allowed','multi_dialog_control_allowed','live_verified')}
$requiredTrue=if($aExpression){@('durable_send_stages','native_identity_ack_complete_required','fresh_execute_binding_required','original_global_guard_unchanged')}else{@('native_probe_only','serial_global_guard_unchanged','overlap_requires_prior_alternating_pass')}
foreach($field in $requiredFalse){
    if($manifest.$field-isnot[bool]-or$manifest.$field-ne$false){throw ('NONDB_PROBE_FORBIDDEN_CAPABILITY:'+ $field)}
}
foreach($field in $requiredTrue){
    if($manifest.$field-isnot[bool]-or$manifest.$field-ne$true){throw ('NONDB_PROBE_REQUIRED_CAPABILITY:'+ $field)}
}
if($aExpression-and($manifest.intent-cne'ExecuteFixedAExpressionValidation'-or$manifest.phase-cne'A_ONLY_FIXED_EXPRESSION'-or$manifest.send_owner-cne'A'-or$manifest.send_max_count-ne1-or$manifest.B_send_max_count-ne0-or$manifest.timeout_seconds-ne20-or$manifest.duration_ms-ne0-or$manifest.expression_delta-cne'ONE_QUOTE_BEFORE_EMITTER_LAMBDA')){throw 'A_EXPR_MANIFEST_BOUNDARY'}
$bindings=@{}
foreach($property in $Draft.program.PSObject.Properties){
    if($property.Name.EndsWith('_sha256')){
        $key=$property.Name.Substring(0,$property.Name.Length-7);$pair=$Draft.program.PSObject.Properties[$key]
        if($null-eq$pair){throw 'NONDB_PROBE_PROGRAM_PAIR_MISSING'}
        $path=ProbePath ([string]$pair.Value)
        if($bindings.ContainsKey($path)-and$bindings[$path]-cne[string]$property.Value){throw 'NONDB_PROBE_PROGRAM_CONFLICT'}
        $bindings[$path]=[string]$property.Value
    }
}
function AssertProbeBound([string]$Value,[string]$Hash) {
    $path=ProbePath $Value
    if($Hash-cnotmatch'^[A-F0-9]{64}$'-or(ProbeHash $path)-cne$Hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$Hash){throw ('NONDB_PROBE_REQUIRED_BINDING:'+ $Value)}
}
$candidateFiles=@($manifest.files)+@([pscustomobject]@{path=$Contract.manifest_path;sha256=$Contract.manifest_sha256})
if($fileDocumentProbe){$candidateFiles+=@($manifest.validation_dependencies)}
foreach($file in $candidateFiles){AssertProbeBound $file.path $file.sha256}
$controller=ProbePath $Contract.controller
if((ProbePath $Draft.program.controller)-ine$controller){throw 'NONDB_PROBE_CONTROLLER_NOT_ADMITTED'}
$scopePath=ProbePath $profile.scope_path
AssertProbeBound $scopePath ([string]$profile.scope_sha256)
# Load only the admitted, hash-checked pure contract; no worker or controller.
. (ProbePath $Contract.scope_contract)
$scope=Read-CadPreparationScopeV1 $scopePath
$run=Join-Path (Join-Path $Root 'runs') ([string]$Draft.run_id)
$v=if($aExpression){Assert-CadAExpressionScopeV2 $scope $Root $run}elseif($fileDocumentProbe){& $scopeValidator $scope $Root $run}else{Assert-CadProbeScopeV1 $scope $Root $run}
$phase=if($aExpression){[string]$scope.phase}else{[string]$v.phase}
if($v.run_id-cne[string]$Draft.run_id-or$phase-cne[string]$profile.phase-or$phase-cnotin@($Contract.phases)){throw 'NONDB_PROBE_SCOPE_IDENTITY'}
Assert-CadMultiOwnerProtectedHashesV1 $v.identity
$historyPrefixes=if($aExpression){@('prior_get_return','prior_get_scope','prior_probe_return','prior_diagnostic_return','prior_diagnostic_scope','prior_focus_return','prior_focus_scope','prior_nativeom_return','prior_nativeom_scope')}elseif($fileDocumentProbe){@('prior_A_return','prior_B_background_return','prior_B_background_scope')+@(if($phase-ceq'OVERLAP'){'prior_alternating_return';'prior_alternating_receipt'})}else{@('prior_read_return','prior_read_scope')+@(if($phase-ceq'OVERLAP'){'prior_alternating_return';'prior_alternating_receipt'})}
foreach($prefix in $historyPrefixes){
    AssertProbeBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))
}
if(-not$aExpression-and-not$fileDocumentProbe){
    $prior=Read-CadPreparationScopeV1 $scope.prior_read_return_path
    if((ProbePath $scope.prior_read_return_path)-ine(Join-Path $Root ('runs/'+$prior.run_id+'/execution_return.json'))){throw 'NONDB_PROBE_PRIOR_READ_RETURN_NOT_IMMUTABLE'}
}
if($fileDocumentProbe){
    if($scope.candidate_version-ne$candidateVersion-or$scope.lookup_intent-cne$profile.lookup_intent-or$phase-cnotin@('ALTERNATING','OVERLAP')){throw 'NONDB_PROBE_FILE_SCOPE_IDENTITY'}
    $operations=@($scope.operations);$expectedOrder=if($phase-ceq'ALTERNATING'){'A,B,A'}else{'A,B'}
    if((@($scope.owners.id)-join',')-cne'A,B'-or($operations.owner-join',')-cne$expectedOrder){throw 'NONDB_PROBE_FILE_OWNER_PLAN'}
    foreach($op in $operations){if(($phase-ceq'ALTERNATING'-and$op.duration_ms-ne0)-or($phase-ceq'OVERLAP'-and($op.duration_ms-lt3000-or$op.duration_ms-gt8000))){throw 'NONDB_PROBE_FILE_DURATION'}}
    # Verify real immutable provenance independently of the private scope
    # validator. Existing A strict-read and B background PASS are not recast
    # as a fictional historical ABA run; fresh per-target binding is required.
    $priorA=Read-CadPreparationScopeV1 $scope.prior_A_return_path
    $priorB=Read-CadPreparationScopeV1 $scope.prior_B_background_return_path
    foreach($item in @(@($priorA,$scope.prior_A_return_path),@($priorB,$scope.prior_B_background_return_path))){
        $r=$item[0]
        if((ProbePath $item[1])-ine(Join-Path $Root ('runs/'+$r.run_id+'/execution_return.json'))-or$r.writer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$r.execution_control_released-isnot[bool]-or-not$r.execution_control_released-or$r.retry_count-ne0){throw 'NONDB_PROBE_FILE_PRIOR_PROVENANCE'}
        AssertProbeBound ([string]$r.controller_report_path) ([string]$r.controller_report_sha256)
    }
    $ac=$priorA.controller_report;$bc=$priorB.controller_report;$bw=$bc.worker_receipt
    if($ac.status-cne'PASS_FRESH_A_ONLY_PREPARED_AND_STRICT_READ'-or$ac.strict_a.status-cne'PASS_A_ONLY_STRICT_READ'-or$ac.strict_a.strict_state.dbmod-ne0-or$bc.status-cne'PASS_SINGLE_BACKGROUND_INPUT_SAMPLED'-or$bc.protected_hashes_after-cne'UNCHANGED'-or$bw.status-cne'PASS_FIXED_READ_NATIVE_ACK_COMPLETE'-or$bw.command_send_count-ne1-or-not$bw.send_call_returned-or$bw.native_evidence.status-cne'PASS'-or$bw.native_evidence.owner-cne'B'){throw 'NONDB_PROBE_FILE_PRIOR_NOT_PASS'}
    $a=@($scope.owners|Where-Object id -CEQ 'A')[0]
    foreach($field in @('process_id','process_start_time_utc','window_handle','protected_sha256')){if([string]$a.$field-cne[string]$ac.fresh_owner_a.$field){throw ('NONDB_PROBE_FILE_PRIOR_A_OWNER:'+ $field)}}
    if((ProbePath $a.document_full_path)-ine(ProbePath $ac.strict_a.strict_state.full_path)-or[long]$a.window_handle-ne[long]$ac.strict_a.strict_state.hwnd){throw 'NONDB_PROBE_FILE_PRIOR_A_DOCUMENT'}
    $bs=Read-CadPreparationScopeV1 $scope.prior_B_background_scope_path
    if($bs.run_id-cne$priorB.run_id-or$bc.scope_sha256-cne$scope.prior_B_background_scope_sha256){throw 'NONDB_PROBE_FILE_PRIOR_B_SCOPE'}
    foreach($owner in $scope.owners){
        $old=@($bs.owners|Where-Object id -CEQ $owner.id)
        if($old.Count-ne1){throw 'NONDB_PROBE_FILE_PRIOR_B_OWNER_MISSING'}
        foreach($field in @('id','scope_kind','process_id','process_start_time_utc','process_image_path','window_handle','document_full_path','protected_sha256')){if([string]$owner.$field-cne[string]$old[0].$field){throw ('NONDB_PROBE_FILE_PRIOR_B_OWNER:'+ $field)}}
    }
}
foreach($field in @('run_directory','controller_receipt')){if([IO.Path]::IsPathRooted([string]$Draft.reporting.$field)){throw 'NONDB_PROBE_REPORT_PROJECT_RELATIVE_REQUIRED'}}
if((ProbePath $Draft.reporting.run_directory)-ine$run-or(ProbePath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'NONDB_PROBE_REPORT_PATH'}
foreach($name in @('canonical_open','launch_policy')){
    if($null-ne$Draft.PSObject.Properties[$name]){
        $policy=$Draft.$name
        if($policy.launch_permitted_for_this_handoff-isnot[bool]-or$policy.launch_permitted_for_this_handoff-ne$false){throw 'NONDB_PROBE_LAUNCH_FORBIDDEN'}
    }
}
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$tokens,[ref]$parseErrors)
$commands=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]},$true))
if($parseErrors.Count-ne0-or$commands.Count-ne1-or$ast.EndBlock.Statements.Count-ne1-or$ast.EndBlock.Statements[0]-isnot[Management.Automation.Language.PipelineAst]-or$ast.EndBlock.Statements[0].PipelineElements.Count-ne1){throw 'NONDB_PROBE_TEMPLATE_NOT_LITERAL'}
$command=$commands[0]
if((ProbePath $command.GetCommandName())-ine$controller){throw 'NONDB_PROBE_TEMPLATE_CONTROLLER'}
$callParameters=@{};$elements=$command.CommandElements
for($i=1;$i-lt$elements.Count;$i+=2){
    if($elements[$i]-isnot[Management.Automation.Language.CommandParameterAst]-or$null-ne$elements[$i].Argument-or$i+1-ge$elements.Count){throw 'NONDB_PROBE_TEMPLATE_PARAMETER'}
    $name=$elements[$i].ParameterName;$value=$elements[$i+1]
    if($callParameters.ContainsKey($name)){throw 'NONDB_PROBE_TEMPLATE_DUPLICATE_PARAMETER'}
    if($value-isnot[Management.Automation.Language.StringConstantExpressionAst]){throw 'NONDB_PROBE_TEMPLATE_NOT_LITERAL'}
    $callParameters[$name]=$value.Value
}
if($callParameters.Count-ne3-or@('RunDirectory','ScopePath','ScopeSha256'|Where-Object{-not$callParameters.ContainsKey($_)}).Count){throw 'NONDB_PROBE_TEMPLATE_PARAMETER_SET'}
if(-not[IO.Path]::IsPathRooted($callParameters.RunDirectory)-or-not[IO.Path]::IsPathRooted($callParameters.ScopePath)){throw 'NONDB_PROBE_TEMPLATE_ABSOLUTE_REQUIRED'}
if((ProbePath $callParameters.RunDirectory)-ine$run-or(ProbePath $callParameters.ScopePath)-ine$scopePath-or$callParameters.ScopeSha256-cne[string]$profile.scope_sha256){throw 'NONDB_PROBE_TEMPLATE_SCOPE_MISMATCH'}
[pscustomobject]@{status='PASS';profile_id=$profile.profile_id;phase=$phase;owner_count=2;operations=if($aExpression){1}else{$v.operations.Count};cad_calls=0;live_verified=$false}
