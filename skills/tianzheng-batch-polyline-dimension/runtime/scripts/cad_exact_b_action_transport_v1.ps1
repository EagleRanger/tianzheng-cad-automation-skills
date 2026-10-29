. (Join-Path $PSScriptRoot 'common/CadPublicBuildTrust.ps1')
# Shared transport only. Import inside one bounded OwnHelperJob worker owned by
# the existing execution controller. This is NOT a controller, READY or business
# acceptance. Old single-owner whitelist and geometry/layout recipes stay frozen.

function Get-CadExactBActionDependenciesV1 {
    @(
        'scripts/cad_exact_b_action_transport_v1.ps1'
        'reports/cad_multi_window_interface_research/command_probe_v1/strict_binding_adapter_v1.ps1'
        'reports/cad_multi_window_interface_research/v3/cad_multi_owner_preflight_contract_v3.ps1'
        'reports/cad_multi_window_interface_research/v2/cad_exact_target_candidate_v2.ps1'
        'reports/cad_multi_window_interface_research/read_session_v8/file_rot_backend_v5.ps1'
        'reports/cad_multi_window_interface_research/read_session_v8/file_document_normalizer_v8.ps1'
        'reports/cad_multi_window_interface_research/read_session_v8/com_identity_v1.ps1'
        'reports/cad_multi_window_interface_research/binding_diagnostic_v2/diagnostic_contract_v1.ps1'
        'reports/cad_multi_window_interface_research/lifecycle_v1/preparation_contract_v1.ps1'
        'reports/cad_multi_window_interface_research/b_existing_settlement_v4/selector_trace_v4.ps1'
        'reports/cad_multi_window_interface_research/command_probe_v3/file_binding_v3.ps1'
        'reports/cad_multi_window_interface_research/single_background_input_v3/send_once_v3.ps1'
        'reports/cad_multi_window_interface_research/single_background_input_v3/BackgroundNative.cs'
        'reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll'
        'scripts/get_shared_file_sha256_v1.ps1'
    )
}

function Resolve-CadExactBProjectPathV1([string]$Root,[string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'EXACT_B_PATH_EMPTY' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $full = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Path)) {$Path} else {Join-Path $base $Path}))
    if (-not $full.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'EXACT_B_PATH_OUTSIDE_PROJECT' }
    $cursor=$full
    while ($cursor.Length -gt $base.Length) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'EXACT_B_REPARSE_PATH' }
        $cursor=Split-Path -Parent $cursor
    }
    $full
}

function Read-CadExactBBoundJsonV1([string]$Path,[string]$Hash) {
    if ($Hash -cnotmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash -cne $Hash) { throw 'EXACT_B_BOUND_HASH' }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
}

