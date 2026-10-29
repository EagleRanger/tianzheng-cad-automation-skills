param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$errors = [Collections.Generic.List[string]]::new()

function Read-Json([string]$RelativePath, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "$($Code)_PATH_EMPTY" }
    $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$($Code)_OUTSIDE_PROJECT"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$($Code)_MISSING:$RelativePath" }
    [pscustomobject]@{
        path = $path
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

function Add-Error([bool]$Condition, [string]$Code) {
    if ($Condition) { $errors.Add($Code) }
}

$indexRecord = Read-Json 'config/project_execution_index.json' 'RETURN_DELIVERY_INDEX'
$index = $indexRecord.value
$policyRecord = Read-Json ([string]$index.return_delivery_policy) 'RETURN_DELIVERY_POLICY'
$commandRoutingRecord = Read-Json ([string]$index.command_research_routing) 'COMMAND_RESEARCH_ROUTING'
$historyRecord = Read-Json ([string]$index.history_integrity_policy) 'RETURN_DELIVERY_HISTORY'
$handoffRecord = Read-Json ([string]$index.current_execution_handoff) 'RETURN_DELIVERY_HANDOFF'
$returnRecord = Read-Json ([string]$index.current_execution_return) 'RETURN_DELIVERY_RETURN'
$policy = $policyRecord.value
$commandRouting = $commandRoutingRecord.value
$history = $historyRecord.value
$handoff = $handoffRecord.value
$return = $returnRecord.value
$activeProjectThreadId = [string]$policy.native_tasks.project.thread_id
$allowedProjectThreadIds = @($activeProjectThreadId) + @($policy.native_tasks.project.previous_thread_ids | ForEach-Object { [string]$_ })
$allowedReturnThreadIds = @($allowedProjectThreadIds) + @($commandRouting.routes.PSObject.Properties | ForEach-Object { [string]$_.Value.detail_return_thread_id }) | Select-Object -Unique
$allowedIssuerThreadIds = @($allowedProjectThreadIds) + @($commandRouting.routes.PSObject.Properties | ForEach-Object { [string]$_.Value.ready_issuer_thread_id }) | Select-Object -Unique
$activeExecutionThreadId = [string]$policy.native_tasks.execution.thread_id
$allowedExecutionThreadIds = @($activeExecutionThreadId) + @($policy.native_tasks.execution.previous_thread_ids | ForEach-Object { [string]$_ }) | Select-Object -Unique

Add-Error ([string]$index.current_execution_delivery -cne [string]$policy.enforcement.required_delivery_pointer) 'INDEX_DELIVERY_POINTER_INVALID'
Add-Error ([string]$index.return_delivery_assertion -cne [string]$policy.enforcement.assertion) 'INDEX_DELIVERY_ASSERTION_INVALID'
Add-Error ([string]$index.ready_handoff_publisher -cne [string]$policy.enforcement.ready_handoff_publisher) 'INDEX_READY_HANDOFF_PUBLISHER_INVALID'
Add-Error (-not (Test-Path -LiteralPath (Join-Path $projectRoot ([string]$index.ready_handoff_publisher)) -PathType Leaf)) 'READY_HANDOFF_PUBLISHER_MISSING'
Add-Error ([string]$policy.loop_id -cne [string]$index.loop_id) 'RETURN_DELIVERY_LOOP_ID_MISMATCH'
Add-Error ([string]$policy.dispatch.transport -cne 'codex_app__send_message_to_thread') 'DISPATCH_TRANSPORT_INVALID'
Add-Error ([string]$policy.callback.transport -cne 'codex_app__send_message_to_thread') 'CALLBACK_TRANSPORT_INVALID'
Add-Error ([int]$policy.dispatch.attempt_count -ne 1) 'DISPATCH_ATTEMPT_COUNT_INVALID'
Add-Error ([int]$policy.callback.attempt_count -ne 1) 'CALLBACK_ATTEMPT_COUNT_INVALID'
Add-Error (-not [bool]$policy.callback.required_for_new_handoffs) 'EXECUTION_CALLBACK_NOT_REQUIRED'
Add-Error (-not [bool]$policy.callback.failure_does_not_authorize_rerun) 'CALLBACK_FAILURE_STILL_AUTHORIZES_RERUN'
Add-Error (-not [bool]$policy.fallback.rerun_for_missing_callback_forbidden) 'MISSING_CALLBACK_RERUN_NOT_FORBIDDEN'
Add-Error (-not [bool]$policy.fallback.project_status_turn_may_read_once) 'PROJECT_STATUS_READBACK_NOT_ALLOWED'
Add-Error (-not [bool]$history.turn_boundary.project_turn_must_not_poll_or_wait_for_execution_task) 'PROJECT_ISSUANCE_TURN_POLLING_ALLOWED'
if ([string]$handoff.status -ceq 'READY') {
    $exitReceipt = Join-Path $projectRoot ('runs/' + [string]$handoff.run_id + '/execution_envelope_receipt.json')
    if (Test-Path -LiteralPath $exitReceipt -PathType Leaf) {
        $exitEvidence = Get-Content -LiteralPath $exitReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
        Add-Error ([string]$exitEvidence.run_id -cne [string]$handoff.run_id) 'ENVELOPE_EXIT_RUN_MISMATCH'
        Add-Error ([bool]$exitEvidence.controller_exited) 'CONTROLLER_EXITED_BUT_READY_NOT_SETTLED'
    }
    $routeProperty=$commandRouting.routes.PSObject.Properties[[string]$handoff.command_routing.route_id]
    Add-Error ($null-eq$routeProperty) 'HANDOFF_COMMAND_ROUTE_ID_UNKNOWN'
    if($null-ne$routeProperty){
        Add-Error ([string]$handoff.issuer.lane -cne [string]$routeProperty.Value.ready_issuer_lane -or [string]$handoff.issuer.thread_id -cne [string]$routeProperty.Value.ready_issuer_thread_id) 'HANDOFF_ROUTE_ISSUER_MISMATCH'
    }
}
else {
    Add-Error ([string]$handoff.issuer.thread_id -cnotin $allowedIssuerThreadIds) 'HANDOFF_ISSUER_MISMATCH'
}
if ([string]$handoff.status -ceq 'READY') {
    Add-Error ([string]$handoff.target.thread_id -cne $activeExecutionThreadId) 'HANDOFF_EXECUTION_THREAD_MISMATCH'
}
else {
    Add-Error ([string]$handoff.target.thread_id -cnotin $allowedExecutionThreadIds) 'HISTORICAL_HANDOFF_EXECUTION_THREAD_UNKNOWN'
}
Add-Error ([string]$return.writer.thread_id -cnotin $allowedExecutionThreadIds) 'RETURN_EXECUTION_THREAD_MISMATCH'
Add-Error ([string]$return.reader.thread_id -cnotin $allowedReturnThreadIds) 'RETURN_DETAIL_THREAD_MISMATCH'

$minimumSchema = [int]$policy.enforcement.new_ready_handoff_minimum_schema_version
if ([string]$handoff.status -ceq 'READY') {
    Add-Error ([int]$handoff.schema_version -lt $minimumSchema) 'NEW_READY_HANDOFF_SCHEMA_TOO_OLD'
    if ($null -eq $handoff.PSObject.Properties['return_delivery']) {
        $errors.Add('READY_HANDOFF_RETURN_DELIVERY_MISSING')
    }
    else {
        $deliveryContract = $handoff.return_delivery
        Add-Error (-not [bool]$deliveryContract.callback_required) 'READY_CALLBACK_NOT_REQUIRED'
        Add-Error ([string]$deliveryContract.transport -cne [string]$policy.callback.transport) 'READY_CALLBACK_TRANSPORT_MISMATCH'
        Add-Error ([string]$deliveryContract.project_thread_id -cne [string]$policy.native_tasks.project.thread_id) 'READY_CALLBACK_TARGET_MISMATCH'
        Add-Error ([string]$deliveryContract.callback_target_thread_id -cnotin $allowedReturnThreadIds) 'READY_DETAIL_CALLBACK_TARGET_MISMATCH'
        Add-Error ([string]$deliveryContract.milestone_thread_id -cne [string]$policy.native_tasks.project.thread_id) 'READY_MILESTONE_TARGET_MISMATCH'
        Add-Error ([string]$deliveryContract.execution_thread_id -cne [string]$policy.native_tasks.execution.thread_id) 'READY_EXECUTION_TARGET_MISMATCH'
        Add-Error ([int]$deliveryContract.callback_attempt_count -ne 1) 'READY_CALLBACK_ATTEMPT_COUNT_INVALID'
        Add-Error (-not [bool]$deliveryContract.callback_failure_does_not_authorize_rerun) 'READY_CALLBACK_FAILURE_RERUN_NOT_FORBIDDEN'
    }
}

$deliveryRelative = [string]$index.current_execution_delivery
if (Test-Path -LiteralPath (Join-Path $projectRoot $deliveryRelative) -PathType Leaf) {
    $deliveryRecord = Read-Json $deliveryRelative 'RETURN_DELIVERY_POINTER'
    $delivery = $deliveryRecord.value
    Add-Error ([string]$delivery.loop_id -cne [string]$index.loop_id) 'DELIVERY_LOOP_ID_MISMATCH'
    Add-Error ([string]$delivery.handoff_id -cne [string]$return.handoff_id) 'DELIVERY_HANDOFF_ID_MISMATCH'
    Add-Error ([string]$delivery.run_id -cne [string]$return.run_id) 'DELIVERY_RUN_ID_MISMATCH'
    Add-Error ([string]$delivery.immutable_return_path -cne [string]$return.immutable_return_path) 'DELIVERY_RETURN_PATH_MISMATCH'
    Add-Error ([string]$delivery.immutable_return_sha256 -cne [string]$return.immutable_return_sha256) 'DELIVERY_RETURN_HASH_MISMATCH'
    Add-Error ([string]$delivery.callback_target_thread_id -cnotin $allowedReturnThreadIds) 'DELIVERY_CALLBACK_TARGET_MISMATCH'
    Add-Error ([bool]$delivery.business_rerun_authorized) 'DELIVERY_AUTHORIZES_BUSINESS_RERUN'
    if ([string]$delivery.receipt_path) {
        $receiptRecord = Read-Json ([string]$delivery.receipt_path) 'RETURN_DELIVERY_RECEIPT'
        Add-Error ($receiptRecord.sha256 -cne [string]$delivery.receipt_sha256) 'DELIVERY_RECEIPT_HASH_MISMATCH'
    }
    switch ([string]$delivery.status) {
        'DELIVERED' { Add-Error ([int]$delivery.callback_attempt_count -ne 1) 'DELIVERED_ATTEMPT_COUNT_INVALID' }
        'CALLBACK_FAILED' { Add-Error ([int]$delivery.callback_attempt_count -ne 1) 'CALLBACK_FAILED_ATTEMPT_COUNT_INVALID' }
        'RECOVERED_BY_PROJECT_READBACK' { Add-Error ([int]$delivery.callback_attempt_count -ne 0) 'RECOVERED_ATTEMPT_COUNT_INVALID' }
        default { $errors.Add('DELIVERY_STATUS_INVALID') }
    }
}
elseif ([string]$handoff.status -ceq 'TERMINAL_RETURNED' -and [int]$handoff.schema_version -ge $minimumSchema) {
    $errors.Add('TERMINAL_RETURN_DELIVERY_POINTER_MISSING')
}

if ($errors.Count -gt 0) { throw ('CAD_RETURN_DELIVERY_CONTRACT_FAILED:' + ($errors -join '|')) }

$result = [pscustomobject]@{
    status = 'PASS'
    loop_id = [string]$index.loop_id
    handoff_status = [string]$handoff.status
    return_run_id = [string]$return.run_id
    callback_transport = [string]$policy.callback.transport
    callback_failure_authorizes_rerun = $false
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
