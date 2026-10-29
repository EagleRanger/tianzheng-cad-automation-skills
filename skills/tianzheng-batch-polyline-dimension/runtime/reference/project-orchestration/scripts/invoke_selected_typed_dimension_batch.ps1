param(
    [Parameter(Mandatory = $true)][string]$SelectionLedgerPath,
    [Parameter(Mandatory = $true)][string]$ExpectedDrawing,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [Parameter(Mandatory = $true)][string[]]$SourceHandles,
    [Parameter(Mandatory = $true)][ValidateSet('ROAD','SHORE')][string]$Group,
    [Parameter(Mandatory = $true)][double]$Offset,
    [string]$SourceOffsets = '',
    [string]$SegmentOffsets = '',
    [ValidateSet('BatchIsolateAll','SourceSerialExclusiveRetry')][string]$SelectionMode = 'BatchIsolateAll',
    [switch]$Execute,
    [switch]$ClearPubDimBeforeBatch,
    [switch]$SaveAuthorized,
    [int]$ProcessId = 0,
    [string]$OwnerStatePath = '',
    [string]$ExecutionContractPath = '',
    [int]$TimeoutSeconds = 120,
    [double]$AssociationTolerance = 0.000001,
    [string]$PythonPath = $(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Resolve-ProjectFile([string]$Raw, [string]$Code) {
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $Raw)) }
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "${Code}_OUTSIDE_PROJECT" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}_MISSING" }
    return $path
}

function Write-JsonAtomic([string]$Path, $Payload) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Payload | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

if ($Offset -eq 0) { throw 'OFFSET_MUST_BE_NONZERO' }
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'VALIDATED_PYTHON_RUNTIME_MISSING' }
$ledger = Resolve-ProjectFile $SelectionLedgerPath 'SELECTION_LEDGER'
$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'REPORT_DIRECTORY_OUTSIDE_PROJECT' }
if (Test-Path -LiteralPath $report) {
    $existingItems = @(Get-ChildItem -LiteralPath $report -Force)
    $resolvedContractHint = if ([string]::IsNullOrWhiteSpace($ExecutionContractPath)) { '' } elseif ([IO.Path]::IsPathRooted($ExecutionContractPath)) { [IO.Path]::GetFullPath($ExecutionContractPath) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $ExecutionContractPath)) }
    $allowedPreparedContract = $Execute -and $existingItems.Count -eq 1 -and
        $existingItems[0].Name -ceq 'execution_contract.json' -and
        $existingItems[0].FullName.Equals($resolvedContractHint, [StringComparison]::OrdinalIgnoreCase)
    if (-not $allowedPreparedContract) { throw 'REPORT_DIRECTORY_ALREADY_EXISTS_OR_NOT_CONTRACT_ONLY' }
} else {
    New-Item -ItemType Directory -Path $report | Out-Null
}

$handles = @($SourceHandles | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
if ($handles.Count -lt 1 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) { throw 'SOURCE_HANDLES_INVALID' }
$handleCsv = $handles -join ','
$nativeAction = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'TDIM_TYPED_SEGMENT_SERIAL_BATCH' } else { 'TDIM_TYPED_SEGMENT_BATCH' }
$workflowId = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'TZ-TDIM-TYPED-SEGMENT-SERIAL-V2' } else { 'TZ-TDIM-TYPED-SEGMENT-V1' }
$taskSpec = Join-Path $report 'typed_segment_task_spec.lsp'
$compileReport = Join-Path $report 'typed_segment_compile_report.json'
$compiler = Resolve-ProjectFile 'scripts/compile_selected_typed_segment_batch.py' 'TYPED_COMPILER'

