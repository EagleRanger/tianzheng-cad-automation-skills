param([Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$TaskSpecPath)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$output=[IO.Path]::GetFullPath($OutputPath);$spec=[IO.Path]::GetFullPath($TaskSpecPath);$observer=Join-Path $root 'scripts/tdimarc_native_candidate_diagnostic_vector_v1.lsp'
foreach($path in @($output,$spec,$observer)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'GC8_PATH_OUTSIDE_PROJECT'}}
$base=& (Join-Path $PSScriptRoot 'build_full_scope_runtime_candidate_chain_v7.ps1') -OutputPath $output -TaskSpecPath $spec
if([string]$base.status-cne'PASS'){throw 'GC8_V7_BASE_FAILED'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8);$autorun='(c:CXTDIMARCFULLBATCH)'
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw 'GC8_BASE_AUTORUN_COUNT'}
$text=[regex]::Replace($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$','',1)
function Rename-LastDefun([string]$Text,[string]$Public,[string]$Private){$needle='(defun '+$Public;$index=$Text.LastIndexOf($needle,[StringComparison]::Ordinal);if($index-lt0){throw ('GC8_ACTIVE_FUNCTION_NOT_FOUND:'+$Public)};$Text.Substring(0,$index)+'(defun '+$Private+$Text.Substring($index+$needle.Length)}
$text=Rename-LastDefun $text 'cx:geh1-create-candidate' 'cx:cdv1-base-endpoint-candidate'
$text=Rename-LastDefun $text 'cx:gcp1-create-candidate' 'cx:cdv1-base-promotion-candidate'
$text=Rename-LastDefun $text 'cx:ha1-create-candidate' 'cx:cdv1-base-angle-vector'
$trace=[IO.Path]::Combine([IO.Path]::GetDirectoryName($output),'candidate_diagnostic_vector.tsv').Replace('\','/')
$module=[IO.File]::ReadAllText($observer,[Text.Encoding]::UTF8).Trim()
$tail='(setq cx:*cdv1-trace-path* "'+$trace+'")'+[Environment]::NewLine+'(setq cx:*cdv1-stream* (open cx:*cdv1-trace-path* "w"))'+[Environment]::NewLine+'(write-line "STAGE`tROUTE`tFRACTION`tDETAIL" cx:*cdv1-stream*)'+[Environment]::NewLine+'(close cx:*cdv1-stream*)'+[Environment]::NewLine+$module+[Environment]::NewLine+$autorun+[Environment]::NewLine+'(cx:cdv1-post-batch-audit)'+[Environment]::NewLine
$text=$text.TrimEnd()+[Environment]::NewLine+$tail
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false));$final=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
foreach($token in @('(defun cx:cdv1-base-endpoint-candidate','(defun cx:cdv1-base-promotion-candidate','(defun cx:cdv1-base-angle-vector','(defun cx:geh1-create-candidate','(defun cx:gcp1-create-candidate','(defun cx:ha1-create-candidate','TEXTCONTENT_HARD_GATE','(cx:cdv1-post-batch-audit)')){if(-not$final.Contains($token,[StringComparison]::Ordinal)){throw ('GC8_REQUIRED:'+$token)}}
if(([regex]::Matches($final,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1-or([regex]::Matches($final,'\(defun c:CXTDIMARCFULLBATCH')).Count-ne1){throw 'GC8_PUBLIC_COMMAND_COUNT'}
$active=$final.Substring($final.LastIndexOf('(defun cx:cdv1-clean',[StringComparison]::Ordinal));foreach($forbidden in @('vlax-put-property','TDIMARC")','_.REGEN','vla-Save','87/ARC/2','8C/ARC/6','8B/ARC/2','88/ARC/7','87/ARC/6','87/ARC/7')){if($active.Contains($forbidden,[StringComparison]::OrdinalIgnoreCase)){throw ('GC8_OBSERVER_SCOPE:'+$forbidden)}}
$lexical=& (Join-Path $PSScriptRoot 'assert_autolisp_lexical_balance_v1.ps1') -LispPath $output;if([string]$lexical.status-cne'PASS'-or[int]$lexical.final_depth-ne0){throw 'GC8_LEXICAL'}
[pscustomobject]@{status='PASS';task_count=[int]$base.task_count;production_base='V7_UNCHANGED_DECISIONS';diagnostic_vector='ENDPOINT_PROMOTION_ANGLE_RETURN_POST_BATCH_TEXTCONTENT';cad_send_count_added=0;retry_count=0;save_count=0;board_specific_algorithm_literals=0;lexical_balance='PASS';sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash}
