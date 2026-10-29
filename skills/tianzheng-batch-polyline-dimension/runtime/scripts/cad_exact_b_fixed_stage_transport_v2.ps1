# Opt-in data-only invocation adapter. V1 binding, ownership and reservation stay
# unchanged; no per-run executable LSP wrapper is created or loaded by V2.
. (Join-Path $PSScriptRoot 'cad_exact_b_action_transport_v1.ps1')

function Get-CadExactBFixedStageDependenciesV2 {
    Get-CadExactBActionDependenciesV1
    'scripts/cad_exact_b_fixed_stage_transport_v2.ps1'
}

function ConvertTo-CadExactBLispStringV2([string]$Value) {
    if ($null -eq $Value -or $Value -match '[\x00-\x1F\x7F]') { throw 'EXACT_B_FIXED_CONTROL_CHARACTER' }
    '"'+$Value.Replace('\','\\').Replace('"','\"')+'"'
}

function Assert-CadExactBFixedStageV2($Scope,$Manifest,[string]$Root) {
    $v=Assert-CadExactBActionScopeV1 $Scope $Root
    Assert-CadExactBManifestV1 $Manifest $Scope $Root
    if ($Scope.invocation_mode -cne 'FIXED_DIMENSION_STAGE_V2') { throw 'EXACT_B_FIXED_MODE' }
    $entry='scripts/cad_exact_b_fixed_stage_transport_v2.ps1'
    if (@($Manifest.files|Where-Object path -CEQ $entry).Count -ne 1) { throw 'EXACT_B_FIXED_UNBOUND_ADAPTER' }
    $stages=@{
        DISCOVER='TARGET_SEGMENT_GEOMETRY_INVENTORY'
        GENERATE='TDIM_TYPED_SEGMENT_BATCH'
        METRICS='AUDIT_NATIVE_DIM_TEXT_BBOXES'
        LAYOUT='NET_GENERIC_GRIP_BATCH_MOVE'
        FINAL_METRICS='AUDIT_NATIVE_DIM_TEXT_BBOXES'
        VISUAL='DOCUMENT_PREVIEW'
        CHECKPOINT='SAVE_COPY_CHECKPOINT'
    }
    $fixedPath=$null;$fixedHash=$null
    foreach ($op in $v.operations) {
        if ($op.invocation_mode -cne $Scope.invocation_mode -or $op.stage -cnotin @($stages.Keys) -or $op.action -cne $stages[$op.stage]) { throw 'EXACT_B_FIXED_STAGE_ACTION' }
        foreach ($name in @('command','expression','script_body','callback','entry_function','module_path','module_command')) {
            if ($op.PSObject.Properties.Name -contains $name) { throw 'EXACT_B_FIXED_ARBITRARY_EXECUTABLE_FIELD' }
        }
        $path=Resolve-CadExactBProjectPathV1 $Root $op.bundle_path
        $relative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$path).Replace('\','/')
        if ($relative -cnotmatch '^(scripts|reports)/.+\.lsp$') { throw 'EXACT_B_FIXED_RUN_LOCAL_EXECUTABLE' }
        if ($null -eq $fixedPath) {$fixedPath=$path;$fixedHash=$op.bundle_sha256}
        if ($path -ine $fixedPath -or $op.bundle_sha256 -cne $fixedHash) { throw 'EXACT_B_FIXED_MULTIPLE_STAGE_ENTRIES' }
        if ($op.PSObject.Properties.Name -contains 'load_paths') {
            foreach ($load in $op.load_paths) {
                $loadPath=Resolve-CadExactBProjectPathV1 $Root $load
                $loadRelative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Root),$loadPath).Replace('\','/')
                if ($loadRelative -cnotmatch '^(scripts|reports|build)/.+\.(lsp|dll|fas|vlx)$') { throw 'EXACT_B_FIXED_RUN_LOCAL_DEPENDENCY' }
                if (@($Manifest.files|Where-Object {(Resolve-CadExactBProjectPathV1 $Root $_.path) -ieq $loadPath}).Count -ne 1) { throw 'EXACT_B_FIXED_UNBOUND_LOAD_DEPENDENCY' }
            }
        }
    }
    $v
}

function Assert-CadExactBFixedReadyV2($Session) {
    Assert-CadExactBReadyV1 $Session
    $h=Get-Content -LiteralPath (Join-Path $Session.run 'execution_handoff.json') -Raw|ConvertFrom-Json -DateKind String
    $routing=Get-Content -LiteralPath (Join-Path $Session.root 'config/cad_command_research_routing_v1.json') -Raw|ConvertFrom-Json -DateKind String
    $fixed=$routing.routes.batch_polyline_dimension.optional_background_transport.fixed_stage_invocation
    if ($fixed.mode -cne 'FIXED_DIMENSION_STAGE_V2' -or $fixed.entry -cne 'scripts/cad_exact_b_fixed_stage_transport_v2.ps1' -or $h.exact_b_action_transport.invocation_mode -cne $fixed.mode) { throw 'EXACT_B_FIXED_READY_ADMISSION' }
}

