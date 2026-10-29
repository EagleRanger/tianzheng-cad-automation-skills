param([Parameter(Mandatory=$true)][string]$OutputPath,[Parameter(Mandatory=$true)][string]$TaskSpecPath)
$ErrorActionPreference='Stop';$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$output=[IO.Path]::GetFullPath($OutputPath);$spec=[IO.Path]::GetFullPath($TaskSpecPath);$base=Join-Path $root 'scripts/build_full_scope_semantic_promote_v34.ps1';$adapter=Join-Path $root 'scripts/tdimarc_native_generation_exception_rescue_v22.lsp'
foreach($path in @($output,$spec,$base,$adapter)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SPV35_PATH_OUTSIDE_PROJECT'}}
$result=&$base -OutputPath $output -TaskSpecPath $spec;if([string]$result.status-cne'PASS'){throw 'SPV35_BASE'}
$text=[IO.File]::ReadAllText($output,[Text.Encoding]::UTF8);$autorunNeedle='(c:CXTDIMARCFULLBATCH)';$autorun=$text.LastIndexOf($autorunNeedle,[StringComparison]::Ordinal);if($autorun-lt0){throw 'SPV35_AUTORUN'}
$adapterText=[IO.File]::ReadAllText($adapter,[Text.Encoding]::UTF8).Trim();$text=$text.Insert($autorun,$adapterText+[Environment]::NewLine+[Environment]::NewLine)
[IO.File]::WriteAllText($output,$text,[Text.UTF8Encoding]::new($false))
$activeStart=$text.LastIndexOf('(defun cx:er22-direct-source-fraction-rescue',[StringComparison]::Ordinal);$activeEnd=$text.LastIndexOf($autorunNeedle,[StringComparison]::Ordinal);if($activeStart-lt0-or$activeEnd-le$activeStart){throw 'SPV35_ACTIVE_REGION'};$active=$text.Substring($activeStart,$activeEnd-$activeStart)
foreach($token in @('NORMAL_RANK2_PRESERVED','DIRECT_SOURCE_FRACTION','TRANSLATED_FULL_POLYLINE','ALL_RESCUES_EXHAUSTED','cx:ss-v2-run-one','cx:er21-dynamic-full-polyline-rescue')){if(-not$active.Contains($token,[StringComparison]::Ordinal)){throw ('SPV35_REQUIRED:'+$token)}}
if($active.IndexOf('DIRECT_SOURCE_FRACTION',[StringComparison]::Ordinal)-gt$active.IndexOf('TRANSLATED_FULL_POLYLINE',[StringComparison]::Ordinal)){throw 'SPV35_RESCUE_ORDER'}
foreach($literal in @('8D/ARC/8','87/ARC/2','404333','287195','vla-Save','TMirDim')){if($active.Contains($literal,[StringComparison]::OrdinalIgnoreCase)){throw ('SPV35_FORBIDDEN:'+$literal)}}
if([regex]::IsMatch($text,'(?im)^[ \t]*\(prin(?:[ \t]|\()')){throw 'SPV35_TRUNCATED_PRINC'}
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)[ \t]*\r?$')).Count-ne1){throw 'SPV35_AUTORUN_COUNT'}
$lex=&(Join-Path $root 'scripts/assert_autolisp_lexical_balance_v1.ps1') -LispPath $output;if([string]$lex.status-cne'PASS'-or[int]$lex.final_depth-ne0){throw 'SPV35_LEXICAL'}
[pscustomobject]@{status='PASS';output=$output;sha256=(Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;task_count=[int]$result.task_count;ordinary_policy='RANK2_BYTE_PRESERVED';exception_policy='ORDINARY_BELOW2__DIRECT_SOURCE_ADAPTIVE_FRACTIONS__TRANSLATED_FULL_POLYLINE__RANK2_ONLY';commanded_grip4_count=0;board_specific_algorithm_literals=0;truncated_prin_tokens=0;autorun_count=1}
