param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$errors = [Collections.Generic.List[string]]::new()

function Read-ProjectJson([string]$RelativePath) {
    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RECOVERY_AUTHORITY_MISSING:$RelativePath" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Assert-Hash([string]$RelativePath, [string]$Expected, [string]$Label) {
    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("${Label}_MISSING:$RelativePath"); return }
    $stream = [IO.File]::Open(
        $path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actual = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
    if ($actual -cne $Expected) { $errors.Add("${Label}_HASH_MISMATCH:$RelativePath") }
}

$index = Read-ProjectJson 'config/project_execution_index.json'
$recovery = Read-ProjectJson ([string]$index.current_recovery_contract)
$binding = Read-ProjectJson ([string]$index.current_task_binding)
$scope = Read-ProjectJson ([string]$binding.scope.path)
$registry = Read-ProjectJson ([string]$index.component_registry)
$derived = Read-ProjectJson ([string]$index.derived_state)

if ([string]$index.loop_id -cne 'auto-CAD-project-loop') { $errors.Add('RECOVERY_LOOP_ID_INVALID') }
if ([string]$recovery.loop_id -cne [string]$index.loop_id) { $errors.Add('RECOVERY_LOOP_ID_MISMATCH') }
if ([string]$recovery.current_task_binding -cne [string]$index.current_task_binding) { $errors.Add('RECOVERY_TASK_BINDING_MISMATCH') }
$bindingStatus = [string]$binding.status
$bindingIsActive = $bindingStatus -ceq 'ACTIVE_TASK_BINDING'
$bindingRequiresFreshNormalTypedInventory = (
    $bindingStatus -ceq 'REQUIRES_FRESH_RUNTIME_INVENTORY_FOR_NORMAL_TYPED_BATCH' -and
    [string]$recovery.focus_lock.status -ceq 'LOCKED_UNTIL_NORMAL_TYPED_BATCH_COVERAGE_OR_EXPLICIT_REDIRECT' -and
    [string]$binding.candidate_runtime_status -ceq 'STALE_PREPARED_SCOPE_REFERENCE_ONLY__MUST_REINVENTORY_BEFORE_MUTATION'
)
if (-not ($bindingIsActive -or $bindingRequiresFreshNormalTypedInventory)) { $errors.Add('TASK_BINDING_NEITHER_ACTIVE_NOR_VALIDLY_AWAITING_FRESH_NORMAL_TYPED_INVENTORY') }
if ([string]$binding.component_id -cne [string]$scope.component_id) { $errors.Add('TASK_BINDING_SCOPE_COMPONENT_MISMATCH') }
if ([string]$recovery.active_component.id -cne [string]$binding.component_id) { $errors.Add('RECOVERY_ACTIVE_COMPONENT_MISMATCH') }
if ([int]$derived.schema_version -ne 3) { $errors.Add('DERIVED_STATE_NOT_COMPACT_V3') }
if ([string]$derived.active_component.id -cne [string]$binding.component_id) { $errors.Add('DERIVED_ACTIVE_COMPONENT_MISMATCH') }
if ([string]$derived.task_binding.path -cne [string]$index.current_task_binding) { $errors.Add('DERIVED_TASK_BINDING_MISMATCH') }
if ([string]$derived.task_binding.scope_path -cne [string]$binding.scope.path) { $errors.Add('DERIVED_SCOPE_POINTER_MISMATCH') }
if ([string]$derived.task_binding.scope_sha256 -cne [string]$binding.scope.sha256) { $errors.Add('DERIVED_SCOPE_HASH_MISMATCH') }
foreach ($forbiddenProperty in @('mutable_source_segments','mutable_annotation_handles','selected_source_count','target_arc_count','target_line_count','baseline_path','hard_blocks')) {
    if ($null -ne $derived.PSObject.Properties[$forbiddenProperty]) { $errors.Add("DERIVED_STATE_COPIES_RUNTIME_DATA:$forbiddenProperty") }
}

