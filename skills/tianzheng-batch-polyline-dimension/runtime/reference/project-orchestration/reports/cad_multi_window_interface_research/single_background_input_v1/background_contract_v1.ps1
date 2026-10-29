. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/command_probe_v2/probe_expression_fix_v2.ps1')

function Get-CadSingleBackgroundCapsV1 {
    [pscustomobject]@{serial_executor_required=$true;original_global_guard_unchanged=$true;owner_max_count=1;target_owner_id='A';send_max_count=1;fixed_read_probe_only=$true;native_ack_complete_required=$true;background_at_send_required=$true;foreground_sampling_ms=20;helper_timeout_seconds=15;drain_timeout_seconds=3;job_memory_limit_bytes=536870912;job_active_process_limit=1;foreground_activation_allowed=$false;focus_allowed=$false;keyboard_allowed=$false;database_write_allowed=$false;plugin_load_allowed=$false;launch_allowed=$false;save_close_kill_cad_allowed=$false;retry_allowed=$false;fallback_allowed=$false;concurrency_allowed=$false}
}

function Assert-CadSingleBackgroundScopeV1($Scope,[string]$Root,[string]$RunDirectory) {
    if($Scope.schema_version -ne 1 -or $Scope.profile_id -cne 'CAD-SINGLE-BACKGROUND-INPUT-V1' -or $Scope.intent -cne 'ExecuteSingleBackgroundReadProbe' -or $Scope.phase -cne 'SINGLE_BACKGROUND_READ_ONLY'){throw 'BACKGROUND_SCOPE_IDENTITY'}
    $caps=Get-CadSingleBackgroundCapsV1
    if(@($Scope.capability_bounds.PSObject.Properties).Count -ne @($caps.PSObject.Properties).Count){throw 'BACKGROUND_CAPABILITY_COUNT'}
    foreach($property in $caps.PSObject.Properties){
        $actual=$Scope.capability_bounds.PSObject.Properties[$property.Name]
        if($null -eq $actual -or ($actual.Value|ConvertTo-Json -Compress) -cne ($property.Value|ConvertTo-Json -Compress)){throw ('BACKGROUND_CAPABILITY:'+ $property.Name)}
    }
    if($Scope.run_id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'BACKGROUND_RUN_ID'}
    $run=Assert-CadPreparationPathV1 $RunDirectory $Root
    if($run -ine (Join-Path $Root ('runs/'+$Scope.run_id))){throw 'BACKGROUND_RUN_PATH'}
    $owners=@($Scope.owners)
    if($owners.Count -ne 1 -or (@($Scope.sequence) -join ',') -cne 'A'){throw 'BACKGROUND_SINGLE_OWNER_ONLY'}
    $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$owners;sequence=@('A')}) $Root
    $owner=$identity.by_id['A']
    $admittedCopyRoot=Join-Path $Root 'runs/20261012_multi_owner_a_only_preparation_16/drawings'
    if($owner.document_full_path -ine (Join-Path $admittedCopyRoot 'multi_owner_A_fresh.dwg') -or $owner.protected_sha256 -cne '06F964C0D1B850BE6ED61B8B8C4FAF5F37333F826948F816D5D3CB0925274CB0'){throw 'BACKGROUND_TEST_COPY_NOT_ADMITTED'}
    $prior=Assert-CadPreparationPathV1 $Scope.prior_return_path $Root
    if($prior -ine (Join-Path $Root 'runs/20261013_multi_owner_pinned_pipe_a_bootstrap_17/execution_return.json') -or $Scope.prior_return_sha256 -cne 'CB1F9559AAADC29980440596C0D4BD0408AEE48F649672F271CB7132186BCACF' -or (Get-FileHash $prior).Hash -cne $Scope.prior_return_sha256){throw 'BACKGROUND_ACCEPTED_A_ANCHOR'}
    $previous=Read-CadPreparationScopeV1 $prior
    if($previous.controller_report.status -cne 'PASS_SINGLE_A_HOST_PIPE_AND_CLEANUP_ONLY'){throw 'BACKGROUND_ACCEPTED_A_STATUS'}
    if($Scope.timeout_seconds -ne 15 -or $Scope.sample_interval_ms -ne 20 -or $Scope.observation_settle_ms -ne 200){throw 'BACKGROUND_DEADLINE_OR_SAMPLING'}
    $ops=@($Scope.operations)
    if($ops.Count -ne 1 -or $ops[0].owner -cne 'A' -or $ops[0].id -cne 'A1' -or $ops[0].nonce -cnotmatch '^[a-f0-9]{32}$' -or $ops[0].duration_ms -ne 0){throw 'BACKGROUND_FIXED_OPERATION'}
    if((Assert-CadPreparationPathV1 $ops[0].signal_path $Root) -ine (Join-Path $run 'signals/A1.log')){throw 'BACKGROUND_SIGNAL_PATH'}
    foreach($name in @('command','source','code','lisp','allow_activate','allow_focus','allow_retry')){if($null -ne $Scope.PSObject.Properties[$name]){throw 'BACKGROUND_EXTRA_ACTION'} }
    foreach($file in @($Scope.protected_files)){
        $protectedPath=Assert-CadPreparationPathV1 $file.path $Root
        if($file.sha256 -cnotmatch '^[A-F0-9]{64}$' -or [IO.Path]::GetExtension($protectedPath) -ine '.dwg'){throw 'BACKGROUND_PROTECTION_PATH'}
    }
    [pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$identity;owner=$owner;operation=$ops[0];timeout_seconds=15}
}

