param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
$base=Join-Path $root 'scripts/build_full_scope_runtime_candidate_chain_v11.ps1'
$shim=Join-Path $root 'scripts/tdimarc_native_generation_born_angle_true_wcs_v9.lsp'
foreach($path in @($output,$spec,$base,$shim)){
  if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'RUNTIME_CHAIN_V20_PATH_OUTSIDE_PROJECT'
  }
}
$result=&$base -OutputPath $output -TaskSpecPath $spec
if([string]$result.status-cne'PASS'){throw 'RUNTIME_CHAIN_V20_V11_BUILD_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$autorun='(c:CXTDIMARCFULLBATCH)'
$last=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($last-lt0){throw 'RUNTIME_CHAIN_V20_AUTORUN_NOT_FOUND'}
$shimText=[IO.File]::ReadAllText($shim,[Text.Encoding]::UTF8).Trim()
$text=$text.Substring(0,$last)+$shimText+[Environment]::NewLine+[Environment]::NewLine+$text.Substring($last)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'RUNTIME_CHAIN_V20_AUTORUN_COUNT'}
$activeStart=$text.LastIndexOf('(defun cx:tw9-attempt',[StringComparison]::Ordinal)
$activeEnd=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($activeStart-lt0-or$activeEnd-le$activeStart){throw 'RUNTIME_CHAIN_V20_ACTIVE_REGION'}
$active=$text.Substring($activeStart,$activeEnd-$activeStart)
foreach($required in @(
  'BORN_ANGLE_TRUE_WCS_FULL_POLYLINE_V9',
  'source_hidden_during_pick=YES',
  'helper_wcs_translation_count=0',
  'candidate_back_translation_count=0',
  'transformby_count=0',
  'ucs_mutation_count=0',
  'helper_deleted=',
  'post_cleanup_survivor=',
  'style_write=0'
)){
  if(-not$active.Contains($required,[StringComparison]::Ordinal)){
    throw ('RUNTIME_CHAIN_V20_REQUIRED:'+ $required)
  }
}
foreach($forbidden in @(
  'CXLOCALUCSFRAME',
  'vla-Move',
  'vla-TransformBy',
  'CXNATIVETRANSFORM',
  '87/ARC/2',
  'vlax-put-property (list object ''TextContent',
  'REGEN'
)){
  if($active.Contains($forbidden,[StringComparison]::OrdinalIgnoreCase)){
    throw ('RUNTIME_CHAIN_V20_FORBIDDEN:'+ $forbidden)
  }
}
[pscustomobject]@{
  status='PASS'
  output=$output
  sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
  task_count=[int]$result.task_count
  production_path='TRUE_WCS_COMPLETE_POLYLINE_COPY__SOURCE_TEMP_HIDDEN__MIDPOINT_SINGLE_PROMPT__NO_TRANSLATION_NO_UCS__HELPER_DELETE__POST_CLEANUP_RANK2'
  prompt_fraction_count=1
  helper_wcs_translation_count=0
  candidate_back_translation_count=0
  transformby_count=0
  ucs_mutation_count=0
  board_specific_algorithm_literals=0
}
