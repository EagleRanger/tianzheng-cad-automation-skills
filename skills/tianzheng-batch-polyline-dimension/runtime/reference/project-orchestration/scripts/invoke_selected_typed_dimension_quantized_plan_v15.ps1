param(
  [Parameter(Mandatory=$true)][string]$ReportDirectory,
  [Parameter(Mandatory=$true)][int]$ProcessId,
  [Parameter(Mandatory=$true)][string]$OwnerStatePath,
  [int]$TimeoutSeconds=90,
  [string]$PythonPath=$(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$report=[IO.Path]::GetFullPath($ReportDirectory)
$runs=[IO.Path]::GetFullPath((Join-Path $root 'runs')).TrimEnd('\')+'\'
if(-not$report.StartsWith($runs,[StringComparison]::OrdinalIgnoreCase)){throw 'LAYOUT_V15_REPORT_OUTSIDE_RUNS'}
if(-not(Test-Path -LiteralPath $report -PathType Container)){throw 'LAYOUT_V15_REPORT_MISSING'}
function Resolve-LayoutV15File([string]$Relative){$path=Join-Path $root $Relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "LAYOUT_V15_FILE_MISSING:$Relative"};$path}
function Write-LayoutV15Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
$action=Resolve-LayoutV15File 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action_v5.ps1'
$bboxResolver=Resolve-LayoutV15File 'scripts/resolve_native_dimension_text_bboxes_v1.py'
$base=Resolve-LayoutV15File 'scripts/plan_typed_dimension_quantified_common_band_v2.py'
$sharp=Resolve-LayoutV15File 'scripts/plan_quantized_sharp_cluster_band_v4.py'
$axis=Resolve-LayoutV15File 'scripts/build_axis_constrained_grip0_targets_v3.py'
$predict=Resolve-LayoutV15File 'scripts/apply_axis_targets_to_grip_inventory_v1.py'
$capacity=Resolve-LayoutV15File 'scripts/plan_arc_capacity_side_flip_v2.py'
$merge=Resolve-LayoutV15File 'scripts/merge_axis_capacity_targets_v1.py'
$capacityFormula=Resolve-LayoutV15File 'config/annotation_quantized_layout_formula_v6.json'
$baseFormula=Resolve-LayoutV15File 'config/annotation_vector_layout_formula_v2.json'
$quantFormula=Resolve-LayoutV15File 'config/annotation_quantized_layout_formula_v5.json'
$geometrySource=Join-Path $report 'target_polyline_segments_selected.tsv'
$mappingSource=Join-Path $report 'typed_source_mapping.tsv'
foreach($path in @($geometrySource,$mappingSource)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "LAYOUT_V15_INPUT_MISSING:$path"}}
$layout=Join-Path $report 'quantized_axis_layout_v15';if(Test-Path -LiteralPath $layout){throw 'LAYOUT_V15_ALREADY_EXISTS'};[IO.Directory]::CreateDirectory($layout)|Out-Null
$receiptPath=Join-Path $layout 'axis_plan_receipt.json';$progressPath=Join-Path $layout 'plan_progress.jsonl';$started=Get-Date
function Write-LayoutV15Progress([string]$Stage){[IO.File]::AppendAllText($progressPath,([ordered]@{at=(Get-Date).ToString('o');stage=$Stage;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds}|ConvertTo-Json -Compress)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}
Write-LayoutV15Progress 'PLAN_ENTRY_STARTED'
$quoteKey='Export-Csv:UseQuotes';$had=$PSDefaultParameterValues.ContainsKey($quoteKey);$prior=if($had){$PSDefaultParameterValues[$quoteKey]}else{$null}
try{
  $PSDefaultParameterValues[$quoteKey]='Never'
  $map=@(Import-Csv -LiteralPath $mappingSource -Delimiter "`t" -Encoding UTF8|Where-Object{([string]$_.STATUS).ToUpperInvariant()-ceq'PASS'})
  if($map.Count-lt1){throw 'LAYOUT_V15_PASS_MAPPING_EMPTY'}
  $keys=@{};foreach($row in $map){$key=('{0}|{1}'-f([string]$row.SOURCE_HANDLE).ToUpperInvariant(),[int]$row.SEGMENT_INDEX);if($keys.ContainsKey($key)){throw "LAYOUT_V15_DUPLICATE:$key"};$keys[$key]=$true}
  $geometryRows=@(Import-Csv -LiteralPath $geometrySource -Delimiter "`t" -Encoding UTF8|Where-Object{$keys.ContainsKey(('{0}|{1}'-f([string]$_.SOURCE_HANDLE).ToUpperInvariant(),[int]$_.SEGMENT_INDEX))})
  if($geometryRows.Count-ne$map.Count){throw 'LAYOUT_V15_GEOMETRY_MAPPING_MISMATCH'}
  Write-LayoutV15Progress 'MAPPING_VALIDATED'
  $geometry=Join-Path $layout 'target_polyline_segments_selected.tsv';$mapping=Join-Path $layout 'typed_source_mapping.tsv'
  $geometryRows|Export-Csv -LiteralPath $geometry -Delimiter "`t" -NoTypeInformation -Encoding utf8;$map|Export-Csv -LiteralPath $mapping -Delimiter "`t" -NoTypeInformation -Encoding utf8
  $handles=@($map|ForEach-Object{([string]$_.NATIVE_HANDLE).ToUpperInvariant()}|Select-Object -Unique);if($handles.Count-ne$map.Count){throw 'LAYOUT_V15_HANDLES_NOT_UNIQUE'}
  $styles=Join-Path $layout 'polyline_styles.tsv';@($geometryRows|Group-Object{([string]$_.SOURCE_HANDLE).ToUpperInvariant()}|ForEach-Object{$widths=@($_.Group|ForEach-Object{[double]$_.CONSTANT_WIDTH}|Sort-Object -Unique);if($widths.Count-ne1){throw "LAYOUT_V15_WIDTH_AMBIGUOUS:$($_.Name)"};[pscustomobject]@{HANDLE=$_.Name;CONSTANT_WIDTH=$widths[0].ToString('R',[Globalization.CultureInfo]::InvariantCulture);SOURCE='BOUND_GEOMETRY'}})|Export-Csv -LiteralPath $styles -Delimiter "`t" -NoTypeInformation -Encoding utf8

  $bboxDir=Join-Path $layout 'seed_text_bboxes';Write-LayoutV15Progress 'TEXT_BBOX_AUDIT_START'
  & $action -ProcessId $ProcessId -Action AUDIT_NATIVE_DIM_TEXT_BBOXES -OwnerStatePath $OwnerStatePath -TargetHandles ($handles-join',') -ReportDirectory $bboxDir -TimeoutSeconds $TimeoutSeconds|Out-Null
  Write-LayoutV15Progress 'TEXT_BBOX_AUDIT_COMPLETE'
  $grips=Join-Path $layout 'native_grips_seed.tsv';Write-LayoutV15Progress 'GRIP_INVENTORY_START'
  & $action -ProcessId $ProcessId -Action NET_NATIVE_GRIP_INVENTORY -OwnerStatePath $OwnerStatePath -ReportPath $grips -SkipPluginLoad -TimeoutSeconds $TimeoutSeconds|Out-Null
  Write-LayoutV15Progress 'GRIP_INVENTORY_COMPLETE'

  $resolvedBboxes=Join-Path $layout 'resolved_text_bboxes.tsv';$bboxResolutionAudit=Join-Path $layout 'text_bbox_resolution_audit.tsv';$bboxResolutionSummary=Join-Path $layout 'text_bbox_resolution_summary.json'
  Write-LayoutV15Progress 'TEXT_BBOX_RESOLVE_START'
  & $PythonPath $bboxResolver --mapping $mapping --grips $grips --text-bboxes (Join-Path $bboxDir 'dimension_text_bboxes.tsv') --output-bboxes $resolvedBboxes --output-audit $bboxResolutionAudit --output-summary $bboxResolutionSummary|Out-Null
  if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_TEXT_BBOX_RESOLUTION_FAILED'}
  $bboxResolution=Get-Content -LiteralPath $bboxResolutionSummary -Raw -Encoding UTF8|ConvertFrom-Json
  if([string]$bboxResolution.status-cne'PASS'-or[int]$bboxResolution.resolved_total_count-ne$map.Count-or[int]$bboxResolution.unresolved_count-ne0){throw 'LAYOUT_V15_TEXT_BBOX_COVERAGE_INVALID'}
  Write-LayoutV15Progress 'TEXT_BBOX_RESOLVE_COMPLETE'

  $basePlan=Join-Path $layout 'ordinary_common_band_plan.tsv';$baseAudit=Join-Path $layout 'ordinary_common_band_audit.tsv';$baseSummary=Join-Path $layout 'ordinary_common_band_summary.json'
  Write-LayoutV15Progress 'ORDINARY_PLAN_START';& $PythonPath $base --geometry $geometry --mapping $mapping --grips $grips --text-bboxes $resolvedBboxes --source-styles $styles --formula $baseFormula --output-plan $basePlan --output-audit $baseAudit --output-summary $baseSummary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_BASE_FAILED'};Write-LayoutV15Progress 'ORDINARY_PLAN_COMPLETE'
  $plan=Join-Path $layout 'quantized_final_grip0_plan.tsv';$audit=Join-Path $layout 'quantized_final_audit.tsv';$summary=Join-Path $layout 'quantized_final_summary.json'
  Write-LayoutV15Progress 'SHARP_PLAN_START';& $PythonPath $sharp --geometry $geometry --mapping $mapping --grips $grips --text-bboxes $resolvedBboxes --common-band-audit $baseAudit --formula $quantFormula --output-plan $plan --output-audit $audit --output-summary $summary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_SHARP_FAILED'};Write-LayoutV15Progress 'SHARP_PLAN_COMPLETE'
  $baseTargets=Join-Path $layout 'axis_constrained_grip0_targets_base.tsv';$axisAudit=Join-Path $layout 'axis_constrained_grip0_targets_audit.tsv'
  Write-LayoutV15Progress 'AXIS_TARGET_BUILD_START';& $PythonPath $axis --seed-grips $grips --current-grips $grips --delta-plan $plan --geometry $geometry --mapping $mapping --output $baseTargets --audit $axisAudit|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_AXIS_FAILED'};Write-LayoutV15Progress 'AXIS_TARGET_BUILD_COMPLETE'
  $predictedGrips=Join-Path $layout 'native_grips_after_base_plan_predicted.tsv';$predictionSummary=Join-Path $layout 'native_grips_after_base_plan_prediction_summary.json'
  Write-LayoutV15Progress 'BASE_PLAN_GRIP0_PREDICTION_START';& $PythonPath $predict --grips $grips --targets $baseTargets --output $predictedGrips --summary $predictionSummary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_BASE_PLAN_GRIP0_PREDICTION_FAILED'};$prediction=Get-Content -LiteralPath $predictionSummary -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$prediction.status-cne'PASS'-or-not[bool]$prediction.row_count_preserved-or-not[bool]$prediction.key_set_preserved-or[int]$prediction.updated_grip0_count-ne@(Import-Csv -LiteralPath $baseTargets -Delimiter "`t").Count){throw 'LAYOUT_V15_BASE_PLAN_GRIP0_PREDICTION_INVALID'};Write-LayoutV15Progress 'BASE_PLAN_GRIP0_PREDICTION_COMPLETE'
  $capacityTargets=Join-Path $layout 'arc_capacity_side_flip_targets.tsv';$capacityAudit=Join-Path $layout 'arc_capacity_side_flip_audit.tsv';$capacitySummary=Join-Path $layout 'arc_capacity_side_flip_summary.json'
  Write-LayoutV15Progress 'CAPACITY_PLAN_START';& $PythonPath $capacity --mapping $mapping --source $geometry --grips $predictedGrips --text-bboxes $resolvedBboxes --formula $capacityFormula --targets $capacityTargets --audit-tsv $capacityAudit --summary $capacitySummary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_CAPACITY_FAILED'};Write-LayoutV15Progress 'CAPACITY_PLAN_COMPLETE'
  $targets=Join-Path $layout 'axis_constrained_grip0_targets.tsv';$mergeSummary=Join-Path $layout 'axis_capacity_merge_summary.json'
  Write-LayoutV15Progress 'CAPACITY_MERGE_START';& $PythonPath $merge --base $baseTargets --capacity $capacityTargets --output $targets --summary $mergeSummary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V15_CAPACITY_MERGE_FAILED'};Write-LayoutV15Progress 'CAPACITY_MERGE_COMPLETE'
  $final=Get-Content -LiteralPath $summary -Raw -Encoding UTF8|ConvertFrom-Json;$targetCount=@(Import-Csv -LiteralPath $targets -Delimiter "`t").Count
  $receipt=[ordered]@{schema_version=15;status='AXIS_TARGET_PLAN_READY';completed_at=(Get-Date).ToString('o');elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds;pass_mapping_count=$map.Count;target_count=$targetCount;capacity_replacement_count=[int](Get-Content -LiteralPath $mergeSummary -Raw -Encoding UTF8|ConvertFrom-Json).capacity_replacement_count;text_bbox_direct_count=[int]$bboxResolution.direct_text_bbox_count;text_bbox_proxy_count=[int]$bboxResolution.resolved_proxy_count;text_bbox_unresolved_count=0;text_grip_index=[int]$bboxResolution.learned_text_grip_index;unresolved_sharp_cluster_count=[int]$final.unresolved_sharp_cluster_count;open_path_side_policy='ENDPOINT_CHORD_VIRTUAL_EXTERIOR__NO_SEGMENT_FLIP';allowed_grip_indexes=@(0);business_mutation_count=0;progress_path=$progressPath;next_gate='ONE_OBSERVED_SCALAR_CONVERGENCE_THEN_USER_VISUAL_REVIEW'}
  Write-LayoutV15Json $receiptPath $receipt;Write-LayoutV15Progress 'PLAN_READY';$receipt
}catch{Write-LayoutV15Progress 'PLAN_FAILED';Write-LayoutV15Json $receiptPath ([ordered]@{schema_version=15;status='LAYOUT_V15_PLAN_FAILED';detail=$_.Exception.Message;business_mutation_count=0;progress_path=$progressPath;next_gate='FIX_EXACT_FAILURE_NO_RETRY'});throw}
finally{if($had){$PSDefaultParameterValues[$quoteKey]=$prior}else{[void]$PSDefaultParameterValues.Remove($quoteKey)}}
