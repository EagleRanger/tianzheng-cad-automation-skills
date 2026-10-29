param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $root 'config\project_execution_index.json'
$loopDocumentPath = Join-Path $root '.project-reasoning\PROJECT_LOOP.md'
$machineLoopPath = Join-Path $root 'config\cad_project_loop.json'
$architecturePath = Join-Path $root 'config\cad_development_architecture.json'
$recoveryPath = Join-Path $root 'config\current_recovery_contract.json'
$derivedPath = Join-Path $root 'config\derived_project_state.json'
$layoutCompositionPath = Join-Path $root 'scripts\assert_typed_dimension_layout_composition.ps1'
$commandRegistryPath = Join-Path $root 'knowledge\t20v10_command_registry.tsv'
$workflowRegistryPath = Join-Path $root 'config\verified_workflow_registry.json'
$rejectedRegistryPath = Join-Path $root 'config\rejected_legacy_entrypoints.json'
$errors = [Collections.Generic.List[string]]::new()

foreach ($path in @($indexPath,$loopDocumentPath,$machineLoopPath,$architecturePath,$recoveryPath,$derivedPath,$layoutCompositionPath,$commandRegistryPath,$workflowRegistryPath,$rejectedRegistryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add('PROMOTION_AUTHORITY_MISSING:' + $path) }
}
if ($errors.Count -gt 0) { throw ('CAD_KNOWLEDGE_PROMOTION_CONSISTENCY_FAILED:' + ($errors -join '|')) }

