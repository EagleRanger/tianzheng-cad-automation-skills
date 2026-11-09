Set-StrictMode -Version Latest

if (-not ('CodexTianzhengLifecycleWin32' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class CodexTianzhengLifecycleWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int count);

    public static string WindowTitle(IntPtr hWnd) {
        var value = new StringBuilder(2048);
        GetWindowText(hWnd, value, value.Capacity);
        return value.ToString();
    }

    public static long[] VisibleWindowsForProcess(uint wantedPid) {
        var result = new List<long>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == wantedPid && IsWindowVisible(hWnd)) result.Add(hWnd.ToInt64());
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
}
'@
}

function Get-TaskListWindowTitle {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$ProcessId)

    try {
        $taskList = Join-Path $env:SystemRoot 'System32\tasklist.exe'
        $line = @(& $taskList /V /FO CSV /NH /FI "PID eq $ProcessId" 2>$null | Select-Object -First 1)
        if ($line.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$line[0])) { return '' }
        $row = @($line[0] | ConvertFrom-Csv -Header ImageName,PID,SessionName,SessionNumber,MemoryUsage,Status,UserName,CPUTime,WindowTitle)
        if ($row.Count -ne 1) { return '' }
        $title = [string]$row[0].WindowTitle
        if ($title -match '^(N/A|暂缺|不适用)$') { return '' }
        return $title
    } catch {
        return ''
    }
}

function Get-OwnerProcessIds {
    [CmdletBinding()]
    param([string[]]$OwnerStatePaths = @())

    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($path in @($OwnerStatePaths)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $owner = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $pidValue = [int]$owner.process_id
            if ($pidValue -gt 0 -and (Test-TianzhengOwnerStatePathLive -Path $path)) { [void]$ids.Add($pidValue) }
        } catch {}
    }
    return @($ids)
}

function Test-TianzhengOwnerStateIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$OwnerState,
        [Parameter(Mandatory = $true)][int]$LiveProcessId,
        [Parameter(Mandatory = $true)][string]$LiveProcessName,
        [Parameter(Mandatory = $true)][datetime]$LiveProcessStartTime,
        [datetimeoffset]$ObservedAt = [datetimeoffset]::Now
    )

    $status = [string]$OwnerState.status
    if ($status -notin @('launching','opening_drawing','ready')) { return $false }
    if ([int]$OwnerState.process_id -ne $LiveProcessId -or $LiveProcessId -le 0) { return $false }

    $name = $LiveProcessName.Trim()
    if ($name -notin @('acad','TGStart')) { return $false }
    if ($status -in @('opening_drawing','ready') -and $name -cne 'acad') { return $false }

    $updatedAt = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse([string]$OwnerState.updated_at, [ref]$updatedAt)) { return $false }
    $startedAt = [datetimeoffset]$LiveProcessStartTime
    if ($updatedAt -lt $startedAt.AddSeconds(-5) -or $updatedAt -gt $ObservedAt.AddSeconds(5)) { return $false }

    if ($status -ceq 'ready') {
        $target = [string]$OwnerState.target_dwg
        $recordedTitle = [string]$OwnerState.main_window_title
        $documentVerified=($OwnerState.PSObject.Properties['document_identity_verified']-and[bool]$OwnerState.document_identity_verified)
        $activePath=if($OwnerState.PSObject.Properties['active_document_path']){[string]$OwnerState.active_document_path}else{''}
        if ([string]::IsNullOrWhiteSpace($target)) { return $false }
        $fileName = [IO.Path]::GetFileName($target)
        $titleMatch=(-not[string]::IsNullOrWhiteSpace($fileName)-and-not[string]::IsNullOrWhiteSpace($recordedTitle)-and$recordedTitle.IndexOf($fileName,[StringComparison]::OrdinalIgnoreCase)-ge0)
        $pathMatch=($documentVerified-and-not[string]::IsNullOrWhiteSpace($activePath)-and[IO.Path]::GetFullPath($activePath)-ceq[IO.Path]::GetFullPath($target))
        if(-not($titleMatch-or$pathMatch)){return $false}
    }
    return $true
}

