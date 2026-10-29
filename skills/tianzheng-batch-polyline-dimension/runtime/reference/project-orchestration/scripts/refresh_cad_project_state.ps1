param([string]$OutputPath = '')

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'config\derived_project_state.json'
}
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'DERIVED_STATE_OUTPUT_OUTSIDE_PROJECT'
}

function Resolve-ProjectFile([string]$RelativePath, [string]$Code) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw "$($Code)_EMPTY" }
    $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$($Code)_OUTSIDE_PROJECT"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$($Code)_MISSING" }
    return $path
}

function Read-ProjectJson([string]$RelativePath, [string]$Code) {
    $path = Resolve-ProjectFile $RelativePath $Code
    return [pscustomobject]@{
        path = $path
        relative = $RelativePath.Replace('\','/')
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
}

$indexRecord = Read-ProjectJson 'config/project_execution_index.json' 'DERIVED_INDEX'
$index = $indexRecord.value
$roadmapRecord = Read-ProjectJson ([string]$index.roadmap) 'DERIVED_ROADMAP'
$registryRecord = Read-ProjectJson ([string]$index.component_registry) 'DERIVED_REGISTRY'
$bindingRecord = Read-ProjectJson ([string]$index.current_task_binding) 'DERIVED_BINDING'
$recoveryRecord = Read-ProjectJson ([string]$index.current_recovery_contract) 'DERIVED_RECOVERY'
$handoffRecord = Read-ProjectJson ([string]$index.current_execution_handoff) 'DERIVED_HANDOFF'
$returnRecord = Read-ProjectJson ([string]$index.current_execution_return) 'DERIVED_RETURN'
$policyRecord = Read-ProjectJson ([string]$index.history_integrity_policy) 'DERIVED_HISTORY_POLICY'

$roadmap = $roadmapRecord.value
$registry = $registryRecord.value
$binding = $bindingRecord.value
$recovery = $recoveryRecord.value
$executionHandoff = $handoffRecord.value
$executionReturn = $returnRecord.value
$historyPolicy = $policyRecord.value
$scopeRecord = Read-ProjectJson ([string]$binding.scope.path) 'DERIVED_SCOPE'
$scope = $scopeRecord.value

if (
    [string]$recovery.loop_id -cne [string]$index.loop_id -or
    [string]$executionHandoff.loop_id -cne [string]$index.loop_id -or
    [string]$executionReturn.loop_id -cne [string]$index.loop_id -or
    [string]$historyPolicy.loop_id -cne [string]$index.loop_id
) {
    throw 'DERIVED_STATE_LOOP_ID_MISMATCH'
}
if ([string]$recovery.current_task_binding -cne [string]$index.current_task_binding) { throw 'DERIVED_STATE_TASK_BINDING_MISMATCH' }
if ([string]$binding.component_id -cne [string]$scope.component_id) { throw 'DERIVED_STATE_BINDING_COMPONENT_MISMATCH' }
if ([string]$binding.scope.sha256 -cne [string]$scopeRecord.sha256) { throw 'DERIVED_STATE_BINDING_SCOPE_HASH_MISMATCH' }

$ledgerPath = Resolve-ProjectFile ([string]$binding.selection_ledger.path) 'DERIVED_LEDGER'
$ledgerSha256 = (Get-FileHash -LiteralPath $ledgerPath -Algorithm SHA256).Hash
if ($ledgerSha256 -cne [string]$binding.selection_ledger.sha256) { throw 'DERIVED_STATE_BINDING_LEDGER_HASH_MISMATCH' }

$terminalPath = Resolve-ProjectFile ([string]$binding.latest_terminal_evidence.path) 'DERIVED_TERMINAL_EVIDENCE'
$terminalSha256 = (Get-FileHash -LiteralPath $terminalPath -Algorithm SHA256).Hash
if ($terminalSha256 -cne [string]$binding.latest_terminal_evidence.sha256) { throw 'DERIVED_STATE_TERMINAL_EVIDENCE_HASH_MISMATCH' }

$immutableReturnPath = Resolve-ProjectFile ([string]$executionReturn.immutable_return_path) 'DERIVED_IMMUTABLE_RETURN'
$immutableReturnSha256 = (Get-FileHash -LiteralPath $immutableReturnPath -Algorithm SHA256).Hash
if ($immutableReturnSha256 -cne [string]$executionReturn.immutable_return_sha256) { throw 'DERIVED_STATE_IMMUTABLE_RETURN_HASH_MISMATCH' }
$immutableReturn = Get-Content -LiteralPath $immutableReturnPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (
    [string]$immutableReturn.handoff_id -cne [string]$executionReturn.handoff_id -or
    [string]$immutableReturn.run_id -cne [string]$executionReturn.run_id -or
    [string]$immutableReturn.status -cne [string]$executionReturn.status -or
    [string]$immutableReturn.terminal_state -cne [string]$executionReturn.terminal_state
) {
    throw 'DERIVED_STATE_CURRENT_RETURN_IMMUTABLE_IDENTITY_MISMATCH'
}
if (
    [string]$binding.latest_terminal_evidence.path -cne [string]$executionReturn.immutable_return_path -or
    [string]$binding.latest_terminal_evidence.sha256 -cne [string]$executionReturn.immutable_return_sha256 -or
    [string]$binding.latest_terminal_evidence.status -cne [string]$executionReturn.terminal_state
) {
    throw 'DERIVED_STATE_BINDING_TERMINAL_EVIDENCE_MISMATCH'
}
if (
    [string]$recovery.latest_terminal_execution.handoff_id -cne [string]$executionReturn.handoff_id -or
    [string]$recovery.latest_terminal_execution.run_id -cne [string]$executionReturn.run_id -or
    [string]$recovery.latest_terminal_execution.path -cne [string]$executionReturn.immutable_return_path -or
    [string]$recovery.latest_terminal_execution.sha256 -cne [string]$executionReturn.immutable_return_sha256 -or
    [string]$recovery.latest_terminal_execution.status -cne [string]$executionReturn.terminal_state
) {
    throw 'DERIVED_STATE_RECOVERY_TERMINAL_EXECUTION_MISMATCH'
}

$sameExecutionIdentity = (
    [string]$executionHandoff.handoff_id -ceq [string]$executionReturn.handoff_id -and
    [string]$executionHandoff.run_id -ceq [string]$executionReturn.run_id
)
if ([string]$executionHandoff.status -ceq 'READY' -and $sameExecutionIdentity) {
    throw 'DERIVED_STATE_TERMINAL_RETURN_HAS_MATCHING_READY_HANDOFF'
}
$pendingReadyHandoff = (
    [string]$executionHandoff.status -ceq 'READY' -and
    -not $sameExecutionIdentity
)
$nextGate = if ($pendingReadyHandoff) {
    'execute_pending_ready_handoff:' + [string]$executionHandoff.run_id
}
else {
    [string]$recovery.next_checkpoint
}

$component = @($registry.components | Where-Object { [string]$_.id -ceq [string]$binding.component_id })
if ($component.Count -ne 1) { throw 'DERIVED_STATE_COMPONENT_NOT_UNIQUE' }
if ([string]$recovery.active_component.id -cne [string]$binding.component_id) { throw 'DERIVED_STATE_RECOVERY_COMPONENT_MISMATCH' }

$saveField = $executionReturn.PSObject.Properties['save_performed']
$state = [ordered]@{
    schema_version = 3
    status = 'PASS'
    generated_at = (Get-Date).ToString('o')
    source = 'compact_pointer_snapshot_without_runtime_object_copy_or_recursive_run_scan'
    loop_id = [string]$index.loop_id
    current_phase = [string]$roadmap.current_phase
    current_objective = [string]$recovery.current_objective
    active_component = [ordered]@{
        id = [string]$component[0].id
        version = [string]$component[0].version
        status = [string]$component[0].status
        entry = [string]$component[0].entry
    }
    task_binding = [ordered]@{
        path = [string]$index.current_task_binding
        sha256 = [string]$bindingRecord.sha256
        scope_path = [string]$binding.scope.path
        scope_sha256 = [string]$scopeRecord.sha256
        selection_ledger_path = [string]$binding.selection_ledger.path
        selection_ledger_sha256 = $ledgerSha256
        latest_terminal_evidence_path = [string]$binding.latest_terminal_evidence.path
        latest_terminal_evidence_sha256 = $terminalSha256
        latest_terminal_evidence_status = [string]$binding.latest_terminal_evidence.status
    }
    execution_return = [ordered]@{
        path = [string]$index.current_execution_return
        sha256 = [string]$returnRecord.sha256
        status = [string]$executionReturn.status
        run_id = [string]$executionReturn.run_id
        terminal_status = [string]$executionReturn.terminal_state
        outcome = [string]$executionReturn.outcome
        save_performed = if ($null -ne $saveField) { $saveField.Value } else { $null }
        save_performed_present = ($null -ne $saveField)
        immutable_path = [string]$executionReturn.immutable_return_path
        immutable_sha256 = $immutableReturnSha256
    }
    execution_handoff = [ordered]@{
        path = [string]$index.current_execution_handoff
        sha256 = [string]$handoffRecord.sha256
        status = [string]$executionHandoff.status
        handoff_id = [string]$executionHandoff.handoff_id
        run_id = [string]$executionHandoff.run_id
        pending = [bool]$pendingReadyHandoff
    }
    runtime_inventory = [ordered]@{
        authority = [string]$binding.scope.path
        policy = 'read_object_counts_handles_segments_layers_offsets_only_from_current_task_binding_scope_and_immutable_run_evidence'
        copied_into_hot_state = $false
    }
    next_gate = $nextGate
}

$parent = Split-Path -Parent $output
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.File]::WriteAllText($output + '.tmp', ($state | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath ($output + '.tmp') -Destination $output -Force

$mirror = @(
    '# CAD Project State (compact machine-derived mirror)'
    ''
    ('Generated: {0}' -f [string]$state.generated_at)
    ''
    ('- Current phase: {0}' -f [string]$state.current_phase)
    ('- Current objective: {0}' -f [string]$state.current_objective)
    ('- Active component: {0}@{1} ({2})' -f [string]$state.active_component.id, [string]$state.active_component.version, [string]$state.active_component.status)
    ('- Current task binding: {0}' -f [string]$state.task_binding.path)
    ('- Latest task evidence: {0} ({1})' -f [string]$state.task_binding.latest_terminal_evidence_path, [string]$state.task_binding.latest_terminal_evidence_status)
    ('- Latest execution return: {0} / {1}' -f [string]$state.execution_return.run_id, [string]$state.execution_return.status)
    ('- Current handoff: {0} / {1}' -f [string]$state.execution_handoff.run_id, [string]$state.execution_handoff.status)
    ('- Next gate: {0}' -f [string]$state.next_gate)
    ''
    'Object counts, handles, segment lists, layers and offsets are read only from the task binding and immutable run evidence.'
    'This file is a compact human mirror; config/derived_project_state.json is the machine snapshot.'
) -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $projectRoot '.project-reasoning\STATE.md'), $mirror, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    status = 'PASS'
    output = $output
    current_phase = [string]$state.current_phase
    active_component = [string]$state.active_component.id
    execution_return_status = [string]$state.execution_return.status
    execution_handoff_status = [string]$state.execution_handoff.status
}