function Read-PartitionedGovernanceText([string]$PrimaryRelative, $Index, [string]$Code) {
    $parts = [Collections.Generic.List[string]]::new()
    $primaryPath = [IO.Path]::GetFullPath((Join-Path $root $PrimaryRelative))
    $parts.Add((Get-Content -LiteralPath $primaryPath -Raw -Encoding UTF8))
    $partitionProperty = $Index.PSObject.Properties['context_read_partition']
    if ($null -eq $partitionProperty) { return [string]::Join([Environment]::NewLine, $parts) }
    $warmDocuments = @($partitionProperty.Value.warm_documents)
    if ($warmDocuments.Count -eq 0) { $errors.Add("${Code}_WARM_DOCUMENTS_EMPTY"); return [string]::Join([Environment]::NewLine, $parts) }
    $fingerprinted = @($Index.execution_authority_hash_order | ForEach-Object { ([string]$_).Replace('\','/') })
    foreach ($raw in $warmDocuments) {
        $relative = ([string]$raw).Replace('\','/')
        if ([string]::IsNullOrWhiteSpace($relative)) { $errors.Add("${Code}_WARM_PATH_EMPTY"); continue }
        if ($relative -notin $fingerprinted) { $errors.Add("${Code}_WARM_NOT_FINGERPRINTED:$relative") }
        $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
        if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { $errors.Add("${Code}_WARM_OUTSIDE_PROJECT:$relative"); continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("${Code}_WARM_MISSING:$relative"); continue }
        $parts.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8))
    }
    return [string]::Join([Environment]::NewLine, $parts)
}

$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$loopText = Read-PartitionedGovernanceText '.project-reasoning/PROJECT_LOOP.md' $index 'PROMOTION_LOOP_TOKEN'
$machineLoop = Get-Content -LiteralPath $machineLoopPath -Raw -Encoding UTF8 | ConvertFrom-Json
$architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$recovery = Get-Content -LiteralPath $recoveryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$derived = Get-Content -LiteralPath $derivedPath -Raw -Encoding UTF8 | ConvertFrom-Json
$workflowRegistry = Get-Content -LiteralPath $workflowRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$commandRows = @(Import-Csv -LiteralPath $commandRegistryPath -Delimiter "`t" -Encoding UTF8)

foreach ($token in @('知识晋升事务','命令能力索引','PROMOTION_INCOMPLETE','适配器变更前的能力召回门')) {
    if ($loopText -notmatch [regex]::Escape($token)) { $errors.Add('PROMOTION_LOOP_TOKEN_MISSING:' + $token) }
}

$expectedRecall = @('knowledge/t20v10_command_registry.tsv','config/verified_workflow_registry.json','config/rejected_legacy_entrypoints.json')
if ((@($architecture.implementation_paths.native_command_capability_recall) -join '|') -cne ($expectedRecall -join '|')) {
    $errors.Add('ARCHITECTURE_CAPABILITY_RECALL_ORDER_INVALID')
}
if ([string]$architecture.knowledge_promotion_transaction.incomplete_terminal -cne 'PROMOTION_INCOMPLETE') {
    $errors.Add('ARCHITECTURE_PROMOTION_INCOMPLETE_TERMINAL_MISSING')
}
if (-not [bool]$architecture.knowledge_promotion_transaction.task_specific_runtime_data_forbidden) {
    $errors.Add('ARCHITECTURE_PROMOTION_TASK_DATA_BOUNDARY_MISSING')
}
$historicalHarness = [string]$architecture.knowledge_promotion_transaction.historical_regression_harness
if ($historicalHarness -cne 'scripts/audit_cad_loop_historical_regressions.py' -or -not (Test-Path -LiteralPath (Join-Path $root $historicalHarness) -PathType Leaf)) {
    $errors.Add('ARCHITECTURE_HISTORICAL_REGRESSION_HARNESS_MISSING')
}
if ([string]$machineLoop.knowledge_promotion_transaction.consistency_assertion -cne 'reference/project-orchestration/scripts/assert_cad_knowledge_promotion_consistency.ps1') {
    $errors.Add('MACHINE_LOOP_PROMOTION_ASSERTION_NOT_BOUND')
}
if ([string]$machineLoop.knowledge_promotion_transaction.historical_regression_harness -cne $historicalHarness) {
    $errors.Add('MACHINE_LOOP_HISTORICAL_REGRESSION_HARNESS_MISMATCH')
}
if (-not [bool]$machineLoop.adapter_mutation_gate.unpromoted_same_semantic_candidate_must_remain_retrievable) {
    $errors.Add('MACHINE_LOOP_UNPROMOTED_CANDIDATE_RECALL_MISSING')
}
if ([string]$recovery.promotion_consistency.assertion -cne 'reference/project-orchestration/scripts/assert_cad_knowledge_promotion_consistency.ps1') {
    $errors.Add('RECOVERY_PROMOTION_ASSERTION_NOT_BOUND')
}
if ([string]::IsNullOrWhiteSpace([string]$recovery.history_policy.native_command_or_adapter_failure)) {
    $errors.Add('RECOVERY_NATIVE_COMMAND_CAPABILITY_ROUTE_MISSING')
}
if ([string]$recovery.focus_lock.status -notin @('LOCKED_UNTIL_NORMAL_TYPED_BATCH_COVERAGE_OR_EXPLICIT_REDIRECT','LOCKED_TO_FRESH_BASEBOARD_GENERATION_AND_QUANTIZED_LAYOUT_V3_VALIDATION','LOCKED_TO_FRESH_BASEBOARD_GENERATION_AND_QUANTIZED_LAYOUT_V4_VALIDATION','LOCKED_TO_FRESH_BASEBOARD_PLACEMENT_GATED_GENERATION_VALIDATION','LOCKED_TO_RUN176_D3_QUANTIZED_COMMON_BAND_VISUAL_VALIDATION','LOCKED_TO_USER_ZOOM_REJECTION__D2_87_ARC_2_THEN_D3_OPEN_83_8B','LOCKED_TO_COMPOSED_LAYOUT_GOVERNANCE_REPAIR_AND_FULL_VALIDATION','LOCKED_TO_DIMENSION_FIRST_CROSS_COMMAND_LAYOUT_SEQUENCE') -or [bool]$recovery.focus_lock.assistant_initiated_scope_expansion) {
    $errors.Add('RECOVERY_EXCLUSIVE_FOCUS_LOCK_INVALID')
}
if ([int]$derived.schema_version -ne 3 -or [string]$derived.current_objective -cne [string]$recovery.current_objective) {
    $errors.Add('DERIVED_STATE_RECOVERY_OBJECTIVE_MISMATCH')
}
try { & $layoutCompositionPath | Out-Null } catch { $errors.Add('ACTIVE_LAYOUT_COMPOSITION_ASSERTION_FAILED:' + $_.Exception.Message) }

$tdimmp = @($commandRows | Where-Object { [string]$_.full_command -ieq 'TDimMP' })
$tdimtp = @($commandRows | Where-Object { [string]$_.full_command -ieq 'TDimTP' })
if ($tdimmp.Count -ne 1) { $errors.Add('COMMAND_REGISTRY_TDIMMP_NOT_UNIQUE') }
if ($tdimtp.Count -ne 1) { $errors.Add('COMMAND_REGISTRY_TDIMTP_NOT_UNIQUE') }
if ($tdimmp.Count -eq 1 -and [string]$tdimmp[0].chinese_name -cne '逐点标注') { $errors.Add('COMMAND_REGISTRY_TDIMMP_SEMANTIC_DRIFT') }
if ($tdimtp.Count -eq 1 -and [string]$tdimtp[0].chinese_name -cne '两点标注') { $errors.Add('COMMAND_REGISTRY_TDIMTP_SEMANTIC_DRIFT') }

$typed = @($workflowRegistry.workflows | Where-Object { [string]$_.id -ceq 'TZ-TDIM-TYPED-SEGMENT-V1' })
if ($typed.Count -ne 1) { $errors.Add('VERIFIED_TYPED_WORKFLOW_NOT_UNIQUE') }
elseif ([string]$typed[0].implementation.line_command -cne 'TDimMP') { $errors.Add('VERIFIED_TYPED_WORKFLOW_LINE_COMMAND_DRIFT') }

if ($errors.Count -gt 0) { throw ('CAD_KNOWLEDGE_PROMOTION_CONSISTENCY_FAILED:' + ($errors -join '|')) }
$result = [pscustomobject]@{
    status = 'PASS'
    capability_recall_sources = $expectedRecall.Count
    active_verified_line_command = 'TDimMP'
    retrievable_same_semantic_candidate = 'TDimTP'
    promotion_incomplete_terminal = 'PROMOTION_INCOMPLETE'
    historical_regression_harness = $historicalHarness
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
