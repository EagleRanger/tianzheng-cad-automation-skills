param(
    [Parameter(Mandatory = $true)]
    [string]$RunManifest,

    [Parameter(Mandatory = $true)]
    [string]$OutputDwg,

    [Parameter(Mandatory = $true)]
    [string]$AuditSummary,

    [string]$VerificationReport = ''
)

$ErrorActionPreference = 'Stop'

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Get-Sha256Shared([string]$Path) {
    $stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::ReadWrite
    )
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash($stream)
        return ([BitConverter]::ToString($bytes)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

$manifestPath = Get-FullPath $RunManifest
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourcePath = Get-FullPath ([string]$manifest.source_dwg)
$outputPath = Get-FullPath $OutputDwg
$auditPath = Get-FullPath $AuditSummary

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw 'SOURCE_DWG_MISSING' }
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) { throw 'OUTPUT_DWG_MISSING' }
if (-not (Test-Path -LiteralPath $auditPath -PathType Leaf)) { throw 'AUDIT_SUMMARY_MISSING' }
if ([string]::Equals($sourcePath, $outputPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OUTPUT_MUST_NOT_OVERWRITE_SOURCE'
}

$sourceHashNow = Get-Sha256Shared $sourcePath
$sourceUnchanged = $sourceHashNow -eq [string]$manifest.source_sha256
$outputHash = Get-Sha256Shared $outputPath

$audit = @{}
foreach ($line in Get-Content -LiteralPath $auditPath -Encoding Default) {
    if ($line -match '^([^=]+)=(.*)$') { $audit[$matches[1]] = $matches[2] }
}
$auditPassed = $audit.ContainsKey('PASS') -and $audit['PASS'] -eq 'YES'
$dbmodClean = $audit.ContainsKey('DBMOD_AFTER') -and $audit['DBMOD_AFTER'] -eq '0'

$passed = $sourceUnchanged -and $auditPassed -and $dbmodClean -and -not [string]::IsNullOrWhiteSpace($outputHash)
if ([string]::IsNullOrWhiteSpace($VerificationReport)) {
    $VerificationReport = Join-Path ([IO.Path]::GetDirectoryName($auditPath)) 'delivery_verification.json'
}
$verificationPath = Get-FullPath $VerificationReport

$result = [ordered]@{
    status = $(if ($passed) { 'PASS' } else { 'FAIL' })
    verified_at = (Get-Date).ToString('o')
    source_dwg = $sourcePath
    source_sha256_expected = [string]$manifest.source_sha256
    source_sha256_actual = $sourceHashNow
    source_unchanged = $sourceUnchanged
    output_dwg = $outputPath
    output_sha256 = $outputHash
    output_length = (Get-Item -LiteralPath $outputPath).Length
    audit_summary = $auditPath
    audit_pass = $auditPassed
    dbmod_after_zero = $dbmodClean
}

$json = $result | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($verificationPath, $json, [Text.UTF8Encoding]::new($false))
[pscustomobject]$result

if (-not $passed) { exit 2 }
