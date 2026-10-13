[CmdletBinding()]
param(
    [Parameter()]
    [string]$ProjectRoot = $env:TIANZHENG_CAD_AUTOMATION_HOME,

    [Parameter()]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw 'PROJECT_ROOT_MISSING:Set TIANZHENG_CAD_AUTOMATION_HOME or pass -ProjectRoot'
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "CAPABILITY_FILE_MISSING:$Path"
    }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-FileSha256 {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "BOUND_FILE_MISSING:$Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$resolvedRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$packagePath = Join-Path $resolvedRoot 'config\command_packages\batch_polyline_dimension_v1.json'
$validationPath = Join-Path $resolvedRoot 'config\annotation_special_text_peer_normal_validation_v1.json'
$indexPath = Join-Path $resolvedRoot 'config\project_execution_index.json'
$taskRegistryPath = Join-Path $resolvedRoot 'config\cad_native_task_registry.json'

$package = Read-JsonFile -Path $packagePath
$validation = Read-JsonFile -Path $validationPath
$index = Read-JsonFile -Path $indexPath
$null = Read-JsonFile -Path $taskRegistryPath

if ($package.package_id -ne 'CAD-CMD-BATCH-POLYLINE-DIM-V1') {
    throw "PACKAGE_ID_MISMATCH:$($package.package_id)"
}
if ($validation.component_id -ne 'CAD-DIM-SPECIAL-TEXT-PEER-NORMAL-V2') {
    throw "SPECIAL_COMPONENT_ID_MISMATCH:$($validation.component_id)"
}

$implementationChecks = [ordered]@{}
foreach ($bindingName in @('formula', 'planner', 'controller')) {
    $relativePath = [string]$validation.implementation.$bindingName
    $expectedProperty = "${bindingName}_sha256"
    $expected = ([string]$validation.implementation.$expectedProperty).ToUpperInvariant()
    $actual = Get-FileSha256 -Path (Join-Path $resolvedRoot $relativePath)
    $implementationChecks[$bindingName] = [ordered]@{
        path = $relativePath
        expected_sha256 = $expected
        actual_sha256 = $actual
        pass = ($actual -eq $expected)
    }
}

$allHashesPass = -not (@($implementationChecks.Values | Where-Object { -not $_.pass }).Count)
$result = [ordered]@{
    schema_version = 1
    skill = 'tianzheng-batch-polyline-dimension'
    project_root = $resolvedRoot
    loop_id = [string]$index.loop_id
    package_id = [string]$package.package_id
    package_version = [string]$package.version
    package_status = [string]$package.status
    standalone_runnable = [bool]$package.standalone_runnable
    production_ready = [bool]$package.promotion.production_ready
    special_component_status = [string]$validation.status
    special_component_passes = [int]$validation.current_board_validation.consecutive_complete_passes
    special_component_required_passes = [int]$validation.current_board_validation.required_passes
    whole_command_three_pass_status = [string]$validation.test_boundary.whole_blank_to_full_layout_command_three_pass_status
    cross_structure_dwg = [string]$validation.test_boundary.cross_structure_dwg
    ready_handoff_publisher = [string]$index.ready_handoff_publisher
    native_task_registry = 'config/cad_native_task_registry.json'
    implementation_hashes_pass = [bool]$allHashesPass
    implementation = $implementationChecks
    safe_to_claim = [ordered]@{
        special_text_current_board_3_of_3 = ($validation.status -eq 'CURRENT_BOARD_STABILITY_PASS_3_OF_3' -and $allHashesPass)
        complete_command_production_ready = [bool]$package.promotion.production_ready
        cross_structure_generality = ($validation.test_boundary.cross_structure_dwg -eq 'PASS')
    }
}

if (-not $allHashesPass) {
    throw ('IMPLEMENTATION_HASH_MISMATCH:' + ($result | ConvertTo-Json -Depth 8 -Compress))
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
} else {
    [pscustomobject]$result
}
