param(
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [Parameter(Mandatory=$true)][string]$TaskSpecPath
)

$ErrorActionPreference='Stop'
$v22=Join-Path $PSScriptRoot 'build_targeted_direct_positive_xy_v22.ps1'
$endpointGatePath=Join-Path $PSScriptRoot 'tdimarc_native_generation_endpoint_xy_gate_v1.lsp'
$adapterPath=Join-Path $PSScriptRoot 'tdimarc_native_generation_confirm_arc_place_v5.lsp'
$dispatchPath=Join-Path $PSScriptRoot 'tdimarc_native_generation_direct_positive_dispatch_v3.lsp'
$result=& $v22 -OutputPath $OutputPath -TaskSpecPath $TaskSpecPath
if([string]$result.status-cne'PASS'){throw'V25_V22_BUILD_FAILED'}

$path=[IO.Path]::GetFullPath($OutputPath)
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$endpointGate=[IO.File]::ReadAllText($endpointGatePath,[Text.Encoding]::UTF8).Trim()
$adapter=[IO.File]::ReadAllText($adapterPath,[Text.Encoding]::UTF8).Trim()
$dispatch=[IO.File]::ReadAllText($dispatchPath,[Text.Encoding]::UTF8).Trim()
$autorun='(c:CXTDIMARCFULLBATCH)'
$last=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if($last-lt0){throw'V25_AUTORUN_NOT_FOUND'}
$override=$endpointGate+[Environment]::NewLine+[Environment]::NewLine+$adapter+[Environment]::NewLine+[Environment]::NewLine+$dispatch
$text=$text.Substring(0,$last)+$override+[Environment]::NewLine+[Environment]::NewLine+$text.Substring($last)

$final=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
$gate=$text.LastIndexOf('(defun cx:pg-audit',[StringComparison]::Ordinal)
$candidate=$text.LastIndexOf('(defun cx:sp2-create-candidate',[StringComparison]::Ordinal)
$runOne=$text.LastIndexOf('(defun cx:fb-run-one',[StringComparison]::Ordinal)
if($gate-lt0-or$candidate-lt0-or$runOne-lt0-or$gate-gt$final-or$candidate-gt$final-or$runOne-gt$final){throw'V25_FINAL_OVERRIDE_ORDER_INVALID'}
foreach($token in @(
  'CXNATIVEPLACEMENTAUDITV5',
  '(cx:sp2-send-direct "SELECT_OBJECT" pick)',
  '(cx:sp2-send-direct "CONFIRM_ARC" confirm-point)',
  '(cx:sp2-send-direct "FINAL_DIMENSION_POSITION" dimension-point)',
  'confirm_arc=SOURCE_ARC_MIDPOINT',
  'final_position=E6_DIMENSION_ARC_BAND',
  'CURRENT_ENDPOINT_INVALID_DISCARDED')){
  $index=$text.LastIndexOf($token,[StringComparison]::Ordinal)
  if($index-lt0-or$index-gt$final){throw"V25_REQUIRED_TOKEN_INVALID:$token"}
}
$region=$text.Substring($gate,$final-$gate)
if($region.Contains('DIMENSION_ARC_POSITION')-or$region.Contains('TEXT_POSITION')){throw'V25_V24_TWO_POSITION_SEMANTICS_REINTRODUCED'}
if($text.Contains('TEMP_SINGLE_ARC_PROXY')){throw'V25_PROXY_ROUTE_PRESENT'}
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){throw'V25_AUTORUN_INVALID'}

[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
$semanticAudit=& (Join-Path $PSScriptRoot 'assert_native_generation_bundle_semantics_v1.ps1') `
  -BundlePath $path `
  -PromptContract 'CONFIRM_ARC_SINGLE_POSITION_V1' `
  -EndpointFunction 'CXNATIVEPLACEMENTAUDITV5'
if([string]$semanticAudit.status-cne'PASS'){throw'V25_SEMANTIC_AUDIT_FAILED'}
[pscustomobject]@{
  status='PASS'
  output=$path
  sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  prompt_sequence='START_SELECT_OBJECT_CONFIRM_ARC_FINAL_DIMENSION_POSITION_OPTIONAL_FINISH'
  source_selection_point_count=2
  final_placement_point_count=1
  confirm_arc_basis='SOURCE_ARC_MIDPOINT'
  final_position_band_h=1.825633854835873
  text_anchor_acceptance_band_h=2.750003602460072
  endpoint_gate='CXNATIVEPLACEMENTAUDITV5_WCS_XY'
  invalid_ordinary_survivor='DELETE_AND_RETURN_FAIL'
  semantic_audit='PASS'
  target_plane='WCS_Z0'
  proxy_count=0
  candidate_count_max=1
}
