param(
    [Parameter(Mandatory = $true)][string]$SelectionLedgerPath,
    [Parameter(Mandatory = $true)][string]$GeometryPath,
    [Parameter(Mandatory = $true)][string]$ExpectedDrawing,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [Parameter(Mandatory = $true)][string[]]$SourceHandles,
    [Parameter(Mandatory = $true)][ValidateSet('ROAD','SHORE')][string]$Group,
    [Parameter(Mandatory = $true)][double]$Offset,
    [Parameter(Mandatory = $true)][string]$ParentScopePath,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [switch]$GenerationOnlyDevelopment,
    [string]$LayoutFormulaPath = 'config/annotation_vector_layout_formula_v2.json',
    [int]$TimeoutSeconds = 180,
    [double]$AssociationTolerance = 0.000001,
    [string]$PythonPath = $(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'
$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'POLYLINE_CONTROLLER_REPORT_OUTSIDE_RUNS' }
if (Test-Path -LiteralPath $report) { throw 'POLYLINE_CONTROLLER_REPORT_ALREADY_EXISTS' }
if ($Offset -eq 0) { throw 'POLYLINE_CONTROLLER_OFFSET_ZERO' }
New-Item -ItemType Directory -Path $report | Out-Null

function Resolve-ProjectFile([string]$Raw, [string]$Code) {
    $path = if ([IO.Path]::IsPathRooted($Raw)) { [IO.Path]::GetFullPath($Raw) } else { [IO.Path]::GetFullPath((Join-Path $projectRoot $Raw)) }
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "${Code}_OUTSIDE_PROJECT" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${Code}_MISSING" }
    return $path
}

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Relative-ProjectPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path).Substring($projectRoot.Length + 1).Replace('\','/')
}

