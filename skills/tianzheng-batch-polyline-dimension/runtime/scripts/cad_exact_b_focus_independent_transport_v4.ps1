# Exact-owner execution and foreground observation are separate contracts.
# V1-V3 remain frozen; this explicit variant never activates a window or uses
# keyboard/mouse input. Foreground/unknown samples are evidence, not admission.
. (Join-Path $PSScriptRoot 'cad_exact_b_indexed_stage_transport_v3.ps1')

function Get-CadExactBFocusIndependentDependenciesV4 {
    Get-CadExactBIndexedStageDependenciesV3
    'scripts/cad_exact_b_focus_independent_transport_v4.ps1'
}

function Assert-CadExactBFocusPolicyV4($Scope) {
    if ($Scope.PSObject.Properties.Name -cnotcontains 'focus_policy' -or $Scope.focus_policy -cne 'OBSERVE_ONLY') { throw 'EXACT_B_FOCUS_POLICY_OPT_IN_REQUIRED' }
}

function Assert-CadExactBFocusIndependentScopeV4($Scope,$Manifest,[string]$Root) {
    Assert-CadExactBFocusPolicyV4 $Scope
    $v=Assert-CadExactBIndexedStageV3 $Scope $Manifest $Root
    if (@($Manifest.files|Where-Object path -CEQ 'scripts/cad_exact_b_focus_independent_transport_v4.ps1').Count -ne 1) { throw 'EXACT_B_FOCUS_UNBOUND_ADAPTER' }
    $v
}