function Test-TianzhengOwnerStatePathLive {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $owner = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $processId = [int]$owner.process_id
        if ($processId -le 0) { return $false }
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { return $false }
        $startTime = $process.StartTime
        return (Test-TianzhengOwnerStateIdentity `
            -OwnerState $owner `
            -LiveProcessId $processId `
            -LiveProcessName ([string]$process.ProcessName) `
            -LiveProcessStartTime $startTime)
    }
    catch { return $false }
}

function Test-TianzhengOwnerWindowLive {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $owner = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$owner.status -cne 'ready') { return $false }
        $processId = [int]$owner.process_id
        $windowHandle = [int64]$owner.main_window_handle
        if ($processId -le 0 -or $windowHandle -le 0) { return $false }
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process -or -not $process.Responding) { return $false }
        $visible = @([CodexTianzhengLifecycleWin32]::VisibleWindowsForProcess([uint32]$processId))
        if ($visible -notcontains $windowHandle) { return $false }
        $title = [CodexTianzhengLifecycleWin32]::WindowTitle([IntPtr]$windowHandle)
        $target=[IO.Path]::GetFullPath([string]$owner.target_dwg)
        $targetName=[IO.Path]::GetFileName($target)
        $titleMatch=(-not[string]::IsNullOrWhiteSpace($targetName)-and$title.IndexOf($targetName,[StringComparison]::OrdinalIgnoreCase)-ge0)
        $pathMatch=($owner.PSObject.Properties['document_identity_verified']-and[bool]$owner.document_identity_verified-and$owner.PSObject.Properties['active_document_path']-and[IO.Path]::GetFullPath([string]$owner.active_document_path)-ceq$target)
        return ($titleMatch-or$pathMatch)
    }
    catch { return $false }
}

function Get-TianzhengLifecycleSnapshot {
    [CmdletBinding()]
    param([string[]]$OwnerStatePaths = @())

    $ownedIds = @(Get-OwnerProcessIds -OwnerStatePaths $OwnerStatePaths)
    $now = Get-Date
    $items = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue | ForEach-Object {
        $process = $_
        $visible = @([CodexTianzhengLifecycleWin32]::VisibleWindowsForProcess([uint32]$process.Id))
        $taskTitle = Get-TaskListWindowTitle -ProcessId $process.Id
        $mainTitle = [string]$process.MainWindowTitle
        $hasUiSignal = ($visible.Count -gt 0) -or
            (-not [string]::IsNullOrWhiteSpace($mainTitle)) -or
            (-not [string]::IsNullOrWhiteSpace($taskTitle))
        $started = $null
        try { $started = $process.StartTime } catch {}
        $responding = $false
        try { $responding = [bool]$process.Responding } catch {}
        [pscustomobject]@{
            process_id = [int]$process.Id
            process_name = [string]$process.ProcessName
            session_id = [int]$process.SessionId
            responding = $responding
            start_time = if ($null -ne $started) { $started.ToString('o') } else { '' }
            age_seconds = if ($null -ne $started) { [math]::Round(($now - $started).TotalSeconds, 1) } else { -1 }
            main_window_handle = [int64]$process.MainWindowHandle
            main_window_title = $mainTitle
            tasklist_window_title = $taskTitle
            visible_window_handles = @($visible)
            has_ui_signal = [bool]$hasUiSignal
            owned_by_supplied_state = ($ownedIds -contains [int]$process.Id)
        }
    })

    return [pscustomobject]@{
        captured_at = $now.ToString('o')
        current_session_id = [Diagnostics.Process]::GetCurrentProcess().SessionId
        process_count = $items.Count
        processes = @($items)
    }
}