function Assert-CadSingleBackgroundProtectionV1($Scope,$Validated,[string]$Root) {
    Assert-CadMultiOwnerProtectedHashesV1 $Validated.identity
    foreach($file in @($Scope.protected_files)){
        $hash=& (Join-Path $Root 'scripts/get_shared_file_sha256_v1.ps1') -Path $file.path
        if($hash -cne $file.sha256){throw 'BACKGROUND_PROTECTED_FILE_CHANGED'}
    }
}

function Assert-CadSingleBackgroundDependenciesV1([string]$Root) {
    $manifestPath=Join-Path $PSScriptRoot 'candidate_manifest.json'
    $manifest=Read-CadPreparationScopeV1 $manifestPath
    if($manifest.id -cne 'CAD-SINGLE-BACKGROUND-INPUT-V1'){throw 'BACKGROUND_MANIFEST_IDENTITY'}
    foreach($file in $manifest.files){
        $path=Assert-CadPreparationPathV1 (Join-Path $Root $file.path) $Root
        if((Get-FileHash -LiteralPath $path).Hash -cne $file.sha256){throw ('BACKGROUND_DEPENDENCY_CHANGED:'+ $file.path)}
    }
}

function Get-CadSingleBackgroundVerdictV1($Worker,[bool]$HelperComplete,[bool]$TargetObserved,[int]$Samples) {
    if(-not $HelperComplete){return 'UNKNOWN_HELPER_EFFECT_NOT_SETTLED'}
    if($null -eq $Worker){return 'UNKNOWN_MISSING_WORKER_RECEIPT'}
    if(-not $Worker.send_boundary_entered){return 'BLOCKED_BEFORE_SEND'}
    if($Worker.status -cne 'PASS_FIXED_READ_NATIVE_ACK_COMPLETE'){return 'UNKNOWN_OR_FAILED_AFTER_SEND'}
    if($TargetObserved){return 'PASS_NATIVE_READ__BACKGROUND_NOT_MET'}
    if($Samples -lt 2){return 'PASS_NATIVE_READ__BACKGROUND_UNVERIFIED'}
    'PASS_SINGLE_BACKGROUND_INPUT_SAMPLED'
}

function Assert-CadSingleBackgroundWorkerReceiptV1($Worker,$Scope,[string]$ScopeSha256) {
    if($Worker.run_id -cne $Scope.run_id -or $Worker.profile_id -cne $Scope.profile_id -or $Worker.scope_sha256 -cne $ScopeSha256){throw 'BACKGROUND_WORKER_RECEIPT_IDENTITY'}
    if($Worker.send_boundary_entered -isnot [bool] -or $Worker.send_call_returned -isnot [bool]){throw 'BACKGROUND_WORKER_SEND_STATE'}
    if($Worker.command_send_count -ne $(if($Worker.send_boundary_entered){1}else{0})){throw 'BACKGROUND_WORKER_SEND_COUNT'}
    foreach($field in @('foreground_activation_count','focus_count','plugin_load_count','cad_launch_save_close_kill_count','retry_count','database_write_count')){if($Worker.$field -ne 0){throw 'BACKGROUND_WORKER_FORBIDDEN_EFFECT'} }
}
