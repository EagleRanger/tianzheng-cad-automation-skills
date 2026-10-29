param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath);$specPath=[IO.Path]::GetFullPath($TaskSpecPath)
foreach($path in @($output,$specPath)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RUNTIME_ORDINARY_PATH_OUTSIDE_PROJECT'}}
function Find-RuntimeOrdinaryFormEnd([string]$Text,[int]$StartIndex){
  $depth=0;$seen=$false;$inString=$false
  for($i=$StartIndex;$i-lt$Text.Length;$i++){
    $ch=$Text[$i];if($ch-eq'"'){$inString=-not$inString;continue};if($inString){continue}
    if($ch-eq'('){$depth++;$seen=$true}elseif($ch-eq')'){$depth--;if($seen-and$depth-eq0){return $i+1};if($depth-lt0){throw 'RUNTIME_ORDINARY_UNBALANCED'}}
  }
  throw 'RUNTIME_ORDINARY_FORM_END_NOT_FOUND'
}
$spec=Get-Content -LiteralPath $specPath -Raw -Encoding UTF8|ConvertFrom-Json;$tasks=@($spec.tasks)
if($tasks.Count-lt1){throw 'RUNTIME_ORDINARY_EMPTY_TASK_SET'}
$seen=@{};$lispTasks=[Collections.Generic.List[string]]::new()
foreach($task in $tasks){
  $handle=([string]$task.source_handle).ToUpperInvariant();$type=([string]$task.segment_type).ToUpperInvariant();$index=[int]$task.segment_index;$offset=[double]$task.offset;$group=([string]$task.group).ToUpperInvariant()
  if($handle-notmatch'^[0-9A-F]+$'-or$type-notin@('ARC','LINE')-or$index-lt0-or[Math]::Abs($offset)-lt1e-9-or[string]::IsNullOrWhiteSpace($group)){throw 'RUNTIME_ORDINARY_INVALID_TASK'}
  $key="$handle/$type/$index";if($seen.ContainsKey($key)){throw "RUNTIME_ORDINARY_DUPLICATE:$key"};$seen[$key]=$true
  $offsetText=$offset.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
  $lispTasks.Add(('  (list "{0}" (list (list "{1}" {2})) {3} "{4}")'-f$handle,$type,$index,$offsetText,$group))
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $output))|Out-Null;$tmp=$output+'.runtime-single.tmp.json'
try{
  $single=[pscustomobject]@{schema_version=1;expected_drawing=[IO.Path]::GetFullPath([string]$spec.expected_drawing);summary_path=[IO.Path]::GetFullPath([string]$spec.summary_path);details_path=[IO.Path]::GetFullPath([string]$spec.details_path);stage_trace_path=[IO.Path]::GetFullPath([string]$spec.stage_trace_path);tasks=@($tasks[0])}
  [IO.File]::WriteAllText($tmp,($single|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
  $base=& (Join-Path $PSScriptRoot 'build_targeted_confirm_arc_dimension_positive_v40.ps1') -OutputPath $output -TaskSpecPath $tmp
  if([string]$base.status-cne'PASS'){throw 'RUNTIME_ORDINARY_V40_BASE'}
  $text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8);$taskStart=$text.LastIndexOf('(setq cx:*full-batch-tasks*',[StringComparison]::Ordinal);$autorunIndex=$text.LastIndexOf('(c:CXTDIMARCFULLBATCH)',[StringComparison]::Ordinal)
  if($taskStart-lt0-or$autorunIndex-le$taskStart){throw 'RUNTIME_ORDINARY_TASK_OR_AUTORUN'}
  $taskEnd=Find-RuntimeOrdinaryFormEnd $text $taskStart;$assignment="(setq cx:*full-batch-tasks*`r`n  (list`r`n"+(($lispTasks.ToArray())-join"`r`n")+"`r`n  ))";$text=$text.Substring(0,$taskStart)+$assignment+$text.Substring($taskEnd)
  $dispatchStart=$text.LastIndexOf('(defun cx:dp4-run-one',[StringComparison]::Ordinal);$dispatchEnd=$text.IndexOf('(defun cx:fb-run-one',$dispatchStart,[StringComparison]::Ordinal)
  if($dispatchStart-lt0-or$dispatchEnd-le$dispatchStart){throw 'RUNTIME_ORDINARY_DISPATCH'}
  $dispatch=$text.Substring($dispatchStart,$dispatchEnd-$dispatchStart);$old='(cx:fb-segment-points entity segment 0.50 effective-offset)';$new='(cx:fb-segment-points entity segment 0.35 effective-offset)';$oldTrace='",pick_fallback=" (if fallback-points "MIDPOINT" "NO")';$newTrace='",pick_fallback=" (if fallback-points "HISTORICAL_FRACTION_0.35" "NO")'
  if(([regex]::Matches($dispatch,[regex]::Escape($old))).Count-ne1-or([regex]::Matches($dispatch,[regex]::Escape($oldTrace))).Count-ne1){throw 'RUNTIME_ORDINARY_PICK_MARKERS'}
  $dispatch=$dispatch.Replace($old,$new).Replace($oldTrace,$newTrace);$text=$text.Substring(0,$dispatchStart)+$dispatch+$text.Substring($dispatchEnd);[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
  $semantic=& (Join-Path $PSScriptRoot 'assert_targeted_confirm_arc_dimension_positive_v40_semantics.ps1') -BundlePath $output;if([string]$semantic.status-cne'PASS'){throw 'RUNTIME_ORDINARY_SEMANTIC'}
  $final=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
  if(([regex]::Matches($final,'(?m)^  \(list "[0-9A-F]+" \(list \(list "(?:ARC|LINE)" [0-9]+\)\)')).Count-ne$tasks.Count){throw 'RUNTIME_ORDINARY_EMBEDDED_TASK_COUNT'}
  if(([regex]::Matches($final,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'RUNTIME_ORDINARY_AUTORUN_COUNT'}
}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
[pscustomobject]@{status='PASS';task_count=$tasks.Count;task_discovery='RUNTIME_TASK_SPEC';known_failure_literals=0;source_pick_fraction='0.35_RUNTIME_GEOMETRY';sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
