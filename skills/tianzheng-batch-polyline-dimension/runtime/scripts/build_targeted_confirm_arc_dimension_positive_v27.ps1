param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)

$ErrorActionPreference='Stop'
$v25=Join-Path $PSScriptRoot 'build_targeted_confirm_arc_dimension_positive_v25.ps1'
$dispatchPath=Join-Path $PSScriptRoot 'tdimarc_native_generation_direct_positive_dispatch_v4.lsp'
$result=& $v25 -OutputPath $OutputPath -TaskSpecPath $TaskSpecPath
if([string]$result.status-cne'PASS'){ throw 'V27_V25_BUILD_FAILED' }

$path=[IO.Path]::GetFullPath($OutputPath)
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$dispatch=[IO.File]::ReadAllText($dispatchPath,[Text.Encoding]::UTF8).Trim()
$autorun='(c:CXTDIMARCFULLBATCH)'
$last=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($last-lt0){ throw 'V27_AUTORUN_NOT_FOUND' }
$text=$text.Substring(0,$last)+$dispatch+[Environment]::NewLine+[Environment]::NewLine+$text.Substring($last)

if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){
  throw 'V27_AUTORUN_INVALID'
}
[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))

$semantic=& (Join-Path $PSScriptRoot 'assert_native_generation_bundle_semantics_v3.ps1') `
  -BundlePath $path `
  -EndpointFunction 'CXNATIVEPLACEMENTAUDITV5'
if([string]$semantic.status-cne'PASS'){ throw 'V27_SEMANTIC_AUDIT_FAILED' }

[pscustomobject]@{
  status='PASS'
  output=$path
  sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  prompt_sequence='START_SELECT_OBJECT_CONFIRM_ARC_FINAL_DIMENSION_POSITION_OPTIONAL_FINISH'
  zero_survivor_direct_route='REQUIRED_AND_REACHABLE'
  low_rank_direct_route='REQUIRED_AND_REACHABLE'
  pick_fallback='FROZEN_KERNEL_ORIGINAL_ARC_MIDPOINT'
  runtime_trace_required=$true
  minimum_accepted_rank=1
  preferred_rank=2
  endpoint_gate='CXNATIVEPLACEMENTAUDITV5_WCS_XY'
  proxy_count=0
  candidate_count_max=1
  semantic_audit='PASS_V3'
}

