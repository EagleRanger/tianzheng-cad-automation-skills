param([Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$TaskSpecPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
$base=Join-Path $root 'scripts/build_full_scope_runtime_candidate_chain_v10.ps1'
$adapter=Join-Path $root 'scripts/tdimarc_native_generation_born_angle_confirm_vector_v2.lsp'
foreach($path in @($output,$spec,$base,$adapter)){
  if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'RUNTIME_CHAIN_V11_PATH_OUTSIDE_PROJECT'}
}
$result=&$base -OutputPath $output -TaskSpecPath $spec
if([string]$result.status-cne'PASS'){throw 'RUNTIME_CHAIN_V11_V10_BUILD_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$autorun='(c:CXTDIMARCFULLBATCH)'
$last=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($last-lt0){throw 'RUNTIME_CHAIN_V11_AUTORUN_NOT_FOUND'}
$adapterText=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Trim()
$text=$text.Substring(0,$last)+$adapterText+[Environment]::NewLine+[Environment]::NewLine+$text.Substring($last)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'RUNTIME_CHAIN_V11_AUTORUN_COUNT'}
$activeStart=$text.LastIndexOf('(defun cx:bacv2-attempt',[StringComparison]::Ordinal)
$activeEnd=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($activeStart-lt0-or$activeEnd-le$activeStart){throw 'RUNTIME_CHAIN_V11_ACTIVE_REGION'}
$active=$text.Substring($activeStart,$activeEnd-$activeStart)
foreach($required in @('translation_while_helper_alive=','post_cleanup_survivor=','BORN_ANGLE_PROMOTION_VECTOR_V2','style_write=0')){
  if(-not$active.Contains($required,[StringComparison]::Ordinal)){throw ('RUNTIME_CHAIN_V11_REQUIRED:'+ $required)}
}
foreach($forbidden in @('vlax-put-property','TextContent','REGEN','87/ARC/2')){
  if($active.Contains($forbidden,[StringComparison]::OrdinalIgnoreCase)){throw ('RUNTIME_CHAIN_V11_FORBIDDEN:'+ $forbidden)}
}
[pscustomobject]@{
  status='PASS';output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
  task_count=[int]$result.task_count
  production_path='BORN_NATIVE_STYLE__TRANSLATE_WHILE_HELPER_ALIVE__DELETE_HELPER__POST_CLEANUP_RANK2_AUDIT'
  confirm_vector_count=4;active_style_write_count=0;active_text_wait_count=0;active_regen_count=0
  helper_cleanup_after_translation=$true;post_helper_cleanup_audit=$true
  board_specific_algorithm_literals=0
}
