# V4b reproduced ~3.7s in filesystem-only validation, without any CAD call.
# Build a per-validation path index instead of resolving all manifest paths for
# every operation dependency. No cross-call cache; all hashes are re-read.
. (Join-Path $PSScriptRoot 'cad_exact_b_fixed_stage_transport_v2.ps1')

function Get-CadExactBIndexedStageDependenciesV3 {
    Get-CadExactBFixedStageDependenciesV2
    'scripts/cad_exact_b_indexed_stage_transport_v3.ps1'
}

function Assert-CadExactBIndexedStageV3($Scope,$Manifest,[string]$Root) {
    $v=Assert-CadExactBActionScopeV1 $Scope $Root
    Assert-CadExactBManifestV1 $Manifest $Scope $Root
    if ($Scope.invocation_mode -cne 'FIXED_DIMENSION_STAGE_V2') { throw 'EXACT_B_FIXED_MODE' }
    if ($Scope.validation_engine -cne 'INDEXED_FIXED_STAGE_V3') { throw 'EXACT_B_INDEX_ENGINE' }
    foreach($entry in @('scripts/cad_exact_b_fixed_stage_transport_v2.ps1','scripts/cad_exact_b_indexed_stage_transport_v3.ps1')) {
        if (@($Manifest.files|Where-Object path -CEQ $entry).Count -ne 1) { throw 'EXACT_B_INDEX_UNBOUND_ADAPTER' }
    }
    # V1 just rehashed every file and rejected duplicate canonical paths. This
    # local index preserves its path/reparse checks; it is discarded on return.
    $paths=@{}
    foreach($file in $Manifest.files) {$paths[(Resolve-CadExactBProjectPathV1 $Root $file.path)]=$file.sha256}
    $stages=@{DISCOVER='TARGET_SEGMENT_GEOMETRY_INVENTORY';GENERATE='TDIM_TYPED_SEGMENT_BATCH';METRICS='AUDIT_NATIVE_DIM_TEXT_BBOXES';LAYOUT='NET_GENERIC_GRIP_BATCH_MOVE';FINAL_METRICS='AUDIT_NATIVE_DIM_TEXT_BBOXES';VISUAL='DOCUMENT_PREVIEW';CHECKPOINT='SAVE_COPY_CHECKPOINT'}
    $fixedPath=$null;$fixedHash=$null
    foreach($op in $v.operations) {
        if($op.invocation_mode -cne $Scope.invocation_mode -or $op.stage -cnotin @($stages.Keys) -or $op.action -cne $stages[$op.stage]) {throw 'EXACT_B_FIXED_STAGE_ACTION'}
        foreach($name in @('command','expression','script_body','callback','entry_function','module_path','module_command')) {
            if($op.PSObject.Properties.Name -contains $name) {throw 'EXACT_B_FIXED_ARBITRARY_EXECUTABLE_FIELD'}
        }
        $path=Resolve-CadExactBProjectPathV1 $Root $op.bundle_path
        $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$path).Replace('\','/')
        if($relative -cnotmatch '^(scripts|reports)/.+\.lsp$') {throw 'EXACT_B_FIXED_RUN_LOCAL_EXECUTABLE'}
        if($null -eq $fixedPath) {$fixedPath=$path;$fixedHash=$op.bundle_sha256}
        if($path -ine $fixedPath -or $op.bundle_sha256 -cne $fixedHash) {throw 'EXACT_B_FIXED_MULTIPLE_STAGE_ENTRIES'}
        if($op.PSObject.Properties.Name -contains 'load_paths') {
            foreach($load in $op.load_paths) {
                $loadPath=Resolve-CadExactBProjectPathV1 $Root $load
                $loadRelative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$loadPath).Replace('\','/')
                if($loadRelative -cnotmatch '^(scripts|reports|build)/.+\.(lsp|dll|fas|vlx)$') {throw 'EXACT_B_FIXED_RUN_LOCAL_DEPENDENCY'}
                if(-not $paths.ContainsKey($loadPath)) {throw 'EXACT_B_FIXED_UNBOUND_LOAD_DEPENDENCY'}
            }
        }
    }
    $v
}

