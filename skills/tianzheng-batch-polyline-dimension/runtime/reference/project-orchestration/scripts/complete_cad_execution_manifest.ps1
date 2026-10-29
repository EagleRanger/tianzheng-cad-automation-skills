param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][psobject]$Result
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$resolved = [IO.Path]::GetFullPath($ManifestPath)
if (-not $resolved.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'MANIFEST_OUTSIDE_PROJECT'
}
$manifest = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.status -cne 'PREPARED') { throw 'MANIFEST_NOT_PREPARED' }

$isSchema3 = [int]$manifest.schema_version -ge 3
if ($isSchema3 -and @($manifest.required_acceptance_gate_ids).Count -eq 0) {
    throw 'SCHEMA3_ACCEPTANCE_GATES_REQUIRED'
}
$manifest.status = if ([string]$Result.status -ceq 'PASS') {
    if ($isSchema3) { 'EXECUTED_PASS_PENDING_ACCEPTANCE' } else { 'COMPLETED_PASS' }
} else {
    if ($isSchema3) { 'EXECUTION_FAILED' } else { 'COMPLETED_FAIL' }
}
$manifest.completion = [pscustomobject]@{
    completed_at = (Get-Date).ToString('o')
    result = $Result
}
$temporary = $resolved + '.tmp'
[IO.File]::WriteAllText($temporary, ($manifest | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $resolved -Force

[pscustomobject]@{ status='PASS'; manifest_status=$manifest.status; status_authority=$resolved }
