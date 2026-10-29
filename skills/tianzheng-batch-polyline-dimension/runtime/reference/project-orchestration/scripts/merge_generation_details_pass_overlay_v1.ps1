param(
  [Parameter(Mandatory=$true)][string]$BaseDetailsPath,
  [Parameter(Mandatory=$true)][string]$OverlayDetailsPath,
  [Parameter(Mandatory=$true)][string]$OutputPath,
  [int]$ExpectedRowCount = 86,
  [int]$ExpectedOverlayPassCount = 1,
  [int]$ExpectedFinalPassCount = 86
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$base = [IO.Path]::GetFullPath($BaseDetailsPath)
$overlay = [IO.Path]::GetFullPath($OverlayDetailsPath)
$output = [IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($base, $overlay, $output)) {
  if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'DETAIL_OVERLAY_PATH_OUTSIDE_PROJECT'
  }
}
$baseRows = @(Import-Csv -LiteralPath $base -Delimiter "`t" -Encoding UTF8)
$overlayRows = @(Import-Csv -LiteralPath $overlay -Delimiter "`t" -Encoding UTF8)
if ($baseRows.Count -ne $ExpectedRowCount) { throw "DETAIL_OVERLAY_BASE_COUNT:$($baseRows.Count)" }
$passRows = @($overlayRows | Where-Object { ([string]$_.STATUS).ToUpperInvariant() -ceq 'PASS' })
if ($passRows.Count -ne $ExpectedOverlayPassCount) {
  throw "DETAIL_OVERLAY_PASS_COUNT:$($passRows.Count)"
}
$byKey = [ordered]@{}
foreach ($row in $baseRows) {
  $key = ([string]$row.SOURCE_HANDLE).ToUpperInvariant() + '/' +
    ([string]$row.SEGMENT_TYPE).ToUpperInvariant() + '/' + [int]$row.SEGMENT_INDEX
  if ($byKey.Contains($key)) { throw "DETAIL_OVERLAY_DUPLICATE_BASE_KEY:$key" }
  $byKey[$key] = $row
}
foreach ($row in $passRows) {
  $key = ([string]$row.SOURCE_HANDLE).ToUpperInvariant() + '/' +
    ([string]$row.SEGMENT_TYPE).ToUpperInvariant() + '/' + [int]$row.SEGMENT_INDEX
  if (-not $byKey.Contains($key)) { throw "DETAIL_OVERLAY_UNKNOWN_KEY:$key" }
  $handle = ([string]$row.ADDED_HANDLE).ToUpperInvariant()
  if ($handle -notmatch '^[0-9A-F]+$') { throw "DETAIL_OVERLAY_HANDLE:$key" }
  $byKey[$key] = $row
}
$merged = @($byKey.Values)
$finalPass = @($merged | Where-Object { ([string]$_.STATUS).ToUpperInvariant() -ceq 'PASS' })
if ($merged.Count -ne $ExpectedRowCount -or $finalPass.Count -ne $ExpectedFinalPassCount) {
  throw "DETAIL_OVERLAY_FINAL_COUNTS:rows=$($merged.Count);pass=$($finalPass.Count)"
}
$keys = @{}
$handles = @{}
foreach ($row in $merged) {
  $key = ([string]$row.SOURCE_HANDLE).ToUpperInvariant() + '/' +
    ([string]$row.SEGMENT_TYPE).ToUpperInvariant() + '/' + [int]$row.SEGMENT_INDEX
  if ($keys.ContainsKey($key)) { throw "DETAIL_OVERLAY_DUPLICATE_FINAL_KEY:$key" }
  $keys[$key] = $true
  if (([string]$row.STATUS).ToUpperInvariant() -ceq 'PASS') {
    $handle = ([string]$row.ADDED_HANDLE).ToUpperInvariant()
    if ($handle -notmatch '^[0-9A-F]+$') { throw "DETAIL_OVERLAY_FINAL_HANDLE:$key" }
    if ($handles.ContainsKey($handle)) { throw "DETAIL_OVERLAY_DUPLICATE_HANDLE:$handle" }
    $handles[$handle] = $true
  }
}
$parent = Split-Path -Parent $output
if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$prior = $PSDefaultParameterValues['Export-Csv:UseQuotes']
$had = $PSDefaultParameterValues.ContainsKey('Export-Csv:UseQuotes')
try {
  $PSDefaultParameterValues['Export-Csv:UseQuotes'] = 'Never'
  $merged | Sort-Object SOURCE_HANDLE, SEGMENT_INDEX |
    Export-Csv -LiteralPath $output -Delimiter "`t" -NoTypeInformation -Encoding utf8
}
finally {
  if ($had) { $PSDefaultParameterValues['Export-Csv:UseQuotes'] = $prior }
  else { [void]$PSDefaultParameterValues.Remove('Export-Csv:UseQuotes') }
}
[pscustomobject]@{
  status = 'PASS'
  row_count = $merged.Count
  overlay_pass_count = $passRows.Count
  final_pass_count = $finalPass.Count
  unique_pass_handle_count = $handles.Count
  remaining_failure_count = $merged.Count - $finalPass.Count
  output = $output
  sha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash
}
