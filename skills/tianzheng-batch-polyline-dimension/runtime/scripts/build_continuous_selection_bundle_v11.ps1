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
    throw 'CONTINUOUS_BUNDLE_V11_OUTPUT_OUTSIDE_PROJECT'
}

$corePath = Join-Path $PSScriptRoot 'tdimarc_native_full_batch.lsp'
$placementGatePath = Join-Path $PSScriptRoot 'tdimarc_native_generation_placement_gate_v3.lsp'
$creationBasePath = Join-Path $PSScriptRoot 'tdimarc_native_generation_creation_settle_v3.lsp'
$creationTransactionPath = Join-Path $PSScriptRoot 'tdimarc_native_generation_creation_settle_v5.lsp'
$serialPath = Join-Path $PSScriptRoot 'tdimarc_native_full_batch_source_serial_v5.lsp'
$retryPath = Join-Path $PSScriptRoot 'tdimarc_native_generation_retry_formula_v6.lsp'
$continuousPath = Join-Path $PSScriptRoot 'tdimarc_native_continuous_batch_v1.lsp'
$selectionPath = Join-Path $PSScriptRoot 'tdimarc_native_selection_entry_v1.lsp'
foreach ($path in @($corePath,$placementGatePath,$creationBasePath,
        $creationTransactionPath,$serialPath,$retryPath,$continuousPath,
        $selectionPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "CONTINUOUS_BUNDLE_V11_INPUT_MISSING:$path"
    }
}

function Remove-Autorun([string]$Text,[string]$Code) {
    $without = [regex]::Replace($Text,
        '(?ms)\r?\n\(c:CXTDIMARCFULLBATCH\)\s*\z', '')
    if ($without.Length -eq $Text.Length) {
        throw "${Code}_AUTORUN_MARKER_NOT_FOUND"
    }
    return $without
}

$core = Remove-Autorun ([IO.File]::ReadAllText(
        $corePath,[Text.Encoding]::UTF8)) 'CORE'
$aliases = [ordered]@{
    '(defun cx:fb-isolate-entities' = '(defun cx:ss-v2-isolate-entities'
    '(defun cx:fb-run-one' = '(defun cx:ss-v2-run-one'
    '(defun cx:fb-run-line' = '(defun cx:ss-v2-run-line'
    '(defun cx:fb-unisolate-objects' = '(defun cx:ss-v2-unisolate-objects'
}
foreach ($declaration in $aliases.Keys) {
    if (([regex]::Matches($core,[regex]::Escape($declaration))).Count -ne 1) {
        throw "CORE_ALIAS_DECLARATION_COUNT_INVALID:$declaration"
    }
    $core = $core.Replace($declaration,$aliases[$declaration])
}

$placementGate = [IO.File]::ReadAllText($placementGatePath,[Text.Encoding]::UTF8)
$placementDeclaration = '(defun cx:pg-run-one'
if (([regex]::Matches($placementGate,[regex]::Escape($placementDeclaration))).Count -ne 1) {
    throw 'PLACEMENT_GATE_V3_RUN_ONE_DECLARATION_COUNT_INVALID'
}
$placementGate = $placementGate.Replace(
    $placementDeclaration,'(defun cx:pg-v3-run-one')

$creationBase = [IO.File]::ReadAllText($creationBasePath,[Text.Encoding]::UTF8)
$creationTransaction = [IO.File]::ReadAllText(
    $creationTransactionPath,[Text.Encoding]::UTF8)
$serial = Remove-Autorun ([IO.File]::ReadAllText(
        $serialPath,[Text.Encoding]::UTF8)) 'SERIAL'
$retry = [IO.File]::ReadAllText($retryPath,[Text.Encoding]::UTF8)
$continuous = Remove-Autorun ([IO.File]::ReadAllText(
        $continuousPath,[Text.Encoding]::UTF8)) 'CONTINUOUS'
$selection = [IO.File]::ReadAllText($selectionPath,[Text.Encoding]::UTF8)
$flag = if ($AutoSelectAllPolylines) { 'T' } else { 'nil' }
$offsetText = $Offset.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
$header = @"
;; V11 validation bundle: one CAD load and one internal selection.
;; V3 supplies verified settlement primitives; V5 overrides final settlement
;; with idempotent cleanup and native-actual-band signed correction.
(setq cx:*continuous-offset* $offsetText)
(setq cx:*continuous-group* "$Group")
(setq cx:*continuous-auto-select-all-polylines* $flag)
"@
$tail = if ($AutoRun) { "`r`n(c:CXTDIMSELECTALL)`r`n" } else { "`r`n(princ)`r`n" }
$bundle = $header + "`r`n" + $core + "`r`n" + $placementGate + "`r`n" +
    $creationBase + "`r`n" + $creationTransaction + "`r`n" + $serial +
    "`r`n" + $retry + "`r`n" + $continuous + "`r`n" + $selection + $tail

$directory = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
}
[IO.File]::WriteAllText($output,$bundle,[Text.UTF8Encoding]::new($false))

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
    failed_typed_retry = 'V6_LOCAL_STAGE_HISTORY_PLUS_V5_TRANSACTIONAL_FINAL_SETTLEMENT'
    placement_gate = 'V3_USABLE_BAND_PLUS_V5_IDEMPOTENT_SIGNED_SETTLEMENT'
}
