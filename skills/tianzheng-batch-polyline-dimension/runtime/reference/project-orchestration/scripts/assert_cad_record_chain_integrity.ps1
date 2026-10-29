param(
    [string]$ProjectRoot = '',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$projectRootPath = [IO.Path]::GetFullPath($ProjectRoot)
$errors = [Collections.Generic.List[string]]::new()

function Resolve-ProjectFile([string]$RelativePath, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "$($Label)_PATH_EMPTY"
    }
    $path = [IO.Path]::GetFullPath((Join-Path $projectRootPath $RelativePath))
    if (-not $path.StartsWith($projectRootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$($Label)_OUTSIDE_PROJECT"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$($Label)_MISSING:$RelativePath"
    }
    return $path
}

function Read-ProjectJson([string]$RelativePath, [string]$Label) {
    $path = Resolve-ProjectFile $RelativePath $Label
    [pscustomobject]@{
        path = $path
        relative = $RelativePath.Replace('\','/')
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Add-Mismatch([bool]$Condition, [string]$Code) {
    if ($Condition) { $errors.Add($Code) }
}

$indexRecord = Read-ProjectJson 'config/project_execution_index.json' 'RECORD_CHAIN_INDEX'
$index = $indexRecord.value
$policyRecord = Read-ProjectJson ([string]$index.history_integrity_policy) 'RECORD_CHAIN_POLICY'
$routingRecord = Read-ProjectJson ([string]$index.command_research_routing) 'RECORD_CHAIN_COMMAND_ROUTING'
$handoffRecord = Read-ProjectJson ([string]$index.current_execution_handoff) 'RECORD_CHAIN_HANDOFF'
$returnRecord = Read-ProjectJson ([string]$index.current_execution_return) 'RECORD_CHAIN_RETURN'
$bindingRecord = Read-ProjectJson ([string]$index.current_task_binding) 'RECORD_CHAIN_BINDING'
$recoveryRecord = Read-ProjectJson ([string]$index.current_recovery_contract) 'RECORD_CHAIN_RECOVERY'
$derivedRecord = Read-ProjectJson ([string]$index.derived_state) 'RECORD_CHAIN_DERIVED'

$policy = $policyRecord.value
$routing = $routingRecord.value
$handoff = $handoffRecord.value
$return = $returnRecord.value
$binding = $bindingRecord.value
$recovery = $recoveryRecord.value
$derived = $derivedRecord.value

foreach ($row in @(
    @{ value = [string]$policy.loop_id; code = 'POLICY_LOOP_ID_MISMATCH' },
    @{ value = [string]$handoff.loop_id; code = 'HANDOFF_LOOP_ID_MISMATCH' },
    @{ value = [string]$return.loop_id; code = 'RETURN_LOOP_ID_MISMATCH' },
    @{ value = [string]$recovery.loop_id; code = 'RECOVERY_LOOP_ID_MISMATCH' },
    @{ value = [string]$derived.loop_id; code = 'DERIVED_LOOP_ID_MISMATCH' }
)) {
    Add-Mismatch ($row.value -cne [string]$index.loop_id) $row.code
}

Add-Mismatch (-not [bool]$policy.native_task_history.manual_rewrite_forbidden) 'NATIVE_TASK_MANUAL_REWRITE_NOT_FORBIDDEN'
Add-Mismatch (-not [bool]$policy.native_task_history.compaction_is_not_project_state) 'COMPACTION_STILL_TREATED_AS_PROJECT_STATE'
Add-Mismatch (-not [bool]$policy.turn_boundary.project_turn_closes_after_ready_handoff_is_issued) 'PROJECT_TURN_NOT_CLOSED_AFTER_READY'
Add-Mismatch (-not [bool]$policy.turn_boundary.project_turn_must_not_poll_or_wait_for_execution_task) 'PROJECT_TURN_STILL_POLLS_EXECUTION'
Add-Mismatch (-not [bool]$policy.turn_boundary.execution_result_is_consumed_in_a_new_originating_research_turn) 'EXECUTION_RESULT_NOT_CONSUMED_IN_ORIGIN_RESEARCH_TURN'
Add-Mismatch (-not [bool]$policy.history_retention.immutable_run_evidence_preserved) 'IMMUTABLE_RUN_RETENTION_DISABLED'

$immutableReturnRecord = Read-ProjectJson ([string]$return.immutable_return_path) 'RECORD_CHAIN_IMMUTABLE_RETURN'
$immutableReturn = $immutableReturnRecord.value
Add-Mismatch ($immutableReturnRecord.sha256 -cne [string]$return.immutable_return_sha256) 'CURRENT_RETURN_IMMUTABLE_HASH_MISMATCH'
Add-Mismatch ([string]$immutableReturn.loop_id -cne [string]$index.loop_id) 'IMMUTABLE_RETURN_LOOP_ID_MISMATCH'
Add-Mismatch ([string]$immutableReturn.handoff_id -cne [string]$return.handoff_id) 'CURRENT_RETURN_HANDOFF_ID_MISMATCH'
Add-Mismatch ([string]$immutableReturn.run_id -cne [string]$return.run_id) 'CURRENT_RETURN_RUN_ID_MISMATCH'
Add-Mismatch ([string]$immutableReturn.status -cne [string]$return.status) 'CURRENT_RETURN_STATUS_MISMATCH'
Add-Mismatch ([string]$immutableReturn.terminal_state -cne [string]$return.terminal_state) 'CURRENT_RETURN_TERMINAL_STATE_MISMATCH'
Add-Mismatch ([string]$immutableReturn.writer.lane -cne 'execution_run') 'IMMUTABLE_RETURN_WRITER_LANE_INVALID'
Add-Mismatch ([string]$return.writer.lane -cne 'execution_run') 'CURRENT_RETURN_WRITER_LANE_INVALID'

$handoffRouteId = [string]$handoff.command_routing.route_id
$handoffRouteProperty = $routing.routes.PSObject.Properties[$handoffRouteId]
if ([string]::IsNullOrWhiteSpace($handoffRouteId)) {
    $errors.Add('HANDOFF_COMMAND_ROUTE_ID_MISSING')
}
elseif ($null -eq $handoffRouteProperty) {
    $errors.Add("HANDOFF_COMMAND_ROUTE_ID_UNKNOWN:$handoffRouteId")
}

$returnReaderThreadId = [string]$immutableReturn.reader.thread_id
$returnRouteMatches = @($routing.routes.PSObject.Properties | Where-Object {
    [string]$_.Value.detail_return_thread_id -ceq $returnReaderThreadId
})
# A source may own more than one route. Resolve a terminal return from its own
# immutable handoff, never from a newer pending READY or the first reader match.
if ($returnRouteMatches.Count -gt 1) {
    try {
        $terminalHandoffRelative = Join-Path (Split-Path -Parent $immutableReturnRecord.relative) 'execution_handoff.json'
        $terminalHandoffRecord = Read-ProjectJson $terminalHandoffRelative 'RETURN_ROUTE_IMMUTABLE_HANDOFF'
        $terminalHandoff = $terminalHandoffRecord.value
        if ([string]$terminalHandoff.run_id -cne [string]$immutableReturn.run_id -or [string]$terminalHandoff.handoff_id -cne [string]$immutableReturn.handoff_id) { throw 'RETURN_ROUTE_IMMUTABLE_HANDOFF_IDENTITY_MISMATCH' }
        if ([string]$handoff.run_id -ceq [string]$immutableReturn.run_id -and [string]$handoff.handoff_id -ceq [string]$immutableReturn.handoff_id -and $terminalHandoffRecord.sha256 -cne [string]$handoff.immutable_handoff_sha256) { throw 'RETURN_ROUTE_IMMUTABLE_HANDOFF_HASH_MISMATCH' }
        $terminalRouteId = [string]$terminalHandoff.command_routing.route_id
        $returnRouteMatches = @($returnRouteMatches | Where-Object { [string]$_.Name -ceq $terminalRouteId })
        if ($returnRouteMatches.Count -ne 1) { throw 'RETURN_ROUTE_IMMUTABLE_HANDOFF_ROUTE_MISMATCH' }
        if ([string]$terminalHandoff.command_routing.originating_research_thread_id -cne $returnReaderThreadId -or [string]$terminalHandoff.command_routing.detail_return_thread_id -cne $returnReaderThreadId) { throw 'RETURN_ROUTE_IMMUTABLE_HANDOFF_READER_MISMATCH' }
    } catch { $errors.Add($_.Exception.Message) }
}
$returnRouteId = ''
$compatibilityApplied = $false
if ([string]::IsNullOrWhiteSpace($returnReaderThreadId)) {
    $errors.Add('IMMUTABLE_RETURN_READER_THREAD_ID_MISSING')
}
elseif ($returnRouteMatches.Count -eq 0) {
    $errors.Add("RETURN_READER_ROUTE_NOT_FOUND:$returnReaderThreadId")
}
elseif ($returnRouteMatches.Count -gt 1) {
    $errors.Add("RETURN_READER_ROUTE_NOT_UNIQUE:$returnReaderThreadId")
}
else {
    $returnRouteId = [string]$returnRouteMatches[0].Name
    $returnRoute = $returnRouteMatches[0].Value
    $expectedReaderLane = [string]$returnRoute.owner_lane
    $expectedReaderThreadId = [string]$returnRoute.detail_return_thread_id
    Add-Mismatch ([string]::IsNullOrWhiteSpace($expectedReaderLane)) 'COMMAND_ROUTE_OWNER_LANE_MISSING'
    Add-Mismatch ([string]::IsNullOrWhiteSpace($expectedReaderThreadId)) 'COMMAND_ROUTE_DETAIL_RETURN_THREAD_ID_MISSING'
    Add-Mismatch ([string]$immutableReturn.reader.thread_id -cne $expectedReaderThreadId) 'IMMUTABLE_RETURN_READER_THREAD_ID_INVALID'
    Add-Mismatch ([string]$return.reader.thread_id -cne $expectedReaderThreadId) 'CURRENT_RETURN_READER_THREAD_ID_INVALID'
    $immutableLaneMismatch = [string]$immutableReturn.reader.lane -cne $expectedReaderLane
    $currentLaneMismatch = [string]$return.reader.lane -cne $expectedReaderLane
    if (($immutableLaneMismatch -or $currentLaneMismatch) -and $null -ne $policy.PSObject.Properties['reader_lane_compatibility']) {
        $matchingCases = @($policy.reader_lane_compatibility.allowed_cases | Where-Object {
            [string]$_.immutable_return_sha256 -ceq $immutableReturnRecord.sha256 -and
            [string]$_.route_id -ceq $returnRouteId -and
            [string]$_.observed_lane -ceq [string]$immutableReturn.reader.lane -and
            [string]$_.observed_lane -ceq [string]$return.reader.lane -and
            [string]$_.expected_lane -ceq $expectedReaderLane -and
            [string]$_.exact_reader_thread_id -ceq $expectedReaderThreadId -and
            [bool]$_.future_reuse_forbidden
        })
        $compatibilityApplied = $matchingCases.Count -eq 1
    }
    Add-Mismatch ($immutableLaneMismatch -and -not $compatibilityApplied) 'IMMUTABLE_RETURN_READER_LANE_INVALID'
    Add-Mismatch ($currentLaneMismatch -and -not $compatibilityApplied) 'CURRENT_RETURN_READER_LANE_INVALID'
}

$sameIdentity = (
    [string]$handoff.handoff_id -ceq [string]$return.handoff_id -and
    [string]$handoff.run_id -ceq [string]$return.run_id
)
if ([string]$handoff.status -ceq 'READY' -and $sameIdentity) {
    $errors.Add('TERMINAL_RETURN_HAS_MATCHING_READY_HANDOFF')
}
elseif ([string]$handoff.status -ceq 'TERMINAL_RETURNED') {
    Add-Mismatch (-not $sameIdentity) 'SETTLED_HANDOFF_IDENTITY_MISMATCH'
    Add-Mismatch ($handoffRouteId -cne $returnRouteId) 'SETTLED_HANDOFF_RETURN_ROUTE_MISMATCH'
    Add-Mismatch ([string]$handoff.terminal_return_path -cne [string]$return.immutable_return_path) 'SETTLED_HANDOFF_RETURN_PATH_MISMATCH'
    Add-Mismatch ([string]$handoff.terminal_return_sha256 -cne [string]$return.immutable_return_sha256) 'SETTLED_HANDOFF_RETURN_HASH_MISMATCH'
}
elseif ([string]$handoff.status -ceq 'READY') {
    Add-Mismatch ([string]::IsNullOrWhiteSpace([string]$handoff.immutable_handoff_path)) 'PENDING_READY_HANDOFF_IMMUTABLE_PATH_MISSING'
}
elseif ([string]$handoff.status -ceq 'CANCELLED_UNCONSUMED') {
    $cancelRecord=Read-ProjectJson ('runs/'+[string]$handoff.run_id+'/project_cancellation.json') 'UNCONSUMED_CANCELLATION'
    $cancel=$cancelRecord.value
    Add-Mismatch ($cancel.run_id-cne$handoff.run_id-or$cancel.status-cne'CANCELLED_UNCONSUMED'-or$cancel.not_authorized_for_consumption-ne$true) 'CANCELLED_IDENTITY_INVALID'
    Add-Mismatch ($cancel.immutable_handoff_sha256-cne$handoff.immutable_handoff_sha256) 'CANCELLED_HASH_INVALID'
    Add-Mismatch ((Get-FileHash (Resolve-ProjectFile $handoff.immutable_handoff_path 'CANCELLED_IMMUTABLE')).Hash-cne$handoff.immutable_handoff_sha256) 'CANCELLED_IMMUTABLE_CHANGED'
    foreach($name in @('execution_controller_claim.json','controller_receipt.json','execution_envelope_receipt.json','execution_return.json','execution_delivery.json')) {
        Add-Mismatch (Test-Path -LiteralPath (Join-Path $projectRootPath ('runs/'+$handoff.run_id+'/'+$name))) 'CANCELLED_HAS_EXECUTION_EVIDENCE'
    }
    $previous=$cancel.previous_terminal_preserved
    if ($previous -is [string]) {
        Add-Mismatch ($previous -cne $return.run_id) 'CANCELLED_PREVIOUS_TERMINAL_CHANGED'
    } else {
        # A typed cancellation receipt binds the preserved terminal and delivery hashes.
        Add-Mismatch ([string]$previous.run_id -cne [string]$return.run_id) 'CANCELLED_PREVIOUS_TERMINAL_CHANGED'
        Add-Mismatch ([string]$previous.execution_return_sha256 -cne [string]$return.immutable_return_sha256) 'CANCELLED_PREVIOUS_RETURN_HASH_CHANGED'
        $preservedDelivery=Read-ProjectJson ('runs/'+[string]$return.run_id+'/execution_delivery.json') 'CANCELLED_PREVIOUS_DELIVERY'
        Add-Mismatch ([string]$previous.execution_delivery_sha256 -cne $preservedDelivery.sha256) 'CANCELLED_PREVIOUS_DELIVERY_HASH_CHANGED'
    }
}
else {
    $errors.Add('HANDOFF_STATUS_NOT_READY_OR_TERMINAL_RETURNED')
}

Add-Mismatch ([string]$binding.latest_terminal_evidence.path -cne [string]$return.immutable_return_path) 'BINDING_TERMINAL_PATH_MISMATCH'
Add-Mismatch ([string]$binding.latest_terminal_evidence.sha256 -cne [string]$return.immutable_return_sha256) 'BINDING_TERMINAL_HASH_MISMATCH'
Add-Mismatch ([string]$binding.latest_terminal_evidence.status -cne [string]$return.terminal_state) 'BINDING_TERMINAL_STATUS_MISMATCH'

Add-Mismatch ([string]$recovery.latest_terminal_execution.handoff_id -cne [string]$return.handoff_id) 'RECOVERY_TERMINAL_HANDOFF_ID_MISMATCH'
Add-Mismatch ([string]$recovery.latest_terminal_execution.run_id -cne [string]$return.run_id) 'RECOVERY_TERMINAL_RUN_ID_MISMATCH'
Add-Mismatch ([string]$recovery.latest_terminal_execution.path -cne [string]$return.immutable_return_path) 'RECOVERY_TERMINAL_PATH_MISMATCH'
Add-Mismatch ([string]$recovery.latest_terminal_execution.sha256 -cne [string]$return.immutable_return_sha256) 'RECOVERY_TERMINAL_HASH_MISMATCH'
Add-Mismatch ([string]$recovery.latest_terminal_execution.status -cne [string]$return.terminal_state) 'RECOVERY_TERMINAL_STATUS_MISMATCH'

Add-Mismatch ([string]$derived.execution_return.run_id -cne [string]$return.run_id) 'DERIVED_RETURN_RUN_ID_MISMATCH'
Add-Mismatch ([string]$derived.execution_return.immutable_path -cne [string]$return.immutable_return_path) 'DERIVED_RETURN_PATH_MISMATCH'
Add-Mismatch ([string]$derived.execution_return.immutable_sha256 -cne [string]$return.immutable_return_sha256) 'DERIVED_RETURN_HASH_MISMATCH'
Add-Mismatch ([string]$derived.execution_handoff.status -cne [string]$handoff.status) 'DERIVED_HANDOFF_STATUS_MISMATCH'
Add-Mismatch ([string]$derived.execution_handoff.run_id -cne [string]$handoff.run_id) 'DERIVED_HANDOFF_RUN_ID_MISMATCH'
$expectedDerivedNextGate = if ([string]$handoff.status -ceq 'READY' -and -not $sameIdentity) {
    'execute_pending_ready_handoff:' + [string]$handoff.run_id
}
else {
    [string]$recovery.next_checkpoint
}
Add-Mismatch ([string]$derived.next_gate -cne $expectedDerivedNextGate) 'DERIVED_NEXT_GATE_MISMATCH'

if ($errors.Count -gt 0) {
    throw ('CAD_RECORD_CHAIN_INTEGRITY_FAILED:' + ($errors -join '|'))
}

$result = [pscustomobject]@{
    status = 'PASS'
    loop_id = [string]$index.loop_id
    latest_terminal_run_id = [string]$return.run_id
    latest_terminal_status = [string]$return.terminal_state
    handoff_status = [string]$handoff.status
    next_gate = [string]$recovery.next_checkpoint
    native_history_rewrite = $false
    handoff_route_id = $handoffRouteId
    reader_route_id = $returnRouteId
    reader_lane_compatibility_applied = $compatibilityApplied
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