function Get-NativeHandles([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(
        Import-Csv -LiteralPath $Path -Delimiter "`t" |
            Where-Object { ([string]$_.RXCLASS) -ceq 'TDbDimension2' } |
            ForEach-Object { ([string]$_.HANDLE).ToUpperInvariant() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
}

$ledgerPath = Resolve-ProjectFile $SelectionLedgerPath 'POLYLINE_LEDGER'
$geometryPath = Resolve-ProjectFile $GeometryPath 'POLYLINE_GEOMETRY'
$drawing = Resolve-ProjectFile $ExpectedDrawing 'POLYLINE_DRAWING'
$parentScopeFile = Resolve-ProjectFile $ParentScopePath 'POLYLINE_PARENT_SCOPE'
$ownerState = Resolve-ProjectFile $OwnerStatePath 'POLYLINE_OWNER_STATE'
$compiler = Resolve-ProjectFile 'scripts/compile_selected_typed_segment_batch.py' 'POLYLINE_COMPILER'
$contractBuilder = Resolve-ProjectFile 'reference/project-orchestration/scripts/new_cad_component_execution_contract.ps1' 'POLYLINE_CONTRACT_BUILDER'
$action = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1' 'POLYLINE_OWNED_ACTION'
$auditor = Resolve-ProjectFile 'scripts/audit_native_typed_source_mapping.py' 'POLYLINE_MAPPING_AUDITOR'
$captureEntry = Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1' 'POLYLINE_CAPTURE'
$layoutEntry = if ($GenerationOnlyDevelopment) { $null } else { Resolve-ProjectFile 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_layout_stage.ps1' 'POLYLINE_FINAL_LAYOUT' }
$layoutFormulaFile = Resolve-ProjectFile $LayoutFormulaPath 'POLYLINE_LAYOUT_FORMULA'
$layoutFormula = Get-Content -LiteralPath $layoutFormulaFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$layoutFormula.formula_id)) { throw 'POLYLINE_LAYOUT_FORMULA_ID_MISSING' }
$layoutFormulaHash = (Get-FileHash -LiteralPath $layoutFormulaFile -Algorithm SHA256).Hash

function Get-SourceFormulaOffset([object[]]$SourceRows) {
    $height = [double]$layoutFormula.candidate_geometry.text_width_calibration.native_text_height
    if ($height -le 0) { throw 'POLYLINE_FORMULA_TEXT_HEIGHT_INVALID' }
    $widths = @($SourceRows | ForEach-Object { [Math]::Abs([double]$_.CONSTANT_WIDTH) })
    $width = if ($widths.Count -gt 0) { ($widths | Measure-Object -Maximum).Maximum } else { 0.0 }
    $common = $layoutFormula.quantified_common_band
    $rawBand = [Math]::Max(
        [double]$common.minimum_band_h,
        ($width / (2.0 * $height)) + [double]$common.source_visible_edge_gap_h + 1.0 + [double]$common.text_dimension_gap_h
    )
    $candidates = @($layoutFormula.two_pass_batch_policy.candidate_bands_h | ForEach-Object { [double]$_ } | Sort-Object)
    $band = @($candidates | Where-Object { $_ -ge ($rawBand - 1.0e-12) } | Select-Object -First 1)
    if ($band.Count -eq 0) { throw "POLYLINE_FORMULA_BAND_EXHAUSTED:$rawBand" }
    return [double]$band[0] * $height
}

$owner = Get-Content -LiteralPath $ownerState -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId) { throw 'POLYLINE_OWNER_NOT_READY' }
if ([IO.Path]::GetFullPath([string]$owner.target_dwg) -cne $drawing) { throw 'POLYLINE_OWNER_DRAWING_MISMATCH' }

$parentScope = Get-Content -LiteralPath $parentScopeFile -Raw -Encoding UTF8 | ConvertFrom-Json
$requestedHandles = @($SourceHandles | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
$rows = @(Import-Csv -LiteralPath $ledgerPath -Delimiter "`t")
if ($rows.Count -eq 0 -or @($rows | Where-Object { ([string]$_.SEGMENT_TYPE).ToUpperInvariant() -notin @('ARC','LINE') }).Count -gt 0) { throw 'POLYLINE_LEDGER_INVALID' }
$ledgerHandles = @($rows | ForEach-Object { ([string]$_.SOURCE_HANDLE).ToUpperInvariant() } | Select-Object -Unique)
if ($requestedHandles.Count -ne $ledgerHandles.Count -or @($requestedHandles | Where-Object { $_ -notin $ledgerHandles }).Count -gt 0) { throw 'POLYLINE_SOURCE_SET_MISMATCH' }

$geometryRows = @(Import-Csv -LiteralPath $geometryPath -Delimiter "`t")
$geometryKeys = @{}
foreach ($row in $geometryRows) { $geometryKeys[(([string]$row.SOURCE_HANDLE).ToUpperInvariant() + ':' + [int]$row.SEGMENT_INDEX)] = $true }
$ledgerKeys = @{}
foreach ($row in $rows) {
    $key = ([string]$row.SOURCE_HANDLE).ToUpperInvariant() + ':' + [int]$row.SEGMENT_INDEX
    if (-not $geometryKeys.ContainsKey($key)) { throw "POLYLINE_GEOMETRY_LEDGER_MISMATCH:$key" }
    $ledgerKeys[$key] = $true
}

$dataDirectory = Join-Path $report 'controller_data'
New-Item -ItemType Directory -Path $dataDirectory | Out-Null
$statePath = Join-Path $report 'controller_state.json'
$started = Get-Date
$watch = [Diagnostics.Stopwatch]::StartNew()
$created = [Collections.Generic.List[string]]::new()
$successfulSources = [Collections.Generic.List[string]]::new()
$failedSources = [Collections.Generic.List[object]]::new()
$sourceReceipts = [Collections.Generic.List[object]]::new()

# One lightweight baseline check replaces the former per-chunk safety inventory.
$initialGrips = Join-Path $report 'native_grips_before.tsv'
& $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $ownerState -ReportPath $initialGrips -TimeoutSeconds $TimeoutSeconds | Out-Null
$initialHandles = @(Get-NativeHandles $initialGrips)
$expectedInitial = [int]$parentScope.baseline.native_annotation_count
if ($initialHandles.Count -ne $expectedInitial) { throw "POLYLINE_INITIAL_NATIVE_COUNT_MISMATCH:$($initialHandles.Count):$expectedInitial" }

function New-SourceScope(
    [object[]]$SourceRows,
    [string]$ScopePath,
    [string]$ScopeId,
    [string[]]$CleanupHandles = @(),
    [string[]]$PreservedHandles = @()
) {
    $cleanup = @($CleanupHandles | ForEach-Object { $_.ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $preserved = @($PreservedHandles | ForEach-Object { $_.ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $scope = [ordered]@{
        schema_version = 1
        scope_id = $ScopeId
        status = 'active_validation_slice'
        scope_mode = 'dynamic_selected_one_polyline_inside_one_click_controller'
        governing_phase_id = 'P3_NATIVE_DIMENSION_RELAYOUT'
        component_id = 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1'
        baseline = [ordered]@{
            path = [string]$parentScope.baseline.path
            sha256 = [string]$parentScope.baseline.sha256
            native_annotation_count = $initialHandles.Count + $created.Count + $preserved.Count + $cleanup.Count
        }
        mutable_source_segments = @($SourceRows | ForEach-Object {
            [ordered]@{handle=([string]$_.SOURCE_HANDLE).ToUpperInvariant();segment=[int]$_.SEGMENT_INDEX;type=([string]$_.SEGMENT_TYPE).ToUpperInvariant()}
        })
        mutable_annotation_handles = @()
        obsolete_annotation_handles = $cleanup
        required_cleanup_handles = $cleanup
        clean_slate_object_names = @()
        obstacle_only_source_segments = @()
        obstacle_only_annotation_handles = @()
        frozen_annotation_handles = @($created) + $preserved
        allowed_actions = @('TDIM_TYPED_SEGMENT_BATCH','SCREENSHOT_VISUAL_QA')
        allowed_created_types = @('TDbDimension2')
        allowed_created_layer = 'PUB_DIM'
        allowed_created_dim_style = '_TCH_ARROW'
        maximum_created_count = $SourceRows.Count
        maximum_deleted_count = $cleanup.Count
        expected_final_native_annotation_count = $initialHandles.Count + $created.Count + $preserved.Count + $SourceRows.Count
        required_source_association_tolerance = $AssociationTolerance
        forbidden = @('delete_any_existing_object','save_inside_polyline_controller','touch_other_selected_polylines')
    }
    Write-JsonAtomic $ScopePath $scope
}

function Write-SourceRepairSpec(
    [string]$Path,[string]$Handle,[int]$SegmentIndex,[double]$SignedOffset,
    [double]$Fraction = 0.50,[string[]]$CleanupHandles = @()
) {
    $cleanup = @($CleanupHandles | ForEach-Object { $_.ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $cleanupLisp = if ($cleanup.Count -eq 0) { "'()" } else { "'(" + (($cleanup | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ')' }
    $tasksLisp = if ($Handle) {
        $offsetText = $SignedOffset.ToString('0.############',[Globalization.CultureInfo]::InvariantCulture)
        "'((`"$($Handle.ToUpperInvariant())`" ((`"ARC`" $SegmentIndex)) $offsetText `"$Group`"))"
    } else { "'()" }
    $fractionText = $Fraction.ToString('0.############',[Globalization.CultureInfo]::InvariantCulture)
    $drawingUnix = $drawing.Replace('\','/')
    $lines = @(
        "(setq cx:*full-batch-tasks* $tasksLisp)",
        "(setq cx:*full-batch-cleanup-handles* $cleanupLisp)",
        "(setq cx:*full-batch-clean-slate-object-names* '())",
        "(setq cx:*full-batch-fractions* '($fractionText))",
        "(setq cx:*source-repair-zoom-margin* 0.50)",
        "(setq cx:*source-repair-use-temp-arc* nil)",
        "(setq cx:*full-batch-expected-drawing* `"$drawingUnix`")",
        '(setq cx:*full-batch-summary-path* "C:/tmp/cx_tdimarc_full_shore_summary.tsv")',
        '(setq cx:*full-batch-details-path* "C:/tmp/cx_tdimarc_full_shore_details.tsv")',
        '(setq cx:*full-batch-save-on-success* nil)'
    )
    [IO.File]::WriteAllLines($Path,$lines,[Text.UTF8Encoding]::new($false))
}

function New-SourceRepairScope(
    [object[]]$SourceRows,[string]$ScopePath,[string]$ScopeId,
    [string[]]$CleanupHandles = @(),[string[]]$FrozenHandles = @(),
    [string[]]$ObstacleHandles = @(),[bool]$CreateCandidate = $true
) {
    $cleanup = @($CleanupHandles | ForEach-Object { $_.ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $frozen = @($FrozenHandles | ForEach-Object { $_.ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $obstacles = @($ObstacleHandles | ForEach-Object { $_.ToUpperInvariant() } | Where-Object { $_ } | Select-Object -Unique)
    $liveCount = $initialHandles.Count + $created.Count + $frozen.Count + $obstacles.Count + $cleanup.Count
    $scope = [ordered]@{
        schema_version=1;scope_id=$ScopeId;status='active_validation_slice'
        scope_mode='dynamic_exact_arc_source_isolation_fallback_inside_one_click_controller'
        governing_phase_id='P3_NATIVE_DIMENSION_RELAYOUT';component_id='CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1'
        baseline=[ordered]@{path=[string]$parentScope.baseline.path;sha256=[string]$parentScope.baseline.sha256;native_annotation_count=$liveCount}
        mutable_source_segments=if($CreateCandidate){@($SourceRows|ForEach-Object{[ordered]@{handle=([string]$_.SOURCE_HANDLE).ToUpperInvariant();segment=[int]$_.SEGMENT_INDEX;type='ARC'}})}else{@()}
        mutable_annotation_handles=@();obsolete_annotation_handles=$cleanup;required_cleanup_handles=$cleanup
        clean_slate_object_names=@();obstacle_only_source_segments=@();obstacle_only_annotation_handles=$obstacles
        frozen_annotation_handles=$frozen;allowed_actions=@('TDIMARC_SOURCE_REPAIR')
        allowed_created_types=if($CreateCandidate){@('TDbDimension2')}else{@()};allowed_created_layer='PUB_DIM';allowed_created_dim_style='_TCH_ARROW'
        maximum_created_count=if($CreateCandidate){1}else{0};maximum_deleted_count=$cleanup.Count
        expected_final_native_annotation_count=if($CreateCandidate){$liveCount+1}else{$liveCount-$cleanup.Count}
        required_source_association_tolerance=$AssociationTolerance
        forbidden=@('delete_any_non_contract_object','save_inside_polyline_controller','touch_other_selected_polylines')
    }
    Write-JsonAtomic $ScopePath $scope
}

function Invoke-ExactSourceRepairCleanup(
    [string[]]$Handles,[string]$AttemptId,[string[]]$FrozenHandles=@(),[string[]]$ObstacleHandles=@()
) {
    $targets=@($Handles|ForEach-Object{$_.ToUpperInvariant()}|Where-Object{$_}|Select-Object -Unique)
    if($targets.Count-eq 0){return}
    $cleanupReport=Join-Path $report("source_repair_{0}_cleanup"-f $AttemptId)
    New-Item -ItemType Directory -Path $cleanupReport|Out-Null
    $scopePath=Join-Path $cleanupReport 'scope.json';$specPath=Join-Path $cleanupReport 'source_repair_spec.lsp'
    New-SourceRepairScope -SourceRows @() -ScopePath $scopePath -ScopeId("P3-SOURCE-REPAIR-CLEANUP-$($AttemptId.ToUpperInvariant())") -CleanupHandles $targets -FrozenHandles $FrozenHandles -ObstacleHandles $ObstacleHandles -CreateCandidate $false
    Write-SourceRepairSpec -Path $specPath -Handle '' -SegmentIndex 0 -SignedOffset 1.0 -CleanupHandles $targets
    $contract=& $contractBuilder -ComponentId 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' -GoverningPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' -WorkflowPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' -WorkflowId 'TZ-TDIMARC-SOURCE-REPAIR-V1' -WorkflowMode validation -Action TDIMARC_SOURCE_REPAIR -ScopeContractPath $scopePath -ReportDirectory $cleanupReport
    $result=((& $action -ProcessId $ProcessId -Action TDIMARC_SOURCE_REPAIR -OwnerStatePath $ownerState -TaskSpecPath $specPath -ReportDirectory $cleanupReport -ExecutionContractPath([string]$contract.contract_path) -UseOwnedComDelivery -TimeoutSeconds $TimeoutSeconds|Out-String).Trim()|ConvertFrom-Json)
    if([string]$result.status-cne'PASS'){throw"SOURCE_REPAIR_EXACT_CLEANUP_FAILED:$AttemptId"}
}

function Invoke-SourceRepairArc(
    [object]$SourceRow,[int]$Ordinal,[double]$AttemptOffset,[string]$Reason,
    [string[]]$ObsoleteHandles=@(),[object[]]$CarriedDetailRows=@(),[string[]]$CarriedHandles=@()
) {
    if(([string]$SourceRow.SEGMENT_TYPE).ToUpperInvariant()-cne'ARC'){return $false}
    $handle=([string]$SourceRow.SOURCE_HANDLE).ToUpperInvariant();$segmentIndex=[int]$SourceRow.SEGMENT_INDEX
    $height=[double]$layoutFormula.candidate_geometry.text_width_calibration.native_text_height
    $compactOffset=1.22*$height;$sign=if($AttemptOffset-lt 0){-1.0}else{1.0}
    $candidateOffsets=@($AttemptOffset,(-1.0*$AttemptOffset),($sign*$compactOffset),(-1.0*$sign*$compactOffset))|Select-Object -Unique
    $attemptOrdinal=0
    foreach($candidateOffset in $candidateOffsets){
        $attemptOrdinal++;$attemptId=('{0:D2}_{1}_seg{2:D3}_{3}_{4:D2}'-f $Ordinal,$handle,$segmentIndex,$Reason,$attemptOrdinal).ToLowerInvariant()
        $repairReport=Join-Path $report("source_repair_$attemptId");New-Item -ItemType Directory -Path $repairReport|Out-Null
        $scopePath=Join-Path $repairReport 'scope.json';$specPath=Join-Path $repairReport 'source_repair_spec.lsp'
        New-SourceRepairScope -SourceRows @($SourceRow) -ScopePath $scopePath -ScopeId("P3-SOURCE-REPAIR-$($attemptId.ToUpperInvariant())") -FrozenHandles $CarriedHandles -ObstacleHandles $ObsoleteHandles -CreateCandidate $true
        Write-SourceRepairSpec -Path $specPath -Handle $handle -SegmentIndex $segmentIndex -SignedOffset([double]$candidateOffset) -Fraction 0.50
        try{
            $contract=& $contractBuilder -ComponentId 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' -GoverningPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' -WorkflowPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' -WorkflowId 'TZ-TDIMARC-SOURCE-REPAIR-V1' -WorkflowMode validation -Action TDIMARC_SOURCE_REPAIR -ScopeContractPath $scopePath -ReportDirectory $repairReport
            $result=((& $action -ProcessId $ProcessId -Action TDIMARC_SOURCE_REPAIR -OwnerStatePath $ownerState -TaskSpecPath $specPath -ReportDirectory $repairReport -ExecutionContractPath([string]$contract.contract_path) -UseOwnedComDelivery -TimeoutSeconds $TimeoutSeconds|Out-String).Trim()|ConvertFrom-Json)
            $details=Join-Path $repairReport 'tdimarc_full_shore_details.tsv'
            $detailRows=if(Test-Path -LiteralPath $details -PathType Leaf){@(Import-Csv -LiteralPath $details -Delimiter "`t")}else{@()}
            $newHandles=@($detailRows|Where-Object{([string]$_.STATUS)-ceq'PASS'}|ForEach-Object{([string]$_.ADDED_HANDLE).ToUpperInvariant()})
            if([string]$result.status-cne'PASS'-or $newHandles.Count-ne 1){continue}
            $stateAudit=Get-SourceNativeStateAudit -Handle $handle -SourceRows @($SourceRow) -NativeHandles $newHandles -GenerationDetails $details -ChildReport $repairReport
            if(-not $stateAudit.passed){
                Invoke-ExactSourceRepairCleanup -Handles $newHandles -AttemptId("${attemptId}_candidate") -FrozenHandles $CarriedHandles -ObstacleHandles $ObsoleteHandles
                continue
            }
            if($ObsoleteHandles.Count-gt 0){Invoke-ExactSourceRepairCleanup -Handles $ObsoleteHandles -AttemptId("${attemptId}_obsolete") -FrozenHandles(@($CarriedHandles)+@($newHandles))}
            $allDetailRows=@($CarriedDetailRows)+@($detailRows);$allHandles=@($CarriedHandles)+@($newHandles)
            $combinedSourceDetails=Join-Path $repairReport 'combined_source_details.tsv'
            @($allDetailRows|Sort-Object{[int]$_.SEGMENT_INDEX})|Export-Csv -LiteralPath $combinedSourceDetails -Delimiter "`t" -NoTypeInformation -Encoding utf8
            foreach($newHandle in $allHandles){[void]$created.Add($newHandle)};[void]$successfulSources.Add($handle)
            [void]$sourceReceipts.Add([pscustomobject]@{source=$handle;status='PASS';segment_count=$allHandles.Count;arc_count=@($allDetailRows|Where-Object{$_.SEGMENT_TYPE-ceq'ARC'}).Count;line_count=@($allDetailRows|Where-Object{$_.SEGMENT_TYPE-ceq'LINE'}).Count;created_handles=$allHandles;generation_formula_offset=[double]$candidateOffset;source_isolation_repair_used=$true;source_isolation_reason=$Reason;source_isolation_fraction=0.50;native_state_mapping=(Relative-ProjectPath([string]$stateAudit.mapping));generation_details=(Relative-ProjectPath $combinedSourceDetails);report=(Relative-ProjectPath $repairReport)})
            return $true
        }catch{
            [void]$sourceReceipts.Add([pscustomobject]@{source=$handle;status='SOURCE_ISOLATION_REPAIR_ATTEMPT_FAILED';segment_count=1;report=(Relative-ProjectPath $repairReport);error=$_.Exception.Message;generation_formula_offset=[double]$candidateOffset})
        }
    }
    return $false
}
function Get-SourceNativeStateAudit(
    [string]$Handle,
    [object[]]$SourceRows,
    [string[]]$NativeHandles,
    [string]$GenerationDetails,
    [string]$ChildReport
) {
    $stateDirectory = Join-Path $ChildReport 'native_generation_state'
    New-Item -ItemType Directory -Path $stateDirectory | Out-Null
    $stateGrips = Join-Path $stateDirectory 'native_grips.tsv'
    & $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $ownerState -ReportPath $stateGrips -SkipPluginLoad -TimeoutSeconds $TimeoutSeconds | Out-Null

    $stateGeometry = Join-Path $stateDirectory 'source_geometry.tsv'
    $selectedSegmentSet = @{}
    foreach ($sourceRow in @($SourceRows)) { $selectedSegmentSet[[int]$sourceRow.SEGMENT_INDEX] = $true }
    @($geometryRows | Where-Object {
        ([string]$_.SOURCE_HANDLE).ToUpperInvariant() -ceq $Handle -and
        $selectedSegmentSet.ContainsKey([int]$_.SEGMENT_INDEX)
    }) | Export-Csv -LiteralPath $stateGeometry -Delimiter "`t" -NoTypeInformation -Encoding utf8
    $stateMapping = Join-Path $stateDirectory 'source_mapping.tsv'
    $stateSummary = Join-Path $stateDirectory 'source_mapping_summary.json'
    & $PythonPath $auditor --geometry $stateGeometry --generation-details $GenerationDetails --grips $stateGrips --tolerance $AssociationTolerance --output-mapping $stateMapping --output-summary $stateSummary | Out-Null
    if (-not (Test-Path -LiteralPath $stateMapping -PathType Leaf) -or -not (Test-Path -LiteralPath $stateSummary -PathType Leaf)) {
        throw "POLYLINE_NATIVE_STATE_AUDIT_MISSING:$Handle"
    }
    $mappingRows = @(Import-Csv -LiteralPath $stateMapping -Delimiter "`t" -Encoding UTF8)
    $targetSet = @($NativeHandles | ForEach-Object { $_.ToUpperInvariant() })
    $unexpected = @($mappingRows | Where-Object { ([string]$_.NATIVE_HANDLE).ToUpperInvariant() -notin $targetSet })
    $wrongStateArcs = @($mappingRows | Where-Object {
        ([string]$_.SEGMENT_TYPE).ToUpperInvariant() -ceq 'ARC' -and
        ([string]$_.ASSOCIATION_MODE).ToUpperInvariant() -cne 'ENDPOINT_GRIPS'
    })
    return [pscustomobject]@{
        passed = ($mappingRows.Count -gt 0 -and $unexpected.Count -eq 0 -and $wrongStateArcs.Count -eq 0)
        mapping = $stateMapping
        summary = $stateSummary
        wrong_state_segments = @($wrongStateArcs | ForEach-Object { [int]$_.SEGMENT_INDEX })
        wrong_state_native_handles = @($wrongStateArcs | ForEach-Object { ([string]$_.NATIVE_HANDLE).ToUpperInvariant() })
    }
}

function Invoke-OnePolyline(
    [string]$Handle,
    [object[]]$SourceRows,
    [int]$Ordinal,
    [double]$AttemptOffset = $Offset,
    [string]$AttemptSuffix = '',
    [string[]]$CleanupHandles = @(),
    [bool]$OppositeSideRetryUsed = $false,
    [object[]]$CarriedDetailRows = @(),
    [string[]]$CarriedHandles = @(),
    [object[]]$WholeSourceRows = @()
) {
    if ($WholeSourceRows.Count -eq 0) { $WholeSourceRows = @($SourceRows) }
    $id = '{0:D2}_{1}' -f $Ordinal,$Handle
    $attemptId = if ([string]::IsNullOrWhiteSpace($AttemptSuffix)) { $id } else { "${id}_$AttemptSuffix" }
    $childReport = Join-Path $report ("polyline_$attemptId")
    $childLedger = Join-Path $dataDirectory ("ledger_$attemptId.tsv")
    $childScope = Join-Path $dataDirectory ("scope_$attemptId.json")
    New-Item -ItemType Directory -Path $childReport | Out-Null
    @($SourceRows) | Export-Csv -LiteralPath $childLedger -Delimiter "`t" -NoTypeInformation -Encoding utf8
    New-SourceScope -SourceRows $SourceRows -ScopePath $childScope -ScopeId ("P3-SELECTED-TYPED-POLYLINE-$($attemptId.ToUpperInvariant())") -CleanupHandles $CleanupHandles -PreservedHandles $CarriedHandles

    $taskSpec = Join-Path $childReport 'typed_segment_task_spec.lsp'
    $compileReport = Join-Path $childReport 'typed_segment_compile_report.json'
    & $PythonPath $compiler --ledger $childLedger --output $taskSpec --report $compileReport --expected-drawing $drawing --drawing-binding owner-state --offset $AttemptOffset.ToString('R',[Globalization.CultureInfo]::InvariantCulture) --group $Group --summary-path ("C:/tmp/cx_tdimarc_full_{0}_summary.tsv" -f $Group.ToLowerInvariant()) --details-path ("C:/tmp/cx_tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant()) --source-handles $Handle --cleanup-handles ($CleanupHandles -join ',') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "POLYLINE_COMPILATION_FAILED:${Handle}:$LASTEXITCODE" }

    $contract = & $contractBuilder -ComponentId 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' -GoverningPhaseId 'P3_NATIVE_DIMENSION_RELAYOUT' -WorkflowPhaseId 'P2_LINE_LENGTH_AND_TYPED_SWITCH' -WorkflowId 'TZ-TDIM-TYPED-SEGMENT-V1' -WorkflowMode validation -Action TDIM_TYPED_SEGMENT_BATCH -ScopeContractPath $childScope -ReportDirectory $childReport
    $sourceWatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        & $action -ProcessId $ProcessId -Action TDIM_TYPED_SEGMENT_BATCH -OwnerStatePath $ownerState -TaskSpecPath $taskSpec -ReportDirectory $childReport -ExecutionContractPath ([string]$contract.contract_path) -UseOwnedComDelivery -TimeoutSeconds $TimeoutSeconds | Out-Null
        $details = Join-Path $childReport ("tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant())
        if (-not (Test-Path -LiteralPath $details -PathType Leaf)) { throw "POLYLINE_DETAILS_MISSING:$Handle" }
        $detailRows = @(Import-Csv -LiteralPath $details -Delimiter "`t")
        $newHandles = @($detailRows | Where-Object { ([string]$_.STATUS) -ceq 'PASS' } | ForEach-Object { ([string]$_.ADDED_HANDLE).ToUpperInvariant() })
        if ($detailRows.Count -ne $SourceRows.Count -or $newHandles.Count -ne $SourceRows.Count -or @($newHandles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0 -or @($newHandles | Select-Object -Unique).Count -ne $newHandles.Count) { throw "POLYLINE_RESULT_COUNT_OR_HANDLE_INVALID:$Handle" }

        # A TDIMARC command can create a formally valid TDbDimension2 on the
        # wrong tangent-normal side.  In that state grips 2/3 no longer bind to
        # the source endpoints and later grip-0 distance moves may appear
        # non-responsive.  Classify the native state once per source polyline;
        # retry only that source on the opposite side, replacing the first
        # attempt atomically.  This is task-derived geometry, never a handle
        # patch or screenshot-coordinate rule.
        $stateAudit = Get-SourceNativeStateAudit -Handle $Handle -SourceRows $SourceRows -NativeHandles $newHandles -GenerationDetails $details -ChildReport $childReport
        if (-not $stateAudit.passed) {
            $sourceWatch.Stop()
            [void]$sourceReceipts.Add([pscustomobject]@{
                source=$Handle
                status=if ($OppositeSideRetryUsed) {'FAILED_NATIVE_STATE_OPPOSITE_SIDE_EXHAUSTED'} else {'RETRY_OPPOSITE_SIDE_WRONG_NATIVE_STATE'}
                segment_count=$WholeSourceRows.Count
                created_handles=$newHandles
                generation_formula_offset=$AttemptOffset
                wrong_state_segments=@($stateAudit.wrong_state_segments)
                native_state_mapping=(Relative-ProjectPath ([string]$stateAudit.mapping))
                elapsed_ms=$sourceWatch.ElapsedMilliseconds
                report=(Relative-ProjectPath $childReport)
            })
            if (-not $OppositeSideRetryUsed) {
                $wrongSegmentSet = @{}
                foreach ($segmentIndex in @($stateAudit.wrong_state_segments)) { $wrongSegmentSet[[int]$segmentIndex] = $true }
                $retryRows = @($SourceRows | Where-Object { $wrongSegmentSet.ContainsKey([int]$_.SEGMENT_INDEX) })
                $retryHandles = @($stateAudit.wrong_state_native_handles)
                $keptRows = @($detailRows | Where-Object { -not $wrongSegmentSet.ContainsKey([int]$_.SEGMENT_INDEX) })
                $keptHandles = @($keptRows | ForEach-Object { ([string]$_.ADDED_HANDLE).ToUpperInvariant() })
                if ($retryRows.Count -eq 0 -or $retryRows.Count -ne $retryHandles.Count) {
                    throw "POLYLINE_WRONG_STATE_RETRY_SET_INVALID:$Handle"
                }
                $retrySuffix = if ([string]::IsNullOrWhiteSpace($AttemptSuffix)) { 'opposite_side_state_retry' } else { "${AttemptSuffix}_opposite_side_state_retry" }
                Invoke-OnePolyline -Handle $Handle -SourceRows $retryRows -Ordinal $Ordinal -AttemptOffset (-1.0 * $AttemptOffset) -AttemptSuffix $retrySuffix -CleanupHandles $retryHandles -OppositeSideRetryUsed $true -CarriedDetailRows $keptRows -CarriedHandles $keptHandles -WholeSourceRows $WholeSourceRows
                return
            }
            if ($SourceRows.Count -eq 1 -and ([string]$SourceRows[0].SEGMENT_TYPE).ToUpperInvariant() -ceq 'ARC') {
                $repaired = Invoke-SourceRepairArc -SourceRow $SourceRows[0] -Ordinal $Ordinal -AttemptOffset $AttemptOffset -Reason 'wrong_endpoint_state' -ObsoleteHandles $newHandles -CarriedDetailRows $CarriedDetailRows -CarriedHandles $CarriedHandles
                if ($repaired) { return }
            }
            $allDiagnosticHandles = @($CarriedHandles) + @($newHandles)
            foreach ($newHandle in $allDiagnosticHandles) { [void]$created.Add($newHandle) }
            [void]$failedSources.Add([pscustomobject]@{
                source=$Handle
                rolled_back=$false
                error='NATIVE_ENDPOINT_STATE_FAILED_ON_BOTH_SIDES'
                wrong_state_segments=@($stateAudit.wrong_state_segments)
                wrong_state_native_handles=@($stateAudit.wrong_state_native_handles)
                failure_report=(Relative-ProjectPath ([string]$stateAudit.summary))
            })
            return
        }
        $allDetailRows = @($CarriedDetailRows) + @($detailRows)
        $allDetailRows = @($allDetailRows | Sort-Object {[int]$_.SEGMENT_INDEX})
        $allHandles = @($CarriedHandles) + @($newHandles)
        $combinedSourceDetails = Join-Path $childReport 'combined_source_details.tsv'
        @($allDetailRows) | Export-Csv -LiteralPath $combinedSourceDetails -Delimiter "`t" -NoTypeInformation -Encoding utf8
        foreach ($newHandle in $allHandles) { [void]$created.Add($newHandle) }
        [void]$successfulSources.Add($Handle)
        $sourceWatch.Stop()
        [void]$sourceReceipts.Add([pscustomobject]@{source=$Handle;status='PASS';segment_count=$WholeSourceRows.Count;arc_count=@($WholeSourceRows | Where-Object {$_.SEGMENT_TYPE -ceq 'ARC'}).Count;line_count=@($WholeSourceRows | Where-Object {$_.SEGMENT_TYPE -ceq 'LINE'}).Count;created_handles=$allHandles;generation_formula_offset=$AttemptOffset;opposite_side_retry_used=$OppositeSideRetryUsed;fallback_used=(-not [string]::IsNullOrWhiteSpace($AttemptSuffix));native_state_mapping=(Relative-ProjectPath ([string]$stateAudit.mapping));generation_details=(Relative-ProjectPath $combinedSourceDetails);elapsed_ms=$sourceWatch.ElapsedMilliseconds;report=(Relative-ProjectPath $childReport)})
        return
    }
    catch {
        $sourceWatch.Stop()
        $failureText = $_.Exception.Message
        $engineSummaryPath = Join-Path $childReport ("tdimarc_full_{0}_summary.tsv" -f $Group.ToLowerInvariant())
        $engineDetailsPath = Join-Path $childReport ("tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant())
        $failedDetail = $null
        if (Test-Path -LiteralPath $engineDetailsPath -PathType Leaf) {
            $failedDetail = @(Import-Csv -LiteralPath $engineDetailsPath -Delimiter "`t" | Where-Object { ([string]$_.STATUS) -cne 'PASS' } | Select-Object -First 1)
            if ($failedDetail.Count -gt 0) { $failedDetail = $failedDetail[0] } else { $failedDetail = $null }
        }
        $failureGrips = Join-Path $childReport 'native_grips_after_failure.tsv'
        & $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $ownerState -ReportPath $failureGrips -TimeoutSeconds $TimeoutSeconds | Out-Null
        $observed = @(Get-NativeHandles $failureGrips)
        $expectedSurvivors = @($initialHandles) + @($created) + @($CarriedHandles)
        $unexpected = @($observed | Where-Object { $_ -notin $expectedSurvivors })
        $missing = @($expectedSurvivors | Where-Object { $_ -notin $observed })
        $rolledBack = $unexpected.Count -eq 0 -and $missing.Count -eq 0
        $failureRecord = [ordered]@{
            schema_version = 1
            status = if ($rolledBack) { 'FAILED_POLYLINE_ROLLED_BACK_AND_ISOLATED' } else { 'FAILED_POLYLINE_ROLLBACK_UNVERIFIED_STOP_REQUIRED' }
            source_handle = $Handle
            segment_count = $WholeSourceRows.Count
            segment_indices = @($SourceRows | ForEach-Object {[int]$_.SEGMENT_INDEX})
            segment_types = @($SourceRows | ForEach-Object {[string]$_.SEGMENT_TYPE})
            first_failed_segment = if ($null -ne $failedDetail) { [int]$failedDetail.SEGMENT_INDEX } else { $null }
            first_failed_type = if ($null -ne $failedDetail) { [string]$failedDetail.SEGMENT_TYPE } else { $null }
            first_failed_status = if ($null -ne $failedDetail) { [string]$failedDetail.STATUS } else { $null }
            first_failed_attempts = if ($null -ne $failedDetail) { [string]$failedDetail.ATTEMPTS } else { $null }
            first_failed_pick = if ($null -ne $failedDetail) { @([string]$failedDetail.PICK_X,[string]$failedDetail.PICK_Y) } else { @() }
            first_failed_side = if ($null -ne $failedDetail) { @([string]$failedDetail.SIDE_X,[string]$failedDetail.SIDE_Y) } else { @() }
            error = $failureText
            expected_survivor_handles = $expectedSurvivors
            observed_native_handles = $observed
            unexpected_handles = $unexpected
            missing_handles = $missing
            engine_summary = if (Test-Path -LiteralPath $engineSummaryPath) { Relative-ProjectPath $engineSummaryPath } else { $null }
            engine_details = if (Test-Path -LiteralPath $engineDetailsPath) { Relative-ProjectPath $engineDetailsPath } else { $null }
            elapsed_ms = $sourceWatch.ElapsedMilliseconds
            next_gate = if ($rolledBack) { 'ANALYZE_ONLY_THIS_POLYLINE_AND_ITS_FIRST_FAILED_SEGMENT' } else { 'STOP_WITHOUT_SAVE_AND_RESTORE_EXACT_CANDIDATE_SET' }
        }
        $failurePath = Join-Path $childReport 'isolated_failure.json'
        Write-JsonAtomic $failurePath $failureRecord
        if ($rolledBack -and $SourceRows.Count -gt 1 -and [string]::IsNullOrWhiteSpace($AttemptSuffix)) {
            # A source-level native command may roll its transaction back when
            # one later segment fails.  That is a transport boundary, not a
            # reason to discard every geometrically valid segment.  Decompose
            # only this failed source into one-segment native tasks; every
            # successful child is retained and every failed child remains the
            # exact development subset for the next iteration.
            [void]$sourceReceipts.Add([pscustomobject]@{
                source=$Handle
                status='SOURCE_BATCH_ROLLED_BACK__DECOMPOSED_TO_SEGMENTS'
                segment_count=$SourceRows.Count
                elapsed_ms=$sourceWatch.ElapsedMilliseconds
                report=(Relative-ProjectPath $childReport)
                error=$failureText
            })
            foreach ($segmentRow in @($SourceRows | Sort-Object {[int]$_.SEGMENT_INDEX})) {
                $segmentIndex = [int]$segmentRow.SEGMENT_INDEX
                Invoke-OnePolyline -Handle $Handle -SourceRows @($segmentRow) -Ordinal $Ordinal -AttemptOffset $AttemptOffset -AttemptSuffix ("segment_{0:D3}" -f $segmentIndex) -WholeSourceRows @($segmentRow)
            }
            return
        }
        if ($rolledBack -and $SourceRows.Count -eq 1 -and ([string]$SourceRows[0].SEGMENT_TYPE).ToUpperInvariant() -ceq 'ARC') {
            $repaired = Invoke-SourceRepairArc -SourceRow $SourceRows[0] -Ordinal $Ordinal -AttemptOffset $AttemptOffset -Reason 'ordinary_pick_failed' -CarriedDetailRows $CarriedDetailRows -CarriedHandles $CarriedHandles
            if ($repaired) { return }
        }
        if ($rolledBack -and [string]::IsNullOrWhiteSpace($AttemptSuffix) -and [Math]::Abs($AttemptOffset) -lt 7.999) {
            $fallbackOffset = if ($AttemptOffset -lt 0) { -8.0 } else { 8.0 }
            Invoke-OnePolyline -Handle $Handle -SourceRows $SourceRows -Ordinal $Ordinal -AttemptOffset $fallbackOffset -AttemptSuffix 'fallback_seed_8' -OppositeSideRetryUsed $OppositeSideRetryUsed
            return
        }
        if ($rolledBack) {
            foreach ($carriedHandle in @($CarriedHandles)) { [void]$created.Add($carriedHandle) }
        }
        [void]$failedSources.Add([pscustomobject]@{source=$Handle;rolled_back=$rolledBack;error=$failureText;failure_report=(Relative-ProjectPath $failurePath)})
        [void]$sourceReceipts.Add([pscustomobject]@{source=$Handle;status=$failureRecord.status;segment_count=$WholeSourceRows.Count;elapsed_ms=$sourceWatch.ElapsedMilliseconds;report=(Relative-ProjectPath $childReport);error=$failureText})
        if (-not $rolledBack) { throw "POLYLINE_ROLLBACK_UNVERIFIED:$Handle" }
    }
}

$state = [ordered]@{
    schema_version = 2
    status = 'RUNNING'
    started_at = $started.ToString('o')
    source_count = $requestedHandles.Count
    target_segment_count = $rows.Count
    execution_policy = 'one_user_command__one_polyline_serial_controller__wrong_native_state_retries_only_wrong_segments_on_opposite_side_once__failed_polyline_isolation__one_final_audit'
    safety_policy = 'one_initial_count__one_required_native_state_classification_per_source__failure_only_rollback_check__one_final_mapping_and_diagnostic_capture'
    placement_stage = 'FORMULA_DIRECT_NATIVE_GENERATION__ENDPOINT_STATE_CLASSIFICATION__OPPOSITE_SIDE_RETRY_IF_REQUIRED'
    input_offset_role = 'legacy_command_fallback_only'
    generation_offset_semantics = 'per_source_formula_band__per_segment_native_endpoint_state_selects_signed_side__post_generation_grip0_residual_only'
    layout_formula = [ordered]@{
        id = [string]$layoutFormula.formula_id
        path = Relative-ProjectPath $layoutFormulaFile
        sha256 = $layoutFormulaHash
    }
    final_layout_status = if ($GenerationOnlyDevelopment) { 'DEFERRED_BY_USER_STAGE_ORDER' } else { 'REQUIRED_NOT_RUN' }
    save_performed = $false
}
Write-JsonAtomic $statePath $state

try {
    $annotationWatch = [Diagnostics.Stopwatch]::StartNew()
    $generationWatch = [Diagnostics.Stopwatch]::StartNew()
    $ordinal = 0
    foreach ($handle in $requestedHandles) {
        $ordinal++
        $sourceRows = @($rows | Where-Object { ([string]$_.SOURCE_HANDLE).ToUpperInvariant() -ceq $handle } | Sort-Object {[int]$_.SEGMENT_INDEX})
        $sourceFormulaOffset = Get-SourceFormulaOffset -SourceRows $sourceRows
        Invoke-OnePolyline -Handle $handle -SourceRows $sourceRows -Ordinal $ordinal -AttemptOffset $sourceFormulaOffset
    }

    # One final inventory and mapping audit replace all per-success audits.
    $finalGrips = Join-Path $report 'native_grips_after.tsv'
    & $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $ownerState -ReportPath $finalGrips -TimeoutSeconds $TimeoutSeconds | Out-Null
    $finalHandles = @(Get-NativeHandles $finalGrips)
    $expectedFinal = @($initialHandles) + @($created)
    $unexpectedFinal = @($finalHandles | Where-Object { $_ -notin $expectedFinal })
    $missingFinal = @($expectedFinal | Where-Object { $_ -notin $finalHandles })
    if ($unexpectedFinal.Count -gt 0 -or $missingFinal.Count -gt 0) { throw 'POLYLINE_FINAL_NATIVE_SET_MISMATCH' }

    $combinedRows = @()
    foreach ($receipt in @($sourceReceipts | Where-Object {$_.status -ceq 'PASS'})) {
        $child = Join-Path $projectRoot ([string]$receipt.report)
        $detailsPath = if ($receipt.PSObject.Properties.Name -contains 'generation_details' -and -not [string]::IsNullOrWhiteSpace([string]$receipt.generation_details)) {
            Join-Path $projectRoot ([string]$receipt.generation_details)
        } else {
            Join-Path $child ("tdimarc_full_{0}_details.tsv" -f $Group.ToLowerInvariant())
        }
        $combinedRows += @(Import-Csv -LiteralPath $detailsPath -Delimiter "`t")
    }
    $combined = Join-Path $report 'combined_generation_details.tsv'
    @($combinedRows) | Export-Csv -LiteralPath $combined -Delimiter "`t" -NoTypeInformation -Encoding utf8

    $successfulGeometry = Join-Path $report 'successful_source_geometry.tsv'
    $successfulSegmentKeys = @{}
    foreach ($row in @($combinedRows | Where-Object { ([string]$_.STATUS) -ceq 'PASS' })) {
        $successfulSegmentKeys[((([string]$row.SOURCE_HANDLE).ToUpperInvariant()) + ':' + [int]$row.SEGMENT_INDEX)] = $true
    }
    @($geometryRows | Where-Object {
        $source = ([string]$_.SOURCE_HANDLE).ToUpperInvariant()
        $key = $source + ':' + [int]$_.SEGMENT_INDEX
        $successfulSegmentKeys.ContainsKey($key) -and $ledgerKeys.ContainsKey($key)
    }) | Export-Csv -LiteralPath $successfulGeometry -Delimiter "`t" -NoTypeInformation -Encoding utf8
    $mapping = Join-Path $report 'typed_source_mapping.tsv'
    $mappingSummary = Join-Path $report 'typed_source_mapping_summary.json'
    $mappingAudit = $null
    if ($created.Count -gt 0) {
        & $PythonPath $auditor --geometry $successfulGeometry --generation-details $combined --grips $finalGrips --tolerance $AssociationTolerance --output-mapping $mapping --output-summary $mappingSummary | Out-Null
        if (-not (Test-Path -LiteralPath $mappingSummary -PathType Leaf)) { throw 'POLYLINE_FINAL_MAPPING_REPORT_MISSING' }
        $mappingAudit = Get-Content -LiteralPath $mappingSummary -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        Write-JsonAtomic $mappingSummary ([ordered]@{schema_version=1;status='NO_SUCCESSFUL_POLYLINES';mapped_count=0})
        $mappingAudit = Get-Content -LiteralPath $mappingSummary -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $generationWatch.Stop()
    $mappingPassed = [string]$mappingAudit.status -ceq 'PASS'
    $layoutReceiptPath = $null
    $layoutReceipt = $null
    $layoutElapsedMs = 0
    if ($created.Count -gt 0 -and $mappingPassed) {
        # The final layout adapter consumes the same evidence names as the
        # unified workflow.  Emit those compatibility receipts only after all
        # source polylines and the one final source-mapping audit have passed.
        Copy-Item -LiteralPath $successfulGeometry -Destination (Join-Path $report 'target_polyline_segments_selected.tsv')
        $generationAcceptance = [ordered]@{
            schema_version = 1
            status = if ($GenerationOnlyDevelopment) {
                if ($failedSources.Count -eq 0) { 'NORMAL_TYPED_GENERATION_COMPLETE_QUANTIFICATION_DEFERRED' } else { 'NORMAL_TYPED_GENERATION_PARTIAL_SUCCESS_QUANTIFICATION_DEFERRED' }
            } elseif ($failedSources.Count -eq 0) { 'GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED' } else { 'GENERATION_PARTIAL_SUCCESS_FINAL_LAYOUT_REQUIRED' }
            expected_segments = $created.Count
            generated_segments = $created.Count
            arc_segments = @($combinedRows | Where-Object {$_.SEGMENT_TYPE -ceq 'ARC'}).Count
            line_segments = @($combinedRows | Where-Object {$_.SEGMENT_TYPE -ceq 'LINE'}).Count
            source_mapping_status = [string]$mappingAudit.status
            save_performed = $false
            next_gate = if ($GenerationOnlyDevelopment) { 'USER_VERIFY_NORMAL_ARC_AND_LENGTH_CORRESPONDENCE__THEN_FREEZE_D2_BEFORE_GLOBAL_QUANTIFICATION' } else { 'RUN_FINAL_QUANTIFIED_LAYOUT__PRESERVE_NATIVE_TEXT__DISTANCE_ONLY__THEN_LAYOUT_AUDIT' }
        }
        Write-JsonAtomic (Join-Path $report 'quantitative_acceptance.json') $generationAcceptance
        if (-not $GenerationOnlyDevelopment) {
            $layoutWatch = [Diagnostics.Stopwatch]::StartNew()
            & $layoutEntry -ReportDirectory $report -ProcessId $ProcessId -OwnerStatePath $ownerState -TimeoutSeconds $TimeoutSeconds -PythonPath $PythonPath | Out-Null
            $layoutWatch.Stop()
            $layoutElapsedMs = $layoutWatch.ElapsedMilliseconds
            $layoutReceiptPath = Join-Path $report 'final_quantified_layout\final_layout_receipt.json'
            if (-not (Test-Path -LiteralPath $layoutReceiptPath -PathType Leaf)) { throw 'POLYLINE_FINAL_LAYOUT_RECEIPT_MISSING' }
            $layoutReceipt = Get-Content -LiteralPath $layoutReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
    }
    $annotationWatch.Stop()

    # The review view is derived only from the live CAD geometry inventory.
    # It never uses screenshot/OCR coordinates and does not touch model objects.
    $reviewXs = @($geometryRows | ForEach-Object { [double]$_.START_X; [double]$_.MID_X; [double]$_.END_X })
    $reviewYs = @($geometryRows | ForEach-Object { [double]$_.START_Y; [double]$_.MID_Y; [double]$_.END_Y })
    $reviewMinX = ($reviewXs | Measure-Object -Minimum).Minimum
    $reviewMaxX = ($reviewXs | Measure-Object -Maximum).Maximum
    $reviewMinY = ($reviewYs | Measure-Object -Minimum).Minimum
    $reviewMaxY = ($reviewYs | Measure-Object -Maximum).Maximum
    $reviewMarginX = [Math]::Max(8.0, ($reviewMaxX - $reviewMinX) * 0.04)
    $reviewMarginY = [Math]::Max(8.0, ($reviewMaxY - $reviewMinY) * 0.08)
    & $action -ProcessId $ProcessId -Action ZOOM_WINDOW_COM -OwnerStatePath $ownerState -MinX ($reviewMinX-$reviewMarginX) -MinY ($reviewMinY-$reviewMarginY) -MaxX ($reviewMaxX+$reviewMarginX) -MaxY ($reviewMaxY+$reviewMarginY) -TimeoutSeconds $TimeoutSeconds | Out-Null
    $layoutStateKey = if ($GenerationOnlyDevelopment) { 'generation-only' } elseif ($null -ne $layoutReceipt) { [string]$layoutReceipt.status } else { 'layout-not-run' }
    $evidenceKey = (Get-FileHash -LiteralPath $mappingSummary -Algorithm SHA256).Hash + '-' + $created.Count + '-' + $failedSources.Count + '-' + $layoutStateKey + '-native-geometry-view'
    $captureText = (& $captureEntry -OwnerStatePath $ownerState -CacheDirectory (Join-Path $report 'visual_cache') -Label 'typed_polyline_candidate' -EvidenceKey $evidenceKey | Out-String).Trim()
    $capture = $captureText | ConvertFrom-Json
    if ([string]$capture.status -notin @('PASS','PASS_CACHED_NO_CAPTURE')) { throw 'POLYLINE_CAPTURE_FAILED' }
    $visual = Join-Path $report 'visual_evidence'
    New-Item -ItemType Directory -Path $visual | Out-Null
    Copy-Item -LiteralPath ([string]$capture.raw_path) -Destination (Join-Path $visual 'candidate_full.png')
    Copy-Item -LiteralPath ([string]$capture.review_path) -Destination (Join-Path $visual 'candidate_review.jpg')

    $watch.Stop()
    $state.status = if ($failedSources.Count -gt 0 -or -not $mappingPassed) {
        'PARTIAL_UNSAVED_FAILED_SUBSETS_ISOLATED'
    } elseif ($GenerationOnlyDevelopment) {
        'NORMAL_TYPED_GENERATION_COMPLETE_QUANTIFICATION_DEFERRED'
    } elseif ([string]$layoutReceipt.status -ceq 'PASS') {
        'FINAL_LAYOUT_COMPLETE_VISUAL_QA_REQUIRED'
    } else {
        [string]$layoutReceipt.status
    }
    $state.completed_at = (Get-Date).ToString('o')
    $state.elapsed_ms = $watch.ElapsedMilliseconds
    $state.timing = [ordered]@{
        definition = if ($GenerationOnlyDevelopment) { 'first_source_polyline_dispatch_to_final_generation_mapping_and_background_visual__excludes_CAD_startup_live_inventory_global_quantified_layout_and_human_review' } else { 'first_source_polyline_dispatch_to_final_layout_receipt__excludes_CAD_startup_live_inventory_and_human_review' }
        generation_and_mapping_ms = $generationWatch.ElapsedMilliseconds
        final_layout_ms = $layoutElapsedMs
        annotation_pipeline_ms = $annotationWatch.ElapsedMilliseconds
    }
    $state.successful_source_count = @($successfulSources | Select-Object -Unique).Count
    $state.successful_segment_count = $created.Count
    $state.failed_source_count = $failedSources.Count
    $state.mapping_status = [string]$mappingAudit.status
    $state.mapping_failures = @($mappingAudit.failures)
    $state.generated_count = $created.Count
    $state.arc_count = @($combinedRows | Where-Object {$_.SEGMENT_TYPE -ceq 'ARC'}).Count
    $state.line_count = @($combinedRows | Where-Object {$_.SEGMENT_TYPE -ceq 'LINE'}).Count
    $state.source_receipts = @($sourceReceipts)
    $state.failed_sources = @($failedSources)
    $state.mapping_summary = Relative-ProjectPath $mappingSummary
    $state.visual_review = Relative-ProjectPath (Join-Path $visual 'candidate_review.jpg')
    $state.visual_evidence_role = if ($GenerationOnlyDevelopment) { 'NORMAL_TYPED_GENERATION_DIAGNOSTIC_FOR_TYPE_AND_BASIC_PLACEMENT_REVIEW__NOT_FINAL_LAYOUT' } elseif ([string]$layoutReceipt.status -ceq 'PASS') { 'POST_FINAL_LAYOUT_CANDIDATE_FOR_RASTER_CODEX_AND_HUMAN_REVIEW' } else { 'DIAGNOSTIC_FAILED_SUBSET_PREVIEW__NOT_FORMAL_REVIEW' }
    $state.final_layout_status = if ($GenerationOnlyDevelopment) { 'DEFERRED_BY_USER_STAGE_ORDER' } elseif ($null -ne $layoutReceipt) { [string]$layoutReceipt.status } else { 'NOT_RUN_BECAUSE_GENERATION_OR_MAPPING_INCOMPLETE' }
    $state.final_layout_receipt = if ($layoutReceiptPath) { Relative-ProjectPath $layoutReceiptPath } else { $null }
    $state.save_performed = $false
    $state.next_gate = if ($failedSources.Count -gt 0 -or -not $mappingPassed) { 'ANALYZE_ONLY_FAILED_SEGMENTS_OR_LOCAL_CLUSTERS__KEEP_SUCCESSFUL_OBJECTS_AND_LAYOUT__DO_NOT_REPEAT' } elseif ($GenerationOnlyDevelopment) { 'USER_VERIFY_NORMAL_ARC_AND_LENGTH_CORRESPONDENCE__THEN_FREEZE_D2_BEFORE_GLOBAL_QUANTIFICATION' } elseif ([string]$layoutReceipt.status -ceq 'PASS') { 'CANVAS_RASTER_CODEX_AND_HUMAN_VISUAL_REVIEW' } else { [string]$layoutReceipt.next_gate }
    Write-JsonAtomic $statePath $state
    $state | ConvertTo-Json -Depth 20
}
catch {
    $watch.Stop()
    if ($null -ne (Get-Variable -Name annotationWatch -ErrorAction SilentlyContinue) -and $annotationWatch.IsRunning) { $annotationWatch.Stop() }
    if ($null -ne (Get-Variable -Name generationWatch -ErrorAction SilentlyContinue) -and $generationWatch.IsRunning) { $generationWatch.Stop() }
    if ($null -ne (Get-Variable -Name layoutWatch -ErrorAction SilentlyContinue) -and $layoutWatch.IsRunning) { $layoutWatch.Stop() }
    $state.status = 'CONTROLLER_STOPPED_UNSAVED'
    $state.completed_at = (Get-Date).ToString('o')
    $state.elapsed_ms = $watch.ElapsedMilliseconds
    $state.timing = [ordered]@{
        definition = 'first_source_polyline_dispatch_to_failure_receipt__excludes_CAD_startup_live_inventory_and_human_review'
        generation_and_mapping_ms = if ($null -ne (Get-Variable -Name generationWatch -ErrorAction SilentlyContinue)) { $generationWatch.ElapsedMilliseconds } else { $null }
        final_layout_ms = if ($null -ne (Get-Variable -Name layoutWatch -ErrorAction SilentlyContinue)) { $layoutWatch.ElapsedMilliseconds } else { $null }
        annotation_pipeline_ms = if ($null -ne (Get-Variable -Name annotationWatch -ErrorAction SilentlyContinue)) { $annotationWatch.ElapsedMilliseconds } else { $null }
    }
    $state.failure = $_.Exception.Message
    $state.generated_count = $created.Count
    $state.source_receipts = @($sourceReceipts)
    $state.failed_sources = @($failedSources)
    $state.save_performed = $false
    $state.next_gate = 'READ_ONLY_RECOVERY_AUDIT_BEFORE_ANY_RETRY'
    Write-JsonAtomic $statePath $state
    throw
}
