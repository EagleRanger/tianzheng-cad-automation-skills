param([Parameter(Mandatory)]$Draft,[Parameter(Mandatory)]$Contract,[string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath($Root)
function DiagPath([string]$Value){
    if([string]::IsNullOrWhiteSpace($Value)){throw 'BINDING_DIAG_PATH_EMPTY'}
    $path=if([IO.Path]::IsPathRooted($Value)){[IO.Path]::GetFullPath($Value)}else{[IO.Path]::GetFullPath((Join-Path $Root $Value))}
    if(-not$path.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'BINDING_DIAG_PATH_OUTSIDE_PROJECT'}
    $path
}
# Share only the literal invocation/hash envelope; each profile retains its own
# immutable scope contract and capability boundary.
$focusProfile=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-FOCUS-REGISTRATION-DIAGNOSTIC-V1'
$nativeOmProfile=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-NATIVEOM-DIAGNOSTIC-V1'
$freshDiagnosticV4=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-FRESH-BINDING-DIAGNOSTIC-V4'
$freshDiagnostic=$freshDiagnosticV4-or[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-FRESH-BINDING-DIAGNOSTIC-V3'
$bindingComparison=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-BINDING-COMPARISON-V1'
$pipeBootstrap=[string]$Contract.profile_id-ceq'CAD-PINNED-PIPE-A-BOOTSTRAP-V1'
$pipeVersionCandidate=$false
$pipeRecovery=$pipeBootstrap-and[string]$Draft.multi_owner_pinned_pipe_a_bootstrap.intent-ceq'ReadAndRejectExpiredFixedALoad'
$pipeAlwaysLoad=$pipeBootstrap-and[string]$Draft.multi_owner_pinned_pipe_a_bootstrap.intent-ceq'LoadFixedAAlwaysTrustReadIdentityAndCleanup'
$alwaysFields=@('bound_AlwaysLoad_max','module_trust_scope','current_payload_required','exact_dialog_module_owner_required','raw_dialog_evidence_before_click_required','post_load_identity_verification_required')
if($pipeAlwaysLoad){
    if($null-eq$Contract.PSObject.Properties['load_intents']-or$null-eq$Contract.load_intents.PSObject.Properties['LoadFixedAAlwaysTrustReadIdentityAndCleanup']){throw 'PINNED_ALWAYS_LOAD_NOT_ADMITTED'}
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    foreach($property in $Contract.load_intents.LoadFixedAAlwaysTrustReadIdentityAndCleanup.PSObject.Properties){$Contract|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
}
if($pipeRecovery){
    if($null-eq$Contract.PSObject.Properties['recovery_intents']-or$null-eq$Contract.recovery_intents.PSObject.Properties['ReadAndRejectExpiredFixedALoad']){throw 'PINNED_RECOVERY_NOT_ADMITTED'}
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    foreach($property in $Contract.recovery_intents.ReadAndRejectExpiredFixedALoad.PSObject.Properties){$Contract|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
}
$scopedMetadata=$freshDiagnostic-or$bindingComparison
$scopedEnvelope=$scopedMetadata-or$pipeBootstrap
$bBridgeResume=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-RESUME-V2'
$bBridgeReplacement=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-REPLACEMENT-V3'
$bBridgeFreshA=[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-FRESH-A-V6'
$bVersionCandidate=$false
$bContractVersion=6
$bReject=$bBridgeFreshA-and[string]$Draft.multi_owner_b_startup_bridge_fresh_a.intent-ceq'ReadAndRejectExpiredFixedBLoad'
$bSettlement=$bBridgeFreshA-and([string]$Draft.multi_owner_b_startup_bridge_fresh_a.intent-cin@('ReadExistingOwnersAndRawDialogsOnly','ReadAndRejectExpiredFixedBLoad'))
$bRejectFields=@('bound_reject_max','reject_owner','reject_command_id','fresh_tree_sample_count','post_reject_timeout_seconds','expired_payload_required','prior_helper_and_controller_ended_required','raw_dialog_evidence_before_click_required','exact_dialog_module_owner_required','no_second_bootstrap_same_run')
$bSettlementFields=@('serial_executor_required','original_global_guard_unchanged','existing_owners_only','raw_dialog_read_required','stage_evidence_read_only','modal_blocks_com','strict_read_max_per_owner','owner_max_count','helper_max_count','outer_timeout_seconds_max','launch_allowed','close_allowed','save_allowed','cad_force_kill_allowed','activation_allowed','restore_allowed','input_allowed','cad_command_allowed','netload_allowed','load_once_allowed','persistent_trust_allowed','reject_allowed','register_allowed','revoke_allowed','retry_allowed','second_controller_allowed','concurrent_execution_allowed','global_configuration_change_allowed','canonical_open_transport','open_result_semantics','invocation')
if($bSettlement){
    if($null-eq$Contract.PSObject.Properties['recovery_intents']-or$null-eq$Contract.recovery_intents.PSObject.Properties['ReadExistingOwnersAndRawDialogsOnly']){throw 'B_SETTLEMENT_NOT_ADMITTED'}
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    foreach($property in $Contract.recovery_intents.ReadExistingOwnersAndRawDialogsOnly.PSObject.Properties){$Contract|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
    if($bReject){
        if($null-eq$Contract.recovery_intents.PSObject.Properties['ReadAndRejectExpiredFixedBLoad']-or$Contract.recovery_intents.ReadAndRejectExpiredFixedBLoad.inherits_intent-cne'ReadExistingOwnersAndRawDialogsOnly'){throw 'B_REJECT_NOT_ADMITTED'}
        foreach($property in $Contract.recovery_intents.ReadAndRejectExpiredFixedBLoad.PSObject.Properties){$Contract|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
        $bSettlementFields+= $bRejectFields
    }
}
$bAlwaysLoad=$bBridgeFreshA-and[string]$Draft.multi_owner_b_startup_bridge_fresh_a.intent-ceq'StartOnlyNewBFromFreshAAlwaysTrustAndReadUniqueBridge'
$bCapFields=@('serial_executor_required','original_global_guard_unchanged','fresh_exact_A_and_strict_RAM_baseline_required','new_B_shortcut_start_max_count','bound_DLL_load_once_click_max_count','old_B_normal_close_max_count','old_B_discard_click_max_count','fixed_scr_and_bound_dll_only','reuse_frozen_compile_and_V5_payload_bytes','startup_timeout_seconds_max','strict_read_timeout_seconds_max','cookie_revoke_timeout_seconds_max','outer_timeout_seconds_max','bridge_lifetime_seconds','canonical_open_transport','open_result_semantics','invocation','cad_force_kill_allowed','A_control_allowed','business_commands_allowed','persistent_trust_allowed','global_configuration_change_allowed','retry_allowed','second_controller_allowed','concurrent_execution_allowed','multi_dialog_control_allowed')
$bAlwaysFields=@('bound_DLL_always_load_click_max_count','module_trust_scope','current_payload_required','exact_dialog_module_owner_required','raw_dialog_evidence_before_click_required','post_load_identity_verification_required','fresh_bound_payload_required','reuse_frozen_protocol_source_only')
if($bAlwaysLoad){
    if($null-eq$Contract.PSObject.Properties['load_intents']-or$null-eq$Contract.load_intents.PSObject.Properties['StartOnlyNewBFromFreshAAlwaysTrustAndReadUniqueBridge']){throw 'B_FRESH_A_ALWAYS_LOAD_NOT_ADMITTED'}
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    foreach($property in $Contract.load_intents.StartOnlyNewBFromFreshAAlwaysTrustAndReadUniqueBridge.PSObject.Properties){$Contract|Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
}
$bBridgeProfile=$bBridgeFreshA-or$bBridgeReplacement-or$bBridgeResume-or[string]$Contract.profile_id-ceq'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-V1'
$bLaunch=$bBridgeProfile-and-not$bSettlement
if(-not$scopedEnvelope-and-not$focusProfile-and-not$nativeOmProfile-and-not$bBridgeProfile-and[string]$Contract.profile_id-cne'CAD-MULTI-OWNER-BINDING-DIAGNOSTIC-V1'){throw 'BINDING_DIAG_CONTRACT_UNKNOWN'}
$scopeField=if($pipeBootstrap){'multi_owner_pinned_pipe_a_bootstrap'}elseif($bindingComparison){'multi_owner_binding_comparison'}elseif($bBridgeFreshA){'multi_owner_b_startup_bridge_fresh_a'}elseif($bBridgeReplacement){'multi_owner_b_startup_bridge_replacement'}elseif($bBridgeResume){'multi_owner_b_startup_bridge_resume'}elseif($bBridgeProfile){'multi_owner_b_startup_bridge'}elseif($focusProfile){'multi_owner_focus_registration'}elseif($nativeOmProfile){'multi_owner_nativeom_diagnostic'}else{'multi_owner_binding_diagnostic'}
$expectedIntent=if($pipeAlwaysLoad){'LoadFixedAAlwaysTrustReadIdentityAndCleanup'}elseif($pipeRecovery){'ReadAndRejectExpiredFixedALoad'}elseif($pipeBootstrap){'LoadFixedAReadIdentityAndCleanup'}elseif($bindingComparison){'ReadBindingComparison'}elseif($bReject){'ReadAndRejectExpiredFixedBLoad'}elseif($bSettlement){'ReadExistingOwnersAndRawDialogsOnly'}elseif($bAlwaysLoad){'StartOnlyNewBFromFreshAAlwaysTrustAndReadUniqueBridge'}elseif($bBridgeFreshA){'StartOnlyNewBFromFreshAAndReadUniqueBridge'}elseif($bBridgeReplacement){'RejectExpiredOldPayloadReplaceCurrentBAndReadUniqueBridge'}elseif($bBridgeResume){'ResumeOnlyNewBAfterOldBExitAndReadUniqueBridge'}elseif($bBridgeProfile){'ReplaceOnlyBAndReadUniqueBridge'}elseif($focusProfile){'ReadRegistrationWithOneFocus'}elseif($nativeOmProfile){'ReadNativeOmIdentityOnce'}else{'ReadDiagnostics'}
$profile=$Draft.$scopeField
if([string]$profile.profile_id-cne[string]$Contract.profile_id){throw 'BINDING_DIAG_PROFILE_UNKNOWN'}
foreach($field in @('multi_owner_pinned_pipe_a_bootstrap','multi_owner_binding_comparison','multi_owner_b_startup_bridge_fresh_a','multi_owner_a_only_preparation','multi_owner_test_preparation','multi_owner_read_preflight','multi_owner_non_db_probe','multi_owner_binding_diagnostic','multi_owner_focus_registration','multi_owner_nativeom_diagnostic','multi_owner_a_expression_validation','multi_owner_b_startup_bridge','multi_owner_b_startup_bridge_resume','multi_owner_b_startup_bridge_replacement')){if($field-cne$scopeField-and$null-ne$Draft.PSObject.Properties[$field]){throw 'BINDING_DIAG_MIXED_PROFILE'}}
if($bBridgeFreshA-and($Contract.scope_field-cne$scopeField-or$profile.intent-cne$expectedIntent-or$Contract.intent-cne$expectedIntent)){throw 'B_FRESH_A_ADMISSION_INTENT'}
if($scopedEnvelope-and($Contract.scope_field-cne$scopeField-or$profile.intent-cne$expectedIntent-or$Contract.intent-cne$expectedIntent)){throw 'FRESH_DIAG_ADMISSION_INTENT'}
if($pipeRecovery-and(DiagPath $profile.manifest_path)-ieq(DiagPath $Contract.manifest_path)){throw 'PINNED_RECOVERY_VERSIONED_CANDIDATE_REQUIRED'}
if($pipeAlwaysLoad-and(DiagPath $profile.manifest_path)-ieq(DiagPath $Contract.manifest_path)){throw 'PINNED_ALWAYS_LOAD_VERSIONED_CANDIDATE_REQUIRED'}
if($bAlwaysLoad-and(DiagPath $profile.manifest_path)-ieq(DiagPath $Contract.manifest_path)){throw 'B_FRESH_A_ALWAYS_LOAD_VERSIONED_CANDIDATE_REQUIRED'}
if($bSettlement-and(DiagPath $profile.manifest_path)-ieq(DiagPath $Contract.manifest_path)){throw 'B_SETTLEMENT_VERSIONED_CANDIDATE_REQUIRED'}
# Permissions belong to the stable route. The source may seal a new private
# implementation without requiring shared routing/registry edits for each hash.
if(($pipeBootstrap-or$bBridgeFreshA)-and(DiagPath $profile.manifest_path)-ine(DiagPath $Contract.manifest_path)){
    if($null-eq$Contract.PSObject.Properties['candidate_resolution']-or$Contract.candidate_resolution-cne'source_sealed_version_with_stable_capability_bounds'){throw 'BINDING_DIAG_MANIFEST_BINDING'}
    $relative=[IO.Path]::GetRelativePath($Root,(DiagPath $profile.manifest_path)).Replace('\','/')
    $pattern='^'+[regex]::Escape([string]$Contract.candidate_directory_prefix)+'([1-9][0-9]*)/candidate_manifest\.json$'
    if($relative-cnotmatch$pattern){throw 'PINNED_CANDIDATE_DIRECTORY'}
    $implementationVersion=[long]$Matches[1]
    $candidatePath=DiagPath $profile.manifest_path
    $ancestor=$candidatePath
    while($ancestor.Length-gt$Root.Length){
        if((Test-Path -LiteralPath $ancestor)-and((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'PINNED_CANDIDATE_REPARSE'}
        $ancestor=Split-Path -Parent $ancestor
    }
    if([string]$profile.manifest_sha256-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $candidatePath).Hash-cne$profile.manifest_sha256){throw 'BINDING_DIAG_MANIFEST_BINDING'}
    $candidate=Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if($candidate.id-cne$Contract.profile_id-or$candidate.source_thread_id-cne$Contract.candidate_source_thread_id-or$candidate.implementation_version-isnot[long]-and$candidate.implementation_version-isnot[int]-or$candidate.implementation_version-ne$implementationVersion-or$candidate.scope_field-cne$scopeField-or$candidate.intent-cne$expectedIntent){throw 'PINNED_CANDIDATE_IDENTITY'}
    $candidateDirectory=Split-Path -Parent $candidatePath
    foreach($field in @('controller','scope_contract')){
        $code=DiagPath ([string]$candidate.$field)
        if([IO.Path]::IsPathRooted([string]$candidate.$field)-or(Split-Path -Parent $code)-ine$candidateDirectory-or[IO.Path]::GetExtension($code)-ine'.ps1'){throw 'PINNED_CANDIDATE_CODE_PATH'}
        if((Get-Item -LiteralPath $code -Force).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'PINNED_CANDIDATE_REPARSE'}
    }
    $capFields=if($bBridgeFreshA){$bCapFields}else{@('serial_executor_required','original_global_guard_unchanged','fixed_A_module_only','exact_host_thread_and_full_cleanup_required','netload_send_max','pipe_request_max','bound_LoadOnce_max','outer_timeout_seconds_max','worker_process_execution_policy','B_control_allowed','business_commands_allowed','persistent_trust_allowed','global_configuration_change_allowed','retry_allowed','second_controller_allowed','concurrent_execution_allowed')}
    if($bAlwaysLoad){$capFields+= $bAlwaysFields}
    if($bSettlement){$capFields=$bSettlementFields}
    foreach($field in $capFields){
        $bound=$candidate.capability_bounds.PSObject.Properties[$field]
        if($null-eq$bound-or$bound.Value.GetType()-ne$Contract.$field.GetType()-or$bound.Value-cne$Contract.$field){throw ('PINNED_CANDIDATE_CAPABILITY_CHANGE:'+ $field)}
    }
    if($pipeRecovery){
        foreach($field in @('bound_reject_max','dialog_text_read_only_required','prior_payload_expired_required','prior_helper_and_lease_ended_required','raw_dialog_evidence_before_click_required','no_second_bootstrap_same_run')){
            $bound=$candidate.capability_bounds.PSObject.Properties[$field]
            if($null-eq$bound-or$bound.Value.GetType()-ne$Contract.$field.GetType()-or$bound.Value-cne$Contract.$field){throw ('PINNED_CANDIDATE_CAPABILITY_CHANGE:'+ $field)}
        }
    }
    if($pipeAlwaysLoad){
        foreach($field in $alwaysFields){
            $bound=$candidate.capability_bounds.PSObject.Properties[$field]
            if($null-eq$bound-or$bound.Value.GetType()-ne$Contract.$field.GetType()-or$bound.Value-cne$Contract.$field){throw ('PINNED_CANDIDATE_CAPABILITY_CHANGE:'+ $field)}
        }
    }
    # Work on a local copy; the stable shared route is never rewritten by a candidate.
    $Contract=$Contract|ConvertTo-Json -Depth 20|ConvertFrom-Json -DateKind String
    $Contract.manifest_path=$relative;$Contract.manifest_sha256=$profile.manifest_sha256
    $Contract.controller=$candidate.controller;$Contract.scope_contract=$candidate.scope_contract
    $pipeVersionCandidate=$pipeBootstrap
    $bVersionCandidate=$bBridgeFreshA
    if($bVersionCandidate){
        if($candidate.status-cne'SEALED_PRIVATE_VALIDATION_ONLY'-or$candidate.candidate_version-ne$implementationVersion){throw 'B_FRESH_A_CANDIDATE_UNSEALED_OR_VERSION'}
        $bContractVersion=$implementationVersion
    }
}
$manifestPath=DiagPath $Contract.manifest_path
if((DiagPath $profile.manifest_path)-ine$manifestPath-or[string]$profile.manifest_sha256-cne[string]$Contract.manifest_sha256-or(Get-FileHash -LiteralPath $manifestPath).Hash-cne[string]$Contract.manifest_sha256){throw 'BINDING_DIAG_MANIFEST_BINDING'}
$m=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
if($m.id-cne$profile.profile_id-or(-not$pipeBootstrap-and[string]$m.controller-cne[string]$Contract.controller)){throw 'BINDING_DIAG_MANIFEST_IDENTITY'}
if($pipeBootstrap){
    if($m.status-cne'SEALED_PRIVATE_VALIDATION_ONLY'-or$Contract.outer_timeout_seconds_max-ne$(if($pipeRecovery){30}else{70})-or$Contract.netload_send_max-ne$(if($pipeRecovery){0}else{1})-or$Contract.pipe_request_max-ne$(if($pipeRecovery){0}else{1})-or$Contract.worker_process_execution_policy-cne'RemoteSigned'){throw 'PINNED_ADMISSION_BOUNDARY'}
    foreach($field in @('serial_executor_required','original_global_guard_unchanged','fixed_A_module_only','exact_host_thread_and_full_cleanup_required')){if($Contract.$field-isnot[bool]-or-not$Contract.$field){throw 'PINNED_ADMISSION_BOUNDARY'}}
    foreach($field in @('B_control_allowed','business_commands_allowed','global_configuration_change_allowed','retry_allowed','second_controller_allowed','concurrent_execution_allowed')){if($Contract.$field-isnot[bool]-or$Contract.$field){throw 'PINNED_ADMISSION_BOUNDARY'}}
    if($Contract.persistent_trust_allowed-isnot[bool]-or$Contract.persistent_trust_allowed-ne$pipeAlwaysLoad){throw 'PINNED_ADMISSION_BOUNDARY'}
}elseif($bBridgeProfile){
    $bridgePhase=if($bReject){'EXISTING_OWNERS_EXPIRED_B_LOAD_REJECTION'}elseif($bSettlement){'EXISTING_OWNERS_READ_ONLY_SETTLEMENT'}else{'B_BOOTSTRAP_IDENTITY_READ_ONLY'}
    if($m.scope_field-cne$scopeField-or$m.phase-cne$bridgePhase-or$m.source_thread_id-cne'RECEIVER_ID_REQUIRED'-or$m.live_verified-isnot[bool]-or$m.live_verified-or$m.cad_calls-ne0-or$m.actual_rot_calls-ne0){throw 'B_BRIDGE_MANIFEST_BOUNDARY'}
}else{
if([string]$m.scope_contract-cne[string]$Contract.scope_contract-or$m.intent-cne$expectedIntent){throw 'BINDING_DIAG_MANIFEST_IDENTITY'}
foreach($field in @('cad_command_send_allowed','database_read_content_allowed','database_write_allowed','window_restore_allowed','input_injection_allowed','netload_allowed','launch_save_close_kill_cad_allowed','retry_allowed','strict_action_binding_returned','live_verified')){if($m.$field-isnot[bool]-or$m.$field-ne$false){throw ('BINDING_DIAG_FORBIDDEN_CAPABILITY:'+ $field)}}
if($m.foreground_activation_allowed-isnot[bool]-or$m.foreground_activation_allowed-ne$focusProfile){throw 'BINDING_DIAG_FOREGROUND_CAPABILITY'}
foreach($field in @('document_path_metadata_only','original_global_guard_unchanged')){if($m.$field-isnot[bool]-or$m.$field-ne$true){throw ('BINDING_DIAG_REQUIRED_CAPABILITY:'+ $field)}}
if(-not$nativeOmProfile-and-not$bindingComparison-and($m.capture_max_per_owner-ne1-or$m.capture_timeout_seconds-ne12)){throw 'BINDING_DIAG_BOUNDARY'}
if($bindingComparison){
    foreach($field in @('capture_allowed','native_idle_read_allowed')){if($m.$field-isnot[bool]-or$m.$field){throw ('COMPARISON_FORBIDDEN_CAPABILITY:'+ $field)}}
    if($m.capture_max_per_owner-ne0-or$m.rot_producer_count-ne2-or$m.selector_bind_calls_max-ne4-or$m.selector_intent-cne'Bind'){throw 'COMPARISON_FIXED_BOUNDARY'}
}
if($nativeOmProfile){
    if($m.nativeom_owner-cne'B'-or$m.nativeom_max_count-ne1-or$m.timeout_seconds-ne20-or$m.fallback_allowed-isnot[bool]-or$m.fallback_allowed){throw 'NATIVEOM_DIAGNOSTIC_BOUNDARY'}
}elseif($focusProfile){
    if($m.baseline_rot_max_count-ne1-or$m.after_rot_max_count-ne1-or$m.rot_timeout_seconds-ne20-or$m.focus_timeout_seconds-ne5-or$m.focus_owner-cne'B'-or$m.focus_max_count-ne1-or$m.exact_hwnd_only-isnot[bool]-or-not$m.exact_hwnd_only){throw 'FOCUS_REGISTRATION_BOUNDARY'}
}elseif($m.binding_worker_count-ne1-or$m.binding_timeout_seconds-ne20){throw 'BINDING_DIAG_BOUNDARY'}
if($scopedMetadata-and($m.register_or_reuse_revoked_key_allowed-isnot[bool]-or$m.register_or_reuse_revoked_key_allowed-or$m.cad_calls-ne0-or$m.compiler_calls-ne0-or$m.source_thread_id-cne'RECEIVER_ID_REQUIRED'-or$m.scope_field-cne$scopeField)){throw 'FRESH_DIAG_MANIFEST_BOUNDARY'}
}
$bindings=@{}
foreach($property in $Draft.program.PSObject.Properties){
    if($property.Name.EndsWith('_sha256')){
        $key=$property.Name.Substring(0,$property.Name.Length-7);$pair=$Draft.program.PSObject.Properties[$key]
        if($null-eq$pair){throw 'BINDING_DIAG_PROGRAM_PAIR_MISSING'}
        $path=DiagPath ([string]$pair.Value)
        if($bindings.ContainsKey($path)-and$bindings[$path]-cne[string]$property.Value){throw 'BINDING_DIAG_PROGRAM_CONFLICT'}
        $bindings[$path]=[string]$property.Value
    }
}
function AssertDiagBound([string]$Value,[string]$Hash){$path=DiagPath $Value;if($Hash-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$Hash-or-not$bindings.ContainsKey($path)-or$bindings[$path]-cne$Hash){throw ('BINDING_DIAG_REQUIRED_BINDING:'+ $Value)}}
foreach($file in @($m.files)+@([pscustomobject]@{path=$Contract.manifest_path;sha256=$Contract.manifest_sha256})){AssertDiagBound $file.path $file.sha256}
# The shared envelope may dot-source only a contract included in the sealed manifest.
$scopeContractFile=@($m.files|Where-Object {(DiagPath $_.path)-ieq(DiagPath $Contract.scope_contract)})
if($scopeContractFile.Count-ne1){throw 'BINDING_DIAG_SCOPE_CONTRACT_NOT_BOUND'}
AssertDiagBound $Contract.scope_contract ([string]$scopeContractFile[0].sha256)
$controller=DiagPath $Contract.controller
if((DiagPath $Draft.program.controller)-ine$controller){throw 'BINDING_DIAG_CONTROLLER_NOT_ADMITTED'}
$scopePath=DiagPath $profile.scope_path;AssertDiagBound $scopePath ([string]$profile.scope_sha256)
if($bVersionCandidate-and-not$bSettlement){
    # Independently retain the stable permissions before source-owned code runs.
    $scopeBounds=Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if($scopeBounds.profile_id-cne$Contract.profile_id-or$scopeBounds.intent-cne$expectedIntent-or$scopeBounds.phase-cne$Contract.phase-or$scopeBounds.payload_protocol-cne$Contract.payload_protocol-or$scopeBounds.run_id-cne$Draft.run_id-or$scopeBounds.candidate_version-ne$bContractVersion){throw 'B_FRESH_A_CANDIDATE_SCOPE_IDENTITY'}
    foreach($field in @('allow_one_shortcut_start_b','allow_fixed_scr_netload')){if($scopeBounds.$field-isnot[bool]-or-not$scopeBounds.$field){throw ('B_FRESH_A_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
    foreach($field in @('allow_reject_expired_old_dll','allow_normal_close_old_b','allow_exact_save_prompt_discard','allow_load_expired_old_dll','allow_old_stage_mutation','allow_cad_force_kill','allow_a_control','allow_third_cad','allow_business_commands','allow_global_configuration_change','allow_retry','allow_second_controller','allow_offline_job_on_cad')){if($scopeBounds.$field-isnot[bool]-or$scopeBounds.$field){throw ('B_FRESH_A_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
    foreach($pair in @(@('startup_timeout_seconds','startup_timeout_seconds_max'),@('read_timeout_seconds','strict_read_timeout_seconds_max'),@('cleanup_timeout_seconds','cookie_revoke_timeout_seconds_max'),@('outer_timeout_seconds','outer_timeout_seconds_max'),@('bridge_lifetime_seconds','bridge_lifetime_seconds'))){$value=$scopeBounds.($pair[0]);if(($value-isnot[int]-and$value-isnot[long])-or$value-ne$Contract.($pair[1])){throw ('B_FRESH_A_CANDIDATE_SCOPE_BOUND:'+ $pair[0])}}
    if($scopeBounds.allow_persistent_trust-isnot[bool]-or$scopeBounds.allow_persistent_trust-ne$bAlwaysLoad-or$scopeBounds.allow_one_bound_dll_load_once-isnot[bool]-or$scopeBounds.allow_one_bound_dll_load_once-eq$bAlwaysLoad){throw 'B_FRESH_A_CANDIDATE_SCOPE_TRUST'}
    if($bAlwaysLoad){
        foreach($field in @('allow_one_bound_dll_always_load','current_payload_required','exact_dialog_module_owner_required','raw_dialog_evidence_before_click_required','post_load_identity_verification_required')){if($scopeBounds.$field-isnot[bool]-or-not$scopeBounds.$field){throw ('B_FRESH_A_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
        foreach($pair in @(@('bound_LoadOnce_max','bound_DLL_load_once_click_max_count'),@('bound_AlwaysLoad_max','bound_DLL_always_load_click_max_count'))){$value=$scopeBounds.($pair[0]);if(($value-isnot[int]-and$value-isnot[long])-or$value-ne$Contract.($pair[1])){throw 'B_FRESH_A_CANDIDATE_SCOPE_CLICK_BOUND'}}
        if($scopeBounds.module_trust_scope-cne$Contract.module_trust_scope){throw 'B_FRESH_A_CANDIDATE_SCOPE_TRUST'}
    }else{
        if($null-ne$scopeBounds.PSObject.Properties['allow_one_bound_dll_always_load']-and$scopeBounds.allow_one_bound_dll_always_load-cne$false){throw 'B_FRESH_A_CANDIDATE_SCOPE_TRUST'}
        if($null-ne$scopeBounds.PSObject.Properties['bound_AlwaysLoad_max']-and$scopeBounds.bound_AlwaysLoad_max-ne0){throw 'B_FRESH_A_CANDIDATE_SCOPE_CLICK_BOUND'}
    }
    foreach($prefix in @('prior_a_return','prior_a_scope','prior_a_controller','prior_a_owner','prior_a_strict','retired_b_scope','request','module','scr')){
        $pathField=if($prefix-in@('request','module','scr')){$prefix+'_source_path'}else{$prefix+'_path'}
        AssertDiagBound ([string]$scopeBounds.$pathField) ([string]$scopeBounds.($prefix+'_sha256'))
    }
    if($bAlwaysLoad){
        $hostEvidencePrefixes=@('build_receipt','prior_host_return','prior_host_acceptance')
        $explicitCurrentAProof=$null-ne$m.PSObject.Properties['A_pinned_host_required']-or$null-ne$m.PSObject.Properties['preserved_a_binding']-or$null-ne$scopeBounds.PSObject.Properties['A_pinned_host_required']-or$null-ne$scopeBounds.PSObject.Properties['preserved_a_binding']
        if($explicitCurrentAProof){
            # Stable B capabilities and all five current-A evidence bindings were
            # checked above. A B-only bridge need not load a separate host in A.
            # Both sealed producers must explicitly agree; legacy packages keep
            # their original host-evidence requirement when these fields are absent.
            foreach($proof in @($m,$scopeBounds)){
                if($null-eq$proof.PSObject.Properties['A_pinned_host_required']-or$proof.A_pinned_host_required-isnot[bool]-or$proof.A_pinned_host_required-or$null-eq$proof.PSObject.Properties['preserved_a_binding']-or[string]$proof.preserved_a_binding-cne'EXACT_COM_READ_ONLY_NO_HOST'){throw 'B_FRESH_A_CURRENT_COM_PROOF_DECLARATION'}
            }
            $hostEvidencePrefixes=@('build_receipt')
        }
        foreach($prefix in $hostEvidencePrefixes){AssertDiagBound ([string]$scopeBounds.($prefix+'_path')) ([string]$scopeBounds.($prefix+'_sha256'))}
    }
}
if($bSettlement){
    $scopeBounds=Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if($scopeBounds.profile_id-cne$Contract.profile_id-or$scopeBounds.intent-cne$expectedIntent-or$scopeBounds.phase-cne$Contract.phase-or$scopeBounds.run_id-cne$Draft.run_id-or$scopeBounds.candidate_version-ne$bContractVersion){throw 'B_SETTLEMENT_SCOPE_IDENTITY'}
    foreach($field in @('allow_raw_dialog_read','allow_stage_evidence_read','allow_strict_read_when_no_modal','modal_blocks_com')){if($scopeBounds.$field-isnot[bool]-or-not$scopeBounds.$field){throw ('B_SETTLEMENT_REQUIRED:'+ $field)}}
    foreach($field in @('allow_launch','allow_close','allow_save','allow_kill_cad','allow_activate','allow_restore','allow_input','allow_command','allow_netload','allow_load_once','allow_always_load','allow_register','allow_revoke','allow_retry','allow_second_controller','allow_global_configuration_change')){if($scopeBounds.$field-isnot[bool]-or$scopeBounds.$field){throw ('B_SETTLEMENT_FORBIDDEN:'+ $field)}}
    if($scopeBounds.allow_reject-isnot[bool]-or$scopeBounds.allow_reject-ne$bReject){throw 'B_SETTLEMENT_FORBIDDEN:allow_reject'}
    foreach($pair in @(@('outer_timeout_seconds','outer_timeout_seconds_max'),@('owner_max_count','owner_max_count'),@('helper_max_count','helper_max_count'),@('strict_read_max_per_owner','strict_read_max_per_owner'))){$value=$scopeBounds.($pair[0]);if(($value-isnot[int]-and$value-isnot[long])-or$value-ne$Contract.($pair[1])){throw ('B_SETTLEMENT_BOUND:'+ $pair[0])}}
    $owners=@($scopeBounds.owners)
    if($owners.Count-ne2-or@($owners.id|Select-Object -Unique).Count-ne2-or@($owners.id|Where-Object {$_-cnotin@('A','B')}).Count){throw 'B_SETTLEMENT_OWNER_SET'}
    foreach($owner in $owners){
        if(($owner.process_id-isnot[int]-and$owner.process_id-isnot[long])-or$owner.process_id-le0-or($owner.window_handle-isnot[int]-and$owner.window_handle-isnot[long])-or$owner.window_handle-le0-or[string]::IsNullOrWhiteSpace($owner.process_start_time_utc)-or-not[IO.Path]::IsPathRooted($owner.process_image_path)-or-not[IO.Path]::IsPathRooted($owner.document_full_path)-or$owner.protected_sha256-cne$scopeBounds.source_sha256){throw 'B_SETTLEMENT_OWNER_IDENTITY'}
    }
    if($owners[0].process_id-eq$owners[1].process_id-or$owners[0].window_handle-eq$owners[1].window_handle-or$owners[0].document_full_path-ieq$owners[1].document_full_path){throw 'B_SETTLEMENT_OWNER_DUPLICATE'}
    foreach($prefix in @('prior_bridge_return','prior_bridge_scope')){AssertDiagBound ([string]$scopeBounds.($prefix+'_path')) ([string]$scopeBounds.($prefix+'_sha256'))}
    $prior=Get-Content -LiteralPath (DiagPath $scopeBounds.prior_bridge_return_path) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    $priorScope=Get-Content -LiteralPath (DiagPath $scopeBounds.prior_bridge_scope_path) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if($prior.run_id-ceq$Draft.run_id-or$prior.run_id-cne$priorScope.run_id-or$prior.workflow_id-cne$Contract.profile_id-or$priorScope.profile_id-cne$Contract.profile_id){throw 'B_SETTLEMENT_PREDECESSOR_IDENTITY'}
    if($bReject){
        foreach($field in $bRejectFields){$actual=$scopeBounds.PSObject.Properties[$field];if($null-eq$actual-or$null-eq$actual.Value-or$actual.Value.GetType()-ne$Contract.$field.GetType()-or$actual.Value-cne$Contract.$field){throw ('B_REJECT_SCOPE_BOUND:'+ $field)}}
        foreach($prefix in @('prior_settlement_return','prior_settlement_scope','prior_settlement_controller','prior_prompt_windows','prior_prompt_children','prior_prompt_uia')){AssertDiagBound ([string]$scopeBounds.($prefix+'_path')) ([string]$scopeBounds.($prefix+'_sha256'))}
        foreach($prefix in @('request','module')){AssertDiagBound ([string]$scopeBounds.($prefix+'_source_path')) ([string]$scopeBounds.($prefix+'_sha256'))}
        $settled=Get-Content -LiteralPath (DiagPath $scopeBounds.prior_settlement_return_path) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        $settledScope=Get-Content -LiteralPath (DiagPath $scopeBounds.prior_settlement_scope_path) -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
        if($settled.run_id-ceq$Draft.run_id-or$settled.run_id-cne$settledScope.run_id-or$settled.workflow_id-cne$Contract.profile_id-or$settledScope.intent-cne'ReadExistingOwnersAndRawDialogsOnly'-or$settledScope.prior_bridge_return_sha256-cne$scopeBounds.prior_bridge_return_sha256){throw 'B_REJECT_SETTLEMENT_PROVENANCE'}
    }elseif($null-ne$scopeBounds.PSObject.Properties['bound_reject_max']-and$scopeBounds.bound_reject_max-ne0){throw 'B_REJECT_NOT_GRANTED_BY_READ_ONLY_INTENT'}
}
if($pipeVersionCandidate){
    # Do not delegate the stable permission boundary to candidate-owned code.
    $scopeBounds=Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8|ConvertFrom-Json -DateKind String
    if($scopeBounds.profile_id-cne$Contract.profile_id-or$scopeBounds.intent-cne$expectedIntent-or$scopeBounds.run_id-cne$Draft.run_id){throw 'PINNED_CANDIDATE_SCOPE_IDENTITY'}
    $requiredRights=if($pipeAlwaysLoad){@('allow_fixed_a_netload','allow_bound_always_load','allow_read_identity','allow_native_idle_read','allow_dbmod_model_count_read')}elseif($pipeRecovery){@('allow_read_identity','allow_native_idle_read','allow_dialog_text_read','allow_reject_expired_fixed_load')}else{@('allow_fixed_a_netload','allow_bound_load_once','allow_read_identity','allow_native_idle_read','allow_dbmod_model_count_read')}
    foreach($field in $requiredRights){if($scopeBounds.$field-isnot[bool]-or-not$scopeBounds.$field){throw ('PINNED_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
    foreach($field in @('allow_b_control','allow_launch','allow_close','allow_save','allow_kill_cad','allow_activate','allow_restore','allow_input','allow_business_commands','allow_global_trust_change','allow_secureload_change','allow_retry','allow_second_controller','allow_rot_registration','allow_capture')){if($scopeBounds.$field-isnot[bool]-or$scopeBounds.$field){throw ('PINNED_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
    foreach($pair in @(@('netload_send_max','netload_send_max'),@('load_once_click_max','bound_LoadOnce_max'),@('pipe_request_max','pipe_request_max'),@('outer_timeout_seconds','outer_timeout_seconds_max'),@('worker_process_execution_policy','worker_process_execution_policy'))){if($scopeBounds.($pair[0])-cne$Contract.($pair[1])){throw ('PINNED_CANDIDATE_SCOPE_BOUND:'+ $pair[0])}}
    if($pipeAlwaysLoad){
        if($scopeBounds.allow_bound_load_once-isnot[bool]-or$scopeBounds.allow_bound_load_once){throw 'PINNED_CANDIDATE_SCOPE_RIGHT:allow_bound_load_once'}
        if($scopeBounds.always_load_click_max-isnot[long]-and$scopeBounds.always_load_click_max-isnot[int]-or$scopeBounds.always_load_click_max-ne$Contract.bound_AlwaysLoad_max){throw 'PINNED_CANDIDATE_SCOPE_BOUND:always_load_click_max'}
        if($scopeBounds.module_trust_scope-cne$Contract.module_trust_scope){throw 'PINNED_CANDIDATE_SCOPE_BOUND:module_trust_scope'}
        foreach($field in @('current_payload_required','exact_dialog_module_owner_required','raw_dialog_evidence_before_click_required','post_load_identity_verification_required')){if($scopeBounds.$field-isnot[bool]-or-not$scopeBounds.$field){throw ('PINNED_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
    }else{
        # Old LoadOnce and expired-reject packages do not gain persistent trust.
        if($null-ne$scopeBounds.PSObject.Properties['allow_bound_always_load']-and$scopeBounds.allow_bound_always_load-cne$false){throw 'PINNED_CANDIDATE_SCOPE_RIGHT:allow_bound_always_load'}
        if($null-ne$scopeBounds.PSObject.Properties['always_load_click_max']-and$scopeBounds.always_load_click_max-ne0){throw 'PINNED_CANDIDATE_SCOPE_BOUND:always_load_click_max'}
    }
    if($pipeRecovery){
        foreach($field in @('allow_fixed_a_netload','allow_bound_load_once','allow_dbmod_model_count_read')){if($scopeBounds.$field-isnot[bool]-or$scopeBounds.$field){throw ('PINNED_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
        if($scopeBounds.reject_click_max-ne$Contract.bound_reject_max){throw 'PINNED_CANDIDATE_SCOPE_BOUND:reject_click_max'}
        foreach($field in @('prior_payload_expired_required','prior_helper_and_lease_ended_required','raw_dialog_evidence_before_click_required','no_second_bootstrap_same_run')){if($scopeBounds.$field-isnot[bool]-or-not$scopeBounds.$field){throw ('PINNED_CANDIDATE_SCOPE_RIGHT:'+ $field)}}
    }
}
. (DiagPath $Contract.scope_contract)
$scope=Read-CadPreparationScopeV1 $scopePath
$run=Join-Path $Root ('runs/'+$Draft.run_id)
$v=if($pipeBootstrap){Assert-CadPinnedBootstrapScopeV1 $scope $Root $run}elseif($bindingComparison){Assert-CadBindingComparisonScopeV1 $scope $Root $run}elseif($freshDiagnosticV4){Assert-CadFreshDiagnosticScopeV4 $scope $Root $run}elseif($freshDiagnostic){Assert-CadFreshDiagnosticScopeV3 $scope $Root $run}elseif($bBridgeFreshA){& ('Assert-CadBBridgeScopeV'+$bContractVersion) $scope $Root $run}elseif($bBridgeReplacement){Assert-CadBBridgeScopeV3 $scope $Root $run}elseif($bBridgeResume){Assert-CadBBridgeScopeV2 $scope $Root $run}elseif($bBridgeProfile){Assert-CadBBridgeScopeV1 $scope $Root $run}elseif($nativeOmProfile){Assert-CadNativeOmScopeV1 $scope $Root $run}elseif($focusProfile){Assert-CadFocusRegistrationScopeV1 $scope $Root $run}else{Assert-CadBindingDiagnosticScopeV1 $scope $Root $run}
if($v.run_id-cne[string]$Draft.run_id){throw 'BINDING_DIAG_RUN_MISMATCH'}
if($pipeBootstrap){
    Assert-CadPinnedBootstrapDependenciesV1 (Split-Path -Parent (DiagPath $Contract.scope_contract)) $Root
    Assert-CadPinnedBootstrapProtectionV1 $scope $Root
    if((DiagPath $Draft.program.scope)-ine$scopePath-or$Draft.program.scope_sha256-cne$profile.scope_sha256-or(DiagPath $Draft.program.manifest)-ine$manifestPath-or$Draft.program.manifest_sha256-cne$Contract.manifest_sha256){throw 'FRESH_DIAG_NAMED_BINDINGS'}
    if($Draft.governance.workflow_id-cne$Contract.profile_id){throw 'FRESH_DIAG_WORKFLOW'}
    if([string]$Draft.status-cnotin@('DRAFT','READY')){throw 'FRESH_DIAG_ADMISSION_STAGE'}
    if($Draft.status-ceq'READY'-and-not(Test-Path -LiteralPath (Join-Path $run 'execution_handoff.json'))){throw 'PUBLISHED_HANDOFF_REQUIRED'}
    AssertCadPinnedBootstrapRunStageV1 $scope $Root $run $profile.scope_sha256 $(if($Draft.status-ceq'READY'){'Ready'}else{'Candidate'})
}elseif($bBridgeProfile){
    if([string]$profile.phase-cne$scope.phase){throw 'B_BRIDGE_SCOPE_PHASE'}
    if(-not$bSettlement){foreach($prefix in @('prior_a_return','prior_a_scope')){AssertDiagBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))}}
    if($bBridgeResume){foreach($prefix in @('prior_bridge_return','prior_bridge_scope')){AssertDiagBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))}}
    if($bBridgeReplacement){foreach($prefix in @('prior_bridge_return','prior_bridge_scope','prior_bridge_stages','prior_bridge_dialog','prior_bridge_ack','prior_bridge_lease_context','transition_owner_observation')){AssertDiagBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))}}
    foreach($path in @($v.source)+@($v.owners.document_full_path)){$hash=if($bBridgeFreshA){& ('Get-CadBBridgeHashV'+$bContractVersion) $path $Root}elseif($bBridgeReplacement){Get-CadBBridgeHashV3 $path $Root}elseif($bBridgeResume){Get-CadBBridgeHashV2 $path $Root}else{Get-CadBBridgeHashV1 $path $Root};if($hash-cne$scope.source_sha256){throw 'B_BRIDGE_PROTECTED_DISK_HASH'}}
    if($bBridgeFreshA){
        if($profile.phase-cne$Contract.phase-or$scope.phase-cne$Contract.phase-or$Draft.governance.workflow_id-cne$Contract.profile_id){throw 'B_FRESH_A_ADMISSION_PHASE'}
        if((DiagPath $Draft.program.scope)-ine$scopePath-or$Draft.program.scope_sha256-cne$profile.scope_sha256-or(DiagPath $Draft.program.manifest)-ine$manifestPath-or$Draft.program.manifest_sha256-cne$Contract.manifest_sha256){throw 'B_FRESH_A_NAMED_BINDINGS'}
        if([string]$Draft.status-cnotin@('DRAFT','READY')){throw 'B_FRESH_A_ADMISSION_STAGE'}
        if($Draft.status-ceq'READY'-and-not(Test-Path -LiteralPath (Join-Path $run 'execution_handoff.json'))){throw 'PUBLISHED_HANDOFF_REQUIRED'}
        & ('AssertCadBBridgeRunStageV'+$bContractVersion) $scope $Root $run $profile.scope_sha256 $(if($Draft.status-ceq'READY'){'Ready'}else{'Candidate'})
    }
    if(-not$bSettlement){
    if((Test-Path -LiteralPath $v.stage)-or(Test-Path -LiteralPath $v.drawing)){throw 'B_BRIDGE_STAGE_OR_DRAWING_EXISTS'}
    $ancestor=Split-Path -Parent $v.drawing
    while($ancestor.Length-ge$Root.Length){if((Test-Path -LiteralPath $ancestor)-and((Get-Item -LiteralPath $ancestor -Force).Attributes-band[IO.FileAttributes]::ReparsePoint)){throw 'B_BRIDGE_DRAWING_REPARSE_PARENT'};if($ancestor-ieq$Root){break};$ancestor=Split-Path -Parent $ancestor}
    }
}else{
Assert-CadMultiOwnerProtectedHashesV1 $v.identity
if($scopedMetadata){
    if($bindingComparison){Assert-CadBindingComparisonDependenciesV1 (Split-Path -Parent (DiagPath $Contract.scope_contract)) $Root}elseif($freshDiagnosticV4){Assert-CadFreshDiagnosticDependenciesV4 (Split-Path -Parent (DiagPath $Contract.scope_contract)) $Root}else{Assert-CadFreshDiagnosticDependenciesV3 (Split-Path -Parent (DiagPath $Contract.scope_contract)) $Root}
    if((Get-FileHash -LiteralPath (DiagPath $scope.source_path)).Hash-cne$scope.source_sha256){throw 'FRESH_DIAG_SOURCE_HASH'}
    if((DiagPath $Draft.program.scope)-ine$scopePath-or$Draft.program.scope_sha256-cne$profile.scope_sha256-or(DiagPath $Draft.program.manifest)-ine$manifestPath-or$Draft.program.manifest_sha256-cne$Contract.manifest_sha256){throw 'FRESH_DIAG_NAMED_BINDINGS'}
    if($Draft.governance.workflow_id-cne$Contract.profile_id){throw 'FRESH_DIAG_WORKFLOW'}
    if([string]$Draft.status-cnotin@('DRAFT','READY')){throw 'FRESH_DIAG_ADMISSION_STAGE'}
    if($bindingComparison){AssertCadBindingComparisonRunStageV1 $scope $Root $run $profile.scope_sha256 $(if($Draft.status-ceq'READY'){'Ready'}else{'Candidate'})}elseif($freshDiagnosticV4){AssertCadFreshDiagnosticRunStageV4 $scope $Root $run $profile.scope_sha256 $(if($Draft.status-ceq'READY'){'Ready'}else{'Candidate'})}else{AssertCadFreshDiagnosticRunStageV3 $scope $Root $run $profile.scope_sha256 $(if($Draft.status-ceq'READY'){'Ready'}else{'Candidate'})}
}else{
foreach($prefix in @('prior_get_return','prior_get_scope','prior_probe_return')){AssertDiagBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))}
if($focusProfile-or$nativeOmProfile){foreach($prefix in @('prior_diagnostic_return','prior_diagnostic_scope')){AssertDiagBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))}}
if($nativeOmProfile){foreach($prefix in @('prior_focus_return','prior_focus_scope')){AssertDiagBound ([string]$scope.($prefix+'_path')) ([string]$scope.($prefix+'_sha256'))}}
}
}
foreach($field in @('run_directory','controller_receipt')){if([IO.Path]::IsPathRooted([string]$Draft.reporting.$field)){throw 'BINDING_DIAG_REPORT_PROJECT_RELATIVE_REQUIRED'}}
if((DiagPath $Draft.reporting.run_directory)-ine$run-or(DiagPath $Draft.reporting.controller_receipt)-ine(Join-Path $run 'controller_receipt.json')){throw 'BINDING_DIAG_REPORT_PATH'}
foreach($name in @('canonical_open','launch_policy')){
    if($bBridgeProfile-and$null-eq$Draft.PSObject.Properties[$name]){throw 'B_BRIDGE_LAUNCH_POLICY_REQUIRED'}
    if($scopedEnvelope-and$null-eq$Draft.PSObject.Properties[$name]){throw 'FRESH_DIAG_NO_LAUNCH_POLICY_REQUIRED'}
    if($null-ne$Draft.PSObject.Properties[$name]){if($Draft.$name.launch_permitted_for_this_handoff-isnot[bool]-or$Draft.$name.launch_permitted_for_this_handoff-ne$bLaunch){throw 'BINDING_DIAG_LAUNCH_FORBIDDEN'}}
}
if($scopedEnvelope-or$bSettlement){
    foreach($field in @('inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open','standalone_close_allowed')){
        $policyField=$Draft.launch_policy.PSObject.Properties[$field]
        if($null-eq$policyField-or$policyField.Value-isnot[bool]-or$policyField.Value){throw ('FRESH_DIAG_FORBIDDEN_LAUNCH_POLICY:'+ $field)}
    }
}
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput([string]$Draft.action.controller_template,[ref]$tokens,[ref]$parseErrors)
$commands=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]},$true))
if($parseErrors.Count-ne0-or$commands.Count-ne1-or$ast.EndBlock.Statements.Count-ne1-or$ast.EndBlock.Statements[0]-isnot[Management.Automation.Language.PipelineAst]-or$ast.EndBlock.Statements[0].PipelineElements.Count-ne1){throw 'BINDING_DIAG_TEMPLATE_NOT_LITERAL'}
$command=$commands[0]
if($bBridgeFreshA){
    # Frozen terminal envelope adds '&' and resolves a project-relative command token.
    if($command.InvocationOperator-ne[Management.Automation.Language.TokenKind]::Unknown-or[IO.Path]::IsPathRooted([string]$command.GetCommandName())-or[IO.Path]::IsPathRooted([string]$Draft.program.controller)){throw 'B_FRESH_A_ENVELOPE_COMMAND_ABI'}
    if([IO.Path]::GetFullPath((Join-Path $Root $command.GetCommandName()))-ine$controller){throw 'B_FRESH_A_ENVELOPE_COMMAND_ABI'}
}
if($scopedEnvelope){
    if($command.InvocationOperator-ne[Management.Automation.Language.TokenKind]::Unknown-or[IO.Path]::IsPathRooted([string]$command.GetCommandName())-or[IO.Path]::IsPathRooted([string]$Draft.program.controller)){throw 'FRESH_DIAG_ENVELOPE_COMMAND_ABI'}
    if([IO.Path]::GetFullPath((Join-Path $Root $command.GetCommandName()))-ine$controller){throw 'FRESH_DIAG_ENVELOPE_COMMAND_ABI'}
}
if((DiagPath $command.GetCommandName())-ine$controller){throw 'BINDING_DIAG_TEMPLATE_CONTROLLER'}
$callParameters=@{};$elements=$command.CommandElements
for($i=1;$i-lt$elements.Count;$i+=2){
    if($elements[$i]-isnot[Management.Automation.Language.CommandParameterAst]-or$null-ne$elements[$i].Argument-or$i+1-ge$elements.Count){throw 'BINDING_DIAG_TEMPLATE_PARAMETER'}
    $name=$elements[$i].ParameterName;$value=$elements[$i+1]
    if($callParameters.ContainsKey($name)){throw 'BINDING_DIAG_TEMPLATE_DUPLICATE_PARAMETER'}
    if($value-isnot[Management.Automation.Language.StringConstantExpressionAst]){throw 'BINDING_DIAG_TEMPLATE_NOT_LITERAL'}
    $callParameters[$name]=$value.Value
}
if($callParameters.Count-ne3-or@('RunDirectory','ScopePath','ScopeSha256'|Where-Object{-not$callParameters.ContainsKey($_)}).Count){throw 'BINDING_DIAG_TEMPLATE_PARAMETER_SET'}
if(-not[IO.Path]::IsPathRooted($callParameters.RunDirectory)-or-not[IO.Path]::IsPathRooted($callParameters.ScopePath)){throw 'BINDING_DIAG_TEMPLATE_ABSOLUTE_REQUIRED'}
if((DiagPath $callParameters.RunDirectory)-ine$run-or(DiagPath $callParameters.ScopePath)-ine$scopePath-or$callParameters.ScopeSha256-cne[string]$profile.scope_sha256){throw 'BINDING_DIAG_TEMPLATE_SCOPE_MISMATCH'}
[pscustomobject]@{status='PASS';profile_id=$profile.profile_id;intent=$expectedIntent;cad_calls=0;rot_calls=0;foreground_calls=0;capture_calls=0;live_verified=$false}
