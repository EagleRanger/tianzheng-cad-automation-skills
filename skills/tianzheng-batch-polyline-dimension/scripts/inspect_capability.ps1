[CmdletBinding()]
param(
    [string]$ProjectRoot = $env:TIANZHENG_CAD_AUTOMATION_HOME,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$prefix = $root.TrimEnd([char[]]'\/') + [IO.Path]::DirectorySeparatorChar
$manifestPath = Join-Path $root 'public-runtime-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'PUBLIC_RUNTIME_MANIFEST_MISSING: Keep the complete runtime directory or pass its path with -ProjectRoot.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.files -or @($manifest.files).Count -eq 0) { throw 'EMPTY_SOURCE_MANIFEST' }
$seen = @{}
$checked = 0
foreach ($file in $manifest.files) {
    $relative = [string]$file.path
    if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative)) { throw 'INVALID_MANIFEST_PATH' }
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "PATH_OUTSIDE_RUNTIME:$relative" }
    if ($seen.ContainsKey($full)) { throw "DUPLICATE_MANIFEST_PATH:$relative" }
    $seen[$full] = $true
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "SOURCE_MISSING:$relative" }
    if ((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "LINKED_SOURCE_NOT_ALLOWED:$relative" }
    $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if ($actual -ne [string]$file.sha256) { throw "SOURCE_HASH_MISMATCH:$relative" }
    $checked++
}
$result = [ordered]@{
    schema_version = 2
    skill = 'tianzheng-batch-polyline-dimension'
    package_version = '1.1.1'
    runtime_root = $root
    source_files_checked = $checked
    implementation_hashes_pass = $true
    maturity = $manifest.maturity
    receiver_status = 'NOT_VALIDATED_BY_THIS_CHECK'
    receiver_input_requirements = $manifest.required_receiver_inputs
    cad_started = $false
    commands_loaded = $false
    safe_to_claim = [ordered]@{
        bundled_source_integrity = $true
        complete_command_production_ready = $false
        receiver_runtime_pass = $false
        cross_structure_generality = $false
    }
}
if ($AsJson) { $result | ConvertTo-Json -Depth 20 } else { [pscustomobject]$result }
