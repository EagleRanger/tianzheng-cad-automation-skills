param(
    [Parameter(Mandatory = $true)][string]$DrawingPath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$DialogLogPath,
    [ValidateRange(0,840)][int]$StartupTimeoutSeconds = 0,
    [ValidateRange(0,840)][int]$NoProgressTimeoutSeconds = 0,
    [int]$DialogWatchSeconds = 20,
    [int]$StableSeconds = 12,
    [int]$AssociationProbeSeconds = 45,
    [ValidateRange(1,2)][int]$MaxLaunchAttempts = 2,
    # AutoCAD may keep a blank #32770 shell briefly after an approved XREF
    # dialog is dismissed. Three seconds produced a false UNKNOWN_STOP on the
    # verified 2026-08-09 direct-open path; ten seconds still bounds genuinely
    # unknown modal windows while allowing the stale shell to disappear.
    [int]$TransientBlankDialogGraceMilliseconds = 10000
)

$ErrorActionPreference = 'Stop'
$drawing = [IO.Path]::GetFullPath($DrawingPath)
$owner_state = [IO.Path]::GetFullPath($OwnerStatePath)
$expected = $ExpectedSha256.ToUpperInvariant()
$targetToken = [IO.Path]::GetFileName($drawing)
$activeLaunchTransport = 'TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'
$launchAttempt = 0
$script:documentIdentityVerified = $false
$script:activeDocumentPath = ''
$script:documentOpenRequested = $false
$script:documentOpenRequestedAtSeconds = -1.0
$script:ownedProcessObserved = $false
$script:ownedProcessObservedAtSeconds = -1.0
$budgetEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/get_tianzheng_adaptive_startup_budget.ps1'
$resourceQuiescenceEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/wait_tianzheng_resource_quiescence.ps1'
$platformSelectorModule = Join-Path $PSScriptRoot 'common\TianzhengPlatformSelector.psm1'
Import-Module $platformSelectorModule -Force
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class TzExactDocumentWindow {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumChildProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint first, uint second, bool attach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, StringBuilder lParam);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint objectId, ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object value);
    public static string Title(IntPtr hWnd) { var value = new StringBuilder(2048); GetWindowText(hWnd, value, value.Capacity); return value.ToString(); }
    public static string ClassName(IntPtr hWnd) { var value = new StringBuilder(256); GetClassName(hWnd, value, value.Capacity); return value.ToString(); }
    public static IntPtr Find(uint pid, string token) {
        IntPtr found = IntPtr.Zero;
        IntPtr fallback = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
            uint actual; GetWindowThreadProcessId(hWnd, out actual);
            string title = Title(hWnd);
            if (actual == pid && IsWindowVisible(hWnd) && !String.IsNullOrWhiteSpace(title)
                && title.IndexOf(token, StringComparison.OrdinalIgnoreCase) >= 0) { found = hWnd; return false; }
            if (actual == pid && IsWindowVisible(hWnd) && fallback == IntPtr.Zero
                && ClassName(hWnd) == "AfxMDIFrame140u") { fallback = hWnd; }
            return true;
        }, IntPtr.Zero);
        return found != IntPtr.Zero ? found : fallback;
    }
    public static object NativeOm(IntPtr hwnd) {
        object result; Guid iid = new Guid("00020400-0000-0000-C000-000000000046");
        int hr = AccessibleObjectFromWindow(hwnd, 0xFFFFFFF0, ref iid, out result);
        if (hr != 0) Marshal.ThrowExceptionForHR(hr);
        return result;
    }
}
'@
if (-not (Test-Path -LiteralPath $drawing -PathType Leaf)) { throw "DRAWING_NOT_FOUND=$drawing" }
if ([IO.Path]::GetExtension($drawing) -cne '.dwg') { throw 'DRAWING_EXTENSION_NOT_DWG' }
if ($drawing -like '*\Desktop\*') { throw "DIRECT_SOURCE_OPEN_FORBIDDEN=$drawing" }
if ($expected -notmatch '^[A-F0-9]{64}$') { throw 'EXPECTED_SHA256_INVALID' }
$recover = $false
$prior = $null
if (Test-Path -LiteralPath $owner_state) {
    $prior = Get-Content -LiteralPath $owner_state -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($prior.target_dwg -cne $drawing -or
        $prior.target_sha256 -cne $expected -or
        @('launching','ready') -notcontains [string]$prior.status) {
        throw 'OWNER_STATE_TARGET_MISMATCH'
    }
    $actual = [string]$prior.target_sha256
    $recover = $true
} else {
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $drawing).Hash
    if ($actual -cne $expected) { throw "DRAWING_HASH_MISMATCH=expected:$expected;actual:$actual" }
}