function New-TianzhengCleanupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [ValidateSet('Observe','Auto','ForceAll')][string]$Mode = 'Auto',
        [int]$ResidualGraceSeconds = 120,
        [switch]$ConfirmNoOtherCadProject
    )

    $processes = @($Snapshot.processes)
    if ($Mode -eq 'ForceAll' -and -not $ConfirmNoOtherCadProject) {
        throw 'FORCE_ALL_REQUIRES_CONFIRM_NO_OTHER_CAD_PROJECT'
    }

    $targets = @()
    $protected = @()
    foreach ($process in $processes) {
        $reason = ''
        if ($Mode -eq 'ForceAll') {
            $reason = 'USER_CONFIRMED_FULL_CAD_RESTART'
        } elseif ($Mode -eq 'Auto') {
            if ([bool]$process.owned_by_supplied_state) {
                $reason = 'OWNED_BY_CURRENT_AUTOMATION_STATE'
            } elseif ([string]$process.process_name -eq 'TGStart' -and
                -not [bool]$process.has_ui_signal -and
                [double]$process.age_seconds -ge $ResidualGraceSeconds) {
                # TGStart is only a launcher.  A stale launcher without any UI
                # can be cleaned automatically, but an unowned acad.exe may
                # still contain another project even when window discovery is
                # temporarily unavailable.  Keep unowned acad.exe protected.
                $reason = 'STALE_TGSTART_RESIDUE_WITHOUT_UI_SIGNAL'
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            $targets += [pscustomobject]@{ process_id=[int]$process.process_id; process_name=[string]$process.process_name; reason=$reason }
        } else {
            $protected += $process
        }
    }

    $decisionRequired = ($Mode -ne 'Observe' -and $protected.Count -gt 0)
    $status = if ($Mode -eq 'Observe') { 'OBSERVE_ONLY' } elseif ($decisionRequired) { 'USER_DECISION_REQUIRED' } else { 'READY_TO_CLEAN' }
    return [pscustomobject]@{
        status = $status
        mode = $Mode
        confirm_no_other_cad_project = [bool]$ConfirmNoOtherCadProject
        target_count = $targets.Count
        targets = @($targets)
        protected_count = $protected.Count
        protected_processes = @($protected)
    }
}

function Stop-TianzhengProcessesExact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int[]]$ProcessIds,
        [int]$ExitTimeoutSeconds = 15
    )

    $allowedNames = @('acad','TGStart')
    $results = @()
    foreach ($processId in @($ProcessIds | Sort-Object -Unique)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            $results += [pscustomobject]@{ process_id=$processId; status='ALREADY_EXITED'; process_name='' }
            continue
        }
        if ($allowedNames -notcontains [string]$process.ProcessName) {
            throw "REFUSE_NON_CAD_PROCESS=$processId;$($process.ProcessName)"
        }
        $name = [string]$process.ProcessName
        Stop-Process -Id $processId -Force -ErrorAction Stop
        $deadline = (Get-Date).AddSeconds($ExitTimeoutSeconds)
        while ((Get-Date) -lt $deadline -and (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 250
        }
        if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
            throw "CAD_PROCESS_DID_NOT_EXIT=$processId"
        }
        $results += [pscustomobject]@{ process_id=$processId; status='STOPPED'; process_name=$name }
    }
    return @($results)
}

function Wait-TianzhengEnvironmentEmpty {
    [CmdletBinding()]
    param([int]$QuietSeconds = 5, [int]$TimeoutSeconds = 30)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $quietSince = $null
    while ((Get-Date) -lt $deadline) {
        $count = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue).Count
        if ($count -eq 0) {
            if ($null -eq $quietSince) { $quietSince = Get-Date }
            elseif (((Get-Date) - $quietSince).TotalSeconds -ge $QuietSeconds) { return $true }
        } else {
            $quietSince = $null
        }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

Export-ModuleMember -Function Get-TianzhengLifecycleSnapshot, New-TianzhengCleanupPlan, Stop-TianzhengProcessesExact, Wait-TianzhengEnvironmentEmpty, Test-TianzhengOwnerStateIdentity, Test-TianzhengOwnerStatePathLive, Test-TianzhengOwnerWindowLive
