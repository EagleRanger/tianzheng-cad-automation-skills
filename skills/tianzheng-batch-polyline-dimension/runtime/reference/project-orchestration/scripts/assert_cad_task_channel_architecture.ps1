param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$errors = [Collections.Generic.List[string]]::new()

function Read-Json([string]$RelativePath) {
    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "CAD_TASK_CHANNEL_FILE_MISSING:$RelativePath" }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-ProjectFile([string]$RelativePath, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { $errors.Add("$($Code)_PATH_EMPTY"); return $null }
    $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add("$($Code)_OUTSIDE_PROJECT")
        return $null
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("$($Code)_MISSING")
        return $null
    }
    return $path
}

function Read-PartitionedGovernanceText([string]$PrimaryRelative, $Index, [string]$Code) {
    $parts = [Collections.Generic.List[string]]::new()
    $primaryPath = Resolve-ProjectFile $PrimaryRelative $Code
    if ($null -ne $primaryPath) { $parts.Add((Get-Content -LiteralPath $primaryPath -Raw -Encoding UTF8)) }
    $partitionProperty = $Index.PSObject.Properties['context_read_partition']
    if ($null -eq $partitionProperty) { return [string]::Join([Environment]::NewLine, $parts) }
    $warmDocuments = @($partitionProperty.Value.warm_documents)
    if ($warmDocuments.Count -eq 0) { $errors.Add("${Code}_WARM_DOCUMENTS_EMPTY"); return [string]::Join([Environment]::NewLine, $parts) }
    $fingerprinted = @($Index.execution_authority_hash_order | ForEach-Object { ([string]$_).Replace('\','/') })
    foreach ($raw in $warmDocuments) {
        $relative = ([string]$raw).Replace('\','/')
        if ([string]::IsNullOrWhiteSpace($relative)) { $errors.Add("${Code}_WARM_PATH_EMPTY"); continue }
        if ($relative -notin $fingerprinted) { $errors.Add("${Code}_WARM_NOT_FINGERPRINTED:$relative") }
        $path = Resolve-ProjectFile $relative "${Code}_WARM"
        if ($null -ne $path) { $parts.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8)) }
    }
    return [string]::Join([Environment]::NewLine, $parts)
}

$index = Read-Json 'config/project_execution_index.json'
$loop = Read-Json 'config/cad_project_loop.json'
$registry = Read-Json 'config/cad_native_task_registry.json'
$handoff = Read-Json 'config/current_execution_handoff.json'
$return = Read-Json 'config/current_execution_return.json'
$routing = Read-Json 'config/cad_channel_record_routing.json'
$commandRouting = Read-Json ([string]$index.command_research_routing)
$historyPolicy = Read-Json ([string]$index.history_integrity_policy)
$productionState = Read-Json 'config/current_production_task_state.json'
$taskRegistryAssertion = Join-Path $projectRoot 'scripts\assert_cad_native_task_registry.ps1'
$activeProjectThreadId = [string]$registry.tasks.project_strategy.thread_id
$allowedProjectThreadIds = @($activeProjectThreadId) + @($registry.tasks.project_strategy.previous_thread_ids | ForEach-Object { [string]$_ })
$allowedReturnThreadIds = @($allowedProjectThreadIds) + @($commandRouting.routes.PSObject.Properties | ForEach-Object { [string]$_.Value.detail_return_thread_id }) | Select-Object -Unique
$executionThreadId = [string]$registry.tasks.execution_run.thread_id
$allowedExecutionThreadIds = @($executionThreadId) + @($registry.tasks.execution_run.previous_thread_ids | ForEach-Object { [string]$_ }) | Select-Object -Unique
$productionThreadId = [string]$registry.tasks.production_modify.thread_id

if (-not (Test-Path -LiteralPath $taskRegistryAssertion -PathType Leaf)) { $errors.Add('NATIVE_TASK_REGISTRY_ASSERTION_MISSING') }
else { try { & $taskRegistryAssertion | Out-Null } catch { $errors.Add('NATIVE_TASK_REGISTRY_INVALID:' + $_.Exception.Message) } }

if ([string]$index.current_execution_handoff -cne 'config/current_execution_handoff.json') { $errors.Add('INDEX_HANDOFF_POINTER_INVALID') }
if ([string]$index.current_execution_return -cne 'config/current_execution_return.json') { $errors.Add('INDEX_RETURN_POINTER_INVALID') }
if ([string]$index.channel_record_routing -cne 'config/cad_channel_record_routing.json') { $errors.Add('INDEX_ROUTING_POINTER_INVALID') }
if ([string]$index.native_task_registry -cne 'config/cad_native_task_registry.json') { $errors.Add('INDEX_NATIVE_TASK_REGISTRY_POINTER_INVALID') }
if ([string]$index.command_research_routing -cne 'config/cad_command_research_routing_v1.json') { $errors.Add('INDEX_COMMAND_RESEARCH_ROUTING_POINTER_INVALID') }
if ([string]$index.current_production_task_state -cne 'config/current_production_task_state.json') { $errors.Add('INDEX_PRODUCTION_STATE_POINTER_INVALID') }
if ([string]$loop.task_lanes.project_strategy.label -cne '【项目】CAD自动化开发') { $errors.Add('PROJECT_LANE_LABEL_INVALID') }
if ([string]$loop.task_lanes.execution_run.label -cne [string]$registry.tasks.execution_run.canonical_title) { $errors.Add('EXECUTION_LANE_LABEL_INVALID') }
if ([string]$loop.task_lanes.production_modify.label -cne '【生产】CAD检查与修改') { $errors.Add('PRODUCTION_LANE_LABEL_INVALID') }
if ([string]$loop.task_lanes.project_strategy.thread_id -cne $activeProjectThreadId) { $errors.Add('PROJECT_LANE_THREAD_ID_INVALID') }
if ([string]$loop.task_lanes.execution_run.thread_id -cne $executionThreadId) { $errors.Add('EXECUTION_LANE_THREAD_ID_INVALID') }
if ([string]$loop.task_lanes.production_modify.thread_id -cne $productionThreadId) { $errors.Add('PRODUCTION_LANE_THREAD_ID_INVALID') }
foreach($lane in @('command_research_batch_polyline_dimension','command_research_batch_radius_dimension')) {
    if ([string]$loop.task_lanes.$lane.thread_id -cne [string]$registry.tasks.$lane.thread_id) { $errors.Add("RESEARCH_LANE_THREAD_ID_INVALID:$lane") }
    if ([bool]$registry.tasks.$lane.may_control_cad -or [bool]$registry.tasks.$lane.may_write_project_authority) { $errors.Add("RESEARCH_LANE_AUTHORITY_INVALID:$lane") }
    $expectedRoute=[string]$registry.tasks.$lane.route_id
    if (-not [bool]$registry.tasks.$lane.may_publish_ready -or [string]$registry.tasks.$lane.publish_scope.route_id -cne $expectedRoute -or [string]$registry.tasks.$lane.publish_scope.publisher -cne [string]$index.ready_handoff_publisher -or [string]$registry.tasks.$lane.publish_scope.target_thread_id -cne $executionThreadId) { $errors.Add("RESEARCH_SCOPED_PUBLISH_INVALID:$lane") }
}
if ([string]$handoff.loop_id -cne 'auto-CAD-project-loop' -or [string]$return.loop_id -cne 'auto-CAD-project-loop') { $errors.Add('CHANNEL_LOOP_ID_INVALID') }
$handoffRouteId=[string]$handoff.command_routing.route_id
$handoffRouteProperty=$commandRouting.routes.PSObject.Properties[$handoffRouteId]
if($null-eq$handoffRouteProperty){$errors.Add('HANDOFF_COMMAND_ROUTE_ID_UNKNOWN')}
$handoffRoute=if($null-ne$handoffRouteProperty){$handoffRouteProperty.Value}else{$null}
if ([string]$handoff.target.lane -cne 'execution_run') { $errors.Add('HANDOFF_DIRECTION_INVALID') }
if ([string]$handoff.status -ceq 'READY') {
    if ([string]$handoff.target.thread_id -cne $executionThreadId) { $errors.Add('HANDOFF_NATIVE_TASK_ID_INVALID') }
    if ($null-ne$handoffRoute -and([string]$handoff.issuer.lane -cne [string]$handoffRoute.ready_issuer_lane -or [string]$handoff.issuer.thread_id -cne [string]$handoffRoute.ready_issuer_thread_id)) { $errors.Add('READY_HANDOFF_ROUTE_ISSUER_INVALID') }
} else {
    if ([string]$handoff.target.thread_id -cnotin $allowedExecutionThreadIds) { $errors.Add('HISTORICAL_HANDOFF_EXECUTION_TASK_UNKNOWN') }
    $allowedHistoricalIssuerThreadIds=@($allowedProjectThreadIds)+@($commandRouting.routes.PSObject.Properties|ForEach-Object{[string]$_.Value.ready_issuer_thread_id})|Select-Object -Unique
    if ([string]$handoff.issuer.thread_id -cnotin $allowedHistoricalIssuerThreadIds) { $errors.Add('HISTORICAL_HANDOFF_ISSUER_UNKNOWN') }
}
if ([string]$return.writer.lane -cne 'execution_run') { $errors.Add('RETURN_DIRECTION_INVALID') }
if ([string]$return.writer.thread_id -cnotin $allowedExecutionThreadIds -or [string]$return.reader.thread_id -cnotin $allowedReturnThreadIds) { $errors.Add('RETURN_NATIVE_TASK_ID_INVALID') }
if ([string]$productionState.native_task.thread_id -cne $productionThreadId) { $errors.Add('PRODUCTION_STATE_NATIVE_TASK_ID_INVALID') }
if ([bool]$routing.historical_migration.bulk_move -or [bool]$routing.historical_migration.rewrite_historical_files -or [bool]$routing.historical_migration.rehash_historical_evidence) { $errors.Add('HISTORICAL_EVIDENCE_MUTATION_FORBIDDEN') }
if (-not [bool]$historyPolicy.native_task_history.manual_rewrite_forbidden) { $errors.Add('NATIVE_TASK_MANUAL_REWRITE_NOT_FORBIDDEN') }
if ([string]$index.current_execution_delivery -cne 'config/current_execution_delivery.json') { $errors.Add('INDEX_DELIVERY_POINTER_INVALID') }
if ([string]$index.return_delivery_policy -cne 'config/cad_task_return_delivery_policy.json') { $errors.Add('INDEX_RETURN_DELIVERY_POLICY_INVALID') }
$returnDeliveryAssertion = Join-Path $projectRoot ([string]$index.return_delivery_assertion)
if (-not (Test-Path -LiteralPath $returnDeliveryAssertion -PathType Leaf)) { $errors.Add('RETURN_DELIVERY_ASSERTION_MISSING') }
else { try { & $returnDeliveryAssertion | Out-Null } catch { $errors.Add('RETURN_DELIVERY_CONTRACT_INVALID:' + $_.Exception.Message) } }

$sameIdentity = (
    [string]$handoff.handoff_id -ceq [string]$return.handoff_id -and
    [string]$handoff.run_id -ceq [string]$return.run_id
)
if ([string]$handoff.status -ceq 'READY') {
    if ($sameIdentity) { $errors.Add('MATCHING_TERMINAL_RETURN_DID_NOT_SETTLE_READY_HANDOFF') }
    foreach ($required in @('handoff_id','run_id','immutable_handoff_path','immutable_handoff_sha256')) {
        if ([string]::IsNullOrWhiteSpace([string]$handoff.$required)) { $errors.Add("READY_HANDOFF_FIELD_MISSING:$required") }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$handoff.immutable_handoff_path)) {
        $immutablePath = Resolve-ProjectFile ([string]$handoff.immutable_handoff_path) 'READY_HANDOFF'
        if ($null -ne $immutablePath) {
            $actualHash = (Get-FileHash -LiteralPath $immutablePath -Algorithm SHA256).Hash
            if ($actualHash -cne [string]$handoff.immutable_handoff_sha256) { $errors.Add('READY_HANDOFF_IMMUTABLE_HASH_MISMATCH') }
            $immutable = Get-Content -LiteralPath $immutablePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$immutable.status -cne 'READY') { $errors.Add('IMMUTABLE_HANDOFF_STATUS_INVALID') }
            if ([string]$immutable.handoff_id -cne [string]$handoff.handoff_id -or [string]$immutable.run_id -cne [string]$handoff.run_id) { $errors.Add('IMMUTABLE_HANDOFF_IDENTITY_MISMATCH') }
        }
    }
}
elseif ([string]$handoff.status -ceq 'TERMINAL_RETURNED') {
    if (-not $sameIdentity) { $errors.Add('SETTLED_HANDOFF_IDENTITY_MISMATCH') }
    $terminalPath = Resolve-ProjectFile ([string]$handoff.terminal_return_path) 'SETTLED_HANDOFF_RETURN'
    if ($null -ne $terminalPath) {
        $terminalHash = (Get-FileHash -LiteralPath $terminalPath -Algorithm SHA256).Hash
        if ($terminalHash -cne [string]$handoff.terminal_return_sha256) { $errors.Add('SETTLED_HANDOFF_RETURN_HASH_MISMATCH') }
        if ([string]$handoff.terminal_return_path -cne [string]$return.immutable_return_path) { $errors.Add('SETTLED_HANDOFF_CURRENT_RETURN_PATH_MISMATCH') }
        if ([string]$handoff.terminal_return_sha256 -cne [string]$return.immutable_return_sha256) { $errors.Add('SETTLED_HANDOFF_CURRENT_RETURN_HASH_MISMATCH') }
    }
}
elseif ([string]$handoff.status -ceq 'CANCELLED_UNCONSUMED') {
    # Cancellation is non-executable, not a new READY or an execution success.
    $cancelled=& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_record_chain_integrity.ps1') -PassThru
    if($cancelled.status-cne'PASS'){$errors.Add('CANCELLED_UNCONSUMED_EVIDENCE_INVALID')}
}
else {
    $errors.Add('HANDOFF_STATUS_NOT_READY_OR_TERMINAL_RETURNED')
}

