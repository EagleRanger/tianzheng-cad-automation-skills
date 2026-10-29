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
$bboxResolver=Resolve-LayoutV15File 'scripts/resolve_native_dimension_text_bboxes_v2.py'
$base=Resolve-LayoutV15File 'scripts/plan_typed_dimension_quantified_common_band_v2.py'
$sharp=Resolve-LayoutV15File 'scripts/plan_quantized_sharp_cluster_band_v4.py'
$axis=Resolve-LayoutV15File 'scripts/build_axis_constrained_grip0_targets_v3.py'
$predict=Resolve-LayoutV15File 'scripts/apply_axis_targets_to_grip_inventory_v1.py'
$capacity=Resolve-LayoutV15File 'scripts/plan_arc_collapse_rescue_only_v3.py'
$capacityFormula=Resolve-LayoutV15File 'config/annotation_collapse_rescue_formula_v2.json'
$baseFormula=Resolve-LayoutV15File 'config/annotation_vector_layout_formula_v2.json'
$quantFormula=Resolve-LayoutV15File 'config/annotation_quantized_layout_formula_v5.json'
$geometrySource=Join-Path $report 'target_polyline_segments_selected.tsv'
$mappingSource=Join-Path $report 'typed_source_mapping.tsv'
foreach($path in @($geometrySource,$mappingSource)){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "LAYOUT_V15_INPUT_MISSING:$path"}}
$layout=Join-Path $report 'quantized_axis_layout_v21';if(Test-Path -LiteralPath $layout){throw 'LAYOUT_V19_ALREADY_EXISTS'};[IO.Directory]::CreateDirectory($layout)|Out-Null
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
  $baseTargets=Join-Path $layout 'axis_constrained_grip0_targets_base.tsv';$axisAudit=Join-Path $layout 'axis_constrained_grip0_targets_audit.tsv';$predictedGrips=Join-Path $layout 'native_grips_after_base_plan_predicted.tsv';$predictionSummary=Join-Path $layout 'native_grips_after_base_plan_prediction_summary.json';$deltaRows=@(Import-Csv -LiteralPath $plan -Delimiter "`t" -Encoding UTF8);$emptyBasePassthrough=$deltaRows.Count-eq0
  if($emptyBasePassthrough){
    Write-LayoutV15Progress 'BASE_PLAN_EMPTY_PASSTHROUGH_START';$header='HANDLE'+"`t"+'GRIP_INDEX'+"`t"+'TARGET_X'+"`t"+'TARGET_Y'+"`t"+'TARGET_Z'+"`t"+'TOLERANCE'+"`t"+'AXIS_KIND'+"`t"+'ANCHOR_X'+"`t"+'ANCHOR_Y'+"`t"+'AXIS_X'+"`t"+'AXIS_Y'+"`t"+'TARGET_SCALAR'+[Environment]::NewLine;[IO.File]::WriteAllText($baseTargets,$header,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($axisAudit,('STATUS'+"`t"+'DETAIL'+[Environment]::NewLine+'PASS'+"`t"+'EMPTY_BASE_PLAN_CURRENT_GRIPS_PASSTHROUGH'+[Environment]::NewLine),[Text.UTF8Encoding]::new($false));Copy-Item -LiteralPath $grips -Destination $predictedGrips;Write-LayoutV15Json $predictionSummary ([ordered]@{status='PASS';row_count_preserved=$true;key_set_preserved=$true;updated_grip0_count=0;empty_base_passthrough=$true});Write-LayoutV15Progress 'BASE_PLAN_EMPTY_PASSTHROUGH_COMPLETE'
  }else{
    Write-LayoutV15Progress 'AXIS_TARGET_BUILD_START';& $PythonPath $axis --seed-grips $grips --current-grips $grips --delta-plan $plan --geometry $geometry --mapping $mapping --output $baseTargets --audit $axisAudit|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V17_AXIS_FAILED'};Write-LayoutV15Progress 'AXIS_TARGET_BUILD_COMPLETE';Write-LayoutV15Progress 'BASE_PLAN_GRIP0_PREDICTION_START';& $PythonPath $predict --grips $grips --targets $baseTargets --output $predictedGrips --summary $predictionSummary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V17_BASE_PLAN_GRIP0_PREDICTION_FAILED'};$prediction=Get-Content -LiteralPath $predictionSummary -Raw -Encoding UTF8|ConvertFrom-Json;if([string]$prediction.status-cne'PASS'-or-not[bool]$prediction.row_count_preserved-or-not[bool]$prediction.key_set_preserved-or[int]$prediction.updated_grip0_count-ne$deltaRows.Count){throw 'LAYOUT_V17_BASE_PLAN_GRIP0_PREDICTION_INVALID'};Write-LayoutV15Progress 'BASE_PLAN_GRIP0_PREDICTION_COMPLETE'
  }
  $capacityTargets=Join-Path $layout 'collapse_rescue_only_targets.tsv';$capacityAudit=Join-Path $layout 'collapse_rescue_only_audit.tsv';$capacitySummary=Join-Path $layout 'collapse_rescue_only_summary.json'
  Write-LayoutV15Progress 'COLLAPSE_RESCUE_SELECTION_START';& $PythonPath $capacity --mapping $mapping --source $geometry --grips $grips --text-bboxes $resolvedBboxes --base-targets $baseTargets --formula $capacityFormula --targets $capacityTargets --audit-tsv $capacityAudit --summary $capacitySummary|Out-Null;if($LASTEXITCODE-ne0){throw 'LAYOUT_V20_COLLAPSE_RESCUE_SELECTION_FAILED'};Write-LayoutV15Progress 'COLLAPSE_RESCUE_SELECTION_COMPLETE'
  $targets=Join-Path $layout 'axis_constrained_grip0_targets.tsv';Copy-Item -LiteralPath $capacityTargets -Destination $targets;$capacityResult=Get-Content -LiteralPath $capacitySummary -Raw -Encoding UTF8|ConvertFrom-Json
  $final=Get-Content -LiteralPath $summary -Raw -Encoding UTF8|ConvertFrom-Json;$targetCount=@(Import-Csv -LiteralPath $targets -Delimiter "`t").Count;$receipt=[ordered]@{schema_version=21;status='AXIS_TARGET_PLAN_READY';completed_at=(Get-Date).ToString('o');elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds;pass_mapping_count=$map.Count;target_count=$targetCount;rescue_target_count=[int]$capacityResult.selected_count;normal_frozen_arc_count=[int]$capacityResult.normal_frozen_count;capacity_replacement_count=0;capacity_addition_count=0;theoretical_capacity_branch_count=[int]$capacityResult.theoretical_capacity_branch_count;text_bbox_direct_count=[int]$bboxResolution.direct_text_bbox_count;text_bbox_proxy_count=[int]$bboxResolution.resolved_proxy_count;text_bbox_unresolved_count=0;text_grip_index=[int]$bboxResolution.learned_text_grip_index;unresolved_sharp_cluster_count=[int]$final.unresolved_sharp_cluster_count;open_path_side_policy='DEDICATED_COLLAPSE_CLASSES_ONLY__NORMALS_RECEIVE_ZERO_COMMAND';allowed_grip_indexes=@(0);business_mutation_count=0;progress_path=$progressPath;next_gate='ZERO_OR_ONE_COLLAPSE_RESCUE_SEND_THEN_FULL_AUDIT_AND_VISUAL_REVIEW'}
  Write-LayoutV15Json $receiptPath $receipt;Write-LayoutV15Progress 'PLAN_READY';$receipt
}catch{Write-LayoutV15Progress 'PLAN_FAILED';Write-LayoutV15Json $receiptPath ([ordered]@{schema_version=18;status='LAYOUT_V17_PLAN_FAILED';detail=$_.Exception.Message;business_mutation_count=0;progress_path=$progressPath;next_gate='FIX_EXACT_FAILURE_NO_RETRY'});throw}
finally{if($had){$PSDefaultParameterValues[$quoteKey]=$prior}else{[void]$PSDefaultParameterValues.Remove($quoteKey)}}