function Write-OwnerState([string]$Status, $Process, [string]$Detail) {
    $parent = Split-Path -Parent $owner_state
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $exactWindow = if ($Process) { [TzExactDocumentWindow]::Find([uint32]$Process.Id, $targetToken) } else { [IntPtr]::Zero }
    $payload = [ordered]@{
        schema_version = 1
        status = $Status
        launch_transport = $activeLaunchTransport
        launch_attempt = $launchAttempt
        target_dwg = $drawing
        target_sha256 = $actual
        process_id = if ($Process) { [int]$Process.Id } else { 0 }
        main_window_handle = if ($exactWindow -ne [IntPtr]::Zero) { [int64]$exactWindow } else { 0 }
        main_window_title = if ($exactWindow -ne [IntPtr]::Zero) { [TzExactDocumentWindow]::Title($exactWindow) } else { '' }
        document_identity_verified = [bool]$script:documentIdentityVerified
        active_document_path = [string]$script:activeDocumentPath
        detail = $Detail
        updated_at = (Get-Date).ToString('o')
    }
    $temporary = "$owner_state.tmp"
    [IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $owner_state -Force
}

function Get-ExactRecoverableProcess {
    $all = @(Get-Process -Name acad -ErrorAction SilentlyContinue)
    if ($all.Count -ne 1) { return $null }
    $candidate = $all[0]
    $candidate.Refresh()
    return $candidate
}

function Get-ExactNativeDocumentIdentity($Process) {
    $window=[TzExactDocumentWindow]::Find([uint32]$Process.Id,$targetToken)
    if($window-eq[IntPtr]::Zero){return $null}
    $windowTitle=[TzExactDocumentWindow]::Title($window)
    if(-not[string]::IsNullOrWhiteSpace($windowTitle)-and
       $windowTitle.IndexOf($targetToken,[StringComparison]::OrdinalIgnoreCase)-ge0-and
       $activeLaunchTransport-ceq'TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'){
        return [pscustomobject]@{window=[int64]$window;document=$drawing;identity_method='EXACT_SHORTCUT_ARGUMENT_PLUS_TARGET_WINDOW_TITLE'}
    }
    $application=$null;$document=$null
    try{
        $application=[TzExactDocumentWindow]::NativeOm($window)
        $document=$application.ActiveDocument
        $rawFull=[string]$document.FullName
        if(-not[string]::IsNullOrWhiteSpace($rawFull)){
            $full=[IO.Path]::GetFullPath($rawFull)
            if($full-cne$drawing){return $null}
            return [pscustomobject]@{window=[int64]$window;document=$full;identity_method='ACTIVE_DOCUMENT_FULLNAME'}
        }
        $name=[string]$document.Name
        if($script:documentOpenRequested-and$name-ceq$targetToken){
            return [pscustomobject]@{window=[int64]$window;document=$drawing;identity_method='OPEN_ARGUMENT_PLUS_EXACT_NAME_WHEN_FULLNAME_EMPTY'}
        }
        return $null
    }catch{return $null}
    finally{
        if($document-is[System.__ComObject]){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($document)}
        if($application-is[System.__ComObject]){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($application)}
    }
}

function Get-OwnedTopLevelWindows([int]$ProcessId) {
    $items = [Collections.Generic.List[object]]::new()
    $callback = [TzExactDocumentWindow+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$state)
        [uint32]$windowPid = 0
        [void][TzExactDocumentWindow]::GetWindowThreadProcessId($hWnd, [ref]$windowPid)
        if ([int]$windowPid -eq $ProcessId -and [TzExactDocumentWindow]::IsWindowVisible($hWnd)) {
            $items.Add([pscustomobject]@{
                handle = $hWnd.ToInt64()
                title = [TzExactDocumentWindow]::Title($hWnd)
                class_name = [TzExactDocumentWindow]::ClassName($hWnd)
            })
        }
        return $true
    }
    [void][TzExactDocumentWindow]::EnumWindows($callback, [IntPtr]::Zero)
    return @($items)
}

