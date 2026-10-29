param(
  [Parameter(Mandatory=$true)][string]$BundlePath,
  [ValidateSet('CONFIRM_ARC_SINGLE_POSITION_V1')]
  [string]$PromptContract='CONFIRM_ARC_SINGLE_POSITION_V1',
  [string]$EndpointFunction='CXNATIVEPLACEMENTAUDITV5'
)

$ErrorActionPreference='Stop'
$path=[IO.Path]::GetFullPath($BundlePath)
if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'GENERATION_BUNDLE_MISSING'}
$text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$autorun='(c:CXTDIMARCFULLBATCH)'
$autorunMatches=[regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')
if($autorunMatches.Count-ne1){throw "GENERATION_AUTORUN_COUNT_INVALID:$($autorunMatches.Count)"}
$autorunIndex=$text.LastIndexOf($autorun,[StringComparison]::Ordinal)

# Lexical balance ignores strings and semicolon comments.  This prevents a
# syntactically invalid override from passing token-only tests.
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
  elseif($ch-eq')'){$depth--;if($depth-lt0){throw "GENERATION_LISP_NEGATIVE_DEPTH_AT_LINE:$line"}}
}
if($inString){throw 'GENERATION_LISP_UNCLOSED_STRING'}
if($depth-ne0){throw "GENERATION_LISP_FINAL_DEPTH_INVALID:$depth"}

$lastAudit=$text.LastIndexOf('(defun cx:pg-audit',[StringComparison]::Ordinal)
$lastEndpoint=$text.LastIndexOf("'$EndpointFunction",[StringComparison]::Ordinal)
if($lastAudit-lt0-or$lastEndpoint-lt$lastAudit-or$lastEndpoint-gt$autorunIndex){
  throw "GENERATION_FINAL_ENDPOINT_AUDIT_NOT_ACTIVE:$EndpointFunction"
}

if($PromptContract-ceq'CONFIRM_ARC_SINGLE_POSITION_V1'){
  $adapter=$text.LastIndexOf('(defun cx:tp5-staged-tdimarc',[StringComparison]::Ordinal)
  $select=$text.LastIndexOf('(cx:sp2-send-direct "SELECT_OBJECT" pick)',[StringComparison]::Ordinal)
  $confirm=$text.LastIndexOf('(cx:sp2-send-direct "CONFIRM_ARC" confirm-point)',[StringComparison]::Ordinal)
  $place=$text.LastIndexOf('(cx:sp2-send-direct "FINAL_DIMENSION_POSITION" dimension-point)',[StringComparison]::Ordinal)
  $candidate=$text.LastIndexOf('(defun cx:sp2-create-candidate',[StringComparison]::Ordinal)
  $dispatch=$text.LastIndexOf('(defun cx:dp3-run-one',[StringComparison]::Ordinal)
  $runOne=$text.LastIndexOf('(defun cx:fb-run-one',[StringComparison]::Ordinal)
  if($adapter-lt0-or$select-lt$adapter-or$confirm-lt$select-or$place-lt$confirm-or$candidate-lt$adapter-or$dispatch-lt$candidate-or$runOne-lt$dispatch-or$runOne-gt$autorunIndex){
    throw 'GENERATION_CONFIRM_ARC_PROMPT_OR_OVERRIDE_ORDER_INVALID'
  }
  $activeRegion=$text.Substring($lastAudit,$autorunIndex-$lastAudit)
  foreach($forbidden in @('DIMENSION_ARC_POSITION','TEXT_POSITION','TEMP_SINGLE_ARC_PROXY')){
    if($activeRegion.Contains($forbidden)){throw "GENERATION_FORBIDDEN_ACTIVE_ROUTE:$forbidden"}
  }
  foreach($required in @(
    'confirm_arc=SOURCE_ARC_MIDPOINT',
    'final_position=E6_DIMENSION_ARC_BAND',
    'CURRENT_ENDPOINT_INVALID_DISCARDED',
    '(cx:cs-delete-live-handles added)')){
    if(-not$activeRegion.Contains($required)){throw "GENERATION_REQUIRED_AUDIT_OR_CLEANUP_MISSING:$required"}
  }
}

[pscustomobject]@{
  status='PASS'
  bundle=$path
  sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
  lisp_depth=0
  autorun_count=1
  endpoint_function=$EndpointFunction
  endpoint_audit_is_final=$true
  prompt_contract=$PromptContract
  invalid_endpoint_survivor_policy='DELETE_AND_RETURN_FAIL'
}
