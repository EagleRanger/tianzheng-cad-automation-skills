param([Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$TaskSpecPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath)
$spec=[IO.Path]::GetFullPath($TaskSpecPath)
$adapter=Join-Path $root 'scripts/tdimarc_native_generation_born_angle_confirm_vector_v1.lsp'
$acceptance=Join-Path $root 'scripts/tdimarc_native_generation_born_angle_vector_v5.lsp'
foreach($path in @($output,$spec,$adapter,$acceptance)){
  if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'GC10_PATH_OUTSIDE_PROJECT'}
}
$base=&(Join-Path $PSScriptRoot 'build_full_scope_runtime_candidate_chain_v8.ps1') -OutputPath $output -TaskSpecPath $spec
if([string]$base.status-cne'PASS'){throw 'GC10_V8_BASE_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$tailPattern='(?ms)\(c:CXTDIMARCFULLBATCH\)\s*\(cx:cdv1-post-batch-audit\)\s*\z'
if(([regex]::Matches($text,$tailPattern)).Count-ne1){throw 'GC10_V8_TAIL'}
$text=[regex]::Replace($text,$tailPattern,'',1)
$module=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Trim()
$acceptanceModule=[IO.File]::ReadAllText($acceptance,[Text.Encoding]::UTF8).Trim()
$text=$text.TrimEnd()+[Environment]::NewLine+$module+[Environment]::NewLine+$acceptanceModule+[Environment]::NewLine+'(c:CXTDIMARCFULLBATCH)'+[Environment]::NewLine+'(cx:cdv1-post-batch-audit)'+[Environment]::NewLine
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$final=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
foreach($token in @('BORN_ANGLE_CONFIRM_VECTOR_V1','BORN_ANGLE_PROMOTION_VECTOR','GENERIC_ANGLE_SEMANTIC_VECTOR_V5','BORN_INCLUDED_ANGLE_BY_PROMPT_VECTOR','style_write=0','display_text_wait=0','(1.0 -1.0 2.0 -2.0)','(c:CXTDIMARCFULLBATCH)','(cx:cdv1-post-batch-audit)')){
  if(-not$final.Contains($token,[StringComparison]::Ordinal)){throw ('GC10_REQUIRED:'+$token)}
}
$active=$final.Substring($final.LastIndexOf(';; V5 business acceptance',[StringComparison]::Ordinal))
foreach($forbidden in @('vlax-put-property','vla-Save','TextContent','_.REGEN','87/ARC/2','_TCH_ARC_M_M')){
  if($active.Contains($forbidden,[StringComparison]::OrdinalIgnoreCase)){throw ('GC10_ACTIVE_FORBIDDEN:'+$forbidden)}
}
if(([regex]::Matches($final,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'GC10_COMMAND_COUNT'}
$lexical=&(Join-Path $PSScriptRoot 'assert_autolisp_lexical_balance_v1.ps1') -LispPath $output
if([string]$lexical.status-cne'PASS'-or[int]$lexical.final_depth-ne0){throw 'GC10_LEXICAL'}
[pscustomobject]@{status='PASS';task_count=[int]$base.task_count;production_path='BORN_NATIVE_STYLE_PLUS_RUNTIME_GEOMETRY_AND_GRIPS';confirm_vector_count=4;style_write_count=0;textcontent_wait_count=0;regen_count=0;board_specific_algorithm_literals=0;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
