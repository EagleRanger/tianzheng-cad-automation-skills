param(
    [Parameter(Mandatory = $true)][string]$PhaseId,
    [Parameter(Mandatory = $true)][string]$WorkflowId,
    [Parameter(Mandatory = $true)][ValidateSet('production','validation')][string]$WorkflowMode,
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$Entrypoint,
    [Parameter(Mandatory = $true)][string]$TaskSpecPath,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [long]$WindowHandle = 0,
    [string]$PreRunSnapshotPath = '',
    [string]$ExecutionContractPath = '',
    [switch]$AllowNonCurrentGoverningPhase
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'EXECUTION_REPORT_DIRECTORY_OUTSIDE_PROJECT'
}
New-Item -ItemType Directory -Path $report -Force | Out-Null
$manifestPath = Join-Path $report 'execution_manifest.json'
if (Test-Path -LiteralPath $manifestPath) { throw 'EXECUTION_MANIFEST_ALREADY_EXISTS_USE_UNIQUE_REPORT_DIRECTORY' }
$snapshotPath = Join-Path $report 'pre_run_authority_snapshot.json'
if ([string]::IsNullOrWhiteSpace($PreRunSnapshotPath)) {
    $snapshot = & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/get_cad_pre_run_authority_snapshot.ps1') -OutputPath $snapshotPath
} else {
    $suppliedSnapshot = [IO.Path]::GetFullPath($PreRunSnapshotPath)
    if (-not $suppliedSnapshot.Equals($snapshotPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'PRE_RUN_SNAPSHOT_MUST_BE_COLOCATED_WITH_MANIFEST'
    }
    if (-not (Test-Path -LiteralPath $suppliedSnapshot -PathType Leaf)) { throw 'PRE_RUN_SNAPSHOT_MISSING' }
    $snapshot = Get-Content -LiteralPath $suppliedSnapshot -Raw -Encoding UTF8 | ConvertFrom-Json
}
if ([string]$snapshot.status -cne 'PASS' -or [string]$snapshot.snapshot_type -cne 'pre_run_authority_snapshot') {
    throw 'MANIFEST_PRE_RUN_AUTHORITY_SNAPSHOT_FAILED'
}
$index = Get-Content -LiteralPath (Join-Path $projectRoot 'config\project_execution_index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = $null
$componentScope = $null
$contractPath = $null
$governingPhaseId = $PhaseId
$contractRequired = [bool]$index.governed_write_requires_execution_contract -and ([string]$snapshot.current_phase -in @($index.governed_write_required_phases))
if ($contractRequired -and [string]::IsNullOrWhiteSpace($ExecutionContractPath)) { throw 'GOVERNED_WRITE_EXECUTION_CONTRACT_REQUIRED' }
if (-not [string]::IsNullOrWhiteSpace($ExecutionContractPath)) {
    $contractPath = [IO.Path]::GetFullPath($ExecutionContractPath)
    $expectedContractPath = Join-Path $report 'execution_contract.json'
    if (-not $contractPath.Equals($expectedContractPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'EXECUTION_CONTRACT_MUST_BE_COLOCATED_WITH_MANIFEST' }
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_component_execution_contract.ps1') -ExecutionContractPath $contractPath -TaskSpecPath $TaskSpecPath | Out-Null
    $contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $scopePath = [IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$contract.scope.path)))
    if (-not $scopePath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $scopePath -PathType Leaf)) {
        throw 'EXECUTION_CONTRACT_SCOPE_MISSING_OR_OUTSIDE_PROJECT'
    }
    $componentScope = Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $governingPhaseId = [string]$contract.governing_phase_id
    if ([string]$contract.workflow_phase_id -cne $PhaseId -or [string]$contract.workflow.id -cne $WorkflowId -or [string]$contract.workflow.mode -cne $WorkflowMode -or [string]$contract.workflow.action -cne $Action) {
        throw 'EXECUTION_CONTRACT_WORKFLOW_MISMATCH'
    }
}
if ([string]$snapshot.current_phase -cne $governingPhaseId -and -not $AllowNonCurrentGoverningPhase) { throw 'MANIFEST_PRE_RUN_GOVERNING_PHASE_MISMATCH' }

