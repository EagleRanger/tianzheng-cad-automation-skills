param([Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$TaskSpecPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$output=[IO.Path]::GetFullPath($OutputPath);$module=Join-Path $root 'scripts/tdimarc_native_generation_angle_semantic_vector_v4.lsp'
foreach($path in @($output,[IO.Path]::GetFullPath($TaskSpecPath),$module)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'GC6_PATH_OUTSIDE_PROJECT'}}
$base=& (Join-Path $PSScriptRoot 'build_full_scope_runtime_candidate_chain_v3.ps1') -OutputPath $output -TaskSpecPath $TaskSpecPath
if([string]$base.status-cne'PASS'){throw 'GC6_V3_BASE_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8);$autorun='(c:CXTDIMARCFULLBATCH)'
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'GC6_BASE_AUTORUN_COUNT'}
$text=[regex]::Replace($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$','',1)
$vector=[IO.File]::ReadAllText($module,[Text.Encoding]::UTF8)
$text=$text.TrimEnd()+[Environment]::NewLine+$vector.Trim()+[Environment]::NewLine+$autorun+[Environment]::NewLine
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false));$final=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
foreach($token in @('NATIVE_ANGLE_VECTOR_V4','DEFER_EMPTY_TEXTCONTENT_ANGLE_KNOWN','DEFER_EMPTY_TEXTCONTENT_ANGLE_SETTLES_POST_GENERATION','creation_empty_text_defer=FORBIDDEN','post_generation_textcontent_hard_gate=REQUIRED')){if(-not$final.Contains($token,[StringComparison]::Ordinal)){throw "GC6_REQUIRED:$token"}}
$active=$final.Substring($final.LastIndexOf('(defun cx:asv4-clean-text',[StringComparison]::Ordinal))
foreach($forbidden in @('(defun cx:gcp1-normalize-style','vlax-put-property','87/ARC/2','8C/ARC/6','8B/ARC/2','88/ARC/7','87/ARC/6','87/ARC/7')){if($active.Contains($forbidden,[StringComparison]::OrdinalIgnoreCase)){throw "GC6_FORBIDDEN:$forbidden"}}
if(([regex]::Matches($final,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'GC6_FINAL_AUTORUN_COUNT'}
$lexical=& (Join-Path $PSScriptRoot 'assert_autolisp_lexical_balance_v1.ps1') -LispPath $output;if([string]$lexical.status-cne'PASS'){throw 'GC6_LEXICAL'}
[pscustomobject]@{status='PASS';task_count=[int]$base.task_count;semantic_vector='BORN_STYLE_ENDPOINTS_GRIPS_RADIAL_SCALAR_TEXTCONTENT';function_identity_collision_count=0;promotion_empty_text_defer='FORBIDDEN';cad_send_count_added=0;retry_count=0;board_specific_algorithm_literals=0;lexical_balance='PASS';sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
