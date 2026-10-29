param(
    [Parameter(Mandatory = $true)][string]$SelectionLedgerPath,
    [Parameter(Mandatory = $true)][string]$ExpectedDrawing,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [Parameter(Mandatory = $true)][string[]]$SourceHandles,
    [Parameter(Mandatory = $true)][ValidateSet('ROAD','SHORE')][string]$Group,
    [Parameter(Mandatory = $true)][double]$Offset,
    [Parameter(Mandatory = $true)][string]$ScopeContractPath,
    [ValidateSet('BatchIsolateAll','SourceSerialExclusiveRetry')][string]$SelectionMode = 'BatchIsolateAll',
    [switch]$Execute,
    [switch]$ClearPubDimBeforeBatch,
    [int]$ProcessId = 0,
    [string]$OwnerStatePath = '',
    [int]$TimeoutSeconds = 120,
    [double]$AssociationTolerance = 0.000001,
    [string]$PythonPath = $(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'

function Resolve-ProjectFile([string]$Raw, [string]$Code) {
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $Raw)) }
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "${Code}_OUTSIDE_PROJECT" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}_MISSING" }
    return $path
}

function Write-JsonAtomic([string]$Path, $Payload) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Payload | ConvertTo-Json -Depth 24), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
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

function Set-PostAuditFailure([string]$ManifestPath, [string]$Detail, [string]$AcceptancePath) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifest.status = 'EXECUTION_FAILED'
    $manifest | Add-Member -NotePropertyName post_execution_validation -NotePropertyValue ([ordered]@{
        status = 'FAIL'
        completed_at = (Get-Date).ToString('o')
        detail = $Detail
        quantitative_acceptance = $AcceptancePath
        save_forbidden = $true
    }) -Force
    Write-JsonAtomic $ManifestPath $manifest
}

$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'WORKFLOW_REPORT_MUST_BE_UNDER_RUNS' }
if (Test-Path -LiteralPath $report) { throw 'WORKFLOW_REPORT_ALREADY_EXISTS_USE_UNIQUE_DIRECTORY' }
if ($Offset -eq 0) { throw 'OFFSET_MUST_BE_NONZERO' }

$ledger = Resolve-ProjectFile $SelectionLedgerPath 'WORKFLOW_SELECTION_LEDGER'
$scope = Resolve-ProjectFile $ScopeContractPath 'WORKFLOW_SCOPE_CONTRACT'
$drawing = Resolve-ProjectFile $ExpectedDrawing 'WORKFLOW_EXPECTED_DRAWING'
$core = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_batch.ps1' 'WORKFLOW_TYPED_BATCH_CORE'
$contractEntry = Resolve-ProjectFile 'reference/project-orchestration/scripts/new_cad_component_execution_contract.ps1' 'WORKFLOW_COMPONENT_CONTRACT_ENTRY'
$captureEntry = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1' 'WORKFLOW_BACKGROUND_CAPTURE_ENTRY'
$canvasEntry = Resolve-ProjectFile 'scripts/extract_cad_canvas_roi.py' 'WORKFLOW_CANVAS_ROI_ENTRY'
$rasterEntry = Resolve-ProjectFile 'scripts/audit_annotation_screenshot_layout.py' 'WORKFLOW_RASTER_QA_ENTRY'
$rasterProfile = Resolve-ProjectFile 'config/annotation_visual_qa_profile.json' 'WORKFLOW_RASTER_QA_PROFILE'
$layoutEntry = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_layout_stage.ps1' 'WORKFLOW_FINAL_LAYOUT_ENTRY'

$scopeJson = Get-Content -LiteralPath $scope -Raw -Encoding UTF8 | ConvertFrom-Json
$componentId = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'CAD-DIM-TYPED-SELECTED-SERIAL-BATCH-V2' } else { 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' }
$workflowId = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'TZ-TDIM-TYPED-SEGMENT-SERIAL-V2' } else { 'TZ-TDIM-TYPED-SEGMENT-V1' }
$nativeAction = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'TDIM_TYPED_SEGMENT_SERIAL_BATCH' } else { 'TDIM_TYPED_SEGMENT_BATCH' }
$workflowPhaseId = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'P3_NATIVE_DIMENSION_RELAYOUT' } else { 'P2_LINE_LENGTH_AND_TYPED_SWITCH' }
if ([string]$scopeJson.component_id -cne $componentId) { throw 'WORKFLOW_SCOPE_COMPONENT_MISMATCH' }
$drawingHash = Get-SharedFileSha256 $drawing
if ($drawingHash -cne [string]$scopeJson.baseline.sha256) { throw 'WORKFLOW_DRAWING_NOT_SCOPE_BASELINE_HASH' }

