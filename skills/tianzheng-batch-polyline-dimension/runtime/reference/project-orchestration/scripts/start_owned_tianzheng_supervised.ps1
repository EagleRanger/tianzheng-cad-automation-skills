param(
    [Parameter(Mandatory = $true)][string]$DrawingPath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$DialogLogPath,
    [Parameter(Mandatory = $true)][string]$LifecycleReportPath,
    [string[]]$PriorOwnerStatePaths = @(),
    [ValidateSet('Auto','ForceAll')][string]$CleanupMode = 'Auto',
    [switch]$ConfirmNoOtherCadProject,
    [int]$ResidualGraceSeconds = 120,
    [int]$RetryCount = 1,
    [ValidateRange(0,840)][int]$StartupTimeoutSeconds = 0,
    [ValidateRange(0,840)][int]$InitialFrameTimeoutSeconds = 0,
    [ValidateRange(3000,60000)][int]$TransientBlankDialogGraceMilliseconds = 15000,
    [ValidateRange(15,120)][int]$DialogWatchSeconds = 45,
    [ValidateRange(12,90)][int]$StableSeconds = 30,
    [ValidateRange(1,15)][int]$PostReturnStableSeconds = 3,
    [ValidateRange(0,86400)][int]$KeepAliveSeconds = 0,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
if ($KeepAliveSeconds -ne 0) {
    # Return as soon as the exact owned window is ready. A sleeping launcher
    # does not own CAD; it only blocks the caller before the business command.
    # Keep the parameter for old callers, but reject stale 600/1800 second
    # keepalive values before any CAD action.
    throw 'BLOCKING_KEEPALIVE_FORBIDDEN__USE_ZERO_AND_CONTINUE_IN_SAME_CONTROLLER'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$guardModule = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/common/CadOperationGuard.psm1'
$lifecycleModule = Join-Path $PSScriptRoot 'common\TianzhengLifecycle.psm1'
$canonicalOpen = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/start_owned_tianzheng_direct_dwg.ps1'
$budgetEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/get_tianzheng_adaptive_startup_budget.ps1'
$resourceQuiescenceEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/wait_tianzheng_resource_quiescence.ps1'
Import-Module $guardModule -Force
Import-Module $lifecycleModule -Force

$drawing = [IO.Path]::GetFullPath($DrawingPath)
$ownerState = [IO.Path]::GetFullPath($OwnerStatePath)
$dialogLog = [IO.Path]::GetFullPath($DialogLogPath)
$reportPath = [IO.Path]::GetFullPath($LifecycleReportPath)
$reportDirectory = Split-Path -Parent $reportPath
if (-not (Test-Path -LiteralPath $reportDirectory)) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }

$script:lifecycleEvents = @()
function Add-LifecycleEvent([string]$Stage, [string]$Status, [object]$Data) {
    $script:lifecycleEvents += [pscustomobject]@{ at=(Get-Date).ToString('o'); stage=$Stage; status=$Status; data=$Data }
    $payload = [ordered]@{ schema_version=1; updated_at=(Get-Date).ToString('o'); events=@($script:lifecycleEvents) }
    $temporary = "$reportPath.tmp"
    [IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $reportPath -Force
}

$operationId = "tianzheng-supervised-start-$([guid]::NewGuid().ToString('N'))"
$guard = $null

function Get-LiveKnownOwnerStatePaths {
    $paths = [Collections.Generic.List[string]]::new()
    $candidates = [Collections.Generic.List[string]]::new()
    [void]$candidates.Add($ownerState)

    foreach ($raw in @($PriorOwnerStatePaths)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $resolved = [IO.Path]::GetFullPath($raw)
        if (-not $resolved.StartsWith([IO.Path]::GetFullPath($projectRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "PRIOR_OWNER_STATE_OUTSIDE_PROJECT=$resolved"
        }
        [void]$candidates.Add($resolved)
    }

    $runsRoot = Join-Path $projectRoot 'runs'
    if (Test-Path -LiteralPath $runsRoot -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $runsRoot -Filter 'owner_state.json' -Recurse -File -ErrorAction SilentlyContinue)) {
            [void]$candidates.Add($item.FullName)
        }
    }

    foreach ($candidate in @($candidates | Sort-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $state = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([string]$state.status -ceq 'ready' -and (Test-TianzhengOwnerStatePathLive -Path $candidate)) {
                [void]$paths.Add([IO.Path]::GetFullPath($candidate))
            }
        } catch {}
    }
    return @($paths | Sort-Object -Unique)
}

try {
    $guard = Enter-CadOperationGuard -ProjectRoot $projectRoot -OperationId $operationId -AllowExistingAcad
    # Observe pressure before cleanup.  Otherwise a high-memory residual CAD
    # disappears from the later sample and the immediate restart is incorrectly
    # downgraded to the normal timeout tier.
    $preCleanupBudget = (& $budgetEntry | Out-String).Trim() | ConvertFrom-Json
    Add-LifecycleEvent -Stage 'pre_cleanup_resource_budget' -Status 'OBSERVED' -Data $preCleanupBudget
    $knownOwnerStatePaths = @(Get-LiveKnownOwnerStatePaths)
    Add-LifecycleEvent -Stage 'known_live_owner_states' -Status 'OBSERVED' -Data ([pscustomobject]@{
        count=$knownOwnerStatePaths.Count
        paths=@($knownOwnerStatePaths)
    })
    $snapshot = Get-TianzhengLifecycleSnapshot -OwnerStatePaths $knownOwnerStatePaths
    Add-LifecycleEvent -Stage 'preflight_snapshot' -Status 'OBSERVED' -Data $snapshot
    $plan = New-TianzhengCleanupPlan -Snapshot $snapshot -Mode $CleanupMode -ResidualGraceSeconds $ResidualGraceSeconds -ConfirmNoOtherCadProject:$ConfirmNoOtherCadProject
    Add-LifecycleEvent -Stage 'cleanup_plan' -Status $plan.status -Data $plan

    if ($plan.status -eq 'USER_DECISION_REQUIRED') {
        throw "CAD_RESTART_DECISION_REQUIRED=$reportPath"
    }
    if ($plan.target_count -gt 0) {
        $stopped = Stop-TianzhengProcessesExact -ProcessIds @($plan.targets.process_id)
        Add-LifecycleEvent -Stage 'cleanup' -Status 'PASS' -Data $stopped
    }
    # A normal handoff should behave like a person closing the owned test CAD
    # and immediately opening the next drawing.  A long memory-settle gate is
    # reserved for measured pre-existing pressure; process absence itself only
    # needs one continuous second in the ordinary owned handoff.
    $needsExtendedQuiescence = ($plan.target_count -gt 0 -and [bool]$preCleanupBudget.memory_pressure)
    $emptyQuietSeconds = if ($needsExtendedQuiescence) { 5 } else { 1 }
    if (-not (Wait-TianzhengEnvironmentEmpty -QuietSeconds $emptyQuietSeconds -TimeoutSeconds 30)) {
        $afterCleanup = Get-TianzhengLifecycleSnapshot -OwnerStatePaths @($ownerState)
        Add-LifecycleEvent -Stage 'environment_empty' -Status 'FAIL' -Data $afterCleanup
        throw "CAD_ENVIRONMENT_NOT_EMPTY_AFTER_CLEANUP=$reportPath"
    }
    Add-LifecycleEvent -Stage 'environment_empty' -Status 'PASS' -Data $null

    $recentCadCleanup = ($plan.target_count -gt 0)
    if ($recentCadCleanup -and $needsExtendedQuiescence) {
        # Process exit is not memory release.  Wait for the CAD/TGStart private
        # pages to disappear and available memory to settle before reopening.
        $prelaunchQuiescenceTimeout = [Math]::Max(60, [int]$preCleanupBudget.post_cleanup_quiescence_seconds * 2)
        $prelaunchQuiescenceText = (& $resourceQuiescenceEntry -TimeoutSeconds $prelaunchQuiescenceTimeout | Out-String).Trim()
        $prelaunchQuiescence = $prelaunchQuiescenceText | ConvertFrom-Json
        Add-LifecycleEvent -Stage 'prelaunch_resource_quiescence' -Status $prelaunchQuiescence.status -Data $prelaunchQuiescence
        if (-not $prelaunchQuiescence.ready_to_restart) {
            throw "CAD_RESOURCE_NOT_QUIESCENT_BEFORE_RESTART=$reportPath"
        }
    } elseif ($recentCadCleanup) {
        Add-LifecycleEvent -Stage 'prelaunch_resource_quiescence' -Status 'SKIPPED_FAST_OWNED_HANDOFF' -Data ([pscustomobject]@{
            reason='NO_PREEXISTING_MEMORY_PRESSURE_AND_EXACT_OWNED_PROCESSES_EXITED'
            environment_empty_quiet_seconds=$emptyQuietSeconds
        })
    }

    if ($PreflightOnly) {
        Add-LifecycleEvent -Stage 'preflight_only' -Status 'PASS' -Data $null
        [pscustomobject]@{ status='PASS'; mode='PREFLIGHT_ONLY'; lifecycle_report=$reportPath } | ConvertTo-Json -Depth 5
        return
    }

    $attempt = 0
    while ($attempt -le $RetryCount) {
        $attempt++
        $budget = (& $budgetEntry -ColdStart:($attempt -eq 1) -RecoveryAttempt:($attempt -gt 1) -RecentCadCleanup:$recentCadCleanup | Out-String).Trim() | ConvertFrom-Json
        $effectiveStartupTimeout = if ($StartupTimeoutSeconds -gt 0) { $StartupTimeoutSeconds } else { [int]$budget.total_timeout_seconds }
        $effectiveInitialFrameTimeout = if ($InitialFrameTimeoutSeconds -gt 0) { $InitialFrameTimeoutSeconds } else { $effectiveStartupTimeout }
        Add-LifecycleEvent -Stage 'adaptive_startup_budget' -Status 'PASS' -Data $budget
        $beforeIds = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.Id })
        Add-LifecycleEvent -Stage 'launch_attempt' -Status 'STARTED' -Data ([pscustomobject]@{
            attempt=$attempt
            route='TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'
            platform='AutoCAD 2021'
            launcher=$canonicalOpen
            baseline_pids=$beforeIds
        })
        try {
            # The supervisor owns retry policy.  The canonical opener therefore
            # gets exactly one Explorer-file-open attempt per supervised round;
            # nested retries are forbidden because they obscure process ownership
            # and were the main source of stale CAD sessions.
            $result = & $canonicalOpen `
                -DrawingPath $drawing `
                -ExpectedSha256 $ExpectedSha256 `
                -OwnerStatePath $ownerState `
                -DialogLogPath $dialogLog `
                -StartupTimeoutSeconds $effectiveStartupTimeout `
                -NoProgressTimeoutSeconds $effectiveInitialFrameTimeout `
                -DialogWatchSeconds $DialogWatchSeconds `
                -StableSeconds $StableSeconds `
                -TransientBlankDialogGraceMilliseconds $TransientBlankDialogGraceMilliseconds `
                -MaxLaunchAttempts 1

            # The inner opener can briefly observe a valid Tianzheng window and
            # then lose that HWND as its launch host returns.  That is not a
            # usable ready state.  Require the exact owned window to remain
            # visible after control has returned to the supervisor; otherwise
            # the normal exact-PID cleanup/retry path handles the false ready.
            $readyOwner = Get-Content -LiteralPath $ownerState -Raw -Encoding UTF8 | ConvertFrom-Json
            $readyPid = [int]$readyOwner.process_id
            $postReturnDeadline = (Get-Date).AddSeconds($PostReturnStableSeconds)
            do {
                if (-not (Test-TianzhengOwnerWindowLive -Path $ownerState)) {
                    throw "CAD_POST_RETURN_WINDOW_NOT_PERSISTENT=$reportPath"
                }
                Start-Sleep -Milliseconds 250
            } while ((Get-Date) -lt $postReturnDeadline)
            Add-LifecycleEvent -Stage 'launch_attempt' -Status 'PASS' -Data ([pscustomobject]@{ attempt=$attempt; result=$result })
            [pscustomobject]@{
                status='PASS'
                attempt=$attempt
                route='TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'
                platform='AutoCAD 2021'
                lifecycle_report=$reportPath
                startup_result=$result
            } | ConvertTo-Json -Depth 8
            # The exclusive operation guard protects lifecycle transitions, not
            # the whole visible CAD session.  Release it immediately after the
            # exact ready receipt so the next one-shot handoff can close this
            # owned CAD and open its successor without first killing a sleeping
            # launcher merely to recover the mutex.
            if ($null -ne $guard) {
                Exit-CadOperationGuard -Guard $guard
                $guard = $null
                Add-LifecycleEvent -Stage 'post_ready_operation_guard' -Status 'RELEASED' -Data $null
            }
            return
        } catch {
            $failure = $_.Exception.Message
            $current = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue)
            $newIds = @($current | Where-Object { $beforeIds -notcontains [int]$_.Id } | ForEach-Object { [int]$_.Id })
            Add-LifecycleEvent -Stage 'launch_attempt' -Status 'FAIL' -Data ([pscustomobject]@{ attempt=$attempt; error=$failure; new_pids=$newIds })
            if ($newIds.Count -gt 0) {
                $stopped = Stop-TianzhengProcessesExact -ProcessIds $newIds
                Add-LifecycleEvent -Stage 'failed_attempt_cleanup' -Status 'PASS' -Data $stopped
            }
            if (-not (Wait-TianzhengEnvironmentEmpty -QuietSeconds 5 -TimeoutSeconds 30)) {
                $remaining = Get-TianzhengLifecycleSnapshot -OwnerStatePaths @($ownerState)
                Add-LifecycleEvent -Stage 'failed_attempt_cleanup' -Status 'ENVIRONMENT_NOT_EMPTY' -Data $remaining
                throw "CAD_FULL_RESTART_DECISION_REQUIRED=$reportPath"
            }
            $quiescenceText = (& $resourceQuiescenceEntry -TimeoutSeconds ([Math]::Max(45, [int]$budget.post_cleanup_quiescence_seconds * 2)) | Out-String).Trim()
            $quiescence = $quiescenceText | ConvertFrom-Json
            Add-LifecycleEvent -Stage 'resource_quiescence' -Status $quiescence.status -Data $quiescence
            if (-not $quiescence.ready_to_restart) { throw "CAD_RESOURCE_NOT_QUIESCENT=$reportPath" }
            if ($attempt -gt $RetryCount) { throw }
        }
    }
} finally {
    if ($null -ne $guard) { Exit-CadOperationGuard -Guard $guard }
}
