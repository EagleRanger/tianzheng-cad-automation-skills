param(
  [Parameter(Mandatory=$true)][string]$BundlePath,
  [string]$EndpointFunction='CXNATIVEPLACEMENTAUDITV5'
)

$ErrorActionPreference='Stop'
$v1=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_native_generation_bundle_semantics_v1.ps1'
$base=& $v1 -BundlePath $BundlePath `
  -PromptContract 'CONFIRM_ARC_SINGLE_POSITION_V1' `
  -EndpointFunction $EndpointFunction
if([string]$base.status-cne'PASS'){ throw 'GENERATION_V1_SEMANTIC_AUDIT_FAILED' }

$path=[IO.Path]::GetFullPath($BundlePath)
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$autorun=$text.LastIndexOf('(c:CXTDIMARCFULLBATCH)',[StringComparison]::Ordinal)
$dispatch=$text.LastIndexOf('(defun cx:dp4-run-one',[StringComparison]::Ordinal)
$runOne=$text.LastIndexOf('(defun cx:fb-run-one',[StringComparison]::Ordinal)
if($dispatch-lt0-or$runOne-lt$dispatch-or$runOne-gt$autorun){
  throw 'GENERATION_V4_ZERO_SURVIVOR_DISPATCH_NOT_FINAL'
}
$region=$text.Substring($dispatch,$autorun-$dispatch)
foreach($required in @(
  'DIRECT_ON_ZERO_OR_LOW_RANK',
  'NO_ORDINARY_SURVIVOR',
  'CURRENT_RANK_BELOW_2',
  '(cx:fb-segment-points entity segment 0.50 effective-offset)',
  '(cx:sp2-create-candidate',
  ',prompt_trace=',
  '(cx:dp4-run-one entity segment offset expected-style)')){
  if(-not$region.Contains($required)){
    throw "GENERATION_ZERO_SURVIVOR_REACHABILITY_TOKEN_MISSING:$required"
  }
}

# V3's decisive bug was an early return when the ordinary route did not yield
# exactly one survivor.  That bypass shape is forbidden in the final region.
if($region.Contains('(if (/= (length added) 1)') -or
   $region.Contains('(if (= (length added) 0) result)')){
  throw 'GENERATION_ZERO_SURVIVOR_EARLY_RETURN_REINTRODUCED'
}

[pscustomobject]@{
  status='PASS'
  bundle=$path
  sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  inherited_v1_semantics='PASS'
  zero_survivor_direct_route='REQUIRED_AND_REACHABLE'
  low_rank_direct_route='REQUIRED_AND_REACHABLE'
  pick_fallback='FROZEN_KERNEL_ORIGINAL_ARC_MIDPOINT'
  runtime_trace_required=$true
  endpoint_function=$EndpointFunction
}