$owner = Get-Content -LiteralPath $OwnerStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId) { throw 'MANIFEST_OWNER_STATE_MISMATCH' }
$target = [IO.Path]::GetFullPath([string]$owner.target_dwg)
if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'MANIFEST_TARGET_DWG_MISSING' }
$ownerRecordedHash = if ($owner.target_sha256) { [string]$owner.target_sha256 } elseif ($owner.baseline_sha256) { [string]$owner.baseline_sha256 } else { '' }
$targetHashSource = 'LIVE_FILE'
$targetHashLiveVerified = $true
try {
    $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
}
catch {
    # AutoCAD/Tianzheng may exclusively lock the active DWG.  In that state the
    # live file cannot be hashed without closing the verified owned session.
    # Fall back only to the pre-open hash recorded by the matching owner state,
    # and only while one responsive owned acad process is present.  The caller
    # has already proved the visible title/current document before invoking this
    # manifest gate; this block prevents a sharing violation from bypassing the
    # ownership contract.
    $ownedAcad = @(Get-Process acad -ErrorAction SilentlyContinue)
    $targetName = [IO.Path]::GetFileName($target)
    $ownerTitle = [string]$owner.main_window_title
    if (-not $ownerRecordedHash -or
        $ownedAcad.Count -ne 1 -or
        $ownedAcad[0].Id -ne $ProcessId -or
        -not $ownedAcad[0].Responding -or
        [string]::IsNullOrWhiteSpace($ownerTitle) -or
        $ownerTitle.IndexOf($targetName, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'MANIFEST_TARGET_HASH_UNAVAILABLE_WITHOUT_VERIFIED_OWNED_LOCK'
    }
    $targetHash = $ownerRecordedHash
    $targetHashSource = 'OWNER_STATE_PREOPEN_LOCKED_TARGET'
    $targetHashLiveVerified = $false
}
if ($ownerRecordedHash -and $targetHash -cne $ownerRecordedHash) { throw 'MANIFEST_TARGET_HASH_MISMATCH' }
if ($contract -and $targetHash -cne [string]$contract.baseline.sha256) { throw 'MANIFEST_TARGET_NOT_CONTRACT_BASELINE' }

$entry = [IO.Path]::GetFullPath($Entrypoint)
$spec = [IO.Path]::GetFullPath($TaskSpecPath)
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'MANIFEST_ENTRYPOINT_MISSING' }
if (-not (Test-Path -LiteralPath $spec -PathType Leaf)) { throw 'MANIFEST_TASK_SPEC_MISSING' }
$specText = Get-Content -LiteralPath $spec -Raw -Encoding UTF8
$handles = @([regex]::Matches($specText, '\("(?<handle>[0-9A-F]+)"\s+\(\("', 'IgnoreCase') | ForEach-Object { $_.Groups['handle'].Value.ToUpperInvariant() } | Select-Object -Unique)
$segmentMatches = @([regex]::Matches($specText, '\("(?<type>ARC|LINE)"\s+(?<index>\d+)\)', 'IgnoreCase'))
$segments = @($segmentMatches | ForEach-Object {
    [pscustomobject]@{ type = $_.Groups['type'].Value.ToUpperInvariant(); index = [int]$_.Groups['index'].Value }
})
$cleanupMatch = [regex]::Match(
    $specText,
    "(?is)\(setq\s+cx:\*full-batch-cleanup-handles\*\s+'\((?<body>[^)]*)\)\s*\)"
)
$cleanupHandles = @(if ($cleanupMatch.Success) {
    @(
        [regex]::Matches($cleanupMatch.Groups['body'].Value, '"(?<handle>[0-9A-F]+)"', 'IgnoreCase') |
            ForEach-Object { $_.Groups['handle'].Value.ToUpperInvariant() }
    )
} else { @() })
$cleanSlateMatch = [regex]::Match(
    $specText,
    "(?is)\(setq\s+cx:\*full-batch-clean-slate-object-names\*\s+'\((?<body>[^)]*)\)\s*\)"
)
$cleanSlateNames = @(if ($cleanSlateMatch.Success) {
    @(
        [regex]::Matches($cleanSlateMatch.Groups['body'].Value, '"(?<name>[^\"]+)"') |
            ForEach-Object { $_.Groups['name'].Value }
    )
} else { @() })