$statePath = Join-Path $report 'workflow_state.json'
$started = Get-Date
$baseState = [ordered]@{
    schema_version = 1
    workflow_id = $workflowId
    workflow_entry = 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_workflow.ps1'
    core_entry = 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_batch.ps1'
    started_at = $started.ToString('o')
    expected_drawing = $drawing
    source_handles = @($SourceHandles | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    group = $Group
    offset = $Offset
    selection_mode = $SelectionMode
    mutation_requested = $Execute.IsPresent
    save_performed = $false
}

if (-not $Execute) {
    try {
        $prepared = & $core `
            -SelectionLedgerPath $ledger `
            -ExpectedDrawing $drawing `
            -ReportDirectory $report `
            -SourceHandles $SourceHandles `
            -Group $Group `
            -Offset $Offset `
            -SelectionMode $SelectionMode `
            -PythonPath $PythonPath
        $state = [ordered]@{} + $baseState
        $state.status = 'PREPARED_NO_DWG_MUTATION'
        $state.completed_at = (Get-Date).ToString('o')
        $state.preflight = $prepared
        $state.next_gate = 'OPEN_ONE_FRESH_OWNED_ISOLATED_DWG_THEN_EXECUTE_THIS_SAME_ENTRY_ONCE'
        Write-JsonAtomic $statePath $state
        $state
        exit 0
    }
    catch {
        if (-not (Test-Path -LiteralPath $report)) { New-Item -ItemType Directory -Path $report | Out-Null }
        $state = [ordered]@{} + $baseState
        $state.status = 'PRECHECK_FAILED_NO_DWG_MUTATION'
        $state.completed_at = (Get-Date).ToString('o')
        $state.detail = $_.Exception.Message
        $state.next_gate = 'FIX_INPUT_OR_SCOPE_BEFORE_OPENING_OR_MUTATING_CAD'
        Write-JsonAtomic $statePath $state
        throw
    }
}

if ($ProcessId -le 0) { throw 'WORKFLOW_PROCESS_ID_REQUIRED_FOR_EXECUTION' }
$ownerState = Resolve-ProjectFile $OwnerStatePath 'WORKFLOW_OWNER_STATE'
$owner = Get-Content -LiteralPath $ownerState -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId) { throw 'WORKFLOW_OWNER_NOT_READY' }
if ([IO.Path]::GetFullPath([string]$owner.target_dwg) -cne $drawing) { throw 'WORKFLOW_OWNER_DRAWING_MISMATCH' }

