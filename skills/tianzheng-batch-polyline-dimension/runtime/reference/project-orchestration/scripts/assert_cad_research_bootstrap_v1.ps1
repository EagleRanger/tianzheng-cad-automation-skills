param(
    [string]$ProjectRoot = '',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$root = [IO.Path]::GetFullPath($ProjectRoot)
function Read-Json([string]$RelativePath) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "RESEARCH_BOOTSTRAP_OUTSIDE_PROJECT:$RelativePath" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RESEARCH_BOOTSTRAP_MISSING:$RelativePath" }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$index = Read-Json 'config/project_execution_index.json'
if ([string]$index.iteration_learning.policy -cne 'config/cad_iteration_learning_policy.json') { throw 'RESEARCH_BOOTSTRAP_POLICY_POINTER_INVALID' }
if ([string]$index.iteration_learning.context_builder -cne 'reference/project-orchestration/scripts/get_cad_iteration_context.ps1') { throw 'RESEARCH_BOOTSTRAP_CONTEXT_BUILDER_POINTER_INVALID' }
if ([string]$index.iteration_learning.research_bootstrap_assertion -cne 'reference/project-orchestration/scripts/assert_cad_research_bootstrap_v1.ps1') { throw 'RESEARCH_BOOTSTRAP_INDEX_POINTER_INVALID' }
$requiredBootstrapSources = @([string]$index.iteration_learning.policy,[string]$index.iteration_learning.context_builder,[string]$index.iteration_learning.research_bootstrap_assertion)
$bootstrapSourcePaths = @{}
foreach ($required in $requiredBootstrapSources) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $required))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "RESEARCH_BOOTSTRAP_PARTITION_SOURCE_OUTSIDE_PROJECT:$required" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RESEARCH_BOOTSTRAP_PARTITION_SOURCE_MISSING:$required" }
    $bootstrapSourcePaths[$required] = $path
}
$partitionProperty = $index.PSObject.Properties['context_read_partition']
if ($null -eq $partitionProperty) {
    foreach ($required in $requiredBootstrapSources) {
        if (@($index.command_research_channel_bootstrap_order) -cnotcontains $required) { throw "RESEARCH_BOOTSTRAP_STARTUP_ORDER_MISSING:$required" }
    }
}
else {
    if ([string]$index.iteration_learning.read_mode -cne 'targeted_recall_only__not_a_hot_context_or_execution_authority') { throw 'RESEARCH_BOOTSTRAP_PARTITION_READ_MODE_INVALID' }
    $commandDesign = [string]$partitionProperty.Value.command_design
    if ($commandDesign -notmatch 'get_cad_iteration_context' -or $commandDesign -notmatch 'registered[-_]route') { throw 'RESEARCH_BOOTSTRAP_PARTITION_COMMAND_DESIGN_INVALID' }
}
$policy = Read-Json ([string]$index.iteration_learning.policy)
$routing = Read-Json 'config/cad_command_research_routing_v1.json'
$sharedContracts = Read-Json ([string]$index.shared_contract_knowledge_base)
$aestheticPointer = $sharedContracts.design_policies.annotation_aesthetic
$aestheticPath = Join-Path $root ([string]$aestheticPointer.path)
$acceptancePointer = $sharedContracts.design_policies.acceptance_reuse
$acceptancePath = Join-Path $root ([string]$acceptancePointer.path)
$builder = [string]$bootstrapSourcePaths[[string]$index.iteration_learning.context_builder]
$bootstrap = $policy.shared_research_bootstrap
if ([string]$bootstrap.id -cne 'CAD_COMMAND_RESEARCH_SHARED_BOOTSTRAP_V1') { throw 'RESEARCH_BOOTSTRAP_ID_INVALID' }
if (@($bootstrap.required_component_ids).Count -ne 5) { throw 'RESEARCH_BOOTSTRAP_REQUIRED_COMPONENT_COUNT_INVALID' }
if (@($bootstrap.recall_only_component_ids).Count -ne 3) { throw 'RESEARCH_BOOTSTRAP_RECALL_COMPONENT_COUNT_INVALID' }
if (@($bootstrap.cross_command_lessons).Count -lt 5) { throw 'RESEARCH_BOOTSTRAP_LESSON_COUNT_INVALID' }
$capabilityRecall = $bootstrap.shared_capability_recall
if ([string]$capabilityRecall.id -cne 'CAD-SHARED-CAPABILITY-RECALL-V1' -or [int]$capabilityRecall.max_sources -ne 3 -or @($capabilityRecall.sources).Count -ne 4) { throw 'RESEARCH_BOOTSTRAP_SHARED_CAPABILITY_RECALL_INVALID' }
$capabilityIds = @($capabilityRecall.sources | ForEach-Object { [string]$_.id })
if (@($capabilityIds | Select-Object -Unique).Count -ne $capabilityIds.Count) { throw 'RESEARCH_BOOTSTRAP_SHARED_CAPABILITY_RECALL_DUPLICATE_ID' }
foreach ($source in @($capabilityRecall.sources)) {
    $sourcePath = Join-Path $root ([string]$source.path)
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf) -or @($source.tags).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$source.reference_role)) { throw "RESEARCH_BOOTSTRAP_SHARED_CAPABILITY_SOURCE_INVALID:$($source.id)" }
}

