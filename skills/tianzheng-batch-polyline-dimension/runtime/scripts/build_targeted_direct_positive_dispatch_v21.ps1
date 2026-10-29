param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$TaskSpecPath
)

$ErrorActionPreference = 'Stop'
$v19 = Join-Path $PSScriptRoot 'build_targeted_prompt_staged_user_positive_v19_v2.ps1'
$dispatchPath = Join-Path $PSScriptRoot 'tdimarc_native_generation_direct_positive_dispatch_v2.lsp'
$result = & $v19 -OutputPath $OutputPath -TaskSpecPath $TaskSpecPath
if ([string]$result.status -cne 'PASS') { throw 'V21_V19_BUILD_FAILED' }

$path = [IO.Path]::GetFullPath($OutputPath)
$text = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$dispatch = [IO.File]::ReadAllText($dispatchPath,[Text.Encoding]::UTF8).Trim()
$autorun = '(c:CXTDIMARCFULLBATCH)'
$last = $text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if ($last -lt 0) { throw 'V21_AUTORUN_NOT_FOUND' }
if (([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count -ne 1) {
    throw 'V21_TOP_LEVEL_AUTORUN_NOT_UNIQUE'
}
$text = $text.Substring(0,$last) + $dispatch +
    [Environment]::NewLine + [Environment]::NewLine + $text.Substring($last)

$final = $text.LastIndexOf($autorun,[StringComparison]::Ordinal)
foreach ($token in @(
    '(defun cx:dp2-run-one',
    '(cx:sp2-create-candidate',
    'DIRECT_USER_POSITIVE_DISPATCH_V2',
    'trigger=CURRENT_RANK_BELOW_2',
    'selection=ORIGINAL_ACDBPOLYLINE_ARC',
    'final_position=E6_OUTER_RADIAL_TEXT_ANCHOR')) {
    $index = $text.LastIndexOf($token,[StringComparison]::Ordinal)
    if ($index -lt 0 -or $index -gt $final) {
        throw "V21_REQUIRED_DISPATCH_TOKEN_INVALID:$token"
    }
}
if ($text.Contains('TEMP_SINGLE_ARC_PROXY')) { throw 'V21_PROXY_ROUTE_PRESENT' }
if ($dispatch.Contains('(/= (cx:cs-safe-audit-rank current-audit) 1)')) {
    throw 'V21_EXACT_RANK1_PRECONDITION_STILL_PRESENT'
}
if (-not $dispatch.Contains('(>= (cx:cs-safe-audit-rank current-audit) 2)')) {
    throw 'V21_RANK2_ONLY_SKIP_GATE_MISSING'
}
$lastRunOne = $text.LastIndexOf('(defun cx:fb-run-one',[StringComparison]::Ordinal)
$dispatchRunOne = $text.LastIndexOf('(cx:dp2-run-one entity segment offset expected-style)',[StringComparison]::Ordinal)
if ($lastRunOne -lt 0 -or $dispatchRunOne -lt $lastRunOne -or $dispatchRunOne -gt $final) {
    throw 'V21_FINAL_DISPATCH_ORDER_INVALID'
}

[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    status = 'PASS'
    output = $path
    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    top_level_autorun_count = 1
    target_count = 1
    final_dispatch = 'DIRECT_USER_POSITIVE_DISPATCH_V2'
    trigger = 'CURRENT_RANK_BELOW_2'
    selection_entity = 'ORIGINAL_ACDBPOLYLINE_ARC'
    prompt_mode = 'DIRECT_STAGED_TDIMARC_V2'
    proxy_count = 0
    candidate_count_max = 1
}
