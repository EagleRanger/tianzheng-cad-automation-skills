param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
foreach($path in @($output,$spec)){
  if(-not$path.StartsWith($projectRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'GC3_PATH_OUTSIDE_PROJECT'
  }
}
$base=& (Join-Path $PSScriptRoot 'build_full_scope_runtime_candidate_chain_v2.ps1') -OutputPath $output -TaskSpecPath $spec
if([string]$base.status-cne'PASS'){throw 'GC3_V2_BASE_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$dispatchStart=$text.LastIndexOf('(defun cx:dp4-run-one',[StringComparison]::Ordinal)
$dispatchEnd=$text.IndexOf('(defun cx:fb-run-one',$dispatchStart,[StringComparison]::Ordinal)
if($dispatchStart-lt0-or$dispatchEnd-le$dispatchStart){throw 'GC3_ACTIVE_DISPATCH_NOT_FOUND'}
$dispatch=$text.Substring($dispatchStart,$dispatchEnd-$dispatchStart)
$oldPick='(cx:fb-segment-points entity segment 0.35 effective-offset)'
$newPick='(cx:fb-segment-points entity segment 0.50 effective-offset)'
$oldTrace='",pick_fallback=" (if fallback-points "HISTORICAL_FRACTION_0.35" "NO")'
$newTrace='",pick_fallback=" (if fallback-points "MIDPOINT_RECOVERY_AFTER_NO_ORDINARY_PICK" "NO")'
if(([regex]::Matches($dispatch,[regex]::Escape($oldPick))).Count-ne1-or
   ([regex]::Matches($dispatch,[regex]::Escape($oldTrace))).Count-ne1){
  throw 'GC3_ACTIVE_FALLBACK_MARKERS'
}
$dispatch=$dispatch.Replace($oldPick,$newPick).Replace($oldTrace,$newTrace)
$text=$text.Substring(0,$dispatchStart)+$dispatch+$text.Substring($dispatchEnd)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$final=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$activeStart=$final.LastIndexOf('(defun cx:dp4-run-one',[StringComparison]::Ordinal)
$activeEnd=$final.IndexOf('(defun cx:fb-run-one',$activeStart,[StringComparison]::Ordinal)
$active=$final.Substring($activeStart,$activeEnd-$activeStart)
foreach($token in @(
  $newPick,'MIDPOINT_RECOVERY_AFTER_NO_ORDINARY_PICK','CANCEL_STUCK_AFTER_FINISH',
  'TDIMARC_PRESTART_COMMAND_NOT_IDLE','RUNTIME_ERROR_FINALIZED__SUCCESSFUL_NATIVE_OBJECTS_PRESERVED')){
  if(-not$final.Contains($token,[StringComparison]::Ordinal)){throw "GC3_REQUIRED_TOKEN:$token"}
}
if($active.Contains($oldPick,[StringComparison]::Ordinal)-or
   $active.Contains('HISTORICAL_FRACTION_0.35',[StringComparison]::Ordinal)){
  throw 'GC3_ACTIVE_035_FALLBACK_REMAINS'
}
if(([regex]::Matches($final,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'GC3_AUTORUN_COUNT'}
$lexical=& (Join-Path $PSScriptRoot 'assert_autolisp_lexical_balance_v1.ps1') -LispPath $output
if([string]$lexical.status-cne'PASS'-or[int]$lexical.final_depth-ne0){throw 'GC3_LEXICAL'}
[pscustomobject]@{
  status='PASS';task_count=@((Get-Content -LiteralPath $spec -Raw -Encoding UTF8|ConvertFrom-Json).tasks).Count
  ordinary_pick_policy='UNCHANGED'
  direct_no_ordinary_pick_policy='RUNTIME_SEGMENT_MIDPOINT_0.50'
  prompt_sequence='UNCHANGED_FIVE_STAGE_WITH_CONDITIONAL_CANCEL'
  runtime_error_reports='PRESERVE_ACCEPTED_AND_FINALIZE'
  board_specific_algorithm_literals=0;retry_count=0;lexical_balance='PASS'
  sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
}