$routeIds = @($routing.routes.PSObject.Properties | Where-Object { $_.Name -cne 'project_shared_core' } | ForEach-Object { $_.Name })
foreach ($routeId in $routeIds) {
    $context = & $builder -ProjectRoot $root -CommandFamily $routeId -Tags @('native-object','grip','property','text') -RequireRegisteredRoute -PassThru
    if ([string]$context.status -cne 'PASS') { throw "RESEARCH_BOOTSTRAP_CONTEXT_FAILED:$routeId" }
    if ([string]$context.command_route.route_id -cne $routeId) { throw "RESEARCH_BOOTSTRAP_ROUTE_MISMATCH:$routeId" }
    if ([string]$context.command_route.shared_bootstrap_profile -cne [string]$bootstrap.id) { throw "RESEARCH_BOOTSTRAP_PROFILE_MISMATCH:$routeId" }
    if (@($context.shared_research_bootstrap.required_components).Count -ne 5) { throw "RESEARCH_BOOTSTRAP_REQUIRED_COMPONENTS_UNRESOLVED:$routeId" }
    if (@($context.shared_research_bootstrap.recall_only_components).Count -ne 3) { throw "RESEARCH_BOOTSTRAP_RECALL_COMPONENTS_UNRESOLVED:$routeId" }
    if ([bool]$context.shared_research_bootstrap.native_access_contract.external_nativeom_default) { throw "RESEARCH_BOOTSTRAP_NATIVEOM_DEFAULT_INVALID:$routeId" }
    $sharedCapabilities = $context.shared_research_bootstrap.shared_capability_recall
    if ([string]$sharedCapabilities.id -cne [string]$capabilityRecall.id -or @($sharedCapabilities.sources).Count -ne 3 -or @($sharedCapabilities.sources | Where-Object { [bool]$_.grants_runtime_authority }).Count -ne 0) { throw "RESEARCH_BOOTSTRAP_SHARED_CAPABILITY_RECALL_DRIFT:$routeId" }
    if (@($sharedCapabilities.sources | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root ([string]$_.path)) -PathType Leaf) }).Count -ne 0) { throw "RESEARCH_BOOTSTRAP_SHARED_CAPABILITY_SOURCE_MISSING:$routeId" }
    $aesthetic = $context.shared_research_bootstrap.annotation_aesthetic
    if ([string]$aesthetic.path -cne [string]$aestheticPointer.path -or [string]$aesthetic.policy.id -cne [string]$aestheticPointer.id -or [string]$aesthetic.sha256 -cne (Get-FileHash -LiteralPath $aestheticPath -Algorithm SHA256).Hash) { throw "RESEARCH_BOOTSTRAP_AESTHETIC_RECALL_DRIFT:$routeId" }
    if ([string]$aesthetic.policy.knowledge_type -cne 'user_design_requirement' -or [bool]$aesthetic.policy.workflow_boundary.runtime_authorization) { throw "RESEARCH_BOOTSTRAP_AESTHETIC_AUTHORITY_INVALID:$routeId" }
    $acceptance = $context.shared_research_bootstrap.acceptance_reuse
    if ([string]$acceptance.profile.id -cne [string]$acceptancePointer.id -or [string]$acceptance.sha256 -cne (Get-FileHash -LiteralPath $acceptancePath -Algorithm SHA256).Hash) { throw "RESEARCH_BOOTSTRAP_ACCEPTANCE_REUSE_DRIFT:$routeId" }
    if ($acceptance.profile.routine_three_repeat_required -or $acceptance.profile.scope_rules.new_CAD_authority -or $acceptance.profile.scope_rules.new_kernel_or_runtime_gate) { throw "RESEARCH_BOOTSTRAP_ACCEPTANCE_SCOPE_INVALID:$routeId" }
}
$unknownRejected = $false
try {
    & $builder -ProjectRoot $root -CommandFamily '__unknown_cad_command__' -RequireRegisteredRoute -PassThru | Out-Null
} catch {
    if ($_.Exception.Message -like 'ITERATION_COMMAND_ROUTE_UNKNOWN:*') { $unknownRejected = $true } else { throw }
}
if (-not $unknownRejected) { throw 'RESEARCH_BOOTSTRAP_UNKNOWN_ROUTE_NOT_REJECTED' }

$result = [pscustomobject]@{
    status = 'PASS'
    bootstrap_id = [string]$bootstrap.id
    registered_research_routes = $routeIds.Count
    required_components = @($bootstrap.required_component_ids).Count
    recall_only_components = @($bootstrap.recall_only_component_ids).Count
    cross_command_lessons = @($bootstrap.cross_command_lessons).Count
    annotation_aesthetic_policy = [string]$aestheticPointer.id
    annotation_aesthetic_recall_routes = $routeIds.Count
    acceptance_reuse_recall_routes = $routeIds.Count
    unknown_route_rejected = $unknownRejected
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
