param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
$base=Join-Path $root 'scripts/build_full_scope_semantic_promote_v31.ps1'
$adapter=Join-Path $root 'scripts/tdimarc_native_generation_semantic_exception_only_v24.lsp'
foreach($path in @($output,$spec,$base,$adapter)){
  if(-not $path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'SPV37_PATH_OUTSIDE_PROJECT'
  }
}
$result=& $base -OutputPath $output -TaskSpecPath $spec
if([string]$result.status-cne'PASS'){throw 'SPV37_BASE'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$last=$text.LastIndexOf('(defun cx:ha1-create-candidate',[StringComparison]::Ordinal)
$autorun=$text.LastIndexOf('(c:CXTDIMARCFULLBATCH)',[StringComparison]::Ordinal)
if($last-lt0-or$autorun-lt0-or$last-ge$autorun){throw 'SPV37_OVERRIDE_ORDER'}
$text=$text.Substring(0,$last)+'(defun cx:seo24-semantic-fallback'+$text.Substring($last+'(defun cx:ha1-create-candidate'.Length)
$adapterText=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Trim()
$text=$text.Substring(0,$autorun)+$adapterText+[Environment]::NewLine+[Environment]::NewLine+$text.Substring($autorun)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$activeStart=$text.LastIndexOf('(defun cx:seo24-semantic-fallback',[StringComparison]::Ordinal)
$active=$text.Substring($activeStart,$text.LastIndexOf('(c:CXTDIMARCFULLBATCH)',[StringComparison]::Ordinal)-$activeStart)
foreach($token in @(
  'SEMANTIC_EXCEPTION_ONLY_V24',
  'ORDINARY_ENDPOINT_HELPER_FIVE_GRIP_RANK2_PRESERVED',
  'SPECIAL_BORN_ANGLE_TRUE_WCS',
  'rendered_angle_gate=REQUIRED_BY_CONTROLLER',
  'style_write=0',
  '(cx:cdv1-base-endpoint-candidate',
  '(cx:seo24-semantic-fallback')){
  if($active.IndexOf($token,[StringComparison]::Ordinal)-lt0){throw ('SPV37_REQUIRED:'+$token)}
}
foreach($token in @('87/ARC/2','404337','287183','83.482812','vla-put-','vlax-put-property','_TCH_ARC_M_M')){
  if($active.IndexOf($token,[StringComparison]::OrdinalIgnoreCase)-ge0){throw ('SPV37_FORBIDDEN:'+$token)}
}
$lex=& (Join-Path $root 'scripts/assert_autolisp_lexical_balance_v1.ps1') -LispPath $output
if([string]$lex.status-cne'PASS'-or[int]$lex.final_depth-ne0){throw 'SPV37_LEXICAL'}
[pscustomobject]@{
  status='PASS'
  output=$output
  sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
  task_count=[int]$result.task_count
  ordinary_policy='ENDPOINT_HELPER_FIVE_GRIP_RANK2_FIRST'
  exception_policy='BORN_ANGLE_TRUE_WCS_FIVE_GRIP_SEMANTIC_RANK1_ONLY'
  rendered_semantic_gate='FORMAL_POST_GENERATION_REQUIRED'
  post_creation_style_write_count=0
  board_specific_algorithm_literals=0
}