function Invoke-ExactUiDocumentOpen($Process) {
    $window = [TzExactDocumentWindow]::Find([uint32]$Process.Id, $targetToken)
    if ($window -eq [IntPtr]::Zero) { throw 'BASE_AUTOCAD_WINDOW_NOT_READY_FOR_UI_OPEN' }
    $originalForeground = [TzExactDocumentWindow]::GetForegroundWindow()
    $clipboardHadText = [Windows.Forms.Clipboard]::ContainsText()
    $clipboardText = if ($clipboardHadText) { [Windows.Forms.Clipboard]::GetText() } else { '' }
    $clipboardRestored = $false
    try {
        $currentThread = [TzExactDocumentWindow]::GetCurrentThreadId()
        [uint32]$targetPid = 0
        $targetThread = [TzExactDocumentWindow]::GetWindowThreadProcessId($window, [ref]$targetPid)
        $foregroundWindow = [TzExactDocumentWindow]::GetForegroundWindow()
        [uint32]$foregroundPid = 0
        $foregroundThread = if ($foregroundWindow -ne [IntPtr]::Zero) {
            [TzExactDocumentWindow]::GetWindowThreadProcessId($foregroundWindow, [ref]$foregroundPid)
        } else { 0 }
        if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
            [void][TzExactDocumentWindow]::AttachThreadInput($currentThread, $foregroundThread, $true)
        }
        if ($targetThread -ne 0 -and $targetThread -ne $currentThread) {
            [void][TzExactDocumentWindow]::AttachThreadInput($currentThread, $targetThread, $true)
        }
        try {
            [void][TzExactDocumentWindow]::ShowWindow($window, 9)
            [void][TzExactDocumentWindow]::BringWindowToTop($window)
            [void][TzExactDocumentWindow]::SetForegroundWindow($window)
            [void][TzExactDocumentWindow]::SetFocus($window)
        } finally {
            if ($targetThread -ne 0 -and $targetThread -ne $currentThread) {
                [void][TzExactDocumentWindow]::AttachThreadInput($currentThread, $targetThread, $false)
            }
            if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread) {
                [void][TzExactDocumentWindow]::AttachThreadInput($currentThread, $foregroundThread, $false)
            }
        }
        $foregroundDeadline = (Get-Date).AddSeconds(5)
        do {
            [void][TzExactDocumentWindow]::SetForegroundWindow($window)
            Start-Sleep -Milliseconds 80
        } while ([TzExactDocumentWindow]::GetForegroundWindow() -ne $window -and (Get-Date) -lt $foregroundDeadline)
        if ([TzExactDocumentWindow]::GetForegroundWindow() -ne $window) { throw 'AUTOCAD_FOREGROUND_ACTIVATION_FAILED' }

        [Windows.Forms.SendKeys]::SendWait('^o')
        $fileDialog = $null
        $dialogDeadline = (Get-Date).AddSeconds(20)
        do {
            $candidate = @(Get-OwnedTopLevelWindows -ProcessId $Process.Id | Where-Object {
                $_.handle -ne [int64]$window -and -not [string]::IsNullOrWhiteSpace($_.title)
            } | Select-Object -First 1)
            if ($candidate.Count -gt 0) { $fileDialog = $candidate[0]; break }
            Start-Sleep -Milliseconds 100
        } while ((Get-Date) -lt $dialogDeadline)
        if ($null -eq $fileDialog) { throw 'OPEN_FILE_DIALOG_NOT_FOUND' }

        $dialogHandle = [IntPtr][long]$fileDialog.handle
        [void][TzExactDocumentWindow]::ShowWindow($dialogHandle, 9)
        [void][TzExactDocumentWindow]::BringWindowToTop($dialogHandle)
        [void][TzExactDocumentWindow]::SetForegroundWindow($dialogHandle)
        [void][TzExactDocumentWindow]::SetFocus($dialogHandle)
        Start-Sleep -Milliseconds 200
        $clipboardSet = $false
        for ($attempt = 1; $attempt -le 20 -and -not $clipboardSet; $attempt++) {
            try { [Windows.Forms.Clipboard]::SetText($drawing); $clipboardSet = $true }
            catch { Start-Sleep -Milliseconds 100 }
        }
        if (-not $clipboardSet) { throw 'CLIPBOARD_SET_DRAWING_PATH_FAILED' }
        [Windows.Forms.SendKeys]::SendWait('^l')
        Start-Sleep -Milliseconds 150
        [Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 150
        [Windows.Forms.SendKeys]::SendWait('{ENTER}')
        $dialogCloseDeadline = (Get-Date).AddSeconds(30)
        do {
            $dialogStillVisible = @(Get-OwnedTopLevelWindows -ProcessId $Process.Id | Where-Object {
                $_.handle -eq [long]$fileDialog.handle
            }).Count -gt 0
            if (-not $dialogStillVisible) { break }
            Start-Sleep -Milliseconds 100
        } while ((Get-Date) -lt $dialogCloseDeadline)
        if ($dialogStillVisible) { throw 'OPEN_FILE_DIALOG_DID_NOT_CLOSE' }
        return [pscustomobject]@{status='UI_FILE_OPEN_DISPATCHED_IDENTITY_PENDING';identity_method='EXACT_HWND_CTRL_O_ABSOLUTE_PATH'}
    } finally {
        for ($attempt = 1; $attempt -le 20 -and -not $clipboardRestored; $attempt++) {
            try {
                if ($clipboardHadText) { [Windows.Forms.Clipboard]::SetText($clipboardText) }
                else { [Windows.Forms.Clipboard]::Clear() }
                $clipboardRestored = $true
            } catch { Start-Sleep -Milliseconds 100 }
        }
        if ($originalForeground -ne [IntPtr]::Zero) {
            [void][TzExactDocumentWindow]::SetForegroundWindow($originalForeground)
        }
    }
    if (-not $clipboardRestored) { throw 'CLIPBOARD_RESTORE_FAILED' }
}

