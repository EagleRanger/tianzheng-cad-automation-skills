param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
$base=Join-Path $root 'scripts/build_full_scope_runtime_candidate_chain_v21.ps1'
$adapter=Join-Path $root 'scripts/tdimarc_native_generation_true_wcs_semantic_promote_v19.lsp'
foreach($path in @($output,$spec,$base,$adapter)){
  if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'SPV31_PATH_OUTSIDE_PROJECT'
  }
}
$result=&$base -OutputPath $output -TaskSpecPath $spec
if([string]$result.status-cne'PASS'-or[int]$result.task_count-lt1){throw 'SPV31_BASE'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$last=$text.LastIndexOf('(defun cx:ha1-create-candidate',[StringComparison]::Ordinal)
if($last-lt0){throw 'SPV31_CANDIDATE'}
$text=$text.Substring(0,$last)+'(defun cx:sp19-base-create-candidate'+$text.Substring($last+'(defun cx:ha1-create-candidate'.Length)
$autorun=$text.LastIndexOf('(c:CXTDIMARCFULLBATCH)',[StringComparison]::Ordinal)
if($autorun-lt0){throw 'SPV31_AUTORUN'}
$adapterText=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Trim()
$text=$text.Substring(0,$autorun)+$adapterText+[Environment]::NewLine+[Environment]::NewLine+$text.Substring($autorun)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$start=$text.LastIndexOf('(defun cx:sp19-base-create-candidate',[StringComparison]::Ordinal)
$end=$text.LastIndexOf('(c:CXTDIMARCFULLBATCH)',[StringComparison]::Ordinal)
if($start-lt0-or$end-le$start){throw 'SPV31_ACTIVE_REGION'}
$active=$text.Substring($start,$end-$start)
foreach($required in @('BORN_ANGLE_TRUE_WCS_ADAPTIVE_V10',"fractions '(0.50 0.35)")){
  if($text.IndexOf($required,[StringComparison]::Ordinal)-lt0){throw ('SPV31_REQUIRED:'+$required)}
}
foreach($required in @(
  'TRUE_WCS_SEMANTIC_PROMOTION_V19','ordinary_rank2_preserved=',
  'semantic_first_pass_rank=1','endpoint_rank2_claimed=NO',
  'second_pass_unified_layout_required=YES','(>= original-rank 2)'
)){
  if($active.IndexOf($required,[StringComparison]::Ordinal)-lt0){throw ('SPV31_REQUIRED:'+$required)}
}
foreach($forbidden in @(
  '87/ARC/2','87/ARC/7','404337','287185','TextContent','_.REGEN',
  'vlax-put-property','vla-put-','_.EXPLODE','vla-Save'
)){
  if($active.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase)-ge0){throw ('SPV31_FORBIDDEN:'+$forbidden)}
}
$lex=&(Join-Path $root 'scripts/assert_autolisp_lexical_balance_v1.ps1') -LispPath $output
if([string]$lex.status-cne'PASS'-or[int]$lex.final_depth-ne0){throw 'SPV31_LEXICAL'}
[pscustomobject]@{
  status='PASS';output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
  task_count=[int]$result.task_count
  ordinary_rank2_policy='RETURN_ORIGINAL_RESULT_UNCHANGED'
  exceptional_pick_policy='NORMALIZED_050_THEN_035__STOP_ON_FIRST_NATIVE_SIGNATURE'
  semantic_rank1_policy='NATIVE_FIVE_GRIP_SIGNATURE_ONLY__UNIFIED_SECOND_PASS_REQUIRED'
  board_specific_algorithm_literals=0
}
