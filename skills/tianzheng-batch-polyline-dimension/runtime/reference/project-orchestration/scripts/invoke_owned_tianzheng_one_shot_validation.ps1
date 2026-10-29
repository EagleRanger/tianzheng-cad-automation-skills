param(
    [Parameter(Mandatory = $true)][string]$DrawingPath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [Parameter(Mandatory = $true)][string]$TaskSpecPath,
    [Parameter(Mandatory = $true)][string]$ScopeContractPath,
    [Parameter(Mandatory = $true)][string]$ReportLabel,
    [ValidateSet('DIRECT_FINAL_PLACEMENT','NATIVE_SEED_MANUAL_OFFSET')]
    [string]$ProbeMode = 'DIRECT_FINAL_PLACEMENT',
    [string[]]$PriorOwnerStatePaths = @(),
    [double]$ZoomMinX = 0.0,
    [double]$ZoomMinY = 0.0,
    [double]$ZoomMaxX = 0.0,
    [double]$ZoomMaxY = 0.0,
    [ValidateRange(30,300)][int]$TimeoutSeconds = 120,
    [ValidateRange(0,3600)][int]$ReviewKeepAliveSeconds = 600
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'

function Resolve-ProjectPath([string]$Raw, [string]$Code, [switch]$MustExist) {
    $path = [IO.Path]::GetFullPath($Raw)
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Code}_OUTSIDE_PROJECT"
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $path)) { throw "${Code}_MISSING" }
    return $path
}