function Request-DrawingOpen([string]$Detail) {
    $script:launchAttempt += 1
    Write-OwnerState -Status 'launching' -Process $null -Detail $Detail
    # Reuse the complete lifecycle route that already passed two-cycle Tianzheng
    # open/close validation: invoke the unique Start-menu Tianzheng shortcut via
    # Explorer ShellExecute and give the isolated DWG as its normal launch input.
    $startMenuRoot = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs'
    $shortcutCandidates = @(Get-ChildItem -LiteralPath $startMenuRoot -Recurse -Filter '*.lnk' |
        Where-Object { $_.Name -like '*T20*Arch*V10.0*' })
    if ($shortcutCandidates.Count -ne 1) {
        throw "TIANZHENG_SHORTCUT_NOT_UNIQUE=count:$($shortcutCandidates.Count)"
    }
    $desktopShell = New-Object -ComObject Shell.Application
    try {
        $desktopShell.ShellExecute($shortcutCandidates[0].FullName, ('"' + $drawing + '"'), '', 'open', 1)
    } finally {
        if ($desktopShell -is [System.__ComObject]) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($desktopShell)
        }
    }
}

$existing = @(Get-Process -Name acad -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0 -and -not $recover) {
    throw "UNOWNED_ACAD_ALREADY_RUNNING=$(@($existing.Id) -join ',')"
}
$initialAcadIds = @($existing | ForEach-Object Id)
$budget = (& $budgetEntry -ColdStart:($existing.Count -eq 0) | Out-String).Trim() | ConvertFrom-Json
if ($StartupTimeoutSeconds -eq 0) { $StartupTimeoutSeconds = [int]$budget.total_timeout_seconds }
if ($NoProgressTimeoutSeconds -eq 0) { $NoProgressTimeoutSeconds = [int]$budget.no_progress_timeout_seconds }
$hardCapSeconds = [Math]::Max($StartupTimeoutSeconds, [int]$budget.hard_cap_seconds)
$identityTimeoutSeconds = [Math]::Min($hardCapSeconds,[Math]::Max(120,$NoProgressTimeoutSeconds))
$ownedAcadIds = [Collections.Generic.HashSet[int]]::new()
if ($recover -and $null -ne $prior -and [int]$prior.process_id -gt 0) {
    [void]$ownedAcadIds.Add([int]$prior.process_id)
}