function Open-CadExactBFixedStageSessionV2 {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,
          [Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256,
          [Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][int]$LeaseControllerPid,
          [Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName)
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $sp=Resolve-CadExactBProjectPathV1 $root $ScopePath;$mp=Resolve-CadExactBProjectPathV1 $root $ManifestPath
    $scope=Read-CadExactBBoundJsonV1 $sp $ScopeSha256;$manifest=Read-CadExactBBoundJsonV1 $mp $ManifestSha256
    $v=Assert-CadExactBFixedStageV2 $scope $manifest $root
    $pre=[pscustomobject]@{root=$root;run=$v.run;scope=$scope;scope_path=$sp;scope_hash=$ScopeSha256;manifest_path=$mp;manifest_hash=$ManifestSha256}
    # Opt-in is checked before V1 is allowed to acquire any native/COM object.
    Assert-CadExactBFixedReadyV2 $pre
    Open-CadExactBActionSessionV1 @PSBoundParameters
}

function New-CadExactBFixedStageExpressionV2($Session) {
    # The only executable symbol is a fixed private stage dispatcher. Every
    # parameter is derived from the immutable scope/owner identity, not code.
    $root=[IO.Path]::GetFullPath($Session.root).TrimEnd('\','/')
    $run=Resolve-CadExactBProjectPathV1 $root ('runs/'+$Session.scope.run_id)
    $entry=Resolve-CadExactBProjectPathV1 $root $Session.operation.bundle_path
    $drawing=$Session.identity.by_id.B.document_full_path.Replace('\','/')
    $values=[ordered]@{
        'cxbg:root'=$root.Replace('\','/')
        'cxbg:run-path'=$run.Replace('\','/')
        'cxbg:run-id'=$Session.scope.run_id
        'cxbg:operation-id'=$Session.operation.id
        'cxbg:nonce'=$Session.operation.nonce
        'cxbg:signal-path'=(Join-Path $run ('signals/'+$Session.operation.id+'.log')).Replace('\','/')
        'cxbg:expected-drawing'=$drawing
        'cxbg:stage'=$Session.operation.stage
    }
    $assignments=@(foreach ($key in $values.Keys) {$key+' '+(ConvertTo-CadExactBLispStringV2 $values[$key])}) -join ' '
    $hwnd=[long]$Session.identity.by_id.B.window_handle
    $body='(progn (setq '+$assignments+') (load '+(ConvertTo-CadExactBLispStringV2 $entry.Replace('\','/'))+') (cxbg:run-stage))'
    '(progn (vl-load-com) (if (and (= (rem (+ (vla-get-HWND (vlax-get-acad-object)) 4294967296.0) 4294967296.0) '+$hwnd+') (= (strcase (vl-string-translate "\\" "/" (vla-get-FullName (vla-get-ActiveDocument (vlax-get-acad-object))))) (strcase '+(ConvertTo-CadExactBLispStringV2 $drawing)+'))) '+$body+' (princ "EXACT_B_NATIVE_OWNER_CHANGED_NO_ACTION")) (princ))'+"`n"
}

function Invoke-CadExactBFixedStageSendV2($Session) {
    $root=$Session.root;$LeaseControllerPid=$Session.controller_pid;$LeaseControllerStartUtc=$Session.controller_start;$script:validated=$Session.identity
    Assert-CadExactBFixedReadyV2 $Session;Assert-ReadWorkerLeaseV1
    $scope=Read-CadExactBBoundJsonV1 $Session.scope_path $Session.scope_hash
    $manifest=Read-CadExactBBoundJsonV1 $Session.manifest_path $Session.manifest_hash
    $v=Assert-CadExactBFixedStageV2 $scope $manifest $root
    $fresh=@($v.operations|Where-Object id -CEQ $Session.operation.id)
    if ($fresh.Count -ne 1 -or ($fresh[0]|ConvertTo-Json -Depth 12 -Compress) -cne ($Session.operation|ConvertTo-Json -Depth 12 -Compress) -or ($v.identity.owners|ConvertTo-Json -Depth 12 -Compress) -cne ($Session.identity.owners|ConvertTo-Json -Depth 12 -Compress) -or $Session.scope.run_id -cne $scope.run_id) { throw 'EXACT_B_FIXED_SESSION_MUTATED' }
    $Session.binding=Get-CadProbeFileBindingV3 $Session.identity.owners $Session.identity.by_id.B $Session.lookup $Session.bind_state {Get-CadExactBSnapshotsV1 $Session} {param($event)$Session.events.Add($event)}
    Assert-CadBBackgroundForegroundV3 ([CadSingleBackgroundV1.Native]::Read([long]$Session.identity.by_id.B.window_handle)) $Session.identity.by_id.B
    Invoke-CadExactBReservedSendV1 $Session (New-CadExactBFixedStageExpressionV2 $Session)
}
