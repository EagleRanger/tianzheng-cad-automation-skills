param(
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [double]$Offset = 3.30225,
    [ValidateSet('ROAD','SHORE')][string]$Group = 'SHORE',
    [switch]$AutoSelectAllPolylines,
    [switch]$AutoRun
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$output = [IO.Path]::GetFullPath($OutputPath)
if (-not $output.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'CONTINUOUS_BUNDLE_V12_OUTPUT_OUTSIDE_PROJECT'
}

$baseBuilder = Join-Path $PSScriptRoot 'build_continuous_selection_bundle_v11.ps1'
$retryV7 = Join-Path $PSScriptRoot 'tdimarc_native_generation_retry_formula_v7.lsp'
foreach ($path in @($baseBuilder,$retryV7)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "CONTINUOUS_BUNDLE_V12_INPUT_MISSING:$path"
    }
}

$temporary = $output + '.v11-base.tmp.lsp'
try {
    $parameters = @{
        OutputPath = $temporary
        Offset = $Offset
        Group = $Group
    }
    if ($AutoSelectAllPolylines) { $parameters.AutoSelectAllPolylines = $true }
    $base = & $baseBuilder @parameters
    if ($base.status -cne 'PASS') { throw 'CONTINUOUS_BUNDLE_V12_BASE_BUILD_FAILED' }

    $text = [IO.File]::ReadAllText($temporary,[Text.Encoding]::UTF8)
    $retry = [IO.File]::ReadAllText($retryV7,[Text.Encoding]::UTF8)
    $tail = if ($AutoRun) { "`r`n(c:CXTDIMSELECTALL)`r`n" } else { "`r`n(princ)`r`n" }
    $header = ";; V12 appends a verified graphical-hit fallback after the V11 proven chain.`r`n"
    [IO.File]::WriteAllText(
        $output,$header + $text + "`r`n" + $retry + $tail,
        [Text.UTF8Encoding]::new($false))
}
finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}

[pscustomobject]@{
    status = 'PASS'
    output = $output
    bytes = (Get-Item -LiteralPath $output).Length
    sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
    offset = $Offset
    group = $Group
    auto_select_all_polylines = $AutoSelectAllPolylines.IsPresent
    auto_run = $AutoRun.IsPresent
    external_lsp_load_count = 1
    internal_dispatch = 'ARC_TDIMARC__LINE_TDIMMP'
    failed_typed_retry = 'V7_V6_CHAIN_PLUS_BROAD_VERIFIED_GRAPHICAL_HIT_FALLBACK'
    placement_gate = 'V3_USABLE_BAND_PLUS_V5_IDEMPOTENT_SIGNED_SETTLEMENT'
}