function Assert-CadExactBFocusIndependentReadyV4($Session) {
    Assert-CadExactBFocusPolicyV4 $Session.scope
    Assert-CadExactBIndexedReadyV3 $Session
    $h=Get-Content -LiteralPath (Join-Path $Session.run 'execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
    $routing=Get-Content -LiteralPath (Join-Path $Session.root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String
    $fixed=$routing.routes.batch_polyline_dimension.optional_background_transport.fixed_stage_invocation
    if ($fixed.PSObject.Properties.Name -cnotcontains 'focus_observation' -or $h.exact_b_action_transport.PSObject.Properties.Name -cnotcontains 'focus_policy') { throw 'EXACT_B_FOCUS_READY_ADMISSION' }
    $mode=$fixed.focus_observation
    if ($mode.id -cne 'EXACT_OWNER_FOCUS_OBSERVATION_V4' -or $mode.entry -cne 'scripts/cad_exact_b_focus_independent_transport_v4.ps1' -or $mode.focus_policy -cne 'OBSERVE_ONLY' -or $h.exact_b_action_transport.focus_policy -cne $Session.scope.focus_policy) { throw 'EXACT_B_FOCUS_READY_ADMISSION' }
}

function Open-CadExactBFocusIndependentSessionV4 {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,
          [Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256,
          [Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][int]$LeaseControllerPid,
          [Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $sp=Resolve-CadExactBProjectPathV1 $root $ScopePath;$mp=Resolve-CadExactBProjectPathV1 $root $ManifestPath
    $scope=Read-CadExactBBoundJsonV1 $sp $ScopeSha256;$manifest=Read-CadExactBBoundJsonV1 $mp $ManifestSha256
    $v=Assert-CadExactBFocusIndependentScopeV4 $scope $manifest $root
    $pre=[pscustomobject]@{root=$root;run=$v.run;scope=$scope;scope_path=$sp;scope_hash=$ScopeSha256;manifest_path=$mp;manifest_hash=$ManifestSha256}
    Assert-CadExactBFocusIndependentReadyV4 $pre
    $validationMs=$clock.Elapsed.TotalMilliseconds
    # Identical original OwnJob, lease, protected files, exact File ROT and
    # held-document admission; no additional COM request or foreground action.
    $session=Open-CadExactBActionSessionV1 @PSBoundParameters
    $session|Add-Member NoteProperty transport_timings_v3 ([ordered]@{open_validation_ms=$validationMs;open_v1_binding_and_checks_ms=($clock.Elapsed.TotalMilliseconds-$validationMs)})
    $session
}

function Get-CadExactBFocusSampleV4([long]$WindowHandle) {
    # OS-only observation. Failure to observe focus must not claim background.
    try { [CadSingleBackgroundV1.Native]::Read($WindowHandle) }
    catch { [pscustomobject]@{hwnd=0L;pid=0;observation_error=$_.Exception.Message} }
}

function ConvertTo-CadExactBFocusObservationV4($Sample,$Owner) {
    $state='UNKNOWN';$background=$null;$hwnd=0L;$foregroundPid=0
    if ($null -ne $Sample) {
        if ($Sample.PSObject.Properties.Name -contains 'hwnd') { $hwnd=[long]$Sample.hwnd }
        if ($Sample.PSObject.Properties.Name -contains 'pid') { $foregroundPid=[int]$Sample.pid }
    }
    if ($hwnd -gt 0 -and $foregroundPid -gt 0) {
        if ($foregroundPid -eq $Owner.process_id) { $state='TARGET_OWNER_FOREGROUND';$background=$false }
        else { $state='OTHER_FOREGROUND';$background=$true }
    }
    [pscustomobject]@{event='FOCUS_OBSERVATION';policy='OBSERVE_ONLY';state=$state;hwnd=$hwnd;pid=$foregroundPid;exact_target_hwnd=($hwnd -eq [long]$Owner.window_handle);background_at_sample=$background;continuous_background_proven=$false;business_admission_affected=$false;at_utc=[DateTime]::UtcNow.ToString('o')}
}

function Invoke-CadExactBFocusIndependentSendV4($Session) {
    $root=$Session.root;$LeaseControllerPid=$Session.controller_pid;$LeaseControllerStartUtc=$Session.controller_start;$script:validated=$Session.identity
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Assert-CadExactBFocusIndependentReadyV4 $Session;Assert-ReadWorkerLeaseV1
    Write-CadExactBIndexedTimingV3 $Session 'send_ready_lease_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    $scope=Read-CadExactBBoundJsonV1 $Session.scope_path $Session.scope_hash
    $manifest=Read-CadExactBBoundJsonV1 $Session.manifest_path $Session.manifest_hash
    $v=Assert-CadExactBFocusIndependentScopeV4 $scope $manifest $root
    $fresh=@($v.operations|Where-Object id -CEQ $Session.operation.id)
    if($fresh.Count-ne1-or($fresh[0]|ConvertTo-Json -Depth 12 -Compress)-cne($Session.operation|ConvertTo-Json -Depth 12 -Compress)-or($v.identity.owners|ConvertTo-Json -Depth 12 -Compress)-cne($Session.identity.owners|ConvertTo-Json -Depth 12 -Compress)-or$Session.scope.run_id-cne$scope.run_id) {throw 'EXACT_B_FIXED_SESSION_MUTATED'}
    Write-CadExactBIndexedTimingV3 $Session 'send_fresh_scope_manifest_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    $Session.binding=Get-CadProbeFileBindingV3 $Session.identity.owners $Session.identity.by_id.B $Session.lookup $Session.bind_state {Get-CadExactBSnapshotsV1 $Session} {param($event)$Session.events.Add($event)}
    Write-CadExactBIndexedTimingV3 $Session 'send_strict_binding_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    $focus=ConvertTo-CadExactBFocusObservationV4 (Get-CadExactBFocusSampleV4 ([long]$Session.identity.by_id.B.window_handle)) $Session.identity.by_id.B
    $Session.events.Add($focus)
    [IO.File]::AppendAllText((Join-Path $Session.run ('focus_observation_'+$Session.operation.id+'.jsonl')),($focus|ConvertTo-Json -Compress)+"`n",[Text.UTF8Encoding]::new($false))
    $expression=New-CadExactBFixedStageExpressionV2 $Session
    Write-CadExactBIndexedTimingV3 $Session 'send_expression_and_foreground_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    $result=Invoke-CadExactBReservedSendV1 $Session $expression
    Write-CadExactBIndexedTimingV3 $Session 'send_reservation_and_com_return_ms' $clock.Elapsed.TotalMilliseconds
    $result
}