function Get-RelativeProjectPath([string]$Path) {
    return ([IO.Path]::GetFullPath($Path)).Substring($projectRoot.Length + 1).Replace('\','/')
}

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$drawing = Resolve-ProjectPath $DrawingPath 'ONE_SHOT_DRAWING' -MustExist
$run = Resolve-ProjectPath $RunDirectory 'ONE_SHOT_RUN' -MustExist
$spec = Resolve-ProjectPath $TaskSpecPath 'ONE_SHOT_TASK_SPEC' -MustExist
$scope = Resolve-ProjectPath $ScopeContractPath 'ONE_SHOT_SCOPE' -MustExist
if (-not $run.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'ONE_SHOT_RUN_OUTSIDE_RUNS' }
if (-not $drawing.StartsWith($run.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'ONE_SHOT_DRAWING_OUTSIDE_RUN' }
if ((Get-FileHash -LiteralPath $drawing -Algorithm SHA256).Hash -cne $ExpectedSha256.ToUpperInvariant()) {
    throw 'ONE_SHOT_BASELINE_HASH_MISMATCH'
}
if (($ZoomMinX -ne 0.0 -or $ZoomMinY -ne 0.0 -or $ZoomMaxX -ne 0.0 -or $ZoomMaxY -ne 0.0) -and
    ($ZoomMinX -ge $ZoomMaxX -or $ZoomMinY -ge $ZoomMaxY)) {
    throw 'ONE_SHOT_ZOOM_BOUNDS_INVALID'
}

$safeLabel = [regex]::Replace($ReportLabel, '[^A-Za-z0-9._-]+', '_').Trim('_')
if ([string]::IsNullOrWhiteSpace($safeLabel)) { throw 'ONE_SHOT_REPORT_LABEL_INVALID' }
$afterCaptureLabel = if ($ProbeMode -ceq 'NATIVE_SEED_MANUAL_OFFSET') {
    'after_native_seed_manual_offset'
} else {
    'after_direct_final_placement'
}
$terminalStatus = if ($ProbeMode -ceq 'NATIVE_SEED_MANUAL_OFFSET') {
    'PASS_NATIVE_SEED_GENERATED_AWAITING_USER_MANUAL_OFFSET'
} else {
    'PASS_ONE_ARC_DIRECT_FINAL_PLACEMENT_AWAITING_VISUAL_REVIEW'
}
$nextGate = if ($ProbeMode -ceq 'NATIVE_SEED_MANUAL_OFFSET') {
    'USER_MANUAL_GRIP_OFFSET_TEST__NO_AUTOMATED_MOVE_NO_SAVE'
} else {
    'CODEX_AND_USER_VISUAL_REVIEW__NO_SAVE'
}
$runtime = Join-Path $run ("runtime_{0}" -f $safeLabel)
$report = Join-Path $run ("reports\{0}" -f $safeLabel)
if ((Test-Path -LiteralPath $runtime) -or (Test-Path -LiteralPath $report)) {
    throw "ONE_SHOT_PATH_ALREADY_EXISTS=$safeLabel"
}
New-Item -ItemType Directory -Path $runtime,$report | Out-Null

$ownerState = Join-Path $runtime 'owner_state.json'
$dialogLog = Join-Path $runtime 'dialogs.jsonl'
$lifecycleReport = Join-Path $runtime 'lifecycle_report.json'
$captureCache = Join-Path $report 'visual_evidence'
$overall = [Diagnostics.Stopwatch]::StartNew()
$startupWatch = [Diagnostics.Stopwatch]::StartNew()

# Keep launch, mutation, audit and PrintWindow capture inside this one process.
# Returning between those stages is a validated failure mode for T20/AutoCAD:
# the top-level frame can disappear while acad.exe remains alive.
& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/start_owned_tianzheng_supervised.ps1') `
    -DrawingPath $drawing `
    -ExpectedSha256 $ExpectedSha256 `
    -OwnerStatePath $ownerState `
    -DialogLogPath $dialogLog `
    -LifecycleReportPath $lifecycleReport `
    -PriorOwnerStatePaths $PriorOwnerStatePaths `
    -CleanupMode Auto `
    -ConfirmNoOtherCadProject `
    -ResidualGraceSeconds 0 `
    -RetryCount 0 `
    -DialogWatchSeconds 15 `
    -StableSeconds 12 `
    -KeepAliveSeconds 0 | Out-Null
$startupWatch.Stop()

$owner = Get-Content -LiteralPath $ownerState -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$owner.status -cne 'ready' -or [int]$owner.process_id -le 0 -or [long]$owner.main_window_handle -le 0) {
    throw 'ONE_SHOT_OWNER_NOT_READY'
}
$processId = [int]$owner.process_id
$windowHandle = [long]$owner.main_window_handle

$beforeCaptureText = (& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1') `
    -OwnerStatePath $ownerState `
    -CacheDirectory $captureCache `
    -Label 'before_native_probe' `
    -EvidenceKey ("before:{0}:{1}" -f $processId,$ExpectedSha256) | Out-String).Trim()
$beforeCapture = $beforeCaptureText | ConvertFrom-Json
if ([string]$beforeCapture.status -notmatch '^PASS') { throw 'ONE_SHOT_BEFORE_CAPTURE_FAILED' }

$contractResult = & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/new_cad_component_execution_contract.ps1') `
    -ComponentId 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' `
    -GoverningPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' `
    -WorkflowPhaseId 'P2_LINE_LENGTH_AND_TYPED_SWITCH' `
    -WorkflowId 'TZ-TDIM-TYPED-SEGMENT-V1' `
    -WorkflowMode validation `
    -Action 'TDIM_TYPED_SEGMENT_BATCH' `
    -ScopeContractPath $scope `
    -ReportDirectory $report
$executionContract = [string]$contractResult.contract_path

$actionWatch = [Diagnostics.Stopwatch]::StartNew()
$actionText = (& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1') `
    -ProcessId $processId `
    -WindowHandle $windowHandle `
    -Action TDIM_TYPED_SEGMENT_BATCH `
    -OwnerStatePath $ownerState `
    -TaskSpecPath $spec `
    -ReportDirectory $report `
    -ExecutionContractPath $executionContract `
    -UseOwnedComDelivery `
    -TimeoutSeconds $TimeoutSeconds | Out-String).Trim()
$actionWatch.Stop()
$actionResult = $actionText | ConvertFrom-Json
if ([string]$actionResult.status -cne 'PASS') { throw "ONE_SHOT_NATIVE_ACTION_FAILED=$($actionResult.status)" }
if ([int]$actionResult.success_count -ne 1 -or [int]$actionResult.task_count -ne 1) {
    throw 'ONE_SHOT_NATIVE_RESULT_COUNT_INVALID'
}

$machineAuditDirectory = Join-Path $report 'machine_audit'
New-Item -ItemType Directory -Path $machineAuditDirectory -Force | Out-Null
$bboxText = (& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1') `
    -ProcessId $processId `
    -WindowHandle $windowHandle `
    -Action AUDIT_NATIVE_DIM_BBOXES `
    -OwnerStatePath $ownerState `
    -ReportDirectory $machineAuditDirectory `
    -TimeoutSeconds $TimeoutSeconds | Out-String).Trim()
$bboxAudit = $bboxText | ConvertFrom-Json
if ([string]$bboxAudit.status -cne 'PASS' -or [int]$bboxAudit.native_count -ne 1 -or [int]$bboxAudit.bbox_count -ne 1) {
    throw 'ONE_SHOT_NATIVE_BBOX_AUDIT_FAILED'
}
$gripReport = Join-Path $machineAuditDirectory 'native_grips.txt'
$gripText = (& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1') `
    -ProcessId $processId `
    -WindowHandle $windowHandle `
    -Action NET_NATIVE_GRIP_INVENTORY `
    -OwnerStatePath $ownerState `
    -ReportPath $gripReport `
    -TimeoutSeconds $TimeoutSeconds | Out-String).Trim()
$gripAudit = $gripText | ConvertFrom-Json
if ([string]$gripAudit.status -cne 'PASS' -or -not (Test-Path -LiteralPath $gripReport -PathType Leaf)) {
    throw 'ONE_SHOT_NATIVE_GRIP_AUDIT_FAILED'
}
$addedHandle = ([string]$actionResult.added_handles).Trim().ToUpperInvariant()
$gripRows = @(Import-Csv -LiteralPath $gripReport -Delimiter "`t")
$addedGripRows = @($gripRows | Where-Object { ([string]$_.HANDLE).ToUpperInvariant() -ceq $addedHandle })
if ($addedGripRows.Count -lt 1 -or 0 -notin @($addedGripRows | ForEach-Object { [int]$_.GRIP_INDEX })) {
    throw 'ONE_SHOT_ADDED_NATIVE_GRIP0_NOT_AUDITED'
}

$zoomApplied = $false
if ($ZoomMinX -lt $ZoomMaxX -and $ZoomMinY -lt $ZoomMaxY) {
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1') `
        -ProcessId $processId `
        -WindowHandle $windowHandle `
        -Action ZOOM_WINDOW_COM `
        -OwnerStatePath $ownerState `
        -MinX $ZoomMinX -MinY $ZoomMinY -MaxX $ZoomMaxX -MaxY $ZoomMaxY `
        -ReportDirectory $report `
        -TimeoutSeconds $TimeoutSeconds | Out-Null
    $zoomApplied = $true
}

$afterCaptureText = (& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1') `
    -OwnerStatePath $ownerState `
    -CacheDirectory $captureCache `
    -Label $afterCaptureLabel `
    -EvidenceKey ("after:{0}:{1}:{2}" -f $processId,$ExpectedSha256,[string]$actionResult.added_handles) | Out-String).Trim()
$afterCapture = $afterCaptureText | ConvertFrom-Json
if ([string]$afterCapture.status -notmatch '^PASS') { throw 'ONE_SHOT_AFTER_CAPTURE_FAILED' }

$overall.Stop()
$receipt = [ordered]@{
    schema_version = 1
    status = $terminalStatus
    completed_at = (Get-Date).ToString('o')
    drawing = Get-RelativeProjectPath $drawing
    baseline_sha256 = $ExpectedSha256.ToUpperInvariant()
    process_id = $processId
    window_handle = $windowHandle
    action = 'TDIM_TYPED_SEGMENT_BATCH'
    probe_mode = $ProbeMode
    task_count = [int]$actionResult.task_count
    success_count = [int]$actionResult.success_count
    added_handles = [string]$actionResult.added_handles
    cad_elapsed_ms = [int]$actionResult.cad_elapsed_ms
    machine_audit = [ordered]@{
        native_count = [int]$bboxAudit.native_count
        bbox_count = [int]$bboxAudit.bbox_count
        added_handle_grip_count = $addedGripRows.Count
        grip0_present = $true
        grip_report = Get-RelativeProjectPath $gripReport
    }
    zoom_applied = $zoomApplied
    before_capture = [ordered]@{ status=[string]$beforeCapture.status; review_path=[string]$beforeCapture.review_path; sha256=[string]$beforeCapture.review_sha256 }
    after_capture = [ordered]@{ status=[string]$afterCapture.status; review_path=[string]$afterCapture.review_path; sha256=[string]$afterCapture.review_sha256 }
    timing = [ordered]@{
        startup_ms = $startupWatch.ElapsedMilliseconds
        native_action_ms = $actionWatch.ElapsedMilliseconds
        total_to_visual_receipt_ms = $overall.ElapsedMilliseconds
    }
    save_performed = $false
    post_generation_grip_or_text_mutation = $false
    next_gate = $nextGate
}
$receiptPath = Join-Path $report 'one_shot_validation_receipt.json'
Write-JsonAtomic $receiptPath $receipt
$receipt | ConvertTo-Json -Depth 12

if ($ReviewKeepAliveSeconds -gt 0) {
    $deadline = (Get-Date).AddSeconds($ReviewKeepAliveSeconds)
    while ((Get-Date) -lt $deadline -and (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
        Start-Sleep -Seconds 1
    }
}