function Assert-CadExactBIndexedReadyV3($Session) {
    Assert-CadExactBFixedReadyV2 $Session
    $h=Get-Content -LiteralPath (Join-Path $Session.run 'execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
    $routing=Get-Content -LiteralPath (Join-Path $Session.root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String
    $engine=$routing.routes.batch_polyline_dimension.optional_background_transport.fixed_stage_invocation.indexed_validation
    if($engine.id -cne 'INDEXED_FIXED_STAGE_V3' -or $engine.entry -cne 'scripts/cad_exact_b_indexed_stage_transport_v3.ps1' -or $h.exact_b_action_transport.validation_engine -cne $engine.id) {throw 'EXACT_B_INDEX_READY_ADMISSION'}
}

function Open-CadExactBIndexedStageSessionV3 {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,
          [Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256,
          [Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][int]$LeaseControllerPid,
          [Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $sp=Resolve-CadExactBProjectPathV1 $root $ScopePath;$mp=Resolve-CadExactBProjectPathV1 $root $ManifestPath
    $scope=Read-CadExactBBoundJsonV1 $sp $ScopeSha256;$manifest=Read-CadExactBBoundJsonV1 $mp $ManifestSha256
    $v=Assert-CadExactBIndexedStageV3 $scope $manifest $root
    $pre=[pscustomobject]@{root=$root;run=$v.run;scope=$scope;scope_path=$sp;scope_hash=$ScopeSha256;manifest_path=$mp;manifest_hash=$ManifestSha256}
    Assert-CadExactBIndexedReadyV3 $pre
    $validationMs=$clock.Elapsed.TotalMilliseconds
    # Frozen V1 performs the original full strict admission, OwnJob, lease,
    # protected hashes, exact File ROT lookup and held-document comparison.
    $session=Open-CadExactBActionSessionV1 @PSBoundParameters
    $session|Add-Member NoteProperty transport_timings_v3 ([ordered]@{open_validation_ms=$validationMs;open_v1_binding_and_checks_ms=($clock.Elapsed.TotalMilliseconds-$validationMs)})
    $session
}

function Write-CadExactBIndexedTimingV3($Session,[string]$Phase,[double]$Milliseconds) {
    $Session.transport_timings_v3[$Phase]=$Milliseconds
    $row=@{run_id=$Session.scope.run_id;operation_id=$Session.operation.id;nonce=$Session.operation.nonce;phase=$Phase;elapsed_ms=$Milliseconds;worker_pid=$PID;at_utc=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::AppendAllText((Join-Path $Session.run ('transport_timing_'+$Session.operation.id+'.jsonl')),($row|ConvertTo-Json -Compress)+"`n",[Text.UTF8Encoding]::new($false))
}

function Invoke-CadExactBIndexedStageSendV3($Session) {
    $root=$Session.root;$LeaseControllerPid=$Session.controller_pid;$LeaseControllerStartUtc=$Session.controller_start;$script:validated=$Session.identity
    $clock=[Diagnostics.Stopwatch]::StartNew()
    Assert-CadExactBIndexedReadyV3 $Session;Assert-ReadWorkerLeaseV1
    Write-CadExactBIndexedTimingV3 $Session 'send_ready_lease_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    $scope=Read-CadExactBBoundJsonV1 $Session.scope_path $Session.scope_hash
    $manifest=Read-CadExactBBoundJsonV1 $Session.manifest_path $Session.manifest_hash
    $v=Assert-CadExactBIndexedStageV3 $scope $manifest $root
    $fresh=@($v.operations|Where-Object id -CEQ $Session.operation.id)
    if($fresh.Count-ne1-or($fresh[0]|ConvertTo-Json -Depth 12 -Compress)-cne($Session.operation|ConvertTo-Json -Depth 12 -Compress)-or($v.identity.owners|ConvertTo-Json -Depth 12 -Compress)-cne($Session.identity.owners|ConvertTo-Json -Depth 12 -Compress)-or$Session.scope.run_id-cne$scope.run_id) {throw 'EXACT_B_FIXED_SESSION_MUTATED'}
    Write-CadExactBIndexedTimingV3 $Session 'send_fresh_scope_manifest_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    # No RPC removed: V4b did not prove RPCs caused the filesystem-only cost.
    $Session.binding=Get-CadProbeFileBindingV3 $Session.identity.owners $Session.identity.by_id.B $Session.lookup $Session.bind_state {Get-CadExactBSnapshotsV1 $Session} {param($event)$Session.events.Add($event)}
    Write-CadExactBIndexedTimingV3 $Session 'send_strict_binding_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    Assert-CadBBackgroundForegroundV3 ([CadSingleBackgroundV1.Native]::Read([long]$Session.identity.by_id.B.window_handle)) $Session.identity.by_id.B
    $expression=New-CadExactBFixedStageExpressionV2 $Session
    Write-CadExactBIndexedTimingV3 $Session 'send_expression_and_foreground_ms' $clock.Elapsed.TotalMilliseconds
    $clock.Restart()
    $result=Invoke-CadExactBReservedSendV1 $Session $expression
    Write-CadExactBIndexedTimingV3 $Session 'send_reservation_and_com_return_ms' $clock.Elapsed.TotalMilliseconds
    $result
}
