param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
foreach($path in @($output,$spec)){
  if(-not $path.StartsWith($projectRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'GC2_PATH_OUTSIDE_PROJECT'
  }
}
$base=& (Join-Path $PSScriptRoot 'build_full_scope_runtime_candidate_chain_v1.ps1') -OutputPath $output -TaskSpecPath $spec
if([string]$base.status-cne'PASS'){throw 'GC2_V1_BASE_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$autorun='(c:CXTDIMARCFULLBATCH)'
$autorunIndex=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($autorunIndex-lt0){throw 'GC2_AUTORUN_NOT_FOUND'}
$settlement=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tdimarc_native_generation_prompt_settlement_v1.lsp'),[Text.Encoding]::UTF8).Trim()
$finalizer=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'tdimarc_native_continuous_batch_error_finalizer_v1.lsp'),[Text.Encoding]::UTF8).Trim()
$modules=$settlement+[Environment]::NewLine+[Environment]::NewLine+$finalizer+[Environment]::NewLine+[Environment]::NewLine
$text=$text.Substring(0,$autorunIndex)+$modules+$text.Substring($autorunIndex)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$final=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
if(([regex]::Matches($final,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'GC2_AUTORUN_COUNT'}
foreach($token in @(
  'CANCEL_STUCK_AFTER_FINISH',
  'TDIMARC_PRESTART_COMMAND_NOT_IDLE',
  'TDIMARC_POSTFINISH_COMMAND_NOT_IDLE',
  'RUNTIME_ERROR_FINALIZED__SUCCESSFUL_NATIVE_OBJECTS_PRESERVED',
  '(defun cx:fb-runtime-error (message)',
  'PRESERVED_ACCEPTED_OBJECTS')){
  $position=$final.LastIndexOf($token,[StringComparison]::Ordinal)
  if($position-lt0-or$position-gt$final.LastIndexOf($autorun,[StringComparison]::Ordinal)){
    throw "GC2_REQUIRED_TOKEN:$token"
  }
}
$lastPrompt=$final.LastIndexOf('(defun cx:gm1-staged-tdimarc',[StringComparison]::Ordinal)
$lastError=$final.LastIndexOf('(defun cx:fb-runtime-error (message)',[StringComparison]::Ordinal)
if($lastPrompt-lt0-or$lastError-lt$lastPrompt-or$lastError-gt$final.LastIndexOf($autorun,[StringComparison]::Ordinal)){
  throw 'GC2_OVERRIDE_ORDER'
}
$lexical=& (Join-Path $PSScriptRoot 'assert_autolisp_lexical_balance_v1.ps1') -LispPath $output
if([string]$lexical.status-cne'PASS'-or[int]$lexical.final_depth-ne0){throw 'GC2_LEXICAL'}
[pscustomobject]@{
  status='PASS'
  task_count=@((Get-Content -LiteralPath $spec -Raw -Encoding UTF8|ConvertFrom-Json).tasks).Count
  prompt_sequence='UNCHANGED_FIVE_STAGE_THEN_ONE_CANCEL_ONLY_IF_STILL_ACTIVE'
  prestart_idle_gate='REQUIRED'
  runtime_error_reports='SUMMARY_DETAILS_FINALIZED_WITH_ACCEPTED_OBJECTS_PRESERVED'
  retry_count=0
  lexical_balance='PASS'
  sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
}
