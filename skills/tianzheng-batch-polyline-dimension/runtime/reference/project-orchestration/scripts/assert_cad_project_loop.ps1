param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$corePath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_project_loop_core.ps1'
$recordChainPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_record_chain_integrity.ps1'
$taskRegistryPath = Join-Path $PSScriptRoot 'assert_cad_native_task_registry.ps1'
$researchBootstrapPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_research_bootstrap_v1.ps1'
$iterationLearningPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_iteration_learning.ps1'

foreach ($required in @($corePath, $recordChainPath, $taskRegistryPath, $researchBootstrapPath, $iterationLearningPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('CAD_PROJECT_LOOP_ASSERTION_MISSING:' + $required) }
}

$core = & $corePath -PassThru
$taskRegistry = & $taskRegistryPath -PassThru
$recordChain = & $recordChainPath -PassThru
$researchBootstrap = & $researchBootstrapPath -PassThru
$iterationLearning = & $iterationLearningPath -PassThru

$result = [pscustomobject]@{
    status = 'PASS'
    loop_id = [string]$core.loop_id
    current_phase = [string]$core.current_phase
    authorities_checked = [int]$core.authorities_checked
    registered_task_count = [int]$taskRegistry.registered_task_count
    production_state = [string]$taskRegistry.production_state
    latest_terminal_run_id = [string]$recordChain.latest_terminal_run_id
    handoff_status = [string]$recordChain.handoff_status
    next_gate = [string]$recordChain.next_gate
    native_task_registry = 'PASS'
    record_chain_integrity = 'PASS'
    research_bootstrap = [string]$researchBootstrap.status
    research_bootstrap_routes = [int]$researchBootstrap.registered_research_routes
    iteration_learning = [string]$iterationLearning.status
    iteration_pattern_cards = [int]$iterationLearning.pattern_card_count
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
