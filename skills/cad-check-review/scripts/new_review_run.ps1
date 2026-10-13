param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDwg,

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [string]$RunName = (Get-Date -Format 'yyyyMMdd_HHmmss_cad_review'),

    [string]$CopyName = ''
)

$ErrorActionPreference = 'Stop'

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

$source = Get-Item -LiteralPath (Get-FullPath $SourceDwg)
if ($source.PSIsContainer) { throw 'SOURCE_IS_DIRECTORY' }
if ($source.Extension -ine '.dwg') { throw 'SOURCE_MUST_BE_DWG' }

$runRootFull = Get-FullPath $RunRoot
$runDir = Join-Path $runRootFull $RunName
if (Test-Path -LiteralPath $runDir) { throw "RUN_DIRECTORY_ALREADY_EXISTS: $runDir" }

if ([string]::IsNullOrWhiteSpace($CopyName)) {
    $CopyName = '[CAD校审副本]' + $source.Name
}
if ([IO.Path]::GetExtension($CopyName) -ine '.dwg') { throw 'COPY_NAME_MUST_END_WITH_DWG' }

$copyPath = Join-Path $runDir $CopyName
if ([string]::Equals($source.FullName, $copyPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SOURCE_AND_COPY_MUST_DIFFER'
}

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source.FullName).Hash

[void](New-Item -ItemType Directory -Path $runDir)
[void](New-Item -ItemType Directory -Path (Join-Path $runDir 'reports'))
[void](New-Item -ItemType Directory -Path (Join-Path $runDir 'evidence'))
[void](New-Item -ItemType Directory -Path (Join-Path $runDir 'runtime'))

Copy-Item -LiteralPath $source.FullName -Destination $copyPath
$copy = Get-Item -LiteralPath $copyPath
$copyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $copy.FullName).Hash
if ($copyHash -ne $sourceHash) { throw 'ISOLATED_COPY_HASH_MISMATCH' }

$manifestPath = Join-Path $runDir 'review_manifest.json'
$manifest = [ordered]@{
    schema_version = 1
    status = 'initialized'
    created_at = (Get-Date).ToString('o')
    source_dwg = $source.FullName
    source_sha256 = $sourceHash
    source_length = $source.Length
    source_last_write_time = $source.LastWriteTime.ToString('o')
    working_copy = $copy.FullName
    working_copy_initial_sha256 = $copyHash
    working_copy_initial_length = $copy.Length
    expected_source_unchanged = $true
    reports_dir = (Join-Path $runDir 'reports')
    evidence_dir = (Join-Path $runDir 'evidence')
    runtime_dir = (Join-Path $runDir 'runtime')
}

$json = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($manifestPath, $json, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    status = 'PASS'
    run_dir = $runDir
    manifest = $manifestPath
    source_sha256 = $sourceHash
    working_copy = $copy.FullName
}
