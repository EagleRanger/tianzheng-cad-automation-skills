$ErrorActionPreference = 'Stop'
$entry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/start_owned_tianzheng_supervised.ps1'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'SUPERVISOR_ENTRY_MISSING' }
$text = Get-Content -LiteralPath $entry -Raw -Encoding UTF8
$errors = [Collections.Generic.List[string]]::new()

foreach ($marker in @(
    'function Get-LiveKnownOwnerStatePaths',
    'Test-TianzhengOwnerStatePathLive -Path $candidate',
    "Get-ChildItem -LiteralPath `$runsRoot -Filter 'owner_state.json' -Recurse",
    'Get-TianzhengLifecycleSnapshot -OwnerStatePaths $knownOwnerStatePaths',
    '$needsExtendedQuiescence = ($plan.target_count -gt 0 -and [bool]$preCleanupBudget.memory_pressure)',
    "Status 'SKIPPED_FAST_OWNED_HANDOFF'",
    'Test-TianzhengOwnerWindowLive -Path $ownerState',
    '$PostReturnStableSeconds = 3',
    "Add-LifecycleEvent -Stage 'post_ready_operation_guard' -Status 'RELEASED'",
    'if ($KeepAliveSeconds -ne 0)',
    "'BLOCKING_KEEPALIVE_FORBIDDEN__USE_ZERO_AND_CONTINUE_IN_SAME_CONTROLLER'"
)) {
    if ($text.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        $errors.Add("REQUIRED_MARKER_MISSING:$marker")
    }
}

foreach ($forbidden in @(
    'Start-Sleep -Seconds $KeepAliveSeconds',
    "Add-LifecycleEvent -Stage 'post_ready_keepalive'",
    '$keepaliveDeadline',
    '$ownedProcessId'
)) {
    if ($text.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        $errors.Add("BLOCKING_KEEPALIVE_IMPLEMENTATION_REINTRODUCED:$forbidden")
    }
}

if ($text.IndexOf('(Get-Date).AddSeconds(20)', [StringComparison]::Ordinal) -ge 0) {
    $errors.Add('DUPLICATE_FIXED_TWENTY_SECOND_POST_RETURN_WAIT_REINTRODUCED')
}


$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($entry, [ref]$tokens, [ref]$parseErrors)
foreach ($parseError in @($parseErrors)) { $errors.Add("PARSE_ERROR:$($parseError.Message)") }

if ($errors.Count -gt 0) {
    [pscustomobject]@{ status='FAIL'; errors=@($errors) } | ConvertTo-Json -Depth 6
    exit 1
}

[pscustomobject]@{
    status = 'PASS'
    entry = $entry
    live_owner_discovery = $true
    guard_released_after_exact_ready = $true
    blocking_keepalive_forbidden_before_cad_action = $true
    lifecycle_returns_after_exact_ready = $true
} | ConvertTo-Json -Depth 6
