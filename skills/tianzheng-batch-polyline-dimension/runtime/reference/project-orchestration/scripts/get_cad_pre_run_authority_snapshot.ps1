param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Get-BytesSha256([byte[]]$Bytes) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-','') }
    finally { $algorithm.Dispose() }
}

function Resolve-ProjectFile([string]$RelativeRaw, [string]$ErrorPrefix) {
    if ([string]::IsNullOrWhiteSpace($RelativeRaw)) { throw "${ErrorPrefix}_EMPTY" }
    $relative = $RelativeRaw.Replace('/','\')
    $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "${ErrorPrefix}_OUTSIDE_PROJECT:$RelativeRaw"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${ErrorPrefix}_MISSING:$RelativeRaw" }
    return $path
}

function Get-FileRecord([string]$RelativeRaw, [string]$ErrorPrefix) {
    $path = Resolve-ProjectFile $RelativeRaw $ErrorPrefix
    $bytes = [IO.File]::ReadAllBytes($path)
    if ([IO.Path]::GetExtension($path) -ieq '.json') {
        [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json | Out-Null
    }
    return [pscustomobject]@{
        relative_path = $RelativeRaw.Replace('\','/')
        sha256 = Get-BytesSha256 $bytes
        length = [long]$bytes.Length
    }
}

function Get-UniquePaths([object[]]$Paths) {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result = [Collections.Generic.List[string]]::new()
    foreach ($item in $Paths) {
        $value = ([string]$item).Replace('\','/')
        if ($seen.Add($value)) { $result.Add($value) }
    }
    return @($result)
}

function Get-RecordDigest([object[]]$Records) {
    $material = @($Records | ForEach-Object { "$($_.relative_path)|$($_.sha256)|$($_.length)" }) -join "`n"
    return Get-BytesSha256 ([Text.Encoding]::UTF8.GetBytes($material))
}

$indexPath = Resolve-ProjectFile 'config/project_execution_index.json' 'PROJECT_EXECUTION_INDEX'
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$index.schema_version -ne 4 -or [string]$index.status -cne 'active') { throw 'PROJECT_EXECUTION_INDEX_NOT_ACTIVE_V4' }
if ([string]$index.loop_id -cne 'auto-CAD-project-loop') { throw 'PROJECT_EXECUTION_INDEX_LOOP_MISMATCH' }

$canonicalOpenAssertionPath = Resolve-ProjectFile 'reference/project-orchestration/scripts/assert_cad_canonical_open_consistency.ps1' 'CANONICAL_OPEN_ASSERTION'
try {
    $canonicalOpenAssertion = (& $canonicalOpenAssertionPath | Out-String).Trim() | ConvertFrom-Json
}
catch {
    throw 'PRE_RUN_CANONICAL_OPEN_CONSISTENCY_FAILED:' + $_.Exception.Message
}

$roadmapPath = Resolve-ProjectFile ([string]$index.roadmap) 'ROADMAP'
$roadmap = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentPhaseId = [string]$roadmap.current_phase
$currentPhases = @($roadmap.phases | Where-Object { [string]$_.id -ceq $currentPhaseId })
if ($currentPhases.Count -ne 1) { throw 'ROADMAP_CURRENT_PHASE_NOT_UNIQUE' }
$phaseDetail = [string]$currentPhases[0].detail
if ([string]::IsNullOrWhiteSpace($phaseDetail)) { throw 'ROADMAP_CURRENT_PHASE_DETAIL_MISSING' }

$executionPaths = Get-UniquePaths (@($index.execution_authority_hash_order) + @($phaseDetail))
$modelPaths = Get-UniquePaths (@($index.model_bootstrap_order) + @($phaseDetail))
$executionAuthorities = @($executionPaths | ForEach-Object { Get-FileRecord $_ 'EXECUTION_AUTHORITY' })
$modelDocuments = @($modelPaths | ForEach-Object { Get-FileRecord $_ 'MODEL_BOOTSTRAP' })

$runStatePath = [string]$index.pre_run_state_snapshot
$runStateRecord = Get-FileRecord $runStatePath 'PRE_RUN_STATE'
$runStateJson = Get-Content -LiteralPath (Resolve-ProjectFile $runStatePath 'PRE_RUN_STATE') -Raw -Encoding UTF8 | ConvertFrom-Json

$snapshot = [ordered]@{
    schema_version = 2
    status = 'PASS'
    snapshot_type = 'pre_run_authority_snapshot'
    generated_at = (Get-Date).ToString('o')
    loop_id = 'auto-CAD-project-loop'
    current_phase = $currentPhaseId
    current_phase_detail = $phaseDetail.Replace('\','/')
    execution_authority_digest = Get-RecordDigest $executionAuthorities
    execution_authority_count = $executionAuthorities.Count
    execution_authorities = $executionAuthorities
    model_bootstrap_digest = Get-RecordDigest $modelDocuments
    model_bootstrap_count = $modelDocuments.Count
    model_bootstrap_documents = $modelDocuments
    pre_run_state = [ordered]@{
        relative_path = $runStateRecord.relative_path
        sha256 = $runStateRecord.sha256
        length = $runStateRecord.length
        recorded_phase = [string]$runStateJson.current_phase
        recorded_status = [string]$runStateJson.execution_return.status
    }
    canonical_open = [ordered]@{
        status = [string]$canonicalOpenAssertion.status
        component = [string]$canonicalOpenAssertion.component
        component_version = [string]$canonicalOpenAssertion.component_version
        transport = [string]$canonicalOpenAssertion.transport
        handoff_status = [string]$canonicalOpenAssertion.handoff_status
    }
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    if (-not $resolvedOutput.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'PRE_RUN_SNAPSHOT_OUTPUT_OUTSIDE_PROJECT'
    }
    $parent = Split-Path -Parent $resolvedOutput
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temp = $resolvedOutput + '.tmp'
    [IO.File]::WriteAllText($temp, ($snapshot | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $resolvedOutput -Force
}

[pscustomobject]$snapshot