function Assert-CadExactBActionScopeV1($Scope,[string]$Root) {
    if ($Scope.schema_version -ne 1 -or $Scope.profile_id -cne 'CAD-DIM-EXACT-B-ACTION-V1' -or $Scope.route -cne 'batch_polyline_dimension' -or $Scope.target_owner -cne 'B') { throw 'EXACT_B_SCOPE_IDENTITY' }
    if ($Scope.run_id -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$') { throw 'EXACT_B_RUN_ID' }
    foreach ($flag in @('parallel_writes','retry','foreground_input','global_rot_fallback','save_in_place','close_or_kill_cad')) {
        if ($Scope.$flag -isnot [bool] -or $Scope.$flag) { throw "EXACT_B_FORBIDDEN:$flag" }
    }
    $identity=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
    if ($identity.owners.Count -ne 2) { throw 'EXACT_B_TWO_DECLARED_OWNERS_REQUIRED' }
    # Only the identity schema is borrowed above, not its read-only authority.
    $allowed=@('TARGET_SEGMENT_GEOMETRY_INVENTORY','TDIM_TYPED_SEGMENT_BATCH','AUDIT_NATIVE_DIM_TEXT_BBOXES','NET_NATIVE_GRIP_INVENTORY','NET_GENERIC_GRIP_BATCH_MOVE','REGEN','MODULE_PRELOAD','DOCUMENT_PREVIEW','SAVE_COPY_CHECKPOINT')
    $ops=@($Scope.operations);$ids=@{};$nonces=@{}
    if ($ops.Count -lt 1 -or $ops.Count -gt 24) { throw 'EXACT_B_OPERATION_COUNT' }
    foreach ($op in $ops) {
        if ($op.id -cnotmatch '^[A-Za-z][A-Za-z0-9_]{0,39}$' -or $ids.ContainsKey($op.id) -or $op.owner -cne 'B' -or $op.action -cnotin $allowed) { throw 'EXACT_B_OPERATION_ID_OR_ACTION' }
        if ($op.nonce -cnotmatch '^[a-f0-9]{32}$' -or $nonces.ContainsKey($op.nonce)) { throw 'EXACT_B_OPERATION_NONCE' }
        $bundle=Resolve-CadExactBProjectPathV1 $Root $op.bundle_path
        if ([IO.Path]::GetExtension($bundle) -ine '.lsp' -or $op.bundle_sha256 -cnotmatch '^[A-F0-9]{64}$') { throw 'EXACT_B_BUNDLE_IDENTITY' }
        $ids[$op.id]=$true;$nonces[$op.nonce]=$true
    }
    [pscustomobject]@{identity=$identity;run=(Join-Path $Root ('runs/'+$Scope.run_id));operations=$ops}
}

function Assert-CadExactBManifestV1($Manifest,$Scope,[string]$Root) {
    if ($Manifest.transport_id -cne 'CAD-DIM-EXACT-B-ACTION-V1') { throw 'EXACT_B_MANIFEST_PROFILE' }
    $paths=@{}
    foreach ($file in @($Manifest.files)) {
        $path=Resolve-CadExactBProjectPathV1 $Root $file.path
        if ($paths.ContainsKey($path) -or $file.sha256 -cnotmatch '^[A-F0-9]{64}$' -or (Get-FileHash -LiteralPath $path).Hash -cne $file.sha256) { throw "EXACT_B_MANIFEST_FILE:$($file.path)" }
        $paths[$path]=$file.sha256
    }
    foreach ($relative in Get-CadExactBActionDependenciesV1) {
        if (-not $paths.ContainsKey((Resolve-CadExactBProjectPathV1 $Root $relative))) { throw "EXACT_B_UNBOUND_DEPENDENCY:$relative" }
    }
    foreach ($op in $Scope.operations) {
        $path=Resolve-CadExactBProjectPathV1 $Root $op.bundle_path
        if (-not $paths.ContainsKey($path) -or $paths[$path] -cne $op.bundle_sha256) { throw 'EXACT_B_UNBOUND_BUNDLE' }
    }
}

function Assert-CadExactBReadyV1($Session) {
    $h=Get-Content -LiteralPath (Join-Path $Session.run 'execution_handoff.json') -Raw | ConvertFrom-Json -DateKind String
    $claim=Get-Content -LiteralPath (Join-Path $Session.run 'execution_controller_claim.json') -Raw | ConvertFrom-Json -DateKind String
    $current=Get-Content -LiteralPath (Join-Path $Session.root 'config/current_execution_handoff.json') -Raw | ConvertFrom-Json -DateKind String
    if ((Test-Path -LiteralPath (Join-Path $Session.run 'execution_return.json')) -or $h.schema_version -lt 3 -or $h.status -cne 'READY' -or $current.status -cne 'READY' -or $current.run_id -cne $Session.scope.run_id -or $h.run_id -cne $Session.scope.run_id) { throw 'EXACT_B_NOT_CURRENT_READY_OR_REPLAY' }
    $routing=Get-Content -LiteralPath (Join-Path $Session.root 'config/cad_command_research_routing_v1.json') -Raw | ConvertFrom-Json -DateKind String
    $route=$routing.routes.batch_polyline_dimension
    if ($h.issuer.thread_id -cne $route.ready_issuer_thread_id -or $h.target.thread_id -cne $routing.execution.thread_id) { throw 'EXACT_B_ROUTE_MISMATCH' }
    if ($route.optional_background_transport.profile_id -cne $Session.scope.profile_id -or $route.optional_background_transport.entry -cne 'scripts/cad_exact_b_action_transport_v1.ps1') { throw 'EXACT_B_SHARED_ADMISSION_MISMATCH' }
    if ($current.immutable_handoff_sha256 -cne (Get-FileHash (Join-Path $Session.run 'execution_handoff.json')).Hash -or $h.program.scope_sha256 -cne $Session.scope_hash -or $h.program.manifest_sha256 -cne $Session.manifest_hash -or $h.exact_b_action_transport.profile_id -cne $Session.scope.profile_id) { throw 'EXACT_B_READY_BINDING' }
    if ((Resolve-CadExactBProjectPathV1 $Session.root $h.program.scope) -ine $Session.scope_path -or (Resolve-CadExactBProjectPathV1 $Session.root $h.program.manifest) -ine $Session.manifest_path) { throw 'EXACT_B_READY_PATH' }
    if ($claim.run_id -cne $h.run_id -or $claim.handoff_id -cne $h.handoff_id -or $claim.controller_attempt_reserved -isnot [bool] -or -not $claim.controller_attempt_reserved) { throw 'EXACT_B_CONTROLLER_CLAIM' }
}

function Open-CadExactBActionSessionV1 {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,
          [Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256,
          [Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][int]$LeaseControllerPid,
          [Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName)
    $ErrorActionPreference='Stop';Set-StrictMode -Version Latest
    Assert-CadPublicReceiverConfiguration -Root $Root
    $root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $sp=Resolve-CadExactBProjectPathV1 $root $ScopePath;$mp=Resolve-CadExactBProjectPathV1 $root $ManifestPath
    $scope=Read-CadExactBBoundJsonV1 $sp $ScopeSha256;$manifest=Read-CadExactBBoundJsonV1 $mp $ManifestSha256
    Assert-CadExactBManifestV1 $manifest $scope $root
    $base=Join-Path $root 'reports/cad_multi_window_interface_research'
    $v=Assert-CadExactBActionScopeV1 $scope $root;$script:validated=$v.identity
    $op=@($v.operations|Where-Object id -CEQ $OperationId)
    if ($op.Count -ne 1) { throw 'EXACT_B_OPERATION_UNKNOWN' }
    $session=[pscustomobject]@{root=$root;run=$v.run;scope=$scope;scope_path=$sp;scope_hash=$ScopeSha256;manifest_path=$mp;manifest_hash=$ManifestSha256;operation=$op[0];identity=$v.identity;controller_pid=$LeaseControllerPid;controller_start=$LeaseControllerStartUtc;job_name=$JobName;lookup=$null;binding=$null;bind_state=[pscustomobject]@{bind_count=0};send=[pscustomobject]@{entered=$false;returned=$false};events=[Collections.Generic.List[object]]::new()}
    Assert-CadExactBReadyV1 $session
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'MTA') { throw 'EXACT_B_MTA_REQUIRED' }
    $lib=Join-Path $base 'command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll'
    if ((Get-FileHash $lib).Hash -cne (Get-CadPublicTrustedModuleHash -Root $root -RelativePath 'reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll')) { throw 'EXACT_B_OWN_JOB_LIBRARY' }
    $null=[Reflection.Assembly]::LoadFrom($lib);[CadCommandUiaV2.OwnHelperJob]::VerifyOwnMembership($JobName)
    Assert-ReadWorkerLeaseV1
    Initialize-CadProbeBridgeV1
    if (-not ('CadSingleBackgroundV1.Native' -as [type])) { Add-Type -Path (Join-Path $base 'single_background_input_v3/BackgroundNative.cs') }
    $null=Get-CadExactBSnapshotsV1 $session
    Assert-CadMultiOwnerProtectedHashesV1 $v.identity
    Initialize-CadFileRotBackendV5
    $session.lookup=Invoke-CadFileRotLookupV5 $v.identity.by_id.B.document_full_path ([CadExactFileRotV5.Backend]::new()) $session.events {param($event)}
    if ($session.lookup.status -cne 'REGISTERED_OBJECT_OBTAINED_IDENTITY_UNVERIFIED') { throw ('EXACT_B_LOOKUP:'+ $session.lookup.status) }
    $session.binding=Get-CadProbeFileBindingV3 $v.identity.owners $v.identity.by_id.B $session.lookup $session.bind_state {Get-CadExactBSnapshotsV1 $session} {param($event)$session.events.Add($event)}
    $session
}

function Get-CadExactBSnapshotsV1($Session) {
    $root=$Session.root;$LeaseControllerPid=$Session.controller_pid;$LeaseControllerStartUtc=$Session.controller_start;$script:validated=$Session.identity
    Assert-ReadWorkerLeaseV1
    if ((@(Get-Process -Name acad -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id | Sort-Object)-join ',') -cne (@($Session.identity.owners.process_id|Sort-Object)-join ',')) { throw 'EXACT_B_PROCESS_SET_CHANGED' }
    $rows=@(foreach ($owner in $Session.identity.owners) {$s=Get-ReadWorkerSnapshotV1 $owner;$s|Add-Member NoteProperty id $owner.id;$s})
    Assert-CadProbeSnapshotsV3 $Session.identity.owners $Session.identity.by_id.B $rows
    $rows
}

function Invoke-CadExactBReservedSendV1($Session,[string]$Expression) {
    # Atomic run-local reservation survives worker loss. No function may erase
    # it to retry. Even an exception before the COM return has unknown effects.
    $claim=Join-Path $Session.run ('exact_b_send_'+$Session.operation.id+'.json')
    $stream=[IO.File]::Open($claim,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try {
        $row=@{run_id=$Session.scope.run_id;scope_sha256=$Session.scope_hash;operation_id=$Session.operation.id;nonce=$Session.operation.nonce;state='RESERVED_SEND_MAY_HAVE_ENTERED';worker_pid=$PID}
        $bytes=[Text.Encoding]::UTF8.GetBytes(($row|ConvertTo-Json -Compress));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
    } finally {$stream.Dispose()}
    Invoke-CadBOneDocumentSendV3 $Session.send $Session.binding.document $Expression
    [pscustomobject]@{status='SEND_RETURNED_BUSINESS_UNVERIFIED';post_call_count=1;send_call_returned=$Session.send.returned;business_accepted=$false;claim_path=$claim}
}

function Invoke-CadExactBActionSendV1($Session) {
    $root=$Session.root;$LeaseControllerPid=$Session.controller_pid;$LeaseControllerStartUtc=$Session.controller_start;$script:validated=$Session.identity
    Assert-CadExactBReadyV1 $Session;Assert-ReadWorkerLeaseV1
    $scope=Read-CadExactBBoundJsonV1 $Session.scope_path $Session.scope_hash
    $manifest=Read-CadExactBBoundJsonV1 $Session.manifest_path $Session.manifest_hash
    Assert-CadExactBManifestV1 $manifest $scope $root
    $v=Assert-CadExactBActionScopeV1 $scope $root
    $fresh=@($v.operations|Where-Object id -CEQ $Session.operation.id)
    if ($fresh.Count -ne 1 -or ($fresh[0]|ConvertTo-Json -Depth 12 -Compress) -cne ($Session.operation|ConvertTo-Json -Depth 12 -Compress) -or ($v.identity.owners|ConvertTo-Json -Depth 12 -Compress) -cne ($Session.identity.owners|ConvertTo-Json -Depth 12 -Compress)) { throw 'EXACT_B_SESSION_MUTATED' }
    $Session.binding=Get-CadProbeFileBindingV3 $Session.identity.owners $Session.identity.by_id.B $Session.lookup $Session.bind_state {Get-CadExactBSnapshotsV1 $Session} {param($event)$Session.events.Add($event)}
    Assert-CadBBackgroundForegroundV3 ([CadSingleBackgroundV1.Native]::Read([long]$Session.identity.by_id.B.window_handle)) $Session.identity.by_id.B
    Invoke-CadExactBReservedSendV1 $Session (New-CadExactBActionExpressionV1 $Session)
}

function New-CadExactBActionExpressionV1($Session) {
    $bundle=(Resolve-CadExactBProjectPathV1 $Session.root $Session.operation.bundle_path).Replace('\','/').Replace('"','\"')
    $drawing=$Session.identity.by_id.B.document_full_path.Replace('\','/').Replace('"','\"')
    $hwnd=[long]$Session.identity.by_id.B.window_handle
    # Check again inside the actual CAD process before loading any action. A
    # queue admission is not sufficient if the active document changed meanwhile.
    # The bound bundle supplies nonce-bound ACK/COMPLETE and business reports.
    '(progn (vl-load-com) (if (and (= (rem (+ (vla-get-HWND (vlax-get-acad-object)) 4294967296.0) 4294967296.0) '+$hwnd+') (= (strcase (vl-string-translate "\\" "/" (vla-get-FullName (vla-get-ActiveDocument (vlax-get-acad-object))))) (strcase "'+$drawing+'"))) (load "'+$bundle+'") (princ "EXACT_B_NATIVE_OWNER_CHANGED_NO_ACTION")) (princ))'+"`n"
}

# Definition-only imports at the library's caller scope. These proven helpers
# do not acquire COM, create native types, enumerate windows or send on import.
# Their complete file closure is rehashed before any runtime action.
$cadExactBDefinitionsRoot=Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/cad_multi_window_interface_research'
foreach ($cadExactBDefinition in @('command_probe_v1/strict_binding_adapter_v1.ps1','read_session_v8/file_rot_backend_v5.ps1','binding_diagnostic_v2/diagnostic_contract_v1.ps1','b_existing_settlement_v4/selector_trace_v4.ps1','read_session_v8/file_document_normalizer_v8.ps1','command_probe_v3/file_binding_v3.ps1','single_background_input_v3/send_once_v3.ps1')) {
    . (Join-Path $cadExactBDefinitionsRoot $cadExactBDefinition)
}
