param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$TaskSpecPath
)

$ErrorActionPreference = 'Stop'
$baseBuilder = Join-Path $PSScriptRoot 'build_targeted_prompt_staged_probe_v2.ps1'
$positiveFormula = Join-Path $PSScriptRoot 'tdimarc_native_generation_user_positive_v1.lsp'

$result = & $baseBuilder -OutputPath $OutputPath -TaskSpecPath $TaskSpecPath
if ([string]$result.status -cne 'PASS') {
    throw 'V19_DIRECT_STAGED_BASE_BUILD_FAILED'
}

$path = [IO.Path]::GetFullPath($OutputPath)
$text = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$formula = [IO.File]::ReadAllText($positiveFormula,[Text.Encoding]::UTF8).Trim()
$autorun = '(c:CXTDIMARCFULLBATCH)'
$last = $text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if ($last -lt 0) { throw 'V19_AUTORUN_NOT_FOUND' }
if (([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count -ne 1) {
    throw 'V19_TOP_LEVEL_AUTORUN_NOT_UNIQUE'
}

# Insert the E6-measured formula after the verified direct-prompt adapter but
# before the one top-level autorun. The in-command dispatcher call is retained.
$text = $text.Substring(0,$last) + $formula +
    [Environment]::NewLine + [Environment]::NewLine + $text.Substring($last)

$finalAutorun = $text.LastIndexOf($autorun,[StringComparison]::Ordinal)
foreach ($token in @(
    '(defun cx:sp2-staged-tdimarc',
    '(defun cx:ups-target-text-point-wcs',
    '(defun cx:fb-run-one',
    '(defun cx:cs-settle-final-result',
    'USER_POSITIVE_FINAL_POSITION{target_point_ucs=')) {
    $index = $text.LastIndexOf($token,[StringComparison]::Ordinal)
    if ($index -lt 0 -or $index -gt $finalAutorun) {
        throw "V19_REQUIRED_TOKEN_NOT_BEFORE_AUTORUN:$token"
    }
}

$positiveRunOne = $text.LastIndexOf('(defun cx:fb-run-one',[StringComparison]::Ordinal)
$directAdapter = $text.LastIndexOf('(defun cx:sp2-staged-tdimarc',[StringComparison]::Ordinal)
if ($positiveRunOne -lt $directAdapter) {
    throw 'V19_POSITIVE_DISPATCH_NOT_AFTER_DIRECT_ADAPTER'
}
if ($text.Contains('TEMP_SINGLE_ARC_PROXY')) {
    throw 'V19_PROXY_ROUTE_REINTRODUCED'
}

[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    status = 'PASS'
    output = $path
    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    top_level_autorun_count = 1
    target_count = 1
    selection_entity = 'ORIGINAL_ACDBPOLYLINE_ARC'
    prompt_mode = 'DIRECT_STAGED_TDIMARC_V2'
    final_position_basis = 'E6_OUTER_RADIAL_TEXT_ANCHOR'
    dimension_band_h = 1.825633854835873
    text_anchor_extra_h = 0.924369747624199
    proxy_count = 0
    post_creation_grip_move = $false
}
