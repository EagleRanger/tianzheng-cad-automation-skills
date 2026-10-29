param(
    [switch]$PassThru,
    [string]$RegistryPath,
    [string]$PreflightPath,
    [string]$IndexPath,
    [string]$TombstonePath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$registryPath = if ($RegistryPath) { $RegistryPath } else { Join-Path $projectRoot 'config\verified_workflow_registry.json' }
$preflightPath = if ($PreflightPath) { $PreflightPath } else { Join-Path $projectRoot 'config\tianzheng_execution_preflight.json' }
$indexPath = if ($IndexPath) { $IndexPath } else { Join-Path $projectRoot 'config\project_execution_index.json' }
$tombstonePath = if ($TombstonePath) { $TombstonePath } else { Join-Path $projectRoot 'config\rejected_legacy_entrypoints.json' }

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$preflight = Get-Content -LiteralPath $preflightPath -Raw -Encoding UTF8 | ConvertFrom-Json
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$componentRegistryPath = Join-Path $projectRoot 'config\cad_automation_component_packages.json'
$dispatcherPath = Join-Path $projectRoot 'scripts\invoke_owned_tianzheng_whitelist_action.ps1'
if (-not (Test-Path -LiteralPath $componentRegistryPath -PathType Leaf)) { throw 'COMPONENT_REGISTRY_MISSING' }
if (-not (Test-Path -LiteralPath $dispatcherPath -PathType Leaf)) { throw 'WHITELIST_DISPATCHER_MISSING' }
$componentRegistry = Get-Content -LiteralPath $componentRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$dispatcherText = Get-Content -LiteralPath $dispatcherPath -Raw -Encoding UTF8
if (-not (Test-Path -LiteralPath $tombstonePath -PathType Leaf)) { throw 'REJECTED_ENTRYPOINT_TOMBSTONE_MISSING' }
$tombstone = Get-Content -LiteralPath $tombstonePath -Raw -Encoding UTF8 | ConvertFrom-Json

function Normalize-RelativePath([string]$Value) {
    return $Value.Replace('\','/').TrimStart('/')
}

$blocked = @($registry.blocked_legacy_paths | ForEach-Object { Normalize-RelativePath ([string]$_) })
$deleted = @($tombstone.deleted_entrypoints | ForEach-Object { Normalize-RelativePath ([string]$_.path) })
$forbiddenPaths = @($blocked + $deleted | Sort-Object -Unique)
$removedWorkflowIds = @($tombstone.deleted_entrypoints | ForEach-Object { $p = $_.PSObject.Properties['removed_workflow_ids']; if ($null -ne $p) { @($p.Value) } } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
$removedComponentIds = @($tombstone.deleted_entrypoints | ForEach-Object { $p = $_.PSObject.Properties['removed_component_ids']; if ($null -ne $p) { @($p.Value) } } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
$removedActions = @($tombstone.deleted_entrypoints | ForEach-Object { $p = $_.PSObject.Properties['removed_actions']; if ($null -ne $p) { @($p.Value) } } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -Unique)
$active = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$violations = [Collections.Generic.List[string]]::new()

foreach ($path in $deleted) {
    if (Test-Path -LiteralPath (Join-Path $projectRoot $path)) {
        $violations.Add("TOMBSTONED_ENTRYPOINT_RECREATED:$path")
    }
}
foreach ($workflowId in $removedWorkflowIds) {
    if (@($registry.workflows | Where-Object { [string]$_.id -ceq [string]$workflowId }).Count -gt 0) {
        $violations.Add("TOMBSTONED_WORKFLOW_RECREATED:$workflowId")
    }
    foreach ($activeWorkflow in $registry.active_workflows.PSObject.Properties.Value) {
        if ([string]$activeWorkflow -ceq [string]$workflowId) { $violations.Add("TOMBSTONED_WORKFLOW_REACTIVATED:$workflowId") }
    }
}
foreach ($componentId in $removedComponentIds) {
    if (@($componentRegistry.components | Where-Object { [string]$_.id -ceq [string]$componentId }).Count -gt 0) {
        $violations.Add("TOMBSTONED_COMPONENT_RECREATED:$componentId")
    }
}
foreach ($action in $removedActions) {
    foreach ($component in @($componentRegistry.components)) {
        $allowedActionsProperty = $component.PSObject.Properties['allowed_actions']
        if ($null -ne $allowedActionsProperty -and @($allowedActionsProperty.Value) -ccontains [string]$action) {
            $violations.Add("TOMBSTONED_ACTION_REACTIVATED_IN_COMPONENT:${action}:$($component.id)")
        }
    }
    if ($dispatcherText.IndexOf([string]$action, [StringComparison]::Ordinal) -ge 0) {
        $violations.Add("TOMBSTONED_ACTION_RECREATED_IN_DISPATCHER:$action")
    }
}
foreach ($phase in $preflight.phase_entrypoints.PSObject.Properties) {
    foreach ($value in @($phase.Value)) { [void]$active.Add((Normalize-RelativePath ([string]$value))) }
}
foreach ($workflowId in $registry.active_workflows.PSObject.Properties.Value) {
    if ($null -eq $workflowId -or [string]::IsNullOrWhiteSpace([string]$workflowId)) { continue }
    $workflow = @($registry.workflows | Where-Object { $_.id -ceq [string]$workflowId })
    if ($workflow.Count -ne 1) { throw "ACTIVE_WORKFLOW_ID_INVALID:$workflowId" }
    if ([string]$workflow[0].status -cne 'verified') {
        $violations.Add("ACTIVE_WORKFLOW_NOT_VERIFIED:${workflowId}:$($workflow[0].status)")
    }
    foreach ($property in $workflow[0].implementation.PSObject.Properties) {
        $value = [string]$property.Value
        if ($value -match '\.(ps1|lsp|dll)$') { [void]$active.Add((Normalize-RelativePath $value)) }
    }
}

foreach ($path in $active) {
    if ($forbiddenPaths -ccontains $path) { $violations.Add("ACTIVE_PATH_IS_BLOCKED_OR_DELETED:$path") }
}

$quarantinePatterns = @($preflight.quarantined_paths | ForEach-Object { Normalize-RelativePath ([string]$_) })
foreach ($path in $active) {
    foreach ($pattern in $quarantinePatterns) {
        $matcher = [WildcardPattern]::new($pattern, [Management.Automation.WildcardOptions]::IgnoreCase)
        if ($matcher.IsMatch($path)) { $violations.Add("ACTIVE_PATH_IS_QUARANTINED:${path}:${pattern}") }
    }
}

foreach ($path in $active) {
    $full = Join-Path $projectRoot $path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $violations.Add("ACTIVE_ENTRYPOINT_MISSING:$path")
        continue
    }
    $extension = [IO.Path]::GetExtension($full)
    if ($extension -notin @('.ps1','.lsp','.py','.json')) { continue }
    $text = Get-Content -LiteralPath $full -Raw -Encoding UTF8
    foreach ($legacyPath in $forbiddenPaths) {
        $legacyName = [IO.Path]::GetFileName($legacyPath)
        if ($text.IndexOf($legacyName, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $violations.Add("ACTIVE_ENTRYPOINT_REFERENCES_BLOCKED_PATH:${path}:${legacyPath}")
        }
    }
}

$roadmapPath = Join-Path $projectRoot ([string]$index.roadmap)
$loopPath = Join-Path $projectRoot ([string]$index.machine_loop)
foreach ($authority in @($roadmapPath, $loopPath)) {
    if (-not (Test-Path -LiteralPath $authority -PathType Leaf)) {
        $violations.Add("PHASE_AUTHORITY_MISSING:$authority")
    }
}
if ((Test-Path -LiteralPath $roadmapPath -PathType Leaf) -and (Test-Path -LiteralPath $loopPath -PathType Leaf)) {
    $roadmap = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $loop = Get-Content -LiteralPath $loopPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $current = @($roadmap.phases | Where-Object { [string]$_.id -ceq [string]$roadmap.current_phase })
    if ($current.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$current[0].detail)) { $violations.Add('ROADMAP_CURRENT_PHASE_INVALID') }
    if ([string]$loop.project_authorities.roadmap -cne [string]$index.roadmap) { $violations.Add('PROJECT_LOOP_ROADMAP_POINTER_MISMATCH') }
}

if ($violations.Count -gt 0) {
    throw ('BLOCKED_WORKFLOW_REFERENCE_AUDIT_FAILED:' + ($violations -join '|'))
}

$result = [pscustomobject]@{
    status = 'PASS'
    active_entrypoints_checked = $active.Count
    blocked_paths_checked = $blocked.Count
    deleted_entrypoints_checked = $deleted.Count
    removed_workflow_ids_checked = $removedWorkflowIds.Count
    removed_component_ids_checked = $removedComponentIds.Count
    removed_actions_checked = $removedActions.Count
    violations = 0
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