try {
    $contractResult = & $contractEntry `
        -ComponentId $componentId `
        -GoverningPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' `
        -WorkflowPhaseId $workflowPhaseId `
        -WorkflowId $workflowId `
        -WorkflowMode validation `
        -Action $nativeAction `
        -ScopeContractPath $scope `
        -ReportDirectory $report
    $executionContract = [IO.Path]::GetFullPath([string]$contractResult.contract_path)

    $batchParameters = @{
        SelectionLedgerPath = $ledger
        ExpectedDrawing = $drawing
        ReportDirectory = $report
        SourceHandles = $SourceHandles
        Group = $Group
        Offset = $Offset
        SelectionMode = $SelectionMode
        Execute = $true
        ProcessId = $ProcessId
        OwnerStatePath = $ownerState
        ExecutionContractPath = $executionContract
        TimeoutSeconds = $TimeoutSeconds
        AssociationTolerance = $AssociationTolerance
        PythonPath = $PythonPath
    }
    if ($ClearPubDimBeforeBatch) { $batchParameters.ClearPubDimBeforeBatch = $true }
    # User-facing timing starts when the one-click annotation pipeline begins
    # mutating the first source, not while CAD is starting or preflight is
    # scanning the drawing.  Keep generation and final layout separate so a
    # later optimization can show where time was actually spent.
    $annotationWatch = [Diagnostics.Stopwatch]::StartNew()
    $generationWatch = [Diagnostics.Stopwatch]::StartNew()
    $batchResult = & $core @batchParameters
    $generationWatch.Stop()

    $acceptancePath = Join-Path $report 'quantitative_acceptance.json'
    if (-not (Test-Path -LiteralPath $acceptancePath -PathType Leaf)) { throw 'WORKFLOW_QUANTITATIVE_ACCEPTANCE_MISSING' }
    $acceptance = Get-Content -LiteralPath $acceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$acceptance.status -cne 'GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED') { throw 'WORKFLOW_GENERATION_AUDIT_DID_NOT_PASS' }

    # Generation proves native type and source association only.  It must never
    # jump directly to screenshot or human review.  Run the bound adapter now:
    # quantified common distance band through native grip 0 only, preserving
    # native text position and correcting only proven upside-down reading.
    $layoutWatch = [Diagnostics.Stopwatch]::StartNew()
    $layoutResult = & $layoutEntry `
        -ReportDirectory $report `
        -ProcessId $ProcessId `
        -OwnerStatePath $ownerState `
        -TimeoutSeconds $TimeoutSeconds `
        -PythonPath $PythonPath
    $layoutWatch.Stop()
    $annotationWatch.Stop()
    $layoutReceiptPath = Join-Path $report 'final_quantified_layout\final_layout_receipt.json'
    if (-not (Test-Path -LiteralPath $layoutReceiptPath -PathType Leaf)) { throw 'WORKFLOW_FINAL_LAYOUT_RECEIPT_MISSING' }
    $layoutReceipt = Get-Content -LiteralPath $layoutReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$layoutReceipt.status -cne 'PASS') {
        $state = [ordered]@{} + $baseState
        $state.status = [string]$layoutReceipt.status
        $state.completed_at = (Get-Date).ToString('o')
        $state.generation_audit = $acceptance
        $state.final_layout = $layoutReceiptPath
        $state.batch_result = $batchResult
        $state.execution_contract = $executionContract
        $state.execution_manifest = Join-Path $report 'execution_manifest.json'
        $state.timing = [ordered]@{
            definition = 'first_native_generation_mutation_to_final_layout_receipt__excludes_CAD_startup_preflight_capture_and_human_review'
            generation_ms = $generationWatch.ElapsedMilliseconds
            final_layout_ms = $layoutWatch.ElapsedMilliseconds
            annotation_pipeline_ms = $annotationWatch.ElapsedMilliseconds
        }
        $state.save_forbidden = $true
        $state.next_gate = [string]$layoutReceipt.next_gate
        Write-JsonAtomic $statePath $state
        $state
        exit 0
    }

    $bindingMaterial = @(
        (Get-FileHash -LiteralPath $executionContract -Algorithm SHA256).Hash,
        (Get-FileHash -LiteralPath $acceptancePath -Algorithm SHA256).Hash,
        (Get-FileHash -LiteralPath $layoutReceiptPath -Algorithm SHA256).Hash,
        (Get-FileHash -LiteralPath (Join-Path $report 'typed_source_mapping_summary.json') -Algorithm SHA256).Hash,
        [string]$owner.process_id,
        [string]$owner.main_window_handle,
        $drawing,
        'POST_MACHINE_AUDIT_CURRENT_VIEW'
    ) -join '|'
    $evidenceKey = Get-TextSha256 $bindingMaterial
    $cache = Join-Path $report 'visual_cache'
    $captureText = (& $captureEntry -OwnerStatePath $ownerState -CacheDirectory $cache -Label 'typed_candidate' -EvidenceKey $evidenceKey | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($captureText)) { throw 'WORKFLOW_BACKGROUND_CAPTURE_EMPTY' }
    $capture = $captureText | ConvertFrom-Json
    if ([string]$capture.status -notin @('PASS','PASS_CACHED_NO_CAPTURE')) { throw 'WORKFLOW_BACKGROUND_CAPTURE_FAILED' }

    $evidenceDirectory = Join-Path $report 'visual_evidence'
    New-Item -ItemType Directory -Path $evidenceDirectory | Out-Null
    $formalRaw = Join-Path $evidenceDirectory 'candidate_full.png'
    $formalReview = Join-Path $evidenceDirectory 'candidate_review.jpg'
    Copy-Item -LiteralPath ([string]$capture.raw_path) -Destination $formalRaw
    Copy-Item -LiteralPath ([string]$capture.review_path) -Destination $formalReview

    # A full AutoCAD window contains ribbons, palettes and status text.  Those
    # pixels must never be presented to the drawing-layout raster gate as if
    # they were CAD annotation.  Isolate the dominant canvas first, bind it to
    # the full capture, then fail closed on obvious text/source collisions.
    $canvasPath = Join-Path $evidenceDirectory 'candidate_canvas.png'
    $canvasReceiptPath = Join-Path $evidenceDirectory 'canvas_roi_receipt.json'
    & $PythonPath $canvasEntry `
        --image $formalRaw `
        --output $canvasPath `
        --receipt $canvasReceiptPath | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $canvasReceiptPath -PathType Leaf)) {
        throw 'CAD_CANVAS_ROI_ISOLATION_FAILED'
    }
    $canvasReceipt = Get-Content -LiteralPath $canvasReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$canvasReceipt.status -cne 'PASS') { throw 'CAD_CANVAS_ROI_ISOLATION_NOT_PASS' }

    $rasterAuditPath = Join-Path $evidenceDirectory 'screenshot_raster_qa.json'
    $rasterOverlayPath = Join-Path $evidenceDirectory 'screenshot_raster_overlay.png'
    & $PythonPath $rasterEntry `
        --image $canvasPath `
        --profile $rasterProfile `
        --output $rasterAuditPath `
        --overlay $rasterOverlayPath | Out-Null
    $rasterExitCode = $LASTEXITCODE
    if (-not (Test-Path -LiteralPath $rasterAuditPath -PathType Leaf)) { throw 'SCREENSHOT_RASTER_QA_REPORT_MISSING' }
    $rasterAudit = Get-Content -LiteralPath $rasterAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($rasterExitCode -ne 0 -or [string]$rasterAudit.status -cne 'REVIEW_REQUIRED') {
        $reasonCodes = @($rasterAudit.reason_codes) -join ','
        throw "SCREENSHOT_RASTER_QA_FAILED:$reasonCodes"
    }

    $visualBinding = [ordered]@{
        schema_version = 1
        status = 'PASS_RASTER_PENDING_CODEX_VISUAL_REVIEW'
        evidence_key = $evidenceKey
        foreground_or_input_used = $false
        capture_backend = [string]$capture.backend
        full_path = $formalRaw
        full_sha256 = (Get-FileHash -LiteralPath $formalRaw -Algorithm SHA256).Hash
        review_path = $formalReview
        review_sha256 = (Get-FileHash -LiteralPath $formalReview -Algorithm SHA256).Hash
        canvas_path = $canvasPath
        canvas_sha256 = (Get-FileHash -LiteralPath $canvasPath -Algorithm SHA256).Hash
        canvas_roi_receipt = $canvasReceiptPath
        screenshot_raster_qa = $rasterAuditPath
        screenshot_raster_qa_sha256 = (Get-FileHash -LiteralPath $rasterAuditPath -Algorithm SHA256).Hash
        screenshot_raster_overlay = $rasterOverlayPath
        execution_contract_sha256 = (Get-FileHash -LiteralPath $executionContract -Algorithm SHA256).Hash
        quantitative_acceptance_sha256 = (Get-FileHash -LiteralPath $acceptancePath -Algorithm SHA256).Hash
        final_layout_receipt = $layoutReceiptPath
        final_layout_receipt_sha256 = (Get-FileHash -LiteralPath $layoutReceiptPath -Algorithm SHA256).Hash
    }
    $visualBindingPath = Join-Path $evidenceDirectory 'evidence_binding.json'
    Write-JsonAtomic $visualBindingPath $visualBinding

    $state = [ordered]@{} + $baseState
    $state.status = 'CODEX_VISUAL_REVIEW_REQUIRED'
    $state.completed_at = (Get-Date).ToString('o')
    $state.machine_audit = [ordered]@{ generation = $acceptance; final_layout = $layoutReceipt }
    $state.batch_result = $batchResult
    $state.execution_contract = $executionContract
    $state.execution_manifest = Join-Path $report 'execution_manifest.json'
    $state.timing = [ordered]@{
        definition = 'first_native_generation_mutation_to_final_layout_receipt__excludes_CAD_startup_preflight_capture_and_human_review'
        generation_ms = $generationWatch.ElapsedMilliseconds
        final_layout_ms = $layoutWatch.ElapsedMilliseconds
        annotation_pipeline_ms = $annotationWatch.ElapsedMilliseconds
    }
    $state.visual_evidence = $visualBindingPath
    $state.raster_qa = $rasterAuditPath
    $state.next_gate = 'CODEX_MUST_READ_CANVAS_AND_ISSUE_HASH_BOUND_REVIEW__ONLY_PASS_MAY_REQUEST_HUMAN_APPROVAL'
    Write-JsonAtomic $statePath $state
    $state
}
catch {
    if (-not (Test-Path -LiteralPath $report)) { New-Item -ItemType Directory -Path $report | Out-Null }
    $acceptancePath = Join-Path $report 'quantitative_acceptance.json'
    $manifestPath = Join-Path $report 'execution_manifest.json'
    $invalidAfterMutation = $false
    if (Test-Path -LiteralPath $acceptancePath -PathType Leaf) {
        $acceptance = Get-Content -LiteralPath $acceptancePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $invalidAfterMutation = [string]$acceptance.status -ceq 'INVALID_UNSAVED_CANDIDATE_DO_NOT_SAVE'
    }
    if ($invalidAfterMutation) { Set-PostAuditFailure $manifestPath $_.Exception.Message $acceptancePath }
    $state = [ordered]@{} + $baseState
    $rasterFailure = $_.Exception.Message -like 'SCREENSHOT_RASTER_QA_FAILED:*'
    $state.status = if ($invalidAfterMutation) { 'INVALID_UNSAVED_CANDIDATE_DO_NOT_SAVE' } elseif ($rasterFailure) { 'LAYOUT_FAILED_TEXT_SOURCE_COLLISION' } else { 'EXECUTION_FAILED' }
    $state.completed_at = (Get-Date).ToString('o')
    $state.detail = $_.Exception.Message
    if ($null -ne (Get-Variable -Name annotationWatch -ErrorAction SilentlyContinue)) {
        if ($annotationWatch.IsRunning) { $annotationWatch.Stop() }
        if ($null -ne (Get-Variable -Name generationWatch -ErrorAction SilentlyContinue) -and $generationWatch.IsRunning) { $generationWatch.Stop() }
        if ($null -ne (Get-Variable -Name layoutWatch -ErrorAction SilentlyContinue) -and $layoutWatch.IsRunning) { $layoutWatch.Stop() }
        $state.timing = [ordered]@{
            definition = 'first_native_generation_mutation_to_failure_receipt__excludes_CAD_startup_preflight_capture_and_human_review'
            generation_ms = if ($null -ne (Get-Variable -Name generationWatch -ErrorAction SilentlyContinue)) { $generationWatch.ElapsedMilliseconds } else { $null }
            final_layout_ms = if ($null -ne (Get-Variable -Name layoutWatch -ErrorAction SilentlyContinue)) { $layoutWatch.ElapsedMilliseconds } else { $null }
            annotation_pipeline_ms = $annotationWatch.ElapsedMilliseconds
        }
    }
    $state.execution_manifest = if (Test-Path -LiteralPath $manifestPath) { $manifestPath } else { $null }
    $state.quantitative_acceptance = if (Test-Path -LiteralPath $acceptancePath) { $acceptancePath } else { $null }
    $state.save_forbidden = $true
    $state.next_gate = if ($invalidAfterMutation) {
        'DISCARD_THIS_OWNED_UNSAVED_CANDIDATE_AND_REOPEN_ONE_FRESH_ISOLATED_COPY'
    } elseif ($rasterFailure) {
        'KEEP_FAILED_CANDIDATE_FOR_DIAGNOSIS__REPAIR_ONLY_COLLIDING_LAYOUT_SUBSET__RECAPTURE_ONCE'
    } else {
        'FIX_PRECHECK_OR_EXECUTION_CAUSE_BEFORE_ANY_RETRY'
    }
    Write-JsonAtomic $statePath $state
    throw
}