$agents = Read-PartitionedGovernanceText 'AGENTS.md' $index 'AGENTS_CHANNEL_RULE'
foreach ($label in @('【项目】CAD自动化开发','【研究】CAD批量尺寸标注','【研究】CAD批量半径标注','【执行】CAD开发与调试','【生产】CAD检查与修改','config/cad_native_task_registry.json','config/cad_command_research_routing_v1.json','config/current_execution_handoff.json','config/current_execution_return.json','config/current_production_task_state.json')) {
    if ($agents.IndexOf($label, [StringComparison]::Ordinal) -lt 0) { $errors.Add("AGENTS_CHANNEL_RULE_MISSING:$label") }
}

if ($errors.Count -gt 0) { throw ('CAD_TASK_CHANNEL_ARCHITECTURE_FAILED:' + ($errors -join '|')) }
$result = [pscustomobject]@{
    status = 'PASS'
    project_lane = [string]$loop.task_lanes.project_strategy.label
    execution_lane = [string]$loop.task_lanes.execution_run.label
    production_lane = [string]$loop.task_lanes.production_modify.label
    production_state = [string]$productionState.status
    handoff_status = [string]$handoff.status
    return_status = [string]$return.status
    historical_evidence_preserved = $true
    return_delivery_contract = 'PASS'
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
