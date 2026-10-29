param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output=[IO.Path]::GetFullPath($OutputPath);$spec=[IO.Path]::GetFullPath($TaskSpecPath)
$base=Join-Path $root 'scripts/build_full_scope_runtime_candidate_chain_v21.ps1'
$adapter=Join-Path $root 'scripts/tdimarc_native_generation_exception_rescue_v21.lsp'
foreach($path in @($output,$spec,$base,$adapter)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SPV34_PATH_OUTSIDE_PROJECT'}}
$result=&$base -OutputPath $output -TaskSpecPath $spec
if([string]$result.status-cne'PASS'){throw 'SPV34_BASE'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8)
$dynamicMarker='GENERIC_DYNAMIC_CANDIDATE_PROMOTION_V1'
$markerIndex=$text.IndexOf($dynamicMarker,[StringComparison]::Ordinal)
if($markerIndex-lt0){throw 'SPV34_DYNAMIC_RESCUE_MARKER'}
$dynamicNeedle='(defun cx:cdv1-base-promotion-candidate'
$dynamicDef=$text.LastIndexOf($dynamicNeedle,$markerIndex,[StringComparison]::Ordinal)
if($dynamicDef-lt0){throw 'SPV34_DYNAMIC_RESCUE_DEF'}
$text=$text.Remove($dynamicDef,$dynamicNeedle.Length).Insert($dynamicDef,'(defun cx:er21-dynamic-full-polyline-rescue')
$autorunNeedle='(c:CXTDIMARCFULLBATCH)'
$autorun=$text.LastIndexOf($autorunNeedle,[StringComparison]::Ordinal)
if($autorun-lt0){throw 'SPV34_AUTORUN'}
$activeNeedle='(defun cx:ha1-create-candidate'
$activeBase=$text.LastIndexOf($activeNeedle,$autorun,[StringComparison]::Ordinal)
if($activeBase-lt0){throw 'SPV34_ACTIVE_BASE'}
$text=$text.Remove($activeBase,$activeNeedle.Length).Insert($activeBase,'(defun cx:er21-base-create-candidate')
# Function renames change byte offsets. Re-resolve the autorun boundary after every rename.
$autorun=$text.LastIndexOf($autorunNeedle,[StringComparison]::Ordinal)
if($autorun-lt0){throw 'SPV34_AUTORUN_AFTER_RENAME'}
$adapterText=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Trim()
$text=$text.Insert($autorun,$adapterText+[Environment]::NewLine+[Environment]::NewLine)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$start=$text.LastIndexOf('(defun cx:er21-dynamic-full-polyline-rescue',[StringComparison]::Ordinal);$end=$text.LastIndexOf($autorunNeedle,[StringComparison]::Ordinal)
if($start-lt0-or$end-le$start){throw 'SPV34_ACTIVE_REGION'};$active=$text.Substring($start,$end-$start)
foreach($token in @('GENERIC_DYNAMIC_CANDIDATE_PROMOTION_V1','EXCEPTION_RESCUE_V21','NORMAL_RANK2_PRESERVED','RUNTIME_ABNORMAL_ONLY','ORDINARY_RANK_BELOW_2','normal_objects_frozen=YES')){if(-not$active.Contains($token,[StringComparison]::Ordinal)){throw ('SPV34_REQUIRED:'+$token)}}
foreach($literal in @('87/ARC/2','8D/ARC/8','404337','287183','vla-Save','TMirDim')){if($active.Contains($literal,[StringComparison]::OrdinalIgnoreCase)){throw ('SPV34_FORBIDDEN:'+$literal)}}
if([regex]::IsMatch($text,'(?im)^[ \t]*\(prin(?:[ \t]|\()')){throw 'SPV34_TRUNCATED_PRINC_TOKEN'}
if(([regex]::Matches($text,'(?m)^[ \t]*\(princ\)[ \t]*\r?$')).Count-lt1){throw 'SPV34_PRINC_SENTINEL_MISSING'}
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)[ \t]*\r?$')).Count-ne1){throw 'SPV34_AUTORUN_COUNT'}
$lex=&(Join-Path $root 'scripts/assert_autolisp_lexical_balance_v1.ps1') -LispPath $output;if([string]$lex.status-cne'PASS'-or[int]$lex.final_depth-ne0){throw 'SPV34_LEXICAL'}
[pscustomobject]@{status='PASS';output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;task_count=[int]$result.task_count;ordinary_policy='RANK2_BYTE_PRESERVED';exception_policy='RUNTIME_RANK_BELOW_2__ONE_DYNAMIC_FULL_POLYLINE_RESCUE__RANK2_ONLY';commanded_grip4_count=0;board_specific_algorithm_literals=0;truncated_prin_tokens=0;autorun_count=1}
