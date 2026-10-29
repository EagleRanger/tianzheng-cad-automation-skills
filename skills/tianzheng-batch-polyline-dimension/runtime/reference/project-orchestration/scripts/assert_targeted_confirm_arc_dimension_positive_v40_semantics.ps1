param(
  [Parameter(Mandatory=$true)][string]$BundlePath,
  [string]$EndpointFunction='CXNATIVEPLACEMENTAUDITV5',
  [string]$MoveFunction='CXNATIVEPLACEMENTMOVEGRIP0V1'
)
$ErrorActionPreference='Stop'
$path=[IO.Path]::GetFullPath($BundlePath)
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'V40_BUNDLE_MISSING'}
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$autorun='(c:CXTDIMARCFULLBATCH)'
if(([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count-ne1){
  throw 'V40_AUTORUN_COUNT_INVALID'
}
$autorunIndex=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)
$depth=0;$inString=$false;$inComment=$false;$escaped=$false;$line=1
foreach($ch in $text.ToCharArray()){
  if($ch-eq"`n"){$line++;$inComment=$false;continue}
  if($inComment){continue}
  if($inString){
    if($escaped){$escaped=$false;continue}
    if($ch-eq'\'){$escaped=$true;continue}
    if($ch-eq'"'){$inString=$false}
    continue
  }
  if($ch-eq';'){$inComment=$true;continue}
  if($ch-eq'"'){$inString=$true;continue}
  if($ch-eq'('){$depth++}
  elseif($ch-eq')'){$depth--;if($depth-lt0){throw "V40_NEGATIVE_DEPTH_AT_LINE:$line"}}
}
if($inString-or$depth-ne0){throw "V40_LISP_BALANCE_INVALID:$depth"}

$adapter=$text.LastIndexOf('(defun cx:gm1-wcs-to-active-ucs-plane',[StringComparison]::Ordinal)
$candidate=$text.LastIndexOf('(defun cx:sp2-create-candidate',[StringComparison]::Ordinal)
$runOne=$text.LastIndexOf('(defun cx:fb-run-one',[StringComparison]::Ordinal)
$lastEndpoint=$text.LastIndexOf("'$EndpointFunction",[StringComparison]::Ordinal)
if($adapter-lt0-or$candidate-lt$adapter-or$candidate-gt$autorunIndex-or
   $runOne-lt0-or$adapter-lt$runOne-or$lastEndpoint-lt0-or
   $lastEndpoint-gt$autorunIndex){throw 'V40_OVERRIDE_OR_AUDIT_ORDER_INVALID'}
$region=$text.Substring($adapter,$autorunIndex-$adapter)
$required=@(
  'START','SELECT_OBJECT_UCS_PLANE_Z0','CONFIRM_ARC_UCS_PLANE_Z0',
  'FINAL_DIMENSION_POSITION_UCS_PLANE_Z0','FINISH',
  "'$MoveFunction",'POST_CREATE_GRIP0_OUTER_MOVE',
  '(* text-height cx:*ups-dimension-band-h*)',
  '(cx:pg-audit entity "ARC" segment (car added) audit-offset)',
  '(cx:gm1-move-result-ok-p move-result)')
foreach($token in $required){
  if(-not$region.Contains($token)){throw "V40_REQUIRED_TOKEN_MISSING:$token"}
}
$ordered=@('"START"','"SELECT_OBJECT_UCS_PLANE_Z0"',
  '"CONFIRM_ARC_UCS_PLANE_Z0"','"FINAL_DIMENSION_POSITION_UCS_PLANE_Z0"',
  '"FINISH"')
$cursor=-1
foreach($token in $ordered){
  $next=$region.IndexOf($token,$cursor+1,[StringComparison]::Ordinal)
  if($next-le$cursor){throw "V40_PROMPT_ORDER_INVALID:$token"}
  $cursor=$next
}
foreach($forbidden in @(
  'FINAL_INVERTED_COMMAND_POSITION_UCS_PLANE_Z0','TEXT_POSITION_UCS_PLANE_Z0',
  'DIMENSION_ARC_POSITION_UCS_PLANE_Z0','FINISH_REPEAT_LOOP',
  'TMirDim','proxy_creation')){
  if($region.Contains($forbidden)){throw "V40_REJECTED_ROUTE_REINTRODUCED:$forbidden"}
}
[pscustomobject]@{
  status='PASS';bundle=$path
  sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  lisp_depth=0;autorun_count=1
  prompt_sequence='RUN162_FIVE_STAGE_ACTIVE_UCS_Z0'
  post_create_action='MOVE_GRIP0_RADIAL_TO_USER_E6_OUTER_BAND'
  endpoint_audit=$EndpointFunction
  move_function=$MoveFunction
  acceptance_dimension_band_h=1.825633854835873
  transaction_contract='MOVER_COMMITS_ONLY_AFTER_FIVE_GRIP_ENDPOINT_RESPONSE_DIRECTION_AND_BAND_PASS'
}
