param(
    [Parameter(Mandatory = $true)][string]$ComponentId,
    [Parameter(Mandatory = $true)][string]$GoverningPhaseId,
    [Parameter(Mandatory = $true)][string]$WorkflowPhaseId,
    [Parameter(Mandatory = $true)][string]$WorkflowId,
    [Parameter(Mandatory = $true)][ValidateSet('production','validation')][string]$WorkflowMode,
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $true)][string]$ScopeContractPath,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [string]$ReferenceContractPath = '',
    [ValidateSet('','view_only','ordinary_test','final_stability','saved_delivery')][string]$AcceptanceProfile = '',
    [string]$ParentManifestPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Resolve-ProjectFile([string]$Raw, [string]$Code) {
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $Raw)) }
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "${Code}_OUTSIDE_PROJECT" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}_MISSING" }
    return $path
}
function Get-TextSha256([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','') }
    finally { $sha.Dispose() }
}
function Get-SharedFileSha256([string]$Path) {
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}
function Get-Relative([string]$Path) { return ([IO.Path]::GetFullPath($Path)).Substring($projectRoot.Length + 1).Replace('\','/') }

$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'COMPONENT_CONTRACT_REPORT_OUTSIDE_PROJECT' }
New-Item -ItemType Directory -Path $report -Force | Out-Null
$output = Join-Path $report 'execution_contract.json'
if (Test-Path -LiteralPath $output) { throw 'COMPONENT_CONTRACT_ALREADY_EXISTS' }

$registryPath = Resolve-ProjectFile (Join-Path $projectRoot 'config\cad_automation_component_packages.json') 'COMPONENT_REGISTRY'
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reusableIds = @($registry.component_selection_policy.active_reusable_component_ids | ForEach-Object { [string]$_ })
if ($ComponentId -notin $reusableIds) { throw "COMPONENT_NOT_IN_ACTIVE_REUSABLE_SET:$ComponentId" }
$matches = @($registry.components | Where-Object { [string]$_.id -ceq $ComponentId })
if ($matches.Count -ne 1) { throw 'COMPONENT_ID_NOT_UNIQUE' }
$component = $matches[0]
$componentStatus = [string]$component.status
if ($componentStatus -in @('planned','blocked','rejected','superseded')) { throw "COMPONENT_STATUS_NOT_CALLABLE:${ComponentId}:$componentStatus" }
if ($WorkflowMode -ceq 'production' -and $componentStatus -notin @('verified','active_with_regression')) { throw "COMPONENT_NOT_PRODUCTION_READY:${ComponentId}:$componentStatus" }
if ([string]::IsNullOrWhiteSpace([string]$component.version)) { throw 'COMPONENT_VERSION_MISSING' }
if (@($component.allowed_workflows).Count -gt 0 -and $WorkflowId -notin @($component.allowed_workflows)) { throw "COMPONENT_WORKFLOW_NOT_ALLOWED:$WorkflowId" }
if (@($component.allowed_actions).Count -gt 0 -and $Action -notin @($component.allowed_actions)) { throw "COMPONENT_ACTION_NOT_ALLOWED:$Action" }
$componentRecordHash = Get-TextSha256 ($component | ConvertTo-Json -Depth 30 -Compress)

$scopePath = Resolve-ProjectFile $ScopeContractPath 'COMPONENT_SCOPE'
$scope = Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$scope.component_id -cne $ComponentId -or [string]$scope.governing_phase_id -cne $GoverningPhaseId) { throw 'COMPONENT_SCOPE_IDENTITY_MISMATCH' }
if ($Action -notin @($scope.allowed_actions)) { throw "COMPONENT_ACTION_NOT_ALLOWED:$Action" }
$baselinePath = Resolve-ProjectFile (Join-Path $projectRoot ([string]$scope.baseline.path)) 'COMPONENT_BASELINE'
$baselineHash = Get-SharedFileSha256 $baselinePath
if ($baselineHash -cne [string]$scope.baseline.sha256) { throw 'COMPONENT_BASELINE_HASH_MISMATCH' }

$gateConfigPath = Resolve-ProjectFile (Join-Path $projectRoot 'config\cad_acceptance_gates.json') 'ACCEPTANCE_GATE_CONFIG'
$gateConfig = Get-Content -LiteralPath $gateConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($AcceptanceProfile)) { $AcceptanceProfile = if ($WorkflowMode -ceq 'production') { 'saved_delivery' } else { 'ordinary_test' } }
$requiredGates = @($component.required_acceptance_gate_ids | ForEach-Object { [string]$_ })
if ($requiredGates.Count -eq 0) { $requiredGates = @($gateConfig.profiles.$AcceptanceProfile.required_gate_ids) }

$reference = $null
if (-not [string]::IsNullOrWhiteSpace($ReferenceContractPath)) {
    $referencePath = Resolve-ProjectFile $ReferenceContractPath 'REFERENCE_CONTRACT'
    $referenceJson = Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($WorkflowMode -ceq 'production' -and [string]$referenceJson.status -notmatch 'ACCEPTED|VERIFIED|FROZEN') { throw 'REFERENCE_CONTRACT_NOT_PRODUCTION_ACCEPTED' }
    $reference = [ordered]@{ path=Get-Relative $referencePath; sha256=(Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash; profile_id=[string]$referenceJson.profile_id; status=[string]$referenceJson.status }
}

$parent = $null
if (-not [string]::IsNullOrWhiteSpace($ParentManifestPath)) {
    $parentPath = Resolve-ProjectFile $ParentManifestPath 'PARENT_MANIFEST'
    $parent = [ordered]@{ path=Get-Relative $parentPath; sha256=(Get-FileHash -LiteralPath $parentPath -Algorithm SHA256).Hash }
}

$contract = [ordered]@{
    schema_version = 1
    status = 'PREPARED'
    contract_id = "CADRUN-$([guid]::NewGuid().ToString('N'))"
    created_at = (Get-Date).ToString('o')
    governing_phase_id = $GoverningPhaseId
    workflow_phase_id = $WorkflowPhaseId
    workflow = [ordered]@{ id=$WorkflowId; mode=$WorkflowMode; action=$Action }
    component = [ordered]@{
        id = $ComponentId
        version = [string]$component.version
        registry_path = Get-Relative $registryPath
        registry_sha256 = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash
        record_sha256 = $componentRecordHash
        entry = [string]$component.entry
    }
    baseline = [ordered]@{ path=Get-Relative $baselinePath; sha256=$baselineHash; evidence_level=[string]$scope.baseline.evidence_level }
    scope = [ordered]@{ id=[string]$scope.scope_id; path=Get-Relative $scopePath; sha256=(Get-FileHash -LiteralPath $scopePath -Algorithm SHA256).Hash; frozen_annotation_count=@($scope.frozen_annotation_handles).Count }
    reference_contract = $reference
    lineage = [ordered]@{ parent_manifest=$parent }
    acceptance = [ordered]@{ gate_config_path=Get-Relative $gateConfigPath; gate_config_sha256=(Get-FileHash -LiteralPath $gateConfigPath -Algorithm SHA256).Hash; profile=$AcceptanceProfile; reuse_profile_id=[string]$gateConfig.reuse_profile.id; required_gate_ids=$requiredGates }
}
$temporary = $output + '.tmp'
[IO.File]::WriteAllText($temporary, ($contract | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $output
& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_component_execution_contract.ps1') -ExecutionContractPath $output | Out-Null
[pscustomobject]@{ status='PASS'; contract_path=$output; contract_id=$contract.contract_id; required_gate_count=$requiredGates.Count }