Assert-Hash ([string]$binding.scope.path) ([string]$binding.scope.sha256) 'TASK_SCOPE'
Assert-Hash ([string]$binding.selection_ledger.path) ([string]$binding.selection_ledger.sha256) 'TASK_SELECTION_LEDGER'
Assert-Hash ([string]$binding.latest_terminal_evidence.path) ([string]$binding.latest_terminal_evidence.sha256) 'TASK_TERMINAL_EVIDENCE'
Assert-Hash ([string]$scope.baseline.path) ([string]$scope.baseline.sha256) 'TASK_BASELINE'

$component = @($registry.components | Where-Object { [string]$_.id -ceq [string]$binding.component_id })
if ([string]$binding.component_id -notin @($registry.component_selection_policy.active_reusable_component_ids)) { $errors.Add('RECOVERY_COMPONENT_NOT_IN_ACTIVE_REUSABLE_SET') }
if ($component.Count -ne 1) { $errors.Add('RECOVERY_COMPONENT_NOT_UNIQUE') }
else {
    if ([string]$component[0].status -in @('planned','blocked','rejected','superseded')) { $errors.Add('RECOVERY_COMPONENT_STATUS_NOT_CALLABLE') }
    if ([string]$component[0].version -cne [string]$recovery.active_component.version) { $errors.Add('RECOVERY_COMPONENT_VERSION_MISMATCH') }
    if ([string]$component[0].entry -cne 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_workflow.ps1') { $errors.Add('RECOVERY_COMPONENT_NOT_USING_ONE_SHOT_ENTRY') }
    if ([string]$component[0].task_data_policy -notmatch 'per_run_inventory') { $errors.Add('RECOVERY_COMPONENT_TASK_DATA_POLICY_MISSING') }
}

$segments = @($scope.mutable_source_segments)
$arcCount = @($segments | Where-Object { [string]$_.type -ceq 'ARC' }).Count
$lineCount = @($segments | Where-Object { [string]$_.type -ceq 'LINE' }).Count
if ($segments.Count -lt 1 -or $segments.Count -ne ($arcCount + $lineCount)) { $errors.Add('TASK_RUNTIME_TYPED_INVENTORY_INVALID') }
if ([int]$scope.maximum_created_count -ne $segments.Count) { $errors.Add('TASK_RUNTIME_CREATED_BOUND_INVALID') }
if ([bool]$derived.runtime_inventory.copied_into_hot_state) { $errors.Add('DERIVED_RUNTIME_INVENTORY_WAS_COPIED') }
if ([string]$derived.runtime_inventory.authority -cne [string]$binding.scope.path) { $errors.Add('DERIVED_RUNTIME_INVENTORY_AUTHORITY_MISMATCH') }

$projectLoopText = Get-Content -LiteralPath (Join-Path $projectRoot '.project-reasoning/PROJECT_LOOP.md') -Raw -Encoding UTF8
$phaseText = Get-Content -LiteralPath (Join-Path $projectRoot 'knowledge/phase_plans/P3_NATIVE_DIMENSION_RELAYOUT.md') -Raw -Encoding UTF8
$hotContractText = $projectLoopText + "`n" + $phaseText
foreach ($forbidden in @('config/scopes/','当前唯一天正进程为','source_handle":"','segment_count":')) {
    if ($hotContractText.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $errors.Add("TASK_SPECIFIC_DATA_LEAKED_INTO_LOOP:$forbidden") }
}
if ($hotContractText -match '\b[0-9A-F]{5,}:[0-9]+\b') { $errors.Add('TASK_HANDLE_SEGMENT_LEAKED_INTO_LOOP') }

if ($errors.Count -gt 0) { throw ('CAD_RECOVERY_CONTEXT_ASSERTION_FAILED:' + ($errors -join '|')) }
$result = [pscustomobject]@{
    status = 'PASS'
    loop_id = [string]$index.loop_id
    current_phase = [string]$recovery.current_phase
    active_component = [string]$binding.component_id
    current_task_binding = [string]$index.current_task_binding
    runtime_target_count = $segments.Count
    loop_contains_task_specific_object_data = $false
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
