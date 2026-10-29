param(
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [int]$TimeoutSeconds = 120,
    [string]$PlannerPath = 'scripts/plan_typed_dimension_quantified_common_band.py',
    [string]$FormulaPath = 'config/annotation_vector_layout_formula_v2.json',
    [string]$PythonPath = $(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$report = [IO.Path]::GetFullPath($ReportDirectory)
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'
if (-not $report.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'LAYOUT_REPORT_MUST_BE_UNDER_RUNS' }
if (-not (Test-Path -LiteralPath $report -PathType Container)) { throw 'LAYOUT_GENERATION_REPORT_MISSING' }
if ($ProcessId -le 0) { throw 'LAYOUT_PROCESS_ID_REQUIRED' }
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'LAYOUT_PYTHON_RUNTIME_MISSING' }

function Resolve-ProjectFile([string]$Relative, [string]$Code) {
    $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $Relative))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}_MISSING" }
    return $path
}

function Write-JsonAtomic([string]$Path, $Payload) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Payload | ConvertTo-Json -Depth 24), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-GripMovePlan([string]$Path, [object[]]$Rows) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("HANDLE`tGRIP_INDEX`tDX`tDY`tDZ")
    foreach ($row in @($Rows)) {
        $lines.Add(("{0}`t{1}`t{2}`t{3}`t{4}" -f `
            ([string]$row.HANDLE).ToUpperInvariant(),
            [string]$row.GRIP_INDEX,
            [string]$row.DX,
            [string]$row.DY,
            [string]$row.DZ))
    }
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
}

$action = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1' 'LAYOUT_OWNED_ACTION'
$bandPlanner = Resolve-ProjectFile $PlannerPath 'LAYOUT_COMMON_BAND_PLANNER'
$formula = Resolve-ProjectFile $FormulaPath 'LAYOUT_FORMULA'
$geometry = Join-Path $report 'target_polyline_segments_selected.tsv'
$mapping = Join-Path $report 'typed_source_mapping.tsv'
$generationAcceptance = Join-Path $report 'quantitative_acceptance.json'
foreach ($path in @($geometry, $mapping, $generationAcceptance)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "LAYOUT_GENERATION_EVIDENCE_MISSING:$path" }
}
$acceptance = Get-Content -LiteralPath $generationAcceptance -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$acceptance.status -notin @('GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED','GENERATION_PARTIAL_SUCCESS_FINAL_LAYOUT_REQUIRED')) { throw 'LAYOUT_GENERATION_STATUS_INVALID' }

$layout = Join-Path $report 'final_quantified_layout'
if (Test-Path -LiteralPath $layout) { throw 'LAYOUT_STAGE_ALREADY_EXISTS_USE_FRESH_RUN' }
New-Item -ItemType Directory -Path $layout | Out-Null
$receiptPath = Join-Path $layout 'final_layout_receipt.json'
$started = Get-Date

try {
    $mappingRows = @(Import-Csv -LiteralPath $mapping -Delimiter "`t" -Encoding UTF8 | Where-Object { ([string]$_.STATUS).ToUpperInvariant() -ceq 'PASS' })
    if ($mappingRows.Count -lt 1) { throw 'LAYOUT_MAPPING_EMPTY' }
    $handles = @($mappingRows | ForEach-Object { ([string]$_.NATIVE_HANDLE).ToUpperInvariant() } | Select-Object -Unique)
    if ($handles.Count -ne $mappingRows.Count) { throw 'LAYOUT_MAPPING_HANDLES_NOT_UNIQUE' }
    $handleCsv = $handles -join ','

    # The generation inventory already measured CONSTANT_WIDTH for every exact
    # selected source segment.  Re-scanning the whole model through a second CAD
    # command is redundant and was the dominant layout timeout.  Collapse the
    # bound geometry rows to one measured style row per selected source.
    $stylesDirectory = Join-Path $layout 'source_styles'
    New-Item -ItemType Directory -Path $stylesDirectory | Out-Null
    $styles = Join-Path $stylesDirectory 'polyline_styles.tsv'
    $geometryRows = @(Import-Csv -LiteralPath $geometry -Delimiter "`t" -Encoding UTF8)
    $styleRows = @()
    foreach ($sourceGroup in @($geometryRows | Group-Object { ([string]$_.SOURCE_HANDLE).ToUpperInvariant() })) {
        $widths = @($sourceGroup.Group | ForEach-Object { [double]$_.CONSTANT_WIDTH } | Sort-Object -Unique)
        if ($widths.Count -ne 1) { throw "LAYOUT_SOURCE_WIDTH_AMBIGUOUS:$($sourceGroup.Name)" }
        $styleRows += [pscustomobject]@{
            HANDLE = $sourceGroup.Name
            CONSTANT_WIDTH = $widths[0].ToString('R',[Globalization.CultureInfo]::InvariantCulture)
            SOURCE = 'BOUND_TARGET_SEGMENT_GEOMETRY_INVENTORY'
        }
    }
    $styleRows | Export-Csv -LiteralPath $styles -Delimiter "`t" -NoTypeInformation -Encoding utf8
    Write-JsonAtomic (Join-Path $stylesDirectory 'source_styles_receipt.json') ([ordered]@{
        schema_version = 1
        status = 'PASS'
        source_count = $styleRows.Count
        source = 'target_polyline_segments_selected.tsv'
        cad_rescan_performed = $false
    })

    $seedBboxDirectory = Join-Path $layout 'seed_text_bboxes'
    & $action -ProcessId $ProcessId -Action AUDIT_NATIVE_DIM_TEXT_BBOXES -OwnerStatePath $OwnerStatePath -TargetHandles $handleCsv -ReportDirectory $seedBboxDirectory -TimeoutSeconds $TimeoutSeconds | Out-Null
    $seedBboxes = Join-Path $seedBboxDirectory 'dimension_text_bboxes.tsv'

    $gripsSeed = Join-Path $layout 'native_grips_seed.tsv'
    & $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $OwnerStatePath -ReportPath $gripsSeed -TimeoutSeconds $TimeoutSeconds | Out-Null

    $bandPlan = Join-Path $layout 'quantified_common_band_grip0_plan.tsv'
    $bandAudit = Join-Path $layout 'quantified_common_band_audit.tsv'
    $bandSummary = Join-Path $layout 'quantified_common_band_summary.json'
    & $PythonPath $bandPlanner `
        --geometry $geometry `
        --mapping $mapping `
        --grips $gripsSeed `
        --text-bboxes $seedBboxes `
        --source-styles $styles `
        --formula $formula `
        --output-plan $bandPlan `
        --output-audit $bandAudit `
        --output-summary $bandSummary | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'LAYOUT_COMMON_BAND_PLANNING_FAILED' }
    $bandMoves = @(Import-Csv -LiteralPath $bandPlan -Delimiter "`t" -Encoding UTF8)
    if (@($bandMoves | Where-Object { [int]$_.GRIP_INDEX -ne 0 }).Count -gt 0) { throw 'LAYOUT_DISTANCE_ONLY_GRIP_ALLOWLIST_VIOLATION' }
    $bandApplyDirectory = Join-Path $layout 'quantified_common_band_apply_by_source'
    New-Item -ItemType Directory -Path $bandApplyDirectory | Out-Null
    $bandApplyRows = [Collections.Generic.List[object]]::new()
    $failedDistanceHandles = [Collections.Generic.List[string]]::new()
    $pluginLoaded = $false
    foreach ($sourceGroup in @($mappingRows | Group-Object { ([string]$_.SOURCE_HANDLE).ToUpperInvariant() } | Sort-Object Name)) {
        $sourceHandle = ([string]$sourceGroup.Name).ToUpperInvariant()
        $nativeSet = @($sourceGroup.Group | ForEach-Object { ([string]$_.NATIVE_HANDLE).ToUpperInvariant() })
        $sourceMoves = @($bandMoves | Where-Object { ([string]$_.HANDLE).ToUpperInvariant() -in $nativeSet })
        if ($sourceMoves.Count -eq 0) { continue }
        $sourcePlan = Join-Path $bandApplyDirectory ("source_{0}_plan.tsv" -f $sourceHandle)
        $sourceReport = Join-Path $bandApplyDirectory ("source_{0}_report.tsv" -f $sourceHandle)
        Write-GripMovePlan -Path $sourcePlan -Rows $sourceMoves
        if ($pluginLoaded) {
            & $action -ProcessId $ProcessId -Action NET_GENERIC_GRIP_BATCH_MOVE -OwnerStatePath $OwnerStatePath -PlanPath $sourcePlan -ReportPath $sourceReport -TimeoutSeconds $TimeoutSeconds -SkipPluginLoad | Out-Null
        } else {
            & $action -ProcessId $ProcessId -Action NET_GENERIC_GRIP_BATCH_MOVE -OwnerStatePath $OwnerStatePath -PlanPath $sourcePlan -ReportPath $sourceReport -TimeoutSeconds $TimeoutSeconds | Out-Null
            $pluginLoaded = $true
        }
        $sourceSummary = @(Get-Content -LiteralPath $sourceReport -Encoding UTF8 | Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
        $sourcePassed = $sourceSummary -match '^SUMMARY\tPASS\t'
        if ($sourcePassed) {
            foreach ($move in $sourceMoves) {
                $bandApplyRows.Add([pscustomobject]@{ SOURCE_HANDLE=$sourceHandle; HANDLE=([string]$move.HANDLE).ToUpperInvariant(); STATUS='PASS'; MODE='SOURCE_BATCH'; REPORT=$sourceReport })
            }
            continue
        }

        # The native plugin transaction rolls a failed source batch back.  Only
        # that source is decomposed; successful source polylines stay committed.
        foreach ($move in $sourceMoves) {
            $nativeHandle = ([string]$move.HANDLE).ToUpperInvariant()
            $singlePlan = Join-Path $bandApplyDirectory ("source_{0}_{1}_plan.tsv" -f $sourceHandle,$nativeHandle)
            $singleReport = Join-Path $bandApplyDirectory ("source_{0}_{1}_report.tsv" -f $sourceHandle,$nativeHandle)
            Write-GripMovePlan -Path $singlePlan -Rows @($move)
            & $action -ProcessId $ProcessId -Action NET_GENERIC_GRIP_BATCH_MOVE -OwnerStatePath $OwnerStatePath -PlanPath $singlePlan -ReportPath $singleReport -TimeoutSeconds $TimeoutSeconds -SkipPluginLoad | Out-Null
            $singleSummary = @(Get-Content -LiteralPath $singleReport -Encoding UTF8 | Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
            $singlePassed = $singleSummary -match '^SUMMARY\tPASS\t'
            $singleStatus = if ($singlePassed) { 'PASS' } else { 'FAILED_GRIP0_NO_EFFECT' }
            $bandApplyRows.Add([pscustomobject]@{ SOURCE_HANDLE=$sourceHandle; HANDLE=$nativeHandle; STATUS=$singleStatus; MODE='FAILED_SOURCE_ITEM_FALLBACK'; REPORT=$singleReport })
            if (-not $singlePassed) { $failedDistanceHandles.Add($nativeHandle) }
        }
    }
    $bandApply = Join-Path $layout 'quantified_common_band_apply.tsv'
    $bandApplyRows | Export-Csv -LiteralPath $bandApply -Delimiter "`t" -NoTypeInformation -Encoding utf8

    $gripsCommon = Join-Path $layout 'native_grips_common_band.tsv'
    & $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $OwnerStatePath -ReportPath $gripsCommon -TimeoutSeconds $TimeoutSeconds | Out-Null
    # Shortest-path user contract: Tianzheng already generates readable text.
    # Preserve that native state and change only the quantified grip-0 distance.
    # The existing bbox inventory provides a cheap read-only rotation check;
    # it must never trigger mirror probing, text movement or another CAD pass.
    $nativeTextDirectory = Join-Path $layout 'native_text_observation'
    & $action -ProcessId $ProcessId -Action AUDIT_NATIVE_DIM_TEXT_BBOXES -OwnerStatePath $OwnerStatePath -TargetHandles $handleCsv -ReportDirectory $nativeTextDirectory -TimeoutSeconds $TimeoutSeconds | Out-Null
    $nativeTextBboxes = Join-Path $nativeTextDirectory 'dimension_text_bboxes.tsv'

    $finalGripsForLayout = $gripsCommon
    $finalTextBboxesForLayout = $nativeTextBboxes
    # Special-tip rules are calibrated in the project lane.  The production
    # entry may dispatch only an atomically promoted geometry profile.  The
    # current sharp-corner formula is still a calibration candidate, so this
    # stage deliberately applies only the ordinary quantified common band.
    $layoutProfileDispatchStatus = 'COMMON_BAND_ONLY__NO_PROMOTED_SPECIAL_TIP_PROFILE'

    $upsideDownHandles = @(
        Import-Csv -LiteralPath $finalTextBboxesForLayout -Delimiter "`t" -Encoding UTF8 |
            Where-Object {
                $rotation = [double]$_.ROTATION % (2 * [Math]::PI)
                if ($rotation -lt 0) { $rotation += 2 * [Math]::PI }
                $rotation -gt ([Math]::PI / 2) -and $rotation -lt (3 * [Math]::PI / 2)
            } |
            ForEach-Object { ([string]$_.SOURCE_HANDLE).ToUpperInvariant() }
    )
    $bandSummaryJson = Get-Content -LiteralPath $bandSummary -Raw -Encoding UTF8 | ConvertFrom-Json
    $alreadySatisfiedCount = [Math]::Max(0, [int]$bandSummaryJson.target_count - [int]$bandSummaryJson.move_count)

    # Stable canonical filenames for downstream object and visual acceptance.
    Copy-Item -LiteralPath $finalGripsForLayout -Destination (Join-Path $layout 'native_grips_after_layout.tsv') -Force
    $finalBboxDirectory = Join-Path $layout 'final_text_bboxes'
    New-Item -ItemType Directory -Path $finalBboxDirectory | Out-Null
    Copy-Item -LiteralPath $finalTextBboxesForLayout -Destination (Join-Path $finalBboxDirectory 'dimension_text_bboxes.tsv') -Force

    $finalFailedHandles = @($failedDistanceHandles | Select-Object -Unique)
    $status = if ([string]$bandSummaryJson.status -cne 'PASS') { 'DISTANCE_BAND_FAILED' } elseif ($finalFailedHandles.Count -gt 0) { 'PARTIAL_LAYOUT_SUCCESS_SUBSET_FROZEN_FAILED_LOCAL_SUBSET_RETAINED' } elseif ($upsideDownHandles.Count -gt 0) { 'NATIVE_TEXT_READING_DIRECTION_FAILED' } else { 'PASS' }
    $receipt = [ordered]@{
        schema_version = 2
        status = $status
        completed_at = (Get-Date).ToString('o')
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        formula = $FormulaPath.Replace('\','/')
        formula_sha256 = (Get-FileHash -LiteralPath $formula -Algorithm SHA256).Hash
        planning_unit = 'one_continuous_source_polyline'
        quantified_common_band_summary = $bandSummary
        distance_mutation_count = $bandMoves.Count
        distance_already_satisfied_count = $alreadySatisfiedCount
        distance_apply_pass_count = @($bandApplyRows | Where-Object { $_.STATUS -ceq 'PASS' }).Count + $alreadySatisfiedCount
        distance_apply_failed_count = $finalFailedHandles.Count
        verified_layout_profile_dispatch_status = $layoutProfileDispatchStatus
        mandatory_special_tip_second_pass = $false
        unpromoted_special_tip_auto_apply_count = 0
        allowed_mutable_grip_indexes = @(0)
        text_policy = 'PRESERVE_NATIVE_GENERATED_STATE__DISTANCE_ONLY'
        text_position_mutation_count = 0
        upside_down_observation_count = $upsideDownHandles.Count
        tmirdim_invocation_count = 0
        grip4_move_count = 0
        native_text_observation = $finalTextBboxesForLayout
        successful_subset_policy = 'FREEZE_AND_CARRY_FORWARD_UNSAVED'
        failed_subset = @($finalFailedHandles)
        special_exception_count = 0
        save_forbidden = $true
        next_gate = if ($status -ceq 'PASS') { 'FINAL_LAYOUT_OBJECT_AUDIT_THEN_VISUAL_EVIDENCE' } elseif ($status -ceq 'PARTIAL_LAYOUT_SUCCESS_SUBSET_FROZEN_FAILED_LOCAL_SUBSET_RETAINED') { 'ANALYZE_ONLY_RETAINED_FAILED_LOCAL_SUBSET__DO_NOT_REPEAT_FROZEN_SUCCESS_OBJECTS__NO_SAVE' } else { 'DISTANCE_OR_NATIVE_READABILITY_DIAGNOSIS__NO_SAVE' }
    }
    Write-JsonAtomic $receiptPath $receipt
    $receipt
}
catch {
    $receipt = [ordered]@{
        schema_version = 1
        status = 'LAYOUT_STAGE_FAILED'
        completed_at = (Get-Date).ToString('o')
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        detail = $_.Exception.Message
        save_forbidden = $true
        next_gate = 'DIAGNOSE_LAYOUT_STAGE_WITHOUT_REPEATING_NATIVE_GENERATION'
    }
    Write-JsonAtomic $receiptPath $receipt
    throw
}