if (-not $recover -or $existing.Count -eq 0) {
    $launcherIdsBefore = @(Get-Process -Name TGStart -ErrorAction SilentlyContinue | ForEach-Object Id)
    $launchDetail = if ($recover) { 'AUTOCAD_DIRECT_DWG_REISSUED_AFTER_INTERRUPTED_LAUNCH' } else { 'AUTOCAD_DIRECT_DWG_OPEN_REQUESTED' }
    Request-DrawingOpen -Detail $launchDetail
}

$timer = [Diagnostics.Stopwatch]::StartNew()
$process = $null
$lastProgressAt = 0.0
$lastProgressSignature = ''
while ($timer.Elapsed.TotalSeconds -lt $hardCapSeconds) {
    $currentAcad = @(Get-Process -Name acad -ErrorAction SilentlyContinue)
    $currentTgStart = @(Get-Process -Name TGStart -ErrorAction SilentlyContinue)
    $dialogStamp = if (Test-Path -LiteralPath $DialogLogPath) {
        $item = Get-Item -LiteralPath $DialogLogPath
        "$($item.Length):$($item.LastWriteTimeUtc.Ticks)"
    } else { 'NO_DIALOG_LOG' }
    $windowSignature = @($currentAcad | ForEach-Object {
        $candidateWindow = [TzExactDocumentWindow]::Find([uint32]$_.Id, $targetToken)
        "$($_.Id):$($_.Responding):$([int64]$candidateWindow):$([TzExactDocumentWindow]::Title($candidateWindow))"
    }) -join '|'
    $launcherSignature = @($currentTgStart | ForEach-Object { "$($_.Id):$([int64]$_.MainWindowHandle):$($_.MainWindowTitle)" }) -join '|'
    $progressSignature = "A=$windowSignature;T=$launcherSignature;D=$dialogStamp;L=$launchAttempt"
    if ($progressSignature -cne $lastProgressSignature) {
        $lastProgressSignature = $progressSignature
        $lastProgressAt = $timer.Elapsed.TotalSeconds
    }
    # A normal fresh launch starts with no acad.exe.  While CAD is a serialized
    # desktop resource, the sole process that appears after our file-open
    # request belongs to this launch.  A recovered launch is owned only when it
    # matches the PID persisted in the owner-state file.  Never claim or stop a
    # pre-existing/ambiguous user process.
    if ($initialAcadIds.Count -eq 0 -and $currentAcad.Count -eq 1 -and $launchAttempt -gt 0) {
        [void]$ownedAcadIds.Add([int]$currentAcad[0].Id)
        if(-not$script:ownedProcessObserved){
            $script:ownedProcessObserved = $true
            $script:ownedProcessObservedAtSeconds = $timer.Elapsed.TotalSeconds
        }
    }
    $process = Get-ExactRecoverableProcess
    if ($process) {
        $process.Refresh()
        $nativeIdentity=Get-ExactNativeDocumentIdentity $process
        if($nativeIdentity){$script:documentIdentityVerified=$true;$script:activeDocumentPath=$nativeIdentity.document;break}
    }
    if($script:ownedProcessObserved-and@($currentAcad|Where-Object{$ownedAcadIds.Contains([int]$_.Id)}).Count-eq0){
        Write-OwnerState -Status 'failed' -Process $null -Detail 'AUTOCAD_EXITED_AFTER_OPEN_DISPATCH'
        throw 'AUTOCAD_EXITED_AFTER_OPEN_DISPATCH'
    }
    if($script:ownedProcessObserved-and-not$script:documentIdentityVerified-and
       ($timer.Elapsed.TotalSeconds-$script:ownedProcessObservedAtSeconds)-ge$identityTimeoutSeconds){
        $ownedLive=@(Get-Process -Name acad -ErrorAction SilentlyContinue | Where-Object { $ownedAcadIds.Contains([int]$_.Id) })
        foreach($stuck in $ownedLive){Stop-Process -Id $stuck.Id -Force -ErrorAction SilentlyContinue}
        $identityTimeoutCode=('TARGET_WINDOW_IDENTITY_TIMEOUT_{0}S'-f$identityTimeoutSeconds)
        Write-OwnerState -Status 'failed' -Process $null -Detail $identityTimeoutCode
        throw $identityTimeoutCode
    }
    $platformHandled = $false
    foreach ($launcher in @(Get-Process -Name TGStart -ErrorAction SilentlyContinue | Where-Object { $launcherIdsBefore -notcontains $_.Id })) {
        $platform = Invoke-TianzhengPlatformSelection2021 -ProcessId $launcher.Id -LogPath $DialogLogPath
        if ($platform.confirmed) {
            Write-OwnerState -Status 'launching' -Process $null -Detail 'PLATFORM_AUTOCAD_2021_CONFIRMED'
            $lastProgressAt = $timer.Elapsed.TotalSeconds
            $platformHandled = $true
            break
        }
        if ($platform.code -lt 0) {
            Write-OwnerState -Status 'failed' -Process $null -Detail ("PLATFORM_SELECTION_INVALID=$($platform.code)")
            throw "PLATFORM_SELECTION_INVALID=$($platform.code)"
        }
    }
    if ($platformHandled) { Start-Sleep -Milliseconds 500; continue }
    if (($timer.Elapsed.TotalSeconds - $lastProgressAt) -ge $NoProgressTimeoutSeconds) {
        $currentAcad = @(Get-Process -Name acad -ErrorAction SilentlyContinue)
        $ownedStuck = @($currentAcad | Where-Object {
            $ownedAcadIds.Contains([int]$_.Id) -and
            ((-not $_.Responding) -or
             [TzExactDocumentWindow]::Find([uint32]$_.Id, $targetToken) -eq [IntPtr]::Zero)
        })
        foreach ($stuck in $ownedStuck) {
            Stop-Process -Id $stuck.Id -Force -ErrorAction Stop
            Write-OwnerState -Status 'launching' -Process $null -Detail ("OWNED_STUCK_ACAD_CLEARED_PID=" + $stuck.Id)
        }
        $newLaunchers = @(Get-Process -Name TGStart -ErrorAction SilentlyContinue | Where-Object {
            $launcherIdsBefore -notcontains $_.Id -and $_.MainWindowHandle -eq 0
        })
        foreach ($launcher in $newLaunchers) {
            Stop-Process -Id $launcher.Id -Force -ErrorAction Stop
        }
        $quietDeadline = (Get-Date).AddSeconds(30)
        do {
            $remaining = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) { break }
            Start-Sleep -Milliseconds 500
        } while ((Get-Date) -lt $quietDeadline)
        $residual = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue)
        if ($residual.Count -ne 0) {
            Write-OwnerState -Status 'failed' -Process $null -Detail 'EXPLORER_RETRY_RESIDUAL_PROCESS'
            throw "EXPLORER_RETRY_RESIDUAL_PROCESS=$(@($residual.Id) -join ',')"
        }
        if ($launchAttempt -ge $MaxLaunchAttempts) {
            Write-OwnerState -Status 'failed' -Process $null -Detail 'EXPLORER_LAUNCH_ATTEMPTS_EXHAUSTED'
            throw 'EXPLORER_LAUNCH_ATTEMPTS_EXHAUSTED'
        }
        $recoveryBudget = (& $budgetEntry -RecoveryAttempt | Out-String).Trim() | ConvertFrom-Json
        $quiescence = (& $resourceQuiescenceEntry -TimeoutSeconds ([Math]::Max(45, [int]$recoveryBudget.post_cleanup_quiescence_seconds * 2)) | Out-String).Trim() | ConvertFrom-Json
        if (-not $quiescence.ready_to_restart) {
            throw ('CAD_RESOURCE_NOT_QUIESCENT=' + ($quiescence | ConvertTo-Json -Compress -Depth 5))
        }
        $NoProgressTimeoutSeconds = [int]$recoveryBudget.no_progress_timeout_seconds
        $hardCapSeconds = [Math]::Max($hardCapSeconds, [int]$recoveryBudget.hard_cap_seconds)
        $launcherIdsBefore = @(Get-Process -Name TGStart -ErrorAction SilentlyContinue | ForEach-Object Id)
        Request-DrawingOpen -Detail ('AUTOCAD_DIRECT_DWG_OPEN_RETRY_' + ($launchAttempt + 1))
        $lastProgressAt = $timer.Elapsed.TotalSeconds
        $lastProgressSignature = ''
    }
    Start-Sleep -Milliseconds 500
}
if (-not $process -or -not $script:documentIdentityVerified) {
    Write-OwnerState -Status 'failed' -Process $process -Detail 'MAIN_WINDOW_TIMEOUT'
    throw 'TIANZHENG_MAIN_WINDOW_TIMEOUT'
}