$compileArgs = @(
    '--ledger', $ledger,
    '--output', $taskSpec,
    '--report', $compileReport,
    '--expected-drawing', $ExpectedDrawing,
    '--drawing-binding', 'owner-state',
    '--offset', $Offset.ToString('R', [Globalization.CultureInfo]::InvariantCulture),
    '--group', $Group,
    '--summary-path', ("C:/tmp/cx_tdimarc_full_{0}_summary.tsv" -f $Group.ToLowerInvariant()),
    '--details-path', ("C:/tmp/cx_tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant()),
    '--source-handles', $handleCsv
)
if(-not[string]::IsNullOrWhiteSpace($SourceOffsets)){$compileArgs += @('--source-offsets',$SourceOffsets)}
if(-not[string]::IsNullOrWhiteSpace($SegmentOffsets)){$compileArgs += @('--segment-offsets',$SegmentOffsets)}
& $PythonPath $compiler @compileArgs | Out-Null
<#
    --ledger $ledger `
    --output $taskSpec `
    --report $compileReport `
    --expected-drawing $ExpectedDrawing `
    --drawing-binding owner-state `
    --offset $Offset.ToString('R', [Globalization.CultureInfo]::InvariantCulture) `
    --group $Group `
    --summary-path ("C:/tmp/cx_tdimarc_full_{0}_summary.tsv" -f $Group.ToLowerInvariant()) `
    --details-path ("C:/tmp/cx_tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant()) `
    --source-handles $handleCsv | Out-Null
#>
if ($LASTEXITCODE -ne 0) { throw "TYPED_TASK_COMPILATION_FAILED:$LASTEXITCODE" }
$compiled = Get-Content -LiteralPath $compileReport -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$compiled.target_segment_count -ne ([int]$compiled.arc_segment_count + [int]$compiled.line_segment_count)) { throw 'COMPILED_TYPED_COUNT_MISMATCH' }
if ([int]$compiled.silent_deferred_line_count -ne 0) { throw 'COMPILED_TASK_SILENTLY_DEFERRED_LINE' }

$preparedPath = Join-Path $report 'prepared_batch.json'
$prepared = [ordered]@{
    schema_version = 1
    status = if ($Execute) { 'PREPARED_FOR_GOVERNED_EXECUTION' } else { 'PREPARED_NO_DWG_MUTATION' }
    workflow_id = $workflowId
    unified_entrypoint = 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_batch.ps1'
    frozen_engine = 'scripts/tdimarc_native_full_batch.lsp'
    selection_adapter = if ($SelectionMode -ceq 'SourceSerialExclusiveRetry') { 'scripts/tdimarc_native_full_batch_source_serial_v4.lsp' } else { $null }
    selection_mode = $SelectionMode
    expected_drawing = [IO.Path]::GetFullPath($ExpectedDrawing)
    drawing_binding = 'exact_owner_state_at_execution'
    source_handles = $handles
    source_count = [int]$compiled.source_count
    target_segment_count = [int]$compiled.target_segment_count
    arc_segment_count = [int]$compiled.arc_segment_count
    line_segment_count = [int]$compiled.line_segment_count
    silent_deferred_line_count = [int]$compiled.silent_deferred_line_count
    group = $Group
    offset = $Offset
    source_offsets = $SourceOffsets
    segment_offsets = $SegmentOffsets
    task_spec = $taskSpec.Substring($projectRoot.Length + 1).Replace('\','/')
    execution_requested = $Execute.IsPresent
    clear_pub_dim_before_batch = $ClearPubDimBeforeBatch.IsPresent
    save_authorized = $SaveAuthorized.IsPresent
    next_gate = if ($Execute) { 'EXACT_OWNER_SCOPE_AND_COMPONENT_CONTRACT_THEN_UNSAVED_NATIVE_EXECUTION' } else { 'FRESH_ISOLATED_DWG_EXECUTION_REQUIRED' }
}
Write-JsonAtomic $preparedPath $prepared
if (-not $Execute) {
    [pscustomobject]@{
        status = 'PREPARED_NO_DWG_MUTATION'
        report_directory = $report
        source_count = [int]$compiled.source_count
        target_segments = [int]$compiled.target_segment_count
        arc_segments = [int]$compiled.arc_segment_count
        line_segments = [int]$compiled.line_segment_count
    }
    exit 0
}

if ($ProcessId -le 0) { throw 'PROCESS_ID_REQUIRED_FOR_EXECUTION' }
$ownerState = Resolve-ProjectFile $OwnerStatePath 'OWNER_STATE'
$componentContract = Resolve-ProjectFile $ExecutionContractPath 'COMPONENT_EXECUTION_CONTRACT'
$scopeJson = [pscustomobject]@{}
$componentContractJson = Get-Content -LiteralPath $componentContract -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -ne $componentContractJson.scope -and -not [string]::IsNullOrWhiteSpace([string]$componentContractJson.scope.path)) {
    $scopePath = Resolve-ProjectFile ([string]$componentContractJson.scope.path) 'COMPONENT_SCOPE'
    if ((Get-FileHash -LiteralPath $scopePath -Algorithm SHA256).Hash -cne [string]$componentContractJson.scope.sha256) { throw 'COMPONENT_SCOPE_HASH_MISMATCH' }
    $scopeJson = Get-Content -LiteralPath $scopePath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$owner = Get-Content -LiteralPath $ownerState -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId) { throw 'OWNED_STATE_NOT_READY_FOR_PROCESS' }
if ([IO.Path]::GetFullPath([string]$owner.target_dwg) -cne [IO.Path]::GetFullPath($ExpectedDrawing)) { throw 'OWNED_STATE_DRAWING_MISMATCH' }

$action = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1' 'OWNED_ACTION'
& $action -ProcessId $ProcessId -Action TARGET_SEGMENT_GEOMETRY_INVENTORY -OwnerStatePath $ownerState -TargetHandles $handleCsv -ReportDirectory $report -TimeoutSeconds $TimeoutSeconds | Out-Null
$allGeometry = Join-Path $report 'target_polyline_segments.tsv'
$selectedGeometry = Join-Path $report 'target_polyline_segments_selected.tsv'
$ledgerRows = @(Import-Csv -LiteralPath $ledger -Delimiter "`t") | Where-Object { ([string]$_.SOURCE_HANDLE).ToUpperInvariant() -in $handles }
$wanted = @{}
foreach ($row in $ledgerRows) { $wanted[(([string]$row.SOURCE_HANDLE).ToUpperInvariant() + ':' + [int]$row.SEGMENT_INDEX)] = $true }
$geometryRows = @(
    @(Import-Csv -LiteralPath $allGeometry -Delimiter "`t") |
        Where-Object { $wanted.ContainsKey((([string]$_.SOURCE_HANDLE).ToUpperInvariant() + ':' + [int]$_.SEGMENT_INDEX)) }
)
if ($geometryRows.Count -ne [int]$compiled.target_segment_count) { throw 'LIVE_GEOMETRY_TARGET_COUNT_MISMATCH' }
$ledgerBySegment = @{}
foreach ($row in $ledgerRows) {
    $ledgerBySegment[(([string]$row.SOURCE_HANDLE).ToUpperInvariant() + ':' + [int]$row.SEGMENT_INDEX)] = ([string]$row.SEGMENT_TYPE).ToUpperInvariant()
}
$geometryRows = @($geometryRows | ForEach-Object {
    $key = (([string]$_.SOURCE_HANDLE).ToUpperInvariant() + ':' + [int]$_.SEGMENT_INDEX)
    $declaredType = [string]$ledgerBySegment[$key]
    $liveType = ([string]$_.SEGMENT_TYPE).ToUpperInvariant()
    $length = [double]$_.SEGMENT_LENGTH
    $bulge = [double]$_.BULGE
    if ($length -le 1.0e-8) { throw 'LIVE_GEOMETRY_DEGENERATE_TARGET' }
    if ($declaredType -ceq 'LINE' -and $liveType -ceq 'ARC') {
        if ([math]::Abs($bulge) -gt 1.0e-8) { throw 'LIVE_GEOMETRY_ARC_CANNOT_DISPATCH_AS_LINE' }
        $copy = [ordered]@{}
        foreach ($property in $_.PSObject.Properties) { $copy[$property.Name] = $property.Value }
        $copy['SEGMENT_TYPE'] = 'LINE'
        [pscustomobject]$copy
    }
    elseif ($declaredType -cne $liveType) {
        throw 'LIVE_GEOMETRY_TYPE_MISMATCH'
    }
    else {
        $_
    }
})
$geometryRows | Export-Csv -LiteralPath $selectedGeometry -Delimiter "`t" -NoTypeInformation -Encoding utf8

$gripsBefore = Join-Path $report 'native_grips_before.tsv'
& $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $ownerState -ReportPath $gripsBefore -TimeoutSeconds $TimeoutSeconds | Out-Null
$gripsForPreexistingAudit = $gripsBefore
$cleanupHandles = @()
if ($ClearPubDimBeforeBatch) {
    $nativeGripRows = @(Import-Csv -LiteralPath $gripsBefore -Delimiter "`t")
    $cleanupHandles = @(
        $nativeGripRows |
            Where-Object { ([string]$_.RXCLASS) -ceq 'TDbDimension2' -and ([string]$_.LAYER) -ceq 'PUB_DIM' } |
            ForEach-Object { ([string]$_.HANDLE).ToUpperInvariant() } |
            Sort-Object -Unique
    )
    if ($cleanupHandles.Count -lt 1) { throw 'CLEAR_PUB_DIM_REQUESTED_BUT_NO_NATIVE_DIMENSIONS_FOUND' }
    $specText = [IO.File]::ReadAllText($taskSpec, [Text.Encoding]::UTF8)
    $cleanupText = ($cleanupHandles | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $replacement = "(setq cx:*full-batch-cleanup-handles* '($cleanupText))"
    $updatedSpec = [regex]::Replace(
        $specText,
        "(?is)\(setq\s+cx:\*full-batch-cleanup-handles\*\s+'\([^)]*\)\s*\)",
        $replacement,
        1
    )
    if ($updatedSpec -ceq $specText) { throw 'CLEAR_PUB_DIM_TASK_SPEC_INJECTION_FAILED' }
    [IO.File]::WriteAllText($taskSpec, $updatedSpec, [Text.UTF8Encoding]::new($false))
    $cleanupPlan = [ordered]@{
        schema_version = 1
        mode = 'DELETE_ALL_TDBDIMENSION2_ON_PUB_DIM_BEFORE_BATCH'
        layer = 'PUB_DIM'
        object_type = 'TDbDimension2'
        handle_count = $cleanupHandles.Count
        handles = $cleanupHandles
    }
    Write-JsonAtomic (Join-Path $report 'pub_dim_cleanup_plan.json') $cleanupPlan
    $gripsForPreexistingAudit = Join-Path $report 'native_grips_after_planned_cleanup.tsv'
    @($nativeGripRows | Where-Object { ([string]$_.HANDLE).ToUpperInvariant() -notin $cleanupHandles }) |
        Export-Csv -LiteralPath $gripsForPreexistingAudit -Delimiter "`t" -NoTypeInformation -Encoding utf8
}
$preexistingAuditor = Resolve-ProjectFile 'scripts/audit_preexisting_typed_source_coverage.py' 'PREEXISTING_TYPED_AUDITOR'
$preexistingDetails = Join-Path $report 'preexisting_target_coverage.tsv'
$preexistingSummary = Join-Path $report 'preexisting_target_coverage_summary.json'
& $PythonPath $preexistingAuditor --geometry $selectedGeometry --grips $gripsForPreexistingAudit --tolerance $AssociationTolerance --output-details $preexistingDetails --output-summary $preexistingSummary | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'PREEXISTING_TARGET_DIMENSIONS_FOUND__ABORTED_BEFORE_MUTATION' }

& $action -ProcessId $ProcessId -Action $nativeAction -OwnerStatePath $ownerState -TaskSpecPath $taskSpec -ReportDirectory $report -ExecutionContractPath $componentContract -UseOwnedComDelivery -TimeoutSeconds $TimeoutSeconds | Out-Null
$details = Join-Path $report ("tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant())
if (-not (Test-Path -LiteralPath $details -PathType Leaf)) { throw 'GENERATION_DETAILS_MISSING' }
$detailRows = @(Import-Csv -LiteralPath $details -Delimiter "`t")
if ($detailRows.Count -ne [int]$compiled.target_segment_count) { throw 'GENERATION_DETAIL_COUNT_MISMATCH' }
$addedHandles = @($detailRows | ForEach-Object { ([string]$_.ADDED_HANDLE).ToUpperInvariant() })
if (@($addedHandles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0 -or @($addedHandles | Select-Object -Unique).Count -ne $addedHandles.Count) { throw 'GENERATION_ADDED_HANDLES_INVALID' }

$grips = Join-Path $report 'native_grips_after.tsv'
& $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $ownerState -ReportPath $grips -TimeoutSeconds $TimeoutSeconds | Out-Null
$auditor = Resolve-ProjectFile 'scripts/audit_native_typed_source_mapping.py' 'TYPED_MAPPING_AUDITOR'
$mapping = Join-Path $report 'typed_source_mapping.tsv'
$mappingSummary = Join-Path $report 'typed_source_mapping_summary.json'
$auditArguments = @(
    '--geometry', $selectedGeometry,
    '--generation-details', $details,
    '--grips', $grips,
    '--tolerance', $AssociationTolerance,
    '--output-mapping', $mapping,
    '--output-summary', $mappingSummary
)
if ($scopeJson.PSObject.Properties.Name -contains 'validated_native_mapping_signatures') {
    $signaturePath = Resolve-ProjectFile ([string]$scopeJson.validated_native_mapping_signatures.path) 'VALIDATED_NATIVE_MAPPING_SIGNATURES'
    $signatureHash = (Get-FileHash -LiteralPath $signaturePath -Algorithm SHA256).Hash
    if ($signatureHash -cne [string]$scopeJson.validated_native_mapping_signatures.sha256) { throw 'VALIDATED_NATIVE_MAPPING_SIGNATURES_HASH_MISMATCH' }
    $signatureTolerance = if ($scopeJson.validated_native_mapping_signatures.signature_tolerance) {
        [double]$scopeJson.validated_native_mapping_signatures.signature_tolerance
    } else { $AssociationTolerance }
    $auditArguments += @('--validated-signatures', $signaturePath, '--signature-tolerance', $signatureTolerance)
}
& $PythonPath $auditor @auditArguments | Out-Null
$auditExit = $LASTEXITCODE
$audit = Get-Content -LiteralPath $mappingSummary -Raw -Encoding UTF8 | ConvertFrom-Json
$acceptance = [ordered]@{
    schema_version = 1
    status = if ($auditExit -eq 0 -and [string]$audit.status -ceq 'PASS') { 'GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED' } else { 'INVALID_UNSAVED_CANDIDATE_DO_NOT_SAVE' }
    workflow_id = $workflowId
    expected_segments = [int]$compiled.target_segment_count
    generated_segments = $detailRows.Count
    arc_segments = [int]$compiled.arc_segment_count
    line_segments = [int]$compiled.line_segment_count
    unique_added_handles = @($addedHandles | Select-Object -Unique).Count
    maximum_endpoint_error = [double]$audit.maximum_endpoint_error
    maximum_primary_association_error = [double]$audit.maximum_primary_association_error
    validated_signature_association_count = [int]$audit.validated_signature_association_count
    endpoint_tolerance = $AssociationTolerance
    source_mapping_status = [string]$audit.status
    cleared_pub_dim_native_dimension_count = $cleanupHandles.Count
    cleared_pub_dim_native_dimension_handles = $cleanupHandles
    save_authorized = $SaveAuthorized.IsPresent
    save_performed = $false
    next_gate = if ($auditExit -eq 0) { 'RUN_FINAL_QUANTIFIED_LAYOUT__PRESERVE_NATIVE_TEXT__DISTANCE_ONLY__THEN_LAYOUT_AUDIT' } else { 'DISCARD_ISOLATED_UNSAVED_CANDIDATE_AND_RETRY_FAILED_SUBSET_ONLY' }
}
Write-JsonAtomic (Join-Path $report 'quantitative_acceptance.json') $acceptance
if ($auditExit -ne 0 -or [string]$audit.status -cne 'PASS') { throw 'TYPED_SOURCE_MAPPING_FAILED__DO_NOT_SAVE' }

[pscustomobject]@{
    status = 'GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED'
    report_directory = $report
    target_segments = [int]$compiled.target_segment_count
    arc_segments = [int]$compiled.arc_segment_count
    line_segments = [int]$compiled.line_segment_count
    maximum_endpoint_error = [double]$audit.maximum_endpoint_error
    maximum_primary_association_error = [double]$audit.maximum_primary_association_error
    validated_signature_association_count = [int]$audit.validated_signature_association_count
    save_performed = $false
}