# Native relayout tasks are TSV grip plans rather than Lisp dispatch specs.
# Admit only the exact, auditable schema used by the verified grip engine; do
# not silently interpret arbitrary tabular files as executable task specs.
if ($handles.Count -eq 0 -and $segments.Count -eq 0) {
    $firstLine = @($specText -split "`r?`n")[0]
    if ($firstLine -ceq "HANDLE`tGRIP_INDEX`tDX`tDY`tDZ") {
        $gripRows = @(Import-Csv -LiteralPath $spec -Delimiter "`t")
        if ($gripRows.Count -eq 0) { throw 'EXECUTION_GRIP_TASK_SPEC_EMPTY' }
        foreach ($row in $gripRows) {
            if ([string]$row.HANDLE -notmatch '^[0-9A-Fa-f]+$' -or [string]$row.GRIP_INDEX -notmatch '^\d+$') {
                throw 'EXECUTION_GRIP_TASK_SPEC_INVALID'
            }
        }
        $handles = @($gripRows | ForEach-Object { ([string]$_.HANDLE).ToUpperInvariant() } | Select-Object -Unique)
        $segments = @($gripRows | ForEach-Object {
            [pscustomobject]@{ type = 'NATIVE_DIM_GRIP'; index = [int]$_.GRIP_INDEX }
        })
    }
}

$manifest = [ordered]@{
    schema_version = 3
    status = 'PREPARED'
    created_at = (Get-Date).ToString('o')
    phase_id = $PhaseId
    governing_phase_id = $governingPhaseId
    workflow_id = $WorkflowId
    workflow_mode = $WorkflowMode
    action = $Action
    process_id = $ProcessId
    window_handle = $WindowHandle
    isolated_dwg = $target
    isolated_dwg_sha256 = $targetHash
    isolated_dwg_sha256_source = $targetHashSource
    isolated_dwg_sha256_live_verified = $targetHashLiveVerified
    owner_state = [IO.Path]::GetFullPath($OwnerStatePath)
    entrypoint = $entry
    entrypoint_sha256 = (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash
    task_spec = $spec
    task_spec_sha256 = (Get-FileHash -LiteralPath $spec -Algorithm SHA256).Hash
    source_handles = $handles
    target_segment_count = $segments.Count
    target_segment_types = @($segments | Group-Object type | ForEach-Object { [pscustomobject]@{ type=$_.Name; count=$_.Count } })
    cleanup_handles = $cleanupHandles
    expected_cleanup_count = $cleanupHandles.Count
    clean_slate_requested = [bool]($cleanSlateNames.Count -gt 0)
    clean_slate_object_names = $cleanSlateNames
    save_on_success_requested = [bool]($specText -match 'full-batch-save-on-success\*\s*\)\s*T')
    report_directory = $report
    project_pre_run_snapshot = $snapshotPath
    project_execution_authority_digest = [string]$snapshot.execution_authority_digest
    project_model_bootstrap_digest = [string]$snapshot.model_bootstrap_digest
    project_pre_run_state_sha256 = [string]$snapshot.pre_run_state.sha256
    execution_contract = if ($contractPath) { $contractPath } else { $null }
    execution_contract_sha256 = if ($contractPath) { (Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash } else { $null }
    contract_id = if ($contract) { [string]$contract.contract_id } else { $null }
    component_id = if ($contract) { [string]$contract.component.id } else { $null }
    expected_created_count = if ($componentScope) { [int]$componentScope.maximum_created_count } else { $segments.Count }
    expected_final_native_annotation_count = if ($componentScope -and $null -ne $componentScope.PSObject.Properties['expected_final_native_annotation_count'] -and $null -ne $componentScope.expected_final_native_annotation_count) { [int]$componentScope.expected_final_native_annotation_count } else { $null }
    required_acceptance_gate_ids = if ($contract) { @($contract.acceptance.required_gate_ids) } else { @() }
    completion = $null
    acceptance = $null
}

$temporary = $manifestPath + '.tmp'
[IO.File]::WriteAllText($temporary, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $manifestPath

[pscustomobject]@{ status='PASS'; manifest_path=$manifestPath; target_segment_count=$segments.Count; source_handle_count=$handles.Count }