$watcher = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/watch_tianzheng_dialogs.ps1'
$token = $targetToken
$combinedWatchSeconds = [Math]::Max($DialogWatchSeconds, $StableSeconds + 3)
& $watcher -ProcessId $process.Id -LogPath $DialogLogPath -TimeoutSeconds $combinedWatchSeconds `
    -RequiredMainTitle '' -QuietSeconds $StableSeconds `
    -TransientBlankDialogGraceMilliseconds $TransientBlankDialogGraceMilliseconds

$process.Refresh()
$exactWindow = [TzExactDocumentWindow]::Find([uint32]$process.Id, $targetToken)
$nativeIdentity=Get-ExactNativeDocumentIdentity $process
if ($process.HasExited) { throw 'TIANZHENG_EXITED_BEFORE_READY' }
if (-not $process.Responding -or
    $exactWindow -eq [IntPtr]::Zero -or
    -not $nativeIdentity) {
    Write-OwnerState -Status 'failed' -Process $process -Detail 'MAIN_WINDOW_NOT_READY_AFTER_DIALOG_GUARD'
    throw 'TIANZHENG_NOT_READY_AFTER_DIALOG_GUARD'
}
$script:documentIdentityVerified=$true;$script:activeDocumentPath=$nativeIdentity.document

$detail = if ($recover) { 'RECOVERED_AFTER_CONNECTION_INTERRUPTION' } else { 'TIANZHENG_SHORTCUT_DWG_ARGUMENT_STABLE' }
Write-OwnerState -Status 'ready' -Process $process -Detail $detail
Get-Content -LiteralPath $owner_state -Raw -Encoding UTF8
