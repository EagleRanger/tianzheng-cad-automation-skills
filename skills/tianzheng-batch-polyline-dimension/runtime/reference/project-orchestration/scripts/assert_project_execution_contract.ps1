param(
    [Parameter(Mandatory = $true)][string]$PhaseId,
    [Parameter(Mandatory = $true)][string]$WorkflowId,
    [Parameter(Mandatory = $true)][ValidateSet('production','validation')][string]$Mode,
    [string]$Entrypoint = '',
    [string]$ContextSnapshotOutputPath = '',
    [switch]$AllowFrozenUpstreamPrerequisite
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$indexPath = Join-Path $projectRoot 'config\project_execution_index.json'
if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { throw 'PROJECT_EXECUTION_INDEX_MISSING' }
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$index.schema_version -ne 4 -or [string]$index.status -cne 'active') { throw 'PROJECT_EXECUTION_INDEX_NOT_ACTIVE_V4' }

$roadmapPath = Join-Path $projectRoot ([string]$index.roadmap)
$roadmap = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentPhase = [string]$roadmap.current_phase
$currentRows = @($roadmap.phases | Where-Object { [string]$_.id -ceq $currentPhase })
if ($currentRows.Count -ne 1) { throw 'ROADMAP_CURRENT_PHASE_NOT_UNIQUE' }

$isCurrentPhase = $currentPhase -ceq $PhaseId
$isFrozenUpstreamPrerequisite = $false
if (-not $isCurrentPhase -and $AllowFrozenUpstreamPrerequisite) {
    # P3 relayout may rebuild its clean native baseline only through the exact
    # frozen, verified P1/P2 generators.  No other completed phase is
    # implicitly executable.
    $isFrozenUpstreamPrerequisite =
        $currentPhase -ceq 'P3_NATIVE_DIMENSION_RELAYOUT' -and
        $Mode -ceq 'validation' -and
        (
            ($PhaseId -ceq 'P1_ARC_ANGLE_FAST_COMPLETE' -and $WorkflowId -ceq 'TZ-TDIMARC-FULL-BATCH-V2') -or
            ($PhaseId -ceq 'P2_LINE_LENGTH_AND_TYPED_SWITCH' -and $WorkflowId -ceq 'TZ-TDIM-TYPED-SEGMENT-V1')
        )
}
if (-not $isCurrentPhase -and -not $isFrozenUpstreamPrerequisite) {
    throw "PHASE_NOT_CURRENT:${PhaseId}:$currentPhase"
}

$snapshotScript = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/get_cad_pre_run_authority_snapshot.ps1'
$snapshot = if ([string]::IsNullOrWhiteSpace($ContextSnapshotOutputPath)) {
    & $snapshotScript
} else {
    & $snapshotScript -OutputPath $ContextSnapshotOutputPath
}
if ([string]$snapshot.status -cne 'PASS' -or [string]$snapshot.snapshot_type -cne 'pre_run_authority_snapshot') {
    throw 'PRE_RUN_AUTHORITY_SNAPSHOT_INVALID'
}
if ([string]$snapshot.current_phase -cne $currentPhase) { throw 'PRE_RUN_SNAPSHOT_PHASE_MISMATCH' }

$phase = @($roadmap.phases | Where-Object { [string]$_.id -ceq $PhaseId })
if ($phase.Count -ne 1) { throw 'TARGET_PHASE_NOT_UNIQUE_IN_ROADMAP' }
if ($isFrozenUpstreamPrerequisite) {
    if ([string]$phase[0].status -cne 'completed') { throw 'UPSTREAM_PREREQUISITE_PHASE_NOT_COMPLETED' }
    $registry = Get-Content -LiteralPath (Join-Path $projectRoot ([string]$index.workflow_registry)) -Raw -Encoding UTF8 | ConvertFrom-Json
    $workflow = @($registry.workflows | Where-Object { [string]$_.id -ceq $WorkflowId })
    if ($workflow.Count -ne 1 -or [string]$workflow[0].status -cne 'verified' -or -not [bool]$workflow[0].frozen) {
        throw 'UPSTREAM_PREREQUISITE_WORKFLOW_NOT_VERIFIED_AND_FROZEN'
    }
}
elseif ([string]$phase[0].status -notin @('active','in_progress')) {
    throw "CURRENT_PHASE_STATUS_NOT_EXECUTABLE:$($phase[0].status)"
}

& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_verified_workflow.ps1') -WorkflowId $WorkflowId -Mode $Mode -Entrypoint $Entrypoint | Out-Null

[pscustomobject]@{
    status = 'PASS'
    phase_id = $PhaseId
    workflow_id = $WorkflowId
    mode = $Mode
    execution_role = if ($isFrozenUpstreamPrerequisite) { 'frozen_upstream_prerequisite' } else { 'current_phase' }
    pre_run_snapshot_path = if ([string]::IsNullOrWhiteSpace($ContextSnapshotOutputPath)) { '' } else { [IO.Path]::GetFullPath($ContextSnapshotOutputPath) }
    execution_authority_digest = [string]$snapshot.execution_authority_digest
    model_bootstrap_digest = [string]$snapshot.model_bootstrap_digest
}
