param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$TaskSpecPath
)

$ErrorActionPreference = 'Stop'
$v21 = Join-Path $PSScriptRoot 'build_targeted_direct_positive_dispatch_v21.ps1'
$planePath = Join-Path $PSScriptRoot 'tdimarc_user_positive_xy_plane_v2.lsp'
$result = & $v21 -OutputPath $OutputPath -TaskSpecPath $TaskSpecPath
if ([string]$result.status -cne 'PASS') { throw 'V22_V21_BUILD_FAILED' }

$path = [IO.Path]::GetFullPath($OutputPath)
$text = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$plane = [IO.File]::ReadAllText($planePath,[Text.Encoding]::UTF8).Trim()
$autorun = '(c:CXTDIMARCFULLBATCH)'
$last = $text.LastIndexOf($autorun,[StringComparison]::Ordinal)
if ($last -lt 0) { throw 'V22_AUTORUN_NOT_FOUND' }
$text = $text.Substring(0,$last) + $plane +
    [Environment]::NewLine + [Environment]::NewLine + $text.Substring($last)

$final = $text.LastIndexOf($autorun,[StringComparison]::Ordinal)
foreach ($token in @(
    '(defun cx:upx2-unit-from-center-xy',
    '(defun cx:ups-target-text-point-wcs',
    '(* dx dx)',
    '(* dy dy)',
    '0.0)',
    'DIRECT_USER_POSITIVE_DISPATCH_V2',
    'trigger=CURRENT_RANK_BELOW_2')) {
    $index = $text.LastIndexOf($token,[StringComparison]::Ordinal)
    if ($index -lt 0 -or $index -gt $final) {
        throw "V22_REQUIRED_TOKEN_INVALID:$token"
    }
}
if ($text.Contains('TEMP_SINGLE_ARC_PROXY')) { throw 'V22_PROXY_ROUTE_PRESENT' }
if (([regex]::Matches($text,'(?m)^\(c:CXTDIMARCFULLBATCH\)\s*$')).Count -ne 1) {
    throw 'V22_TOP_LEVEL_AUTORUN_NOT_UNIQUE'
}

[IO.File]::WriteAllText($path,$text,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    status='PASS'
    output=$path
    sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    final_dispatch='DIRECT_USER_POSITIVE_DISPATCH_V2'
    trigger='CURRENT_RANK_BELOW_2'
    target_direction='CENTER_TO_MIDPOINT_XY_ONLY'
    target_plane='WCS_Z0'
    proxy_count=0
    candidate_count_max=1
}
