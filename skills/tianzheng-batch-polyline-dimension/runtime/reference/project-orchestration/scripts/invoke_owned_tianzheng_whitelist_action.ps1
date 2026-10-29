param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][ValidateSet('AUDIT_OWNED_STATE','AUDIT_OWNED_VIEW','AUDIT_OBJECT_VISIBILITY','CLOSE_EXTERNAL_REFERENCE','QSAVE_OWNED','SAVE_COPY_OWNED','REGEN','SET_UCS_WORLD','SET_PLAN_WORLD','RESTORE_ALL_LAYERS','UNISOLATE_OBJECTS','ZOOM_EXTENTS','ZOOM_WINDOW','ZOOM_WINDOW_COM','RESET_VIEWPORT_TARGET','START_ADJUST_COMMAND','PRESELECT_TARGET_HANDLE','SELECT_TARGET_HANDLE','RECOVER_BATCH_VIEW','FINISH_PROMPT','FINISH_POINT','CANCEL_ACTIVE','ROUTE_INVENTORY','TARGET_ARC_GEOMETRY_INVENTORY','TARGET_SEGMENT_GEOMETRY_INVENTORY','EARTHWORK_ELEVATION_INVENTORY','NET_EARTHWORK_LOAD','NET_EARTHWORK_INVENTORY','NET_EARTHWORK_BATCH_INVENTORY','NET_EARTHWORK_RESTORE','POLYLINE_STYLE_INVENTORY','EXPORT_TEST_SUBSET_WBLOCK','NET_REFERENCE_POLYLINE_INVENTORY','TDIMARC_V10_FIVE','TDIMARC_FULL_BATCH','TDIMARC_FULL_BATCH_SOURCE_SERIAL','TDIM_TYPED_SEGMENT_BATCH','TDIM_TYPED_SEGMENT_SERIAL_BATCH','TDIMARC_SOURCE_REPAIR','TDIMARC_TARGETED_REPLACEMENT','CXHDBZ_PRESELECTED_BATCH','FOCUS_TDIMARC_TEST','TMIRDIM_ONE','TMIRDIM_BATCH','TMIRDIM_NATIVE_ANY_ONE','TMOVE_VECTOR_ONE','ADJUST_PROMPT_PROBE','ADJUST_GROUP_PROBE','AUDIT_NATIVE_DIM_BBOXES','PROBE_NATIVE_DIM_EXPLODE','AUDIT_NATIVE_DIM_TEXT_BBOXES','AUDIT_MODELSPACE_TAIL','CLEANUP_PROBE_STANDARD_DIMS','NET_NATIVE_ANNO_INVENTORY','NET_NATIVE_ANNO_TEXT_AUDIT','NET_NATIVE_GRIP_INVENTORY','NET_GRIP_AUDIT','NET_GRIP_MOVE','NET_GRIP_TARGET_PROBE','NET_GRIP_BATCH_MOVE','NET_GENERIC_GRIP_BATCH_MOVE','NET_NATIVE_DIM_DUAL_GRIP_MOVE','NET_NATIVE_DIM_GRIP0_ENDPOINT_RESTORE','NET_NATIVE_DIM_ENDPOINT_REPAIR','NET_NATIVE_DIM_GRIP_RESPONSE_PROBE','NET_NATIVE_CLONE_TRANSLATE')][string]$Action,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [long]$WindowHandle = 0,
    [string]$TargetHandle = '',
    [string]$TargetHandles = '',
    [string]$TaskSpecPath = '',
    [string]$PlanPath = '',
    [string]$ReportDirectory = '',
    [string]$ReportPath = '',
    [string]$OutputPath = '',
    [string]$ExecutionContractPath = '',
    [int]$GripIndex = -1,
    [switch]$SkipPluginLoad,
    [switch]$UseOwnedComDelivery,
    [double]$MoveX = 0.0,
    [double]$MoveY = 0.0,
    [double]$MinX = 0.0,
    [double]$MinY = 0.0,
    [double]$MaxX = 0.0,
    [double]$MaxY = 0.0,
    [ValidateSet('TArrangeDim','TDimAdjust','TMove','TDragMove')][string]$ProbeCommand = 'TArrangeDim',
    [ValidateSet('FIRST_PROMPT','SELECT_CLONE_CANCEL','APPLY_CLONE')][string]$ProbeStage = 'FIRST_PROMPT',
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$trustedInventory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/inventory_route_centerlines_fast.lsp'))
$trustedTargetArcInventory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/inventory_target_polyline_arcs.lsp'))
$trustedTargetSegmentInventory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/inventory_target_polyline_segments.lsp'))
$trustedEarthworkInventory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/earthwork_elevation_inventory_fast.lsp'))
$trustedTdimarcV10 = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_prompt_v10_batch_probe.lsp'))
$trustedAdjustProbe = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_adjust_probe.lsp'))
$trustedNativeAnnoMirrorProbe = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/native_annotation_mirror_probe.lsp'))
$trustedNativeAngleMirrorBatch = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/native_angle_mirror_batch.lsp'))
$trustedOwnedStateAudit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/audit_owned_document_state.lsp'))
$trustedOwnedViewAudit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/audit_owned_view_state.lsp'))
$trustedViewportReset = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/reset_owned_viewport_target.lsp'))
$trustedObjectVisibilityAudit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/audit_owned_object_visibility.lsp'))
$trustedPolylineInventory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/inventory_polyline_styles_fast.lsp'))
$trustedTestSubsetWblock = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/export_test_subset_wblock.lsp'))
$trustedFullBatch = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_full_batch.lsp'))
$trustedFullBatchSourceSerial = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_full_batch_source_serial_v3.lsp'))
$trustedTypedSourceSerial = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_full_batch_source_serial_v4.lsp'))
$trustedCxhdbzCommand = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/cx_tdimarc_batch_command.lsp'))
$trustedSourceRepair = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_source_repair.lsp'))
$trustedTargetedReplacement = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_targeted_replacement_v2.lsp'))
$trustedTargetedReplacementV3 = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tdimarc_native_targeted_replacement_v3.lsp'))
$trustedPromptProbe = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tianzheng_adjust_command_prompt_probe.lsp'))
$trustedGroupProbe = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/tianzheng_adjust_group_probe.lsp'))
$trustedDimensionBboxAudit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/audit_tianzheng_dimension_bboxes.lsp'))
$trustedDimensionExplodeProbe = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/probe_tianzheng_dimension_explode.lsp'))
$trustedDimensionTextBboxAudit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/audit_tianzheng_dimension_text_bboxes.lsp'))
$trustedModelspaceTailAudit = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/audit_modelspace_tail.lsp'))
$trustedStandardDimensionCleanup = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/cleanup_probe_standard_dimensions.lsp'))
$trustedGripPlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexTzGripProbe_20260810_09.dll'))
$trustedGrip0EndpointRestorePlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexTzGripProbe_20260821_10.dll'))
$trustedDualGripPlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexTzGripProbe_20260821_11.dll'))
$trustedGripTargetProbePlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexTzGripTargetProbe_20260822_01.dll'))
$trustedReferenceInventoryPlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexReferenceInventory_20260810_01.dll'))
$trustedEndpointRepairPlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexTzGripProbe_20260810_08.dll'))
$trustedEarthworkPlugin = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $PSScriptRoot) 'build\CodexEarthworkInventory.bundle\Contents\CodexEarthworkInventory.dll'))
$owner = Get-Content -LiteralPath $OwnerStatePath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId) {
    throw 'OWNED_READY_PROCESS_MISMATCH'
}
$acad = @(Get-Process acad -ErrorAction SilentlyContinue)
if ($acad.Count -ne 1 -or $acad[0].Id -ne $ProcessId) { throw 'SINGLE_OWNED_ACAD_REQUIRED' }
$process = $acad[0]
$targetName = [IO.Path]::GetFileName([string]$owner.target_dwg)

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class OwnedTzTopWindowResolver {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder value, int count);
    public static uint ProcessId(IntPtr hWnd) { uint pid; GetWindowThreadProcessId(hWnd, out pid); return pid; }
    public static string Title(IntPtr hWnd) { var value = new StringBuilder(2048); GetWindowText(hWnd, value, value.Capacity); return value.ToString(); }
    public static string Class(IntPtr hWnd) { var value = new StringBuilder(256); GetClassName(hWnd, value, value.Capacity); return value.ToString(); }
    public static IntPtr[] VisibleForProcess(uint wantedPid) {
        var result = new List<IntPtr>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
            uint pid; GetWindowThreadProcessId(hWnd, out pid);
            if (pid == wantedPid && IsWindowVisible(hWnd) && !String.IsNullOrWhiteSpace(Title(hWnd))) result.Add(hWnd);
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
    public static IntPtr[] VisibleDialogsForProcess(uint wantedPid) {
        var result = new List<IntPtr>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
            uint pid; GetWindowThreadProcessId(hWnd, out pid);
            if (pid == wantedPid && IsWindowVisible(hWnd) && Class(hWnd) == "#32770") result.Add(hWnd);
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
}
public static class OwnedTzRotResolver {
    [DllImport("oleaut32.dll", PreserveSig=false)]
    private static extern void GetActiveObject(ref Guid clsid, IntPtr reserved, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    public static object GetActiveObject(string progId) {
        var type = Type.GetTypeFromProgID(progId, true);
        var clsid = type.GUID;
        object instance;
        GetActiveObject(ref clsid, IntPtr.Zero, out instance);
        return instance;
    }
}
'@

if ($WindowHandle -ne 0) {
    $mainWindow = [IntPtr]$WindowHandle
    if (-not [OwnedTzTopWindowResolver]::IsWindow($mainWindow)) { throw 'PROVIDED_WINDOW_HANDLE_INVALID' }
    if ([OwnedTzTopWindowResolver]::ProcessId($mainWindow) -ne [uint32]$ProcessId) { throw 'PROVIDED_WINDOW_PID_MISMATCH' }
}
else {
    $candidates = @([OwnedTzTopWindowResolver]::VisibleForProcess([uint32]$ProcessId) | Where-Object {
        [OwnedTzTopWindowResolver]::Title($_).IndexOf($targetName, [StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($candidates.Count -ne 1) { throw "OWNED_VISIBLE_WINDOW_NOT_UNIQUE:$($candidates.Count)" }
    $mainWindow = $candidates[0]
}
$resolvedTitle = [OwnedTzTopWindowResolver]::Title($mainWindow)
if ($resolvedTitle.IndexOf($targetName, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'OWNED_DRAWING_TITLE_MISMATCH' }

# A manually opened or resumed Tianzheng session does not pass through the
# launch supervisor.  Run the same exact-PID, exact-signature dialog gate at
# the shared business-action entrance, but only when a modal actually exists.
# This keeps the normal path effectively free while preventing a known XREF,
# graphic-repair, or other approved startup dialog from blocking the command
# queue for minutes.  Unknown dialogs still fail closed and leave evidence.
$dialogsBeforeAction = @([OwnedTzTopWindowResolver]::VisibleDialogsForProcess([uint32]$ProcessId))
if ($dialogsBeforeAction.Count -gt 0) {
    $routineWatcher = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/watch_tianzheng_dialogs.ps1'
    if (-not (Test-Path -LiteralPath $routineWatcher -PathType Leaf)) { throw 'ROUTINE_DIALOG_WATCHER_MISSING' }
    $routineLogDirectory = if (-not [string]::IsNullOrWhiteSpace($ReportDirectory)) {
        [IO.Path]::GetFullPath($ReportDirectory)
    }
    else {
        [IO.Path]::GetFullPath((Split-Path -Parent $OwnerStatePath))
    }
    if (-not (Test-Path -LiteralPath $routineLogDirectory)) {
        [void](New-Item -ItemType Directory -Path $routineLogDirectory -Force)
    }
    $routineDialogLog = Join-Path $routineLogDirectory ("pre_action_dialogs_{0}.jsonl" -f $ProcessId)
    & $routineWatcher -ProcessId $ProcessId -LogPath $routineDialogLog -RequiredMainTitle $targetName -TimeoutSeconds 5 -QuietSeconds 1
    $dialogsAfterActionGate = @([OwnedTzTopWindowResolver]::VisibleDialogsForProcess([uint32]$ProcessId))
    if ($dialogsAfterActionGate.Count -gt 0) {
        # CANCEL_ACTIVE is the bounded recovery operation for a command that
        # has left Tianzheng's exact, non-mutating TDimMP palette visible.  The
        # ordinary business gate must still reject every other remaining
        # modal; only the already whitelisted exact title plus the watcher's
        # positive signature receipt may pass through to the three Escape keys.
        $cancelPaletteCount = @($dialogsAfterActionGate | Where-Object {
            [OwnedTzTopWindowResolver]::Title($_) -ceq '逐点标注'
        }).Count
        $cancelPaletteWasRecognized = (Test-Path -LiteralPath $routineDialogLog -PathType Leaf) -and
            ((Get-Content -LiteralPath $routineDialogLog -Raw -Encoding UTF8).IndexOf('KNOWN_NONBLOCKING_DIALOG_OBSERVED', [StringComparison]::Ordinal) -ge 0)
        $allowExactCancelRecovery = $Action -ceq 'CANCEL_ACTIVE' -and
            $cancelPaletteCount -eq $dialogsAfterActionGate.Count -and
            $cancelPaletteWasRecognized
        if (-not $allowExactCancelRecovery) {
            throw "PRE_ACTION_DIALOG_GATE_INCOMPLETE=$($dialogsAfterActionGate.Count);LOG=$routineDialogLog"
        }
    }
}
$process.Refresh()
if (-not $process.Responding) {
    # Windows can report an owned T20/AutoCAD main frame as "not responding"
    # even while AutoCAD's exact COM instance is idle and its command queue is
    # usable (observed after the standard human-flow launcher hands control to
    # the business action).  Do not bypass readiness on the process flag alone:
    # require the same owned HWND, the same active drawing, a quiescent AutoCAD
    # state, and an empty command stack.  Any missing or conflicting signal
    # still fails closed.
    $comReadyFallback = $false
    try {
        $fallbackApplication = [OwnedTzRotResolver]::GetActiveObject('AutoCAD.Application.24')
        $fallbackHwnd = [int64]$fallbackApplication.HWND
        $fallbackDocument = $fallbackApplication.ActiveDocument
        $fallbackFullName = [string]$fallbackDocument.FullName
        $fallbackSameDrawing = if (-not [string]::IsNullOrWhiteSpace($fallbackFullName)) {
            [IO.Path]::GetFileName($fallbackFullName) -ceq $targetName
        }
        else {
            $resolvedTitle.IndexOf($targetName, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }
        $fallbackIsQuiescent = [bool]$fallbackApplication.GetAcadState().IsQuiescent
        $fallbackCommandNames = [string]$fallbackDocument.GetVariable('CMDNAMES')
        $fallbackCommandActive = [int]$fallbackDocument.GetVariable('CMDACTIVE')
        $comReadyFallback = (
            $fallbackHwnd -eq [int64]$mainWindow -and
            $fallbackSameDrawing -and
            $fallbackIsQuiescent -and
            [string]::IsNullOrWhiteSpace($fallbackCommandNames) -and
            $fallbackCommandActive -eq 0
        )
    }
    catch {
        $comReadyFallback = $false
    }
    if (-not $comReadyFallback) { throw 'OWNED_TIANZHENG_NOT_READY_AFTER_PRE_ACTION_DIALOG_GATE' }
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class OwnedTzWhitelistBridge {
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumChildProc callback, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool PostMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    public static IntPtr FindMdiClient(IntPtr main) {
        IntPtr result = IntPtr.Zero;
        EnumChildWindows(main, delegate(IntPtr child, IntPtr ignored) {
            var name = new StringBuilder(128);
            GetClassName(child, name, name.Capacity);
            if (name.ToString() == "MDIClient") { result = child; return false; }
            return true;
        }, IntPtr.Zero);
        return result;
    }
    public static void PostText(IntPtr target, string text) {
        foreach (char value in text) {
            if (!PostMessage(target, 0x0102, (IntPtr)value, IntPtr.Zero)) {
                throw new InvalidOperationException("POST_MESSAGE_FAILED");
            }
        }
    }
    public static void PostVirtualKey(IntPtr target, int key) {
        if (!PostMessage(target, 0x0100, (IntPtr)key, IntPtr.Zero)) throw new InvalidOperationException("POST_KEYDOWN_FAILED");
        if (!PostMessage(target, 0x0101, (IntPtr)key, IntPtr.Zero)) throw new InvalidOperationException("POST_KEYUP_FAILED");
    }
}
'@

$mdi = [OwnedTzWhitelistBridge]::FindMdiClient($mainWindow)
if ($mdi -eq [IntPtr]::Zero) { throw 'MDICLIENT_NOT_FOUND' }
$started = Get-Date

function Invoke-OwnedComRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Operation,
        [int]$TimeoutSeconds = 45,
        [string]$Label = 'COM_OPERATION'
    )
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
    do {
        try { return & $Operation }
        catch {
            # AutoCAD/Tianzheng temporarily rejects COM calls while loading a
            # module, regenerating, or unwinding a command.  Retrying only the
            # two standard "busy" HRESULTs keeps delivery background-only and
            # avoids treating an unrelated COM failure as transient.
            $hresult = $_.Exception.HResult
            if ($hresult -notin @(-2147418111, -2147417846) -or (Get-Date) -ge $deadline) {
                throw "$Label`_FAILED_HRESULT=$hresult DETAIL=$($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds 300
        }
    } while ((Get-Date) -lt $deadline)
    throw "$Label`_TIMEOUT"
}

function Start-TrustedLspAutoLoadWatcher([string[]]$ScriptPaths) {
    if ($ScriptPaths.Count -lt 1) { throw 'TRUSTED_LSP_WATCH_PATH_REQUIRED' }
    $watcherPath = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/watch_tianzheng_dialogs.ps1'
    if (-not (Test-Path -LiteralPath $watcherPath -PathType Leaf)) { throw 'TRUSTED_LSP_WATCHER_MISSING' }
    $trustedStageRoot = [IO.Path]::GetFullPath('C:\tmp\tianzheng_whitelist').TrimEnd('\') + '\'
    $resolvedPaths = New-Object System.Collections.Generic.List[string]
    $hashes = New-Object System.Collections.Generic.List[string]
    foreach ($scriptPath in $ScriptPaths) {
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "TRUSTED_LSP_STAGE_MISSING=$scriptPath" }
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $scriptPath).Path)
        if (-not $resolved.StartsWith($trustedStageRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "TRUSTED_LSP_STAGE_OUTSIDE_ROOT=$resolved" }
        if ([IO.Path]::GetExtension($resolved) -cne '.lsp') { throw "TRUSTED_LSP_STAGE_EXTENSION_INVALID=$resolved" }
        $resolvedPaths.Add($resolved)
        $hashes.Add((Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash)
    }
    $logPath = Join-Path 'C:\tmp\tianzheng_whitelist' ("trusted_lsp_autoload_{0}_{1}.jsonl" -f $ProcessId, $Action.ToLowerInvariant())
    return Start-Job -ScriptBlock {
        param($WatcherPath,$OwnedProcessId,$WatcherLogPath,$Paths,$ExpectedHashes,$MaximumClicks,$OwnedTitle)
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        & $WatcherPath -ProcessId $OwnedProcessId -LogPath $WatcherLogPath -ExpectedTrustedScriptPaths $Paths -ExpectedTrustedScriptSha256s $ExpectedHashes -MaxTrustedScriptAutoDismissCount $MaximumClicks -RequiredMainTitle $OwnedTitle -TimeoutSeconds 90 -QuietSeconds 5
    } -ArgumentList $watcherPath,$ProcessId,$logPath,$resolvedPaths.ToArray(),$hashes.ToArray(),$resolvedPaths.Count,$targetName
}

function Stop-TrustedLspAutoLoadWatcher([object]$WatcherJob) {
    if ($null -eq $WatcherJob) { return }
    if ($WatcherJob.State -eq 'Failed') {
        $failure = Receive-Job -Job $WatcherJob -ErrorAction SilentlyContinue 2>&1 | Out-String
        Remove-Job -Job $WatcherJob -Force -ErrorAction SilentlyContinue
        throw "TRUSTED_LSP_WATCHER_FAILED=$failure"
    }
    if ($WatcherJob.State -eq 'Running') { Stop-Job -Job $WatcherJob -ErrorAction SilentlyContinue }
    Receive-Job -Job $WatcherJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $WatcherJob -Force -ErrorAction SilentlyContinue
}

function Send-TrustedLspCommand([string]$CommandText,[string[]]$ScriptPaths) {
    $watcherJob = Start-TrustedLspAutoLoadWatcher -ScriptPaths $ScriptPaths
    try {
        [OwnedTzWhitelistBridge]::PostText($mdi, $CommandText)
        # A trusted AutoLISP security dialog can appear several seconds after
        # the command text is accepted.  Keep the exact-PID/hash watcher alive
        # through that delayed modal window instead of stopping after the first
        # quiet poll and leaving TDIMARC blocked behind an unseen prompt.
        $watchDeadline = (Get-Date).AddMilliseconds([Math]::Max(8000, 4200 * $ScriptPaths.Count))
        while ((Get-Date) -lt $watchDeadline -and $watcherJob.State -eq 'Running') {
            Start-Sleep -Milliseconds 100
        }
        if ($watcherJob.State -eq 'Failed') { Stop-TrustedLspAutoLoadWatcher -WatcherJob $watcherJob }
    }
    finally {
        if ($null -ne $watcherJob -and $watcherJob.State -ne 'Failed') {
            Stop-TrustedLspAutoLoadWatcher -WatcherJob $watcherJob
        }
    }
}

function Send-TrustedLspCommandCom([string]$CommandText,[string[]]$ScriptPaths) {
    # Parameter-heavy read-only commands are more reliable through AutoCAD's
    # native automation queue than through per-character WM_CHAR injection.
    # Bind to the exact owned HWND so this cannot drift into another CAD
    # session.  The same trusted-script watcher remains in force.
    $application = Invoke-OwnedComRetry -Label 'COM_GET_APPLICATION' -Operation {
        [OwnedTzRotResolver]::GetActiveObject('AutoCAD.Application.24')
    }
    $applicationHwnd = Invoke-OwnedComRetry -Label 'COM_GET_HWND' -Operation { [int64]$application.HWND }
    if ([int64]$applicationHwnd -ne [int64]$mainWindow) { throw 'COM_BOUND_TO_WRONG_OWNED_WINDOW' }
    $document = Invoke-OwnedComRetry -Label 'COM_GET_ACTIVE_DOCUMENT' -Operation { $application.ActiveDocument }
    $activeFullName = Invoke-OwnedComRetry -Label 'COM_GET_ACTIVE_DOCUMENT_PATH' -Operation { [string]$document.FullName }
    # T20 V10 can expose an exact owned AutoCAD COM application while returning
    # empty Name/FullName strings for its proxied ActiveDocument.  In that
    # observed state the exact HWND and main-frame title remain authoritative.
    # Keep the strict pathname check whenever COM supplies a pathname; only
    # fall back to the already-resolved exact owned title when it supplies none.
    if (-not [string]::IsNullOrWhiteSpace($activeFullName)) {
        if ([IO.Path]::GetFileName($activeFullName) -cne $targetName) { throw 'COM_ACTIVE_DRAWING_MISMATCH' }
    }
    elseif ($resolvedTitle.IndexOf($targetName, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'COM_ACTIVE_DRAWING_UNVERIFIABLE'
    }
    $watcherJob = Start-TrustedLspAutoLoadWatcher -ScriptPaths $ScriptPaths
    try {
        Invoke-OwnedComRetry -Label 'COM_SEND_TRUSTED_LSP_COMMAND' -TimeoutSeconds ([Math]::Max(45, $TimeoutSeconds)) -Operation {
            $document.SendCommand($CommandText)
        } | Out-Null
        $watchDeadline = (Get-Date).AddMilliseconds([Math]::Max(8000, 4200 * $ScriptPaths.Count))
        while ((Get-Date) -lt $watchDeadline -and $watcherJob.State -eq 'Running') {
            Start-Sleep -Milliseconds 100
        }
        if ($watcherJob.State -eq 'Failed') { Stop-TrustedLspAutoLoadWatcher -WatcherJob $watcherJob }
    }
    finally {
        if ($null -ne $watcherJob -and $watcherJob.State -ne 'Failed') {
            Stop-TrustedLspAutoLoadWatcher -WatcherJob $watcherJob
        }
    }
}

function Send-OwnedComCommand([string]$CommandText) {
    # Use AutoCAD's native command queue, but keep the same exact owned-window
    # and active-drawing guards as every other governed action.
    $application = Invoke-OwnedComRetry -Label 'COM_GET_APPLICATION' -Operation {
        [OwnedTzRotResolver]::GetActiveObject('AutoCAD.Application.24')
    }
    $applicationHwnd = Invoke-OwnedComRetry -Label 'COM_GET_HWND' -Operation { [int64]$application.HWND }
    if ([int64]$applicationHwnd -ne [int64]$mainWindow) { throw 'COM_BOUND_TO_WRONG_OWNED_WINDOW' }
    $document = Invoke-OwnedComRetry -Label 'COM_GET_ACTIVE_DOCUMENT' -Operation { $application.ActiveDocument }
    $activeFullName = Invoke-OwnedComRetry -Label 'COM_GET_ACTIVE_DOCUMENT_PATH' -Operation { [string]$document.FullName }
    if (-not [string]::IsNullOrWhiteSpace($activeFullName)) {
        if ([IO.Path]::GetFileName($activeFullName) -cne $targetName) { throw 'COM_ACTIVE_DRAWING_MISMATCH' }
    }
    elseif ($resolvedTitle.IndexOf($targetName, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw 'COM_ACTIVE_DRAWING_UNVERIFIABLE'
    }
    Invoke-OwnedComRetry -Label 'COM_SEND_OWNED_COMMAND' -TimeoutSeconds ([Math]::Max(45, $TimeoutSeconds)) -Operation {
        $document.SendCommand($CommandText)
    } | Out-Null
}

if ($Action -ceq 'AUDIT_OWNED_STATE') {
    if (-not (Test-Path -LiteralPath $trustedOwnedStateAudit -PathType Leaf)) { throw 'TRUSTED_OWNED_STATE_AUDIT_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'OWNED_STATE_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OWNED_STATE_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport -Force -ErrorAction SilentlyContinue
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'audit_owned_document_state.lsp'
    Copy-Item -LiteralPath $trustedOwnedStateAudit -Destination $stagedLisp -Force
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $reportForLisp = $resolvedReport.Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*ods-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*ods-report-path* "' + $reportForLisp + '") ' +
        '(load "C:/tmp/tianzheng_whitelist/audit_owned_document_state.lsp"))' + "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'OWNED_STATE_REPORT_TIMEOUT' }
    $rows = @(Import-Csv -LiteralPath $resolvedReport -Delimiter "`t" -Encoding Default)
    if ($rows.Count -ne 1) { throw 'OWNED_STATE_REPORT_INVALID' }
    $result = [pscustomobject]@{
        status = [string]$rows[0].STATUS; action = $Action; process_id = $ProcessId; report = $resolvedReport
        dbmod = [int]$rows[0].DBMOD; command_active = [int]$rows[0].CMDACTIVE; command_names = [string]$rows[0].CMDNAMES
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'CLOSE_EXTERNAL_REFERENCE') {
    $externalReferenceWindows = @([OwnedTzTopWindowResolver]::VisibleForProcess([uint32]$ProcessId) | Where-Object {
        [OwnedTzTopWindowResolver]::Title($_) -ceq '外部参照'
    })
    if ($externalReferenceWindows.Count -gt 1) { throw 'OWNED_EXTERNAL_REFERENCE_WINDOW_NOT_UNIQUE' }
    if ($externalReferenceWindows.Count -eq 1) {
        $closed = [OwnedTzWhitelistBridge]::PostMessage($externalReferenceWindows[0], 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        if (-not $closed) { throw 'OWNED_EXTERNAL_REFERENCE_CLOSE_POST_FAILED' }
        Start-Sleep -Milliseconds 800
        if ([OwnedTzTopWindowResolver]::IsWindow($externalReferenceWindows[0])) { throw 'OWNED_EXTERNAL_REFERENCE_CLOSE_FAILED' }
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        closed_count = $externalReferenceWindows.Count; elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'AUDIT_OWNED_VIEW') {
    if (-not (Test-Path -LiteralPath $trustedOwnedViewAudit -PathType Leaf)) { throw 'TRUSTED_OWNED_VIEW_AUDIT_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'OWNED_VIEW_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OWNED_VIEW_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport -Force -ErrorAction SilentlyContinue
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'audit_owned_view_state.lsp'
    Copy-Item -LiteralPath $trustedOwnedViewAudit -Destination $stagedLisp -Force
    $reportForLisp = $resolvedReport.Replace('\','/')
    $command = '(progn (setq cx:*view-report-path* "' + $reportForLisp + '") ' +
        '(load "C:/tmp/tianzheng_whitelist/audit_owned_view_state.lsp") (c:CXAUDITOWNEDVIEW))' + "`r"
    # Visibility is part of the drawing database, so deliver the audit to the
    # exact owned document queue.  Frame/MDI text delivery can be accepted by
    # the window while Tianzheng is still settling and silently miss the DWG.
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'OWNED_VIEW_REPORT_TIMEOUT' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId; report = $resolvedReport
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'AUDIT_OBJECT_VISIBILITY') {
    if (-not (Test-Path -LiteralPath $trustedObjectVisibilityAudit -PathType Leaf)) { throw 'TRUSTED_OBJECT_VISIBILITY_AUDIT_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'OBJECT_VISIBILITY_REPORT_PATH_REQUIRED' }
    $handles = @($TargetHandles -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -lt 1 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) { throw 'OBJECT_VISIBILITY_HANDLES_INVALID' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OBJECT_VISIBILITY_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport -Force -ErrorAction SilentlyContinue
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'audit_owned_object_visibility.lsp'
    Copy-Item -LiteralPath $trustedObjectVisibilityAudit -Destination $stagedLisp -Force
    $lispHandles = '(' + (($handles | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ')'
    $reportForLisp = $resolvedReport.Replace('\','/')
    $command = '(progn (setq cx:*ov-report-path* "' + $reportForLisp + '" ' +
        'cx:*ov-handles* (quote ' + $lispHandles + ')) ' +
        '(load "C:/tmp/tianzheng_whitelist/audit_owned_object_visibility.lsp") (c:CXAUDITOBJECTVISIBILITY))' + "`r"
    # Audit the exact owned drawing.  MDI text delivery can be accepted by the
    # frame while Tianzheng is still settling and silently miss the document.
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'OBJECT_VISIBILITY_REPORT_TIMEOUT' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId; report = $resolvedReport
        handle_count = $handles.Count; elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'QSAVE_OWNED') {
    $targetDwg = [IO.Path]::GetFullPath([string]$owner.target_dwg)
    if (-not (Test-Path -LiteralPath $targetDwg -PathType Leaf)) { throw 'OWNED_QSAVE_TARGET_MISSING' }
    $beforeItem = Get-Item -LiteralPath $targetDwg
    $beforeWriteUtc = $beforeItem.LastWriteTimeUtc
    $beforeLength = $beforeItem.Length
    Send-OwnedComCommand -CommandText ("_.QSAVE`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $afterItem = $null
    do {
        Start-Sleep -Milliseconds 200
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'OWNED_QSAVE_NOT_RESPONDING' }
        $afterItem = Get-Item -LiteralPath $targetDwg -ErrorAction Stop
        if ($afterItem.LastWriteTimeUtc -gt $beforeWriteUtc) { break }
    } while ((Get-Date) -lt $deadline)
    if ($afterItem.LastWriteTimeUtc -le $beforeWriteUtc) { throw 'OWNED_QSAVE_WRITE_TIMEOUT' }
    Start-Sleep -Milliseconds 600
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId; target_dwg = $targetDwg
        before_length = $beforeLength; after_length = $afterItem.Length
        before_write_utc = $beforeWriteUtc.ToString('o'); after_write_utc = $afterItem.LastWriteTimeUtc.ToString('o')
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'SAVE_COPY_OWNED') {
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'
    $targetDwg = [IO.Path]::GetFullPath([string]$owner.target_dwg)
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'OWNED_SAVE_COPY_OUTPUT_REQUIRED' }
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    if (-not $resolvedOutput.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'OWNED_SAVE_COPY_OUTPUT_OUTSIDE_RUNS' }
    if ([IO.Path]::GetExtension($resolvedOutput) -cne '.dwg') { throw 'OWNED_SAVE_COPY_OUTPUT_EXTENSION_INVALID' }
    if ($resolvedOutput.Equals($targetDwg, [StringComparison]::OrdinalIgnoreCase)) { throw 'OWNED_SAVE_COPY_OUTPUT_EQUALS_WORKING' }
    if (Test-Path -LiteralPath $resolvedOutput) { throw 'OWNED_SAVE_COPY_OUTPUT_ALREADY_EXISTS' }
    $outputParent = Split-Path -Parent $resolvedOutput
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }

    # AutoCAD SAVE (unlike SAVEAS) writes an intermediate copy while keeping
    # the owned working drawing current.  This is the only reliable way to
    # checkpoint a T20 drawing whose DWG file is opened without read sharing.
    $outputForLisp = $resolvedOutput.Replace('\','/').Replace('"','\"')
    # SAVE is a document/file command.  T20/AutoCAD may silently ignore it
    # inside command-s's temporary command processor, so drive the exact
    # command-line protocol through the already-owned document COM queue.
    # This is the same interaction shape as a user entering SAVE and a path,
    # but it does not activate the window or take the physical mouse.
    $saveCopyCommand = `
        '(setq cx:*save-copy-filedia* (getvar "FILEDIA"))' + "`r" + `
        '(setvar "FILEDIA" 0)' + "`r" + `
        '_.SAVE' + "`r" + `
        '"' + $outputForLisp + '"' + "`r" + `
        '(setvar "FILEDIA" cx:*save-copy-filedia*)' + "`r"
    Send-OwnedComCommand -CommandText $saveCopyCommand

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastLength = -1L
    $stableSamples = 0
    do {
        Start-Sleep -Milliseconds 250
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'OWNED_SAVE_COPY_NOT_RESPONDING' }
        if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
            $length = (Get-Item -LiteralPath $resolvedOutput).Length
            if ($length -gt 0 -and $length -eq $lastLength) { $stableSamples++ } else { $stableSamples = 0 }
            $lastLength = $length
        }
    } while ((Get-Date) -lt $deadline -and $stableSamples -lt 2)
    if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) -or $stableSamples -lt 2) { throw 'OWNED_SAVE_COPY_WRITE_TIMEOUT' }

    $copyHash = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        target_dwg = $targetDwg; output_dwg = $resolvedOutput
        output_length = (Get-Item -LiteralPath $resolvedOutput).Length
        output_sha256 = $copyHash
        current_drawing_unchanged = $true
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'REGEN') {
    $regenApplication = Invoke-OwnedComRetry -Label 'REGEN_GET_APPLICATION' -Operation {
        [OwnedTzRotResolver]::GetActiveObject('AutoCAD.Application.24')
    }
    $regenHwnd = Invoke-OwnedComRetry -Label 'REGEN_GET_HWND' -Operation { [int64]$regenApplication.HWND }
    if ([int64]$regenHwnd -ne [int64]$mainWindow) { throw 'REGEN_COM_BOUND_TO_WRONG_OWNED_WINDOW' }
    $regenDocument = Invoke-OwnedComRetry -Label 'REGEN_GET_ACTIVE_DOCUMENT' -Operation { $regenApplication.ActiveDocument }
    $regenFullName = Invoke-OwnedComRetry -Label 'REGEN_GET_ACTIVE_DOCUMENT_PATH' -Operation { [string]$regenDocument.FullName }
    if (-not [string]::IsNullOrWhiteSpace($regenFullName) -and [IO.Path]::GetFileName($regenFullName) -cne $targetName) {
        throw 'REGEN_ACTIVE_DRAWING_MISMATCH'
    }
    Invoke-OwnedComRetry -Label 'REGEN_ALL_VIEWPORTS' -TimeoutSeconds ([Math]::Max(30, $TimeoutSeconds)) -Operation {
        $regenDocument.Regen(1)
        return $true
    } | Out-Null

    # AutoCAD may return from Regen while the display pipeline is still
    # settling.  Replace the former fixed 1.2-second guess with a bounded idle
    # proof: both CMDACTIVE and CMDNAMES must remain empty for ten consecutive
    # samples before the caller may consume its one screenshot.
    $regenDeadline = (Get-Date).AddSeconds([Math]::Max(5, $TimeoutSeconds))
    $regenIdleSamples = 0
    do {
        $regenCommandActive = Invoke-OwnedComRetry -Label 'REGEN_READ_CMDACTIVE' -Operation { [int]$regenDocument.GetVariable('CMDACTIVE') }
        $regenCommandNames = Invoke-OwnedComRetry -Label 'REGEN_READ_CMDNAMES' -Operation { [string]$regenDocument.GetVariable('CMDNAMES') }
        if ($regenCommandActive -eq 0 -and [string]::IsNullOrWhiteSpace($regenCommandNames)) {
            $regenIdleSamples++
        } else {
            $regenIdleSamples = 0
        }
        if ($regenIdleSamples -lt 10) { Start-Sleep -Milliseconds 100 }
    } while ($regenIdleSamples -lt 10 -and (Get-Date) -lt $regenDeadline)
    if ($regenIdleSamples -lt 10) {
        throw "REGEN_NOT_IDLE_BEFORE_CAPTURE=CMDACTIVE:$regenCommandActive;CMDNAMES:$regenCommandNames"
    }
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'REGEN_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        regen_mode = 'COM_DOCUMENT_REGEN_ALL_VIEWPORTS'
        idle_samples = $regenIdleSamples
        command_active = $regenCommandActive
        command_names = $regenCommandNames
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'SET_UCS_WORLD') {
    # Drawing geometry inventories and audit coordinates are WCS.  A saved
    # non-world UCS can otherwise make an otherwise valid zoom window appear
    # blank after reopen.  Keep this as an explicit view-only recovery action
    # rather than silently changing every established zoom call.
    Send-OwnedComCommand -CommandText "_.UCS`r_W`r"
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'SET_UCS_WORLD_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'SET_PLAN_WORLD') {
    # Reset the camera to the plan view of WCS.  A drawing can reopen with a
    # valid WCS but a stale view target/twist, producing a black model view
    # even though all database objects and grips remain intact.
    Send-OwnedComCommand -CommandText "_.PLAN`r_W`r"
    Start-Sleep -Milliseconds 1200
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'SET_PLAN_WORLD_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'RESTORE_ALL_LAYERS') {
    # Recovery is restricted to the owned isolated drawing.  Batch generation
    # may leave layers off/frozen when a process is closed between phases; on
    # reopen that looks like an empty drawing even though the database audit is
    # healthy.  Restore visibility without altering entity geometry.
    Send-OwnedComCommand -CommandText "_.-LAYER`r_ON`r*`r_THAW`r*`r_UNLOCK`r*`r`r"
    Start-Sleep -Milliseconds 1500
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'RESTORE_ALL_LAYERS_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'UNISOLATE_OBJECTS') {
    Send-OwnedComCommand -CommandText ('(progn (vl-catch-all-apply ''command-s (list "_.UNISOLATEOBJECTS")) (vl-catch-all-apply ''command-s (list "_.REGEN")) (princ))' + "`r")
    Start-Sleep -Milliseconds 1400
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'UNISOLATE_OBJECTS_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'ZOOM_EXTENTS') {
    Send-OwnedComCommand -CommandText "_.ZOOM`r_E`r"
    Start-Sleep -Milliseconds 1200
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'ZOOM_EXTENTS_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'ZOOM_WINDOW') {
    if ($MaxX -le $MinX -or $MaxY -le $MinY) { throw 'ZOOM_WINDOW_BOUNDS_INVALID' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $p1 = $MinX.ToString('R', $culture) + ',' + $MinY.ToString('R', $culture)
    $p2 = $MaxX.ToString('R', $culture) + ',' + $MaxY.ToString('R', $culture)
    [OwnedTzWhitelistBridge]::PostText($mdi, "_.ZOOM`r_W`r$p1`r$p2`r")
    Start-Sleep -Milliseconds 1200
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'ZOOM_WINDOW_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        min = $p1; max = $p2
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'ZOOM_WINDOW_COM') {
    if ($MaxX -le $MinX -or $MaxY -le $MinY) { throw 'ZOOM_WINDOW_COM_BOUNDS_INVALID' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $p1 = $MinX.ToString('R', $culture) + ',' + $MinY.ToString('R', $culture) + ',0'
    $p2 = $MaxX.ToString('R', $culture) + ',' + $MaxY.ToString('R', $culture) + ',0'
    $lisp = '(progn (vl-load-com) (vla-ZoomWindow (vlax-get-acad-object) (vlax-3d-point (list ' +
        $MinX.ToString('R', $culture) + ' ' + $MinY.ToString('R', $culture) + ' 0.0)) ' +
        '(vlax-3d-point (list ' + $MaxX.ToString('R', $culture) + ' ' + $MaxY.ToString('R', $culture) + ' 0.0))) ' +
        '(vla-Regen (vla-get-ActiveDocument (vlax-get-acad-object)) 1) (princ))' + "`r"
    Send-OwnedComCommand -CommandText $lisp
    Start-Sleep -Milliseconds 1600
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'ZOOM_WINDOW_COM_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId; min = $p1; max = $p2
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'RESET_VIEWPORT_TARGET') {
    if ($MaxX -le $MinX -or $MaxY -le $MinY) { throw 'RESET_VIEWPORT_TARGET_BOUNDS_INVALID' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'RESET_VIEWPORT_TARGET_REPORT_REQUIRED' }
    if (-not (Test-Path -LiteralPath $trustedViewportReset -PathType Leaf)) { throw 'TRUSTED_VIEWPORT_RESET_MISSING' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $centerX = ($MinX + $MaxX) / 2.0
    $centerY = ($MinY + $MaxY) / 2.0
    $viewHeight = $MaxY - $MinY
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'RESET_VIEWPORT_TARGET_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport -Force -ErrorAction SilentlyContinue
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'reset_owned_viewport_target.lsp'
    Copy-Item -LiteralPath $trustedViewportReset -Destination $stagedLisp -Force
    $reportForLisp = $resolvedReport.Replace('\','/')
    $lisp = '(progn ' +
        '(setq cx:*vp-report-path* "' + $reportForLisp + '" ' +
        'cx:*vp-center-x* ' + $centerX.ToString('R', $culture) + ' ' +
        'cx:*vp-center-y* ' + $centerY.ToString('R', $culture) + ' ' +
        'cx:*vp-height* ' + $viewHeight.ToString('R', $culture) + ') ' +
        '(load "C:/tmp/tianzheng_whitelist/reset_owned_viewport_target.lsp") (c:CXRESETOWNEDVIEWPORT))' + "`r"
    # View repair must use the same exact owned-document COM queue as the
    # proven native annotation actions.  Window-text delivery can be accepted
    # by the frame yet never reach the active drawing when Tianzheng is still
    # settling its MDI command target.
    Send-TrustedLspCommandCom -CommandText $lisp -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'RESET_VIEWPORT_TARGET_REPORT_TIMEOUT' }
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'RESET_VIEWPORT_TARGET_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        target = ($centerX.ToString('R', $culture) + ',' + $centerY.ToString('R', $culture) + ',0')
        view_height = $viewHeight; report = $resolvedReport; elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'NET_NATIVE_ANNO_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_NATIVE_ANNO_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_NATIVE_ANNO_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    if (Test-Path -LiteralPath $resolvedReport -PathType Leaf) { Remove-Item -LiteralPath $resolvedReport -Force }
    if (-not $SkipPluginLoad) {
        # Keep plugin loading and the report command on the exact owned
        # document's AutoCAD queue.  WM_CHAR/PostText is not reliable when the
        # owned Tianzheng window is visible but not foreground.
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripPlugin.Replace('\', '/')
        Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    Send-OwnedComCommand -CommandText ("CXNATIVEANNOINVENTORY`r" + $resolvedReport + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'NET_NATIVE_ANNO_REPORT_TIMEOUT' }
    Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 1)' + "`r")
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId; report = $resolvedReport
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'NET_NATIVE_ANNO_TEXT_AUDIT') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_NATIVE_ANNO_TEXT_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_NATIVE_ANNO_TEXT_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport,($resolvedReport + '.error.txt') -Force -ErrorAction SilentlyContinue
    if (-not $SkipPluginLoad) {
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripPlugin.Replace('\', '/')
        Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    # Keep this read-only audit on the same exact-document COM queue as the
    # proven grip inventory.  WM_CHAR delivery can be lost when the owned
    # Tianzheng window is temporarily not the foreground window.
    Send-OwnedComCommand -CommandText ("CXNATIVEANNOTEXTAUDIT`r" + $resolvedReport + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'NET_NATIVE_ANNO_TEXT_REPORT_TIMEOUT' }
    Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 1)' + "`r")
    $result = [pscustomobject]@{ status='PASS'; action=$Action; process_id=$ProcessId; report=$resolvedReport; elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds }
}
elseif ($Action -ceq 'NET_NATIVE_GRIP_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_NATIVE_GRIP_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_NATIVE_GRIP_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport,($resolvedReport + '.error.txt') -Force -ErrorAction SilentlyContinue
    if (-not $SkipPluginLoad) {
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripPlugin.Replace('\', '/')
        Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    Send-OwnedComCommand -CommandText ("CXNATIVEGRIPINVENTORY`r" + $resolvedReport + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'NET_NATIVE_GRIP_REPORT_TIMEOUT' }
    Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 1)' + "`r")
    $result = [pscustomobject]@{ status='PASS'; action=$Action; process_id=$ProcessId; report=$resolvedReport; elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds }
}
elseif ($Action -ceq 'NET_REFERENCE_POLYLINE_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedReferenceInventoryPlugin -PathType Leaf)) { throw 'TRUSTED_REFERENCE_INVENTORY_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_REFERENCE_POLYLINE_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_REFERENCE_POLYLINE_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    Remove-Item -LiteralPath $resolvedReport,($resolvedReport + '.error.txt') -Force -ErrorAction SilentlyContinue
    if (-not $SkipPluginLoad) {
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedReferenceInventoryPlugin.Replace('\','/')
        Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    Send-OwnedComCommand -CommandText ("CXREFERENCEPOLYINVENTORY`r" + $resolvedReport + "`r")
    $errorReport = $resolvedReport + '.error.txt'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and
           -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf) -and
           -not (Test-Path -LiteralPath $errorReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (Test-Path -LiteralPath $errorReport -PathType Leaf) {
        $pluginError = (Get-Content -LiteralPath $errorReport -Raw -Encoding UTF8).Trim()
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 1)' + "`r")
        throw ('NET_REFERENCE_POLYLINE_PLUGIN_ERROR=' + $pluginError)
    }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'NET_REFERENCE_POLYLINE_REPORT_TIMEOUT' }
    Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 1)' + "`r")
    $result = [pscustomobject]@{ status='PASS'; action=$Action; process_id=$ProcessId; report=$resolvedReport; elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds }
}
elseif ($Action -ceq 'NET_GRIP_TARGET_PROBE') {
    if (-not (Test-Path -LiteralPath $trustedGripTargetProbePlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_TARGET_PROBE_PLUGIN_MISSING' }
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'NET_GRIP_TARGET_HANDLE_INVALID' }
    if ([string]::IsNullOrWhiteSpace($PlanPath)) { throw 'NET_GRIP_TARGET_PLAN_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_GRIP_TARGET_REPORT_REQUIRED' }
    $resolvedPlan = [IO.Path]::GetFullPath($PlanPath)
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedPlan.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_GRIP_TARGET_PLAN_OUTSIDE_PROJECT' }
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_GRIP_TARGET_REPORT_OUTSIDE_PROJECT' }
    if (-not (Test-Path -LiteralPath $resolvedPlan -PathType Leaf)) { throw 'NET_GRIP_TARGET_PLAN_MISSING' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    if (Test-Path -LiteralPath $resolvedReport -PathType Leaf) { Remove-Item -LiteralPath $resolvedReport -Force }
    if (-not $SkipPluginLoad) {
        [OwnedTzWhitelistBridge]::PostText($mdi, '(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripTargetProbePlugin.Replace('\', '/')
        [OwnedTzWhitelistBridge]::PostText($mdi, '(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    $commandText = "CXGRIPTARGETPROBE`r" + $TargetHandle.ToUpperInvariant() + "`r" + $resolvedPlan + "`r" + $resolvedReport + "`r"
    [OwnedTzWhitelistBridge]::PostText($mdi, $commandText)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'NET_GRIP_TARGET_REPORT_TIMEOUT' }
    [OwnedTzWhitelistBridge]::PostText($mdi, '(setvar "SECURELOAD" 1)' + "`r")
    Start-Sleep -Milliseconds 300
    $reportText = Get-Content -LiteralPath $resolvedReport -Raw -Encoding UTF8
    $result = [pscustomobject]@{
        status = if ($reportText -match '(?m)^STATUS\tPASS\r?$') { 'PASS' } else { 'FAIL' }
        action = $Action
        process_id = $ProcessId
        target_handle = $TargetHandle.ToUpperInvariant()
        plan = $resolvedPlan
        report = $resolvedReport
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'NET_GRIP_AUDIT' -or $Action -ceq 'NET_GRIP_MOVE') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'NET_GRIP_TARGET_HANDLE_INVALID' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_GRIP_REPORT_PATH_REQUIRED' }
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_GRIP_REPORT_OUTSIDE_PROJECT' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    if (Test-Path -LiteralPath $resolvedReport -PathType Leaf) { Remove-Item -LiteralPath $resolvedReport -Force }

    if (-not $SkipPluginLoad) {
        [OwnedTzWhitelistBridge]::PostText($mdi, '(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripPlugin.Replace('\', '/')
        [OwnedTzWhitelistBridge]::PostText($mdi, '(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    if ($Action -ceq 'NET_GRIP_AUDIT') {
        $commandText = "CXGRIPAUDIT`r" + $TargetHandle.ToUpperInvariant() + "`r" + $resolvedReport + "`r"
    }
    else {
        if ($GripIndex -lt 0) { throw 'NET_GRIP_INDEX_REQUIRED' }
        $culture = [Globalization.CultureInfo]::InvariantCulture
        $commandText = "CXGRIPMOVE`r" + $TargetHandle.ToUpperInvariant() + "`r" + $GripIndex.ToString($culture) + "`r" + $MoveX.ToString('R', $culture) + "`r" + $MoveY.ToString('R', $culture) + "`r0`r" + $resolvedReport + "`r"
    }
    [OwnedTzWhitelistBridge]::PostText($mdi, $commandText)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $resolvedReport -PathType Leaf)) { throw 'NET_GRIP_REPORT_TIMEOUT' }
    [OwnedTzWhitelistBridge]::PostText($mdi, '(setvar "SECURELOAD" 1)' + "`r")
    Start-Sleep -Milliseconds 300
    $reportText = Get-Content -LiteralPath $resolvedReport -Raw -Encoding UTF8
    $result = [pscustomobject]@{
        status = if ($reportText -match '(?m)^STATUS\tPASS\r?$') { 'PASS' } else { 'FAIL' }
        action = $Action
        process_id = $ProcessId
        target_handle = $TargetHandle.ToUpperInvariant()
        grip_index = $GripIndex
        report = $resolvedReport
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'NET_GRIP_BATCH_MOVE') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath)) { throw 'NET_GRIP_BATCH_PLAN_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_GRIP_BATCH_REPORT_REQUIRED' }
    $resolvedPlan = [IO.Path]::GetFullPath($PlanPath)
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedPlan.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_GRIP_BATCH_PLAN_OUTSIDE_PROJECT' }
    if (-not $resolvedReport.StartsWith($trustedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'NET_GRIP_BATCH_REPORT_OUTSIDE_PROJECT' }
    if (-not (Test-Path -LiteralPath $resolvedPlan -PathType Leaf)) { throw 'NET_GRIP_BATCH_PLAN_MISSING' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    if (Test-Path -LiteralPath $resolvedReport -PathType Leaf) { Remove-Item -LiteralPath $resolvedReport -Force }
    $detailReport = Join-Path $reportParent (([IO.Path]::GetFileNameWithoutExtension($resolvedReport)) + '.details.tsv')
    if (Test-Path -LiteralPath $detailReport -PathType Leaf) { Remove-Item -LiteralPath $detailReport -Force }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    if (-not (Test-Path -LiteralPath $stageDirectory -PathType Container)) { New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null }
    $stagedPlan = Join-Path $stageDirectory 'grip_batch_plan.tsv'
    $stagedReport = 'C:\tmp\cx_grip_batch_move_summary.tsv'
    $stagedDetails = 'C:\tmp\cx_grip_batch_move_summary.details.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force
    Remove-Item -LiteralPath $stagedReport,$stagedDetails -Force -ErrorAction SilentlyContinue

    if (-not $SkipPluginLoad) {
        [OwnedTzWhitelistBridge]::PostText($mdi, '(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripPlugin.Replace('\', '/')
        [OwnedTzWhitelistBridge]::PostText($mdi, '(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    $commandText = "CXGRIPBATCHMOVE`r" + $stagedPlan + "`r" + $stagedReport + "`r"
    [OwnedTzWhitelistBridge]::PostText($mdi, $commandText)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $stagedReport -PathType Leaf)) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $stagedReport -PathType Leaf)) { throw 'NET_GRIP_BATCH_REPORT_TIMEOUT' }
    [OwnedTzWhitelistBridge]::PostText($mdi, '(setvar "SECURELOAD" 1)' + "`r")
    Start-Sleep -Milliseconds 300
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    Copy-Item -LiteralPath $stagedDetails -Destination $detailReport -Force
    $rows = Import-Csv -LiteralPath $resolvedReport -Delimiter "`t"
    $statusRow = @($rows | Where-Object { $_.KEY -ceq 'STATUS' })
    if ($statusRow.Count -ne 1) { throw 'NET_GRIP_BATCH_SUMMARY_INVALID' }
    $result = [pscustomobject]@{
        status = [string]$statusRow[0].VALUE
        action = $Action
        process_id = $ProcessId
        plan = $resolvedPlan
        report = $resolvedReport
        details = $detailReport
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'NET_GENERIC_GRIP_BATCH_MOVE') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_GENERIC_GRIP_PATH_REQUIRED' }
    $resolvedPlan = [IO.Path]::GetFullPath($PlanPath)
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedPlan.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedReport.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'NET_GENERIC_GRIP_OUTSIDE_PROJECT' }
    if (-not (Test-Path -LiteralPath $resolvedPlan -PathType Leaf)) { throw 'NET_GENERIC_GRIP_PLAN_MISSING' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedPlan = Join-Path $stageDirectory 'generic_grip_batch_plan.tsv'
    $stagedReport = 'C:\tmp\cx_generic_grip_batch_report.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force
    Remove-Item -LiteralPath $stagedReport,$resolvedReport -Force -ErrorAction SilentlyContinue
    if (-not $SkipPluginLoad) {
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedGripPlugin.Replace('\', '/')
        Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    Send-OwnedComCommand -CommandText ("CXGENERICGRIPBATCHMOVE`r" + $stagedPlan + "`r" + $stagedReport + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $stagedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $stagedReport -PathType Leaf)) { throw 'NET_GENERIC_GRIP_REPORT_TIMEOUT' }
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    $summary = @(Get-Content -LiteralPath $resolvedReport -Encoding UTF8 | Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
    $result = [pscustomobject]@{ status=if($summary -match '^SUMMARY\tPASS\t'){'PASS'}else{'FAIL'}; action=$Action; process_id=$ProcessId; plan=$resolvedPlan; report=$resolvedReport; elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds }
}
elseif ($Action -ceq 'NET_NATIVE_DIM_GRIP0_ENDPOINT_RESTORE') {
    if (-not (Test-Path -LiteralPath $trustedGrip0EndpointRestorePlugin -PathType Leaf)) { throw 'TRUSTED_GRIP0_ENDPOINT_RESTORE_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_GRIP0_ENDPOINT_RESTORE_PATH_REQUIRED' }
    $resolvedPlan=[IO.Path]::GetFullPath($PlanPath); $resolvedReport=[IO.Path]::GetFullPath($ReportPath)
    $trustedRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if(-not $resolvedPlan.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedReport.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'NET_GRIP0_ENDPOINT_RESTORE_OUTSIDE_PROJECT'}
    if(-not(Test-Path -LiteralPath $resolvedPlan -PathType Leaf)){throw 'NET_GRIP0_ENDPOINT_RESTORE_PLAN_MISSING'}
    $reportParent=Split-Path -Parent $resolvedReport; if(-not(Test-Path -LiteralPath $reportParent -PathType Container)){New-Item -ItemType Directory -Path $reportParent -Force|Out-Null}
    $stageDirectory='C:\tmp\tianzheng_whitelist'; New-Item -ItemType Directory -Path $stageDirectory -Force|Out-Null
    $stagedPlan=Join-Path $stageDirectory 'native_dim_grip0_endpoint_restore_plan.tsv'; $stagedReport='C:\tmp\cx_native_dim_grip0_endpoint_restore_report.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force; Remove-Item -LiteralPath $stagedReport,$resolvedReport -Force -ErrorAction SilentlyContinue
    Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r"); Start-Sleep -Milliseconds 400
    $pluginForLisp=$trustedGrip0EndpointRestorePlugin.Replace('\','/'); Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "'+$pluginForLisp+'")'+"`r"); Start-Sleep -Milliseconds 1200
    Send-OwnedComCommand -CommandText ("CXNATIVEDIMGRIP0ENDPOINTRESTORE`r"+$stagedPlan+"`r"+$stagedReport+"`r")
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds); while((Get-Date)-lt $deadline -and -not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){throw 'NET_GRIP0_ENDPOINT_RESTORE_REPORT_TIMEOUT'}
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    $summary=@(Get-Content -LiteralPath $resolvedReport -Encoding UTF8|Where-Object{$_.StartsWith("SUMMARY`t",[StringComparison]::Ordinal)})
    $result=[pscustomobject]@{status=if($summary -match '^SUMMARY\tPASS\t'){'PASS'}else{'FAIL'};action=$Action;process_id=$ProcessId;plan=$resolvedPlan;report=$resolvedReport;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds}
}
elseif ($Action -ceq 'NET_NATIVE_DIM_DUAL_GRIP_MOVE') {
    if (-not (Test-Path -LiteralPath $trustedDualGripPlugin -PathType Leaf)) { throw 'TRUSTED_DUAL_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_DUAL_GRIP_PATH_REQUIRED' }
    $resolvedPlan=[IO.Path]::GetFullPath($PlanPath); $resolvedReport=[IO.Path]::GetFullPath($ReportPath)
    $trustedRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if(-not $resolvedPlan.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedReport.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'NET_DUAL_GRIP_OUTSIDE_PROJECT'}
    if(-not(Test-Path -LiteralPath $resolvedPlan -PathType Leaf)){throw 'NET_DUAL_GRIP_PLAN_MISSING'}
    $reportParent=Split-Path -Parent $resolvedReport; if(-not(Test-Path -LiteralPath $reportParent -PathType Container)){New-Item -ItemType Directory -Path $reportParent -Force|Out-Null}
    $stageDirectory='C:\tmp\tianzheng_whitelist'; New-Item -ItemType Directory -Path $stageDirectory -Force|Out-Null
    $stagedPlan=Join-Path $stageDirectory 'native_dim_dual_grip_plan.tsv'; $stagedReport='C:\tmp\cx_native_dim_dual_grip_report.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force; Remove-Item -LiteralPath $stagedReport,$resolvedReport -Force -ErrorAction SilentlyContinue
    Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r"); Start-Sleep -Milliseconds 400
    $pluginForLisp=$trustedDualGripPlugin.Replace('\','/'); Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "'+$pluginForLisp+'")'+"`r"); Start-Sleep -Milliseconds 1200
    Send-OwnedComCommand -CommandText ("CXNATIVEDIMDUALGRIPMOVE`r"+$stagedPlan+"`r"+$stagedReport+"`r")
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds); while((Get-Date)-lt $deadline -and -not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){throw 'NET_DUAL_GRIP_REPORT_TIMEOUT'}
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    $summary=@(Get-Content -LiteralPath $resolvedReport -Encoding UTF8|Where-Object{$_.StartsWith("SUMMARY`t",[StringComparison]::Ordinal)})
    $result=[pscustomobject]@{status=if($summary -match '^SUMMARY\tPASS\t'){'PASS'}else{'FAIL'};action=$Action;process_id=$ProcessId;plan=$resolvedPlan;report=$resolvedReport;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds}
}
elseif ($Action -ceq 'NET_NATIVE_DIM_ENDPOINT_REPAIR') {
    if (-not (Test-Path -LiteralPath $trustedEndpointRepairPlugin -PathType Leaf)) { throw 'TRUSTED_ENDPOINT_REPAIR_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_NATIVE_DIM_ENDPOINT_REPAIR_PATH_REQUIRED' }
    $resolvedPlan = [IO.Path]::GetFullPath($PlanPath)
    $resolvedReport = [IO.Path]::GetFullPath($ReportPath)
    $trustedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedPlan.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedReport.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'NET_NATIVE_DIM_ENDPOINT_REPAIR_OUTSIDE_PROJECT' }
    if (-not (Test-Path -LiteralPath $resolvedPlan -PathType Leaf)) { throw 'NET_NATIVE_DIM_ENDPOINT_REPAIR_PLAN_MISSING' }
    $reportParent = Split-Path -Parent $resolvedReport
    if (-not (Test-Path -LiteralPath $reportParent -PathType Container)) { New-Item -ItemType Directory -Path $reportParent -Force | Out-Null }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedPlan = Join-Path $stageDirectory 'native_dim_endpoint_repair_plan.tsv'
    $stagedReport = 'C:\tmp\cx_native_dim_endpoint_repair_report.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force
    Remove-Item -LiteralPath $stagedReport,$resolvedReport -Force -ErrorAction SilentlyContinue
    if (-not $SkipPluginLoad) {
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r")
        Start-Sleep -Milliseconds 400
        $pluginForLisp = $trustedEndpointRepairPlugin.Replace('\', '/')
        Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "' + $pluginForLisp + '")' + "`r")
        Start-Sleep -Milliseconds 1200
    }
    Send-OwnedComCommand -CommandText ("CXNATIVEDIMENDPOINTREPAIR`r" + $stagedPlan + "`r" + $stagedReport + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $stagedReport -PathType Leaf)) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $stagedReport -PathType Leaf)) { throw 'NET_NATIVE_DIM_ENDPOINT_REPAIR_REPORT_TIMEOUT' }
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    $summary = @(Get-Content -LiteralPath $resolvedReport -Encoding UTF8 | Where-Object { $_.StartsWith("SUMMARY`t", [StringComparison]::Ordinal) })
    $result = [pscustomobject]@{ status=if($summary -match '^SUMMARY\tPASS\t'){'PASS'}else{'FAIL'}; action=$Action; process_id=$ProcessId; plan=$resolvedPlan; report=$resolvedReport; elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds }
}
elseif ($Action -ceq 'NET_NATIVE_DIM_GRIP_RESPONSE_PROBE') {
    if (-not (Test-Path -LiteralPath $trustedEndpointRepairPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_RESPONSE_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_NATIVE_DIM_GRIP_RESPONSE_PATH_REQUIRED' }
    $resolvedPlan=[IO.Path]::GetFullPath($PlanPath); $resolvedReport=[IO.Path]::GetFullPath($ReportPath)
    $trustedRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if(-not $resolvedPlan.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedReport.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'NET_NATIVE_DIM_GRIP_RESPONSE_OUTSIDE_PROJECT'}
    if(-not(Test-Path -LiteralPath $resolvedPlan -PathType Leaf)){throw 'NET_NATIVE_DIM_GRIP_RESPONSE_PLAN_MISSING'}
    $reportParent=Split-Path -Parent $resolvedReport; if(-not(Test-Path -LiteralPath $reportParent -PathType Container)){New-Item -ItemType Directory -Path $reportParent -Force|Out-Null}
    $stageDirectory='C:\tmp\tianzheng_whitelist'; New-Item -ItemType Directory -Path $stageDirectory -Force|Out-Null
    $stagedPlan=Join-Path $stageDirectory 'native_dim_grip_response_plan.tsv'; $stagedReport='C:\tmp\cx_native_dim_grip_response_report.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force; Remove-Item -LiteralPath $stagedReport,$resolvedReport -Force -ErrorAction SilentlyContinue
    if(-not $SkipPluginLoad){
        Send-OwnedComCommand -CommandText ('(setvar "SECURELOAD" 0)' + "`r"); Start-Sleep -Milliseconds 400
        $pluginForLisp=$trustedEndpointRepairPlugin.Replace('\','/'); Send-OwnedComCommand -CommandText ('(command "_.NETLOAD" "'+$pluginForLisp+'")'+"`r"); Start-Sleep -Milliseconds 1200
    }
    Send-OwnedComCommand -CommandText ("CXNATIVEDIMGRIPRESPONSEPROBE`r"+$stagedPlan+"`r"+$stagedReport+"`r")
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds); while((Get-Date)-lt $deadline -and -not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){throw 'NET_NATIVE_DIM_GRIP_RESPONSE_REPORT_TIMEOUT'}
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    $summary=@(Get-Content -LiteralPath $resolvedReport -Encoding UTF8|Where-Object{$_.StartsWith("SUMMARY`t",[StringComparison]::Ordinal)})
    $result=[pscustomobject]@{status=if($summary -match '^SUMMARY\tPASS\t'){'PASS'}else{'FAIL'};action=$Action;process_id=$ProcessId;plan=$resolvedPlan;report=$resolvedReport;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds}
}
elseif ($Action -ceq 'NET_NATIVE_CLONE_TRANSLATE') {
    if (-not (Test-Path -LiteralPath $trustedGripPlugin -PathType Leaf)) { throw 'TRUSTED_GRIP_PLUGIN_MISSING' }
    if ([string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($ReportPath)) { throw 'NET_NATIVE_CLONE_PATH_REQUIRED' }
    $resolvedPlan=[IO.Path]::GetFullPath($PlanPath); $resolvedReport=[IO.Path]::GetFullPath($ReportPath)
    $trustedRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if(-not $resolvedPlan.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase) -or -not $resolvedReport.StartsWith($trustedRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'NET_NATIVE_CLONE_OUTSIDE_PROJECT'}
    if(-not(Test-Path -LiteralPath $resolvedPlan -PathType Leaf)){throw 'NET_NATIVE_CLONE_PLAN_MISSING'}
    $stageDirectory='C:\tmp\tianzheng_whitelist'; New-Item -ItemType Directory -Path $stageDirectory -Force|Out-Null
    $stagedPlan=Join-Path $stageDirectory 'native_clone_translate_plan.tsv'; $stagedReport='C:\tmp\cx_native_clone_translate.tsv'
    Copy-Item -LiteralPath $resolvedPlan -Destination $stagedPlan -Force; Remove-Item -LiteralPath $stagedReport,$resolvedReport -Force -ErrorAction SilentlyContinue
    if(-not $SkipPluginLoad){[OwnedTzWhitelistBridge]::PostText($mdi,'(setvar "SECURELOAD" 0)' + "`r");Start-Sleep -Milliseconds 400;$pluginForLisp=$trustedGripPlugin.Replace('\','/');[OwnedTzWhitelistBridge]::PostText($mdi,'(command "_.NETLOAD" "'+$pluginForLisp+'")'+"`r");Start-Sleep -Milliseconds 1200}
    [OwnedTzWhitelistBridge]::PostText($mdi,"CXNATIVECLONETRANSLATE`r"+$stagedPlan+"`r"+$stagedReport+"`r")
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds);while((Get-Date)-lt $deadline -and -not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){Start-Sleep -Milliseconds 100}
    if(-not(Test-Path -LiteralPath $stagedReport -PathType Leaf)){throw 'NET_NATIVE_CLONE_TIMEOUT'}
    Copy-Item -LiteralPath $stagedReport -Destination $resolvedReport -Force
    $summary=@(Get-Content -LiteralPath $resolvedReport -Encoding UTF8|Where-Object{$_.StartsWith("SUMMARY`t",[StringComparison]::Ordinal)})
    $result=[pscustomobject]@{status=if($summary -match '^SUMMARY\tPASS\t'){'PASS'}else{'FAIL'};action=$Action;process_id=$ProcessId;plan=$resolvedPlan;report=$resolvedReport;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds}
}
elseif ($Action -ceq 'START_ADJUST_COMMAND') {
    [OwnedTzWhitelistBridge]::PostText($mdi, $ProbeCommand + "`r")
    Start-Sleep -Milliseconds 600
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'START_ADJUST_COMMAND_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        command = $ProbeCommand
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'SELECT_TARGET_HANDLE') {
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'SELECT_TARGET_HANDLE_INVALID' }
    [OwnedTzWhitelistBridge]::PostText($mdi, '(handent "' + $TargetHandle.ToUpperInvariant() + '")' + "`r`r")
    Start-Sleep -Milliseconds 600
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'SELECT_TARGET_HANDLE_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        target_handle = $TargetHandle.ToUpperInvariant()
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'PRESELECT_TARGET_HANDLE') {
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'PRESELECT_TARGET_HANDLE_INVALID' }
    [OwnedTzWhitelistBridge]::PostText($mdi, '(sssetfirst nil (ssadd (handent "' + $TargetHandle.ToUpperInvariant() + '")))' + "`r")
    Start-Sleep -Milliseconds 600
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'PRESELECT_TARGET_HANDLE_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        target_handle = $TargetHandle.ToUpperInvariant()
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'RECOVER_BATCH_VIEW') {
    [OwnedTzWhitelistBridge]::PostText($mdi, '(progn (if (and (boundp ''cx:*fb-layer-snapshot*) cx:*fb-layer-snapshot*) (cx:fb-restore-layers cx:*fb-layer-snapshot*)) (setq cx:*fb-layer-snapshot* nil) (command-s "_.REGEN") (princ))' + "`r")
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'RECOVER_BATCH_VIEW_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'FINISH_PROMPT') {
    [OwnedTzWhitelistBridge]::PostText($mdi, "`r")
    Start-Sleep -Milliseconds 500
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'FINISH_POINT') {
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $pointText = $MoveX.ToString('R', $culture) + ',' + $MoveY.ToString('R', $culture)
    [OwnedTzWhitelistBridge]::PostText($mdi, $pointText + "`r")
    Start-Sleep -Milliseconds 500
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        point = $pointText; elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'CANCEL_ACTIVE') {
    1..3 | ForEach-Object {
        [OwnedTzWhitelistBridge]::PostVirtualKey($mdi, 0x1B)
        Start-Sleep -Milliseconds 250
    }
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'FOCUS_TDIMARC_TEST') {
    [OwnedTzWhitelistBridge]::PostText($mdi, "_.ZOOM`r_W`r40431360,2875440`r40431475,2875490`r")
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'FOCUS_TDIMARC_TEST_NOT_RESPONDING' }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'ROUTE_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedInventory -PathType Leaf)) { throw 'TRUSTED_INVENTORY_MISSING' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'inventory_route_centerlines_fast.lsp'
    Copy-Item -LiteralPath $trustedInventory -Destination $stagedLisp -Force
    $output = 'C:\tmp\route_centerlines_fast.tsv'
    $probe = 'C:\tmp\route_centerlines_fast_probe.tsv'
    $command = '(progn (load "C:/tmp/tianzheng_whitelist/inventory_route_centerlines_fast.lsp") (c:CXROUTEFASTINVENTORY))' + "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $probeItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $probeItem = Get-Item -LiteralPath $probe -ErrorAction SilentlyContinue
        if ($probeItem -and $probeItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $probeItem -or $probeItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'INVENTORY_TIMEOUT' }
    $probeRows = @(Import-Csv -LiteralPath $probe -Delimiter "`t")
    if ($probeRows.Count -ne 1 -or $probeRows[0].STATUS -cne 'PASS') { throw 'INVENTORY_PROBE_FAILED' }
    if ([int]$probeRows[0].DBMOD_BEFORE -ne [int]$probeRows[0].DBMOD_AFTER) { throw 'INVENTORY_CHANGED_DBMOD' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $output -Destination (Join-Path $ReportDirectory 'route_centerlines_fast.tsv') -Force
        Copy-Item -LiteralPath $probe -Destination (Join-Path $ReportDirectory 'route_centerlines_fast_probe.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        scanned = [int]$probeRows[0].SCANNED
        layer_matched = [int]$probeRows[0].LAYER_MATCHED
        arc_candidates = [int]$probeRows[0].ARC_CANDIDATES
        cad_elapsed_ms = [int]$probeRows[0].ELAPSED_MS
        dbmod_before = [int]$probeRows[0].DBMOD_BEFORE
        dbmod_after = [int]$probeRows[0].DBMOD_AFTER
    }
}
elseif ($Action -ceq 'TARGET_SEGMENT_GEOMETRY_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedTargetSegmentInventory -PathType Leaf)) { throw 'TRUSTED_TARGET_SEGMENT_INVENTORY_MISSING' }
    $handles = @($TargetHandles -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -lt 1 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) {
        throw 'TARGET_SEGMENT_INVENTORY_HANDLES_INVALID'
    }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'inventory_target_polyline_segments.lsp'
    Copy-Item -LiteralPath $trustedTargetSegmentInventory -Destination $stagedLisp -Force
    $detailsPath = 'C:\tmp\cx_target_polyline_segments.tsv'
    $summaryPath = 'C:\tmp\cx_target_polyline_segments_summary.tsv'
    Remove-Item -LiteralPath $detailsPath,$summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $lispHandles = '(list ' + (($handles | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ')'
    $command = @(
        '(setq cx:*segment-inventory-target-handles* ' + $lispHandles + ')'
        '(setq cx:*segment-inventory-expected-drawing* "' + $expectedDrawing + '")'
        '(setq cx:*segment-inventory-details-path* "C:/tmp/cx_target_polyline_segments.tsv")'
        '(setq cx:*segment-inventory-summary-path* "C:/tmp/cx_target_polyline_segments_summary.tsv")'
        '(load "C:/tmp/tianzheng_whitelist/inventory_target_polyline_segments.lsp")'
    ) -join "`r"
    $command += "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'TARGET_SEGMENT_INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'TARGET_SEGMENT_INVENTORY_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
    if ($summaryRows.Count -ne 1 -or $summaryRows[0].STATUS -cne 'PASS') { throw 'TARGET_SEGMENT_INVENTORY_FAILED' }
    if ([int]$summaryRows[0].DBMOD_BEFORE -ne [int]$summaryRows[0].DBMOD_AFTER) { throw 'TARGET_SEGMENT_INVENTORY_CHANGED_DBMOD' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'target_polyline_segments.tsv') -Force
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'target_polyline_segments_summary.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        target_count = [int]$summaryRows[0].TARGET_COUNT
        segment_count = [int]$summaryRows[0].SEGMENT_COUNT
        arc_count = [int]$summaryRows[0].ARC_COUNT
        line_count = [int]$summaryRows[0].LINE_COUNT
        degenerate_count = if ($null -ne $summaryRows[0].DEGENERATE_COUNT) { [int]$summaryRows[0].DEGENERATE_COUNT } else { 0 }
        dimensionable_segment_count = if ($null -ne $summaryRows[0].DIMENSIONABLE_SEGMENT_COUNT) { [int]$summaryRows[0].DIMENSIONABLE_SEGMENT_COUNT } else { [int]$summaryRows[0].SEGMENT_COUNT }
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        dbmod_before = [int]$summaryRows[0].DBMOD_BEFORE
        dbmod_after = [int]$summaryRows[0].DBMOD_AFTER
    }
}
elseif ($Action -ceq 'TARGET_ARC_GEOMETRY_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedTargetArcInventory -PathType Leaf)) { throw 'TRUSTED_TARGET_ARC_INVENTORY_MISSING' }
    $handles = @($TargetHandles -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -lt 1 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) {
        throw 'TARGET_ARC_INVENTORY_HANDLES_INVALID'
    }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'inventory_target_polyline_arcs.lsp'
    Copy-Item -LiteralPath $trustedTargetArcInventory -Destination $stagedLisp -Force
    $detailsPath = 'C:\tmp\cx_target_polyline_arcs.tsv'
    $summaryPath = 'C:\tmp\cx_target_polyline_arcs_summary.tsv'
    Remove-Item -LiteralPath $detailsPath,$summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $lispHandles = '(list ' + (($handles | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ')'
    # Queue one complete expression per command line.  T20 V10's command-line
    # reader rejects the equivalent long PROGN expression in this drawing,
    # while the same SETQ expressions execute correctly one by one through the
    # native AutoCAD command queue.
    $command = @(
        '(setq cx:*arc-inventory-target-handles* ' + $lispHandles + ')'
        '(setq cx:*arc-inventory-expected-drawing* "' + $expectedDrawing + '")'
        '(setq cx:*arc-inventory-details-path* "C:/tmp/cx_target_polyline_arcs.tsv")'
        '(setq cx:*arc-inventory-summary-path* "C:/tmp/cx_target_polyline_arcs_summary.tsv")'
        '(load "C:/tmp/tianzheng_whitelist/inventory_target_polyline_arcs.lsp")'
    ) -join "`r"
    $command += "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'TARGET_ARC_INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'TARGET_ARC_INVENTORY_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
    if ($summaryRows.Count -ne 1 -or $summaryRows[0].STATUS -cne 'PASS') { throw 'TARGET_ARC_INVENTORY_FAILED' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'target_polyline_arcs.tsv') -Force
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'target_polyline_arcs_summary.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        target_count = [int]$summaryRows[0].TARGET_COUNT
        arc_count = [int]$summaryRows[0].ARC_COUNT
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'EARTHWORK_ELEVATION_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedEarthworkInventory -PathType Leaf)) { throw 'TRUSTED_EARTHWORK_INVENTORY_MISSING' }
    $targetDirectory = Split-Path -Parent ([string]$owner.target_dwg)
    $entityPath = Join-Path $targetDirectory 'earthwork_elevation_entities_fast.tsv'
    $attributePath = Join-Path $targetDirectory 'earthwork_elevation_attributes_fast.tsv'
    $donePath = Join-Path $targetDirectory 'earthwork_elevation_inventory_fast.done'
    Remove-Item -LiteralPath $entityPath,$attributePath,$donePath -Force -ErrorAction SilentlyContinue
    $trustedSource = Get-Content -LiteralPath $trustedEarthworkInventory -Raw -Encoding UTF8
    if ($trustedSource -match '[^\x00-\x7F]') { throw 'TRUSTED_EARTHWORK_INVENTORY_MUST_BE_ASCII' }
    $inlineSource = ($trustedSource -replace '[\r\n]+',' ')
    $command = '(progn ' + $inlineSource + ' (c:CXEWFAST))' + "`r"
    [OwnedTzWhitelistBridge]::PostText($mdi, $command)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $doneItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $doneItem = Get-Item -LiteralPath $donePath -ErrorAction SilentlyContinue
        if ($doneItem -and $doneItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'EARTHWORK_INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $doneItem -or $doneItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'EARTHWORK_INVENTORY_TIMEOUT' }
    foreach ($required in @($entityPath,$attributePath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "EARTHWORK_INVENTORY_OUTPUT_MISSING=$required" }
    }
    $doneFields = (Get-Content -LiteralPath $donePath -Raw -Encoding Default).Trim() -split "`t"
    if ($doneFields.Count -lt 7 -or $doneFields[0] -cne 'OK' -or $doneFields[3] -cne 'DBMOD_BEFORE' -or $doneFields[5] -cne 'DBMOD_AFTER') { throw 'EARTHWORK_INVENTORY_DONE_INVALID' }
    if ([int]$doneFields[4] -ne [int]$doneFields[6]) { throw "EARTHWORK_INVENTORY_CHANGED_DBMOD=$($doneFields[4]):$($doneFields[6])" }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $entityPath -Destination (Join-Path $ReportDirectory 'earthwork_elevation_entities_fast.tsv') -Force
        Copy-Item -LiteralPath $attributePath -Destination (Join-Path $ReportDirectory 'earthwork_elevation_attributes_fast.tsv') -Force
        Copy-Item -LiteralPath $donePath -Destination (Join-Path $ReportDirectory 'earthwork_elevation_inventory_fast.done') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        scanned = [int]$doneFields[2]
        dbmod_before = [int]$doneFields[4]
        dbmod_after = [int]$doneFields[6]
        entity_report = $entityPath
        attribute_report = $attributePath
    }
}
elseif ($Action -ceq 'NET_EARTHWORK_LOAD') {
    if (-not (Test-Path -LiteralPath $trustedEarthworkPlugin -PathType Leaf)) { throw 'TRUSTED_EARTHWORK_PLUGIN_MISSING' }
    [OwnedTzWhitelistBridge]::PostText($mdi, "_.NETLOAD`r")
    Start-Sleep -Milliseconds 700
    $result = [pscustomobject]@{
        status = 'POSTED'; action = $Action; process_id = $ProcessId
        trusted_plugin = $trustedEarthworkPlugin
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
    }
}
elseif ($Action -ceq 'NET_EARTHWORK_INVENTORY') {
    if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { throw 'EARTHWORK_REPORT_DIRECTORY_REQUIRED' }
    $resolvedDirectory = [IO.Path]::GetFullPath($ReportDirectory)
    New-Item -ItemType Directory -Path $resolvedDirectory -Force | Out-Null
    $donePath = Join-Path $resolvedDirectory 'earthwork_elevation_inventory_net.done'
    $entityPath = Join-Path $resolvedDirectory 'earthwork_elevation_entities_net.tsv'
    $attributePath = Join-Path $resolvedDirectory 'earthwork_elevation_attributes_net.tsv'
    $classPath = Join-Path $resolvedDirectory 'earthwork_elevation_classes_net.tsv'
    foreach ($path in @($donePath,$entityPath,$attributePath,$classPath)) {
        if (Test-Path -LiteralPath $path) { throw "EARTHWORK_NET_OUTPUT_ALREADY_EXISTS=$path" }
    }
    [OwnedTzWhitelistBridge]::PostText($mdi, "CXEWINVENTORYNET`r" + $resolvedDirectory + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $doneItem = $null
    do {
        Start-Sleep -Milliseconds 100
        $doneItem = Get-Item -LiteralPath $donePath -ErrorAction SilentlyContinue
        if ($doneItem -and $doneItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'EARTHWORK_NET_INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $doneItem -or $doneItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'EARTHWORK_NET_INVENTORY_TIMEOUT' }
    foreach ($path in @($entityPath,$attributePath,$classPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "EARTHWORK_NET_OUTPUT_MISSING=$path" }
    }
    $doneFields = (Get-Content -LiteralPath $donePath -Raw -Encoding UTF8).Trim() -split "`t"
    if ($doneFields.Count -lt 2 -or $doneFields[0] -cne 'STATUS' -or $doneFields[1] -cne 'PASS') {
        throw "EARTHWORK_NET_INVENTORY_FAILED=$($doneFields -join '|')"
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        done = $donePath; entity_report = $entityPath; attribute_report = $attributePath; class_report = $classPath
        details = ($doneFields -join '|')
    }
}
elseif ($Action -ceq 'NET_EARTHWORK_BATCH_INVENTORY') {
    if ([string]::IsNullOrWhiteSpace($TaskSpecPath)) { throw 'EARTHWORK_BATCH_MANIFEST_REQUIRED' }
    $resolvedManifest = [IO.Path]::GetFullPath($TaskSpecPath)
    if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) { throw 'EARTHWORK_BATCH_MANIFEST_MISSING' }
    $rows = @(Import-Csv -LiteralPath $resolvedManifest -Delimiter "`t" -Encoding UTF8)
    if ($rows.Count -lt 1) { throw 'EARTHWORK_BATCH_MANIFEST_EMPTY' }
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace($row.INPUT_DWG) -or -not (Test-Path -LiteralPath $row.INPUT_DWG -PathType Leaf)) {
            throw 'EARTHWORK_BATCH_INPUT_MISSING'
        }
        if ([string]::IsNullOrWhiteSpace($row.REPORT_DIRECTORY)) { throw 'EARTHWORK_BATCH_REPORT_DIRECTORY_MISSING' }
        $done = Join-Path ([IO.Path]::GetFullPath($row.REPORT_DIRECTORY)) 'earthwork_elevation_inventory_net.done'
        if (Test-Path -LiteralPath $done) { throw "EARTHWORK_BATCH_OUTPUT_ALREADY_EXISTS=$done" }
    }
    [OwnedTzWhitelistBridge]::PostText($mdi, "CXEWBATCHINVENTORYNET`r" + $resolvedManifest + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 100
        $complete = @($rows | Where-Object {
            $done = Join-Path ([IO.Path]::GetFullPath($_.REPORT_DIRECTORY)) 'earthwork_elevation_inventory_net.done'
            Test-Path -LiteralPath $done -PathType Leaf
        }).Count
        if ($complete -eq $rows.Count) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'EARTHWORK_BATCH_INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if ($complete -ne $rows.Count) { throw "EARTHWORK_BATCH_INVENTORY_TIMEOUT=$complete/$($rows.Count)" }
    $details = @()
    foreach ($row in $rows) {
        $done = Join-Path ([IO.Path]::GetFullPath($row.REPORT_DIRECTORY)) 'earthwork_elevation_inventory_net.done'
        $content = Get-Content -LiteralPath $done -Raw -Encoding UTF8
        if ($content -notmatch '^STATUS\tPASS\t') { throw "EARTHWORK_BATCH_INVENTORY_FAILED=$done" }
        $details += $content.Trim()
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        completed = $rows.Count; manifest = $resolvedManifest
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        details = $details
    }
}
elseif ($Action -ceq 'NET_EARTHWORK_RESTORE') {
    if ([string]::IsNullOrWhiteSpace($TaskSpecPath)) { throw 'EARTHWORK_RESTORE_MANIFEST_REQUIRED' }
    $resolvedManifest = [IO.Path]::GetFullPath($TaskSpecPath)
    if (-not (Test-Path -LiteralPath $resolvedManifest -PathType Leaf)) { throw 'EARTHWORK_RESTORE_MANIFEST_MISSING' }
    $rows = @(Import-Csv -LiteralPath $resolvedManifest -Delimiter "`t" -Encoding UTF8)
    if ($rows.Count -lt 1) { throw 'EARTHWORK_RESTORE_MANIFEST_EMPTY' }
    foreach ($row in $rows) {
        if (-not (Test-Path -LiteralPath $row.INPUT_DWG -PathType Leaf)) { throw 'EARTHWORK_RESTORE_INPUT_MISSING' }
        if (Test-Path -LiteralPath $row.OUTPUT_DWG) { throw "EARTHWORK_RESTORE_OUTPUT_ALREADY_EXISTS=$($row.OUTPUT_DWG)" }
        $done = Join-Path ([IO.Path]::GetFullPath($row.REPORT_DIRECTORY)) 'earthwork_elevation_restore.done'
        if (Test-Path -LiteralPath $done) { throw "EARTHWORK_RESTORE_REPORT_ALREADY_EXISTS=$done" }
    }
    [OwnedTzWhitelistBridge]::PostText($mdi, "CXEWRESTORENET`r" + $resolvedManifest + "`r")
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 100
        $complete = @($rows | Where-Object {
            $done = Join-Path ([IO.Path]::GetFullPath($_.REPORT_DIRECTORY)) 'earthwork_elevation_restore.done'
            Test-Path -LiteralPath $done -PathType Leaf
        }).Count
        if ($complete -eq $rows.Count) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'EARTHWORK_RESTORE_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if ($complete -ne $rows.Count) { throw "EARTHWORK_RESTORE_TIMEOUT=$complete/$($rows.Count)" }
    $details = @()
    foreach ($row in $rows) {
        $done = Join-Path ([IO.Path]::GetFullPath($row.REPORT_DIRECTORY)) 'earthwork_elevation_restore.done'
        $content = Get-Content -LiteralPath $done -Raw -Encoding UTF8
        if ($content -notmatch '^STATUS\tPASS') { throw "EARTHWORK_RESTORE_FAILED=$done" }
        $details += $content.Trim()
    }
    $result = [pscustomobject]@{
        status = 'PASS'; action = $Action; process_id = $ProcessId
        completed = $rows.Count; manifest = $resolvedManifest
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        details = $details
    }
}
elseif ($Action -ceq 'TMIRDIM_ONE' -or $Action -ceq 'TMOVE_VECTOR_ONE') {
    if (-not (Test-Path -LiteralPath $trustedAdjustProbe -PathType Leaf)) { throw 'TRUSTED_ADJUST_PROBE_MISSING' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'tdimarc_native_adjust_probe.lsp'
    Copy-Item -LiteralPath $trustedAdjustProbe -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_tdimarc_adjust_summary.tsv'
    $detailsPath = 'C:\tmp\cx_tdimarc_adjust_details.tsv'
    Remove-Item -LiteralPath $summaryPath,$detailsPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'TDIMARC_ADJUST_TARGET_HANDLE_INVALID' }
    if ($Action -ceq 'TMOVE_VECTOR_ONE' -and [Math]::Abs($MoveX) -lt 1e-9 -and [Math]::Abs($MoveY) -lt 1e-9) {
        throw 'TMOVE_VECTOR_IS_ZERO'
    }
    $mode = if ($Action -ceq 'TMIRDIM_ONE') { 'MIRROR' } else { 'MOVE_VECTOR' }
    $moveXInvariant = $MoveX.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    $moveYInvariant = $MoveY.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    $command = '(progn ' +
        '(setq cx:*adjust-target-handle* "' + $TargetHandle.ToUpperInvariant() + '") ' +
        '(setq cx:*adjust-mode* "' + $mode + '") ' +
        '(setq cx:*adjust-move-x* ' + $moveXInvariant + ') ' +
        '(setq cx:*adjust-move-y* ' + $moveYInvariant + ') ' +
        '(setq cx:*adjust-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*adjust-summary-path* "C:/tmp/cx_tdimarc_adjust_summary.tsv") ' +
        '(setq cx:*adjust-details-path* "C:/tmp/cx_tdimarc_adjust_details.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/tdimarc_native_adjust_probe.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'TDIMARC_ADJUST_ONE_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'TDIMARC_ADJUST_ONE_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'TDIMARC_ADJUST_ONE_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'tdimarc_adjust_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'tdimarc_adjust_details.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        target_handle = [string]$summaryRows[0].TARGET_HANDLE
        detail = [string]$summaryRows[0].DETAIL
        before_bbox = [string]$summaryRows[0].BEFORE_BBOX
        after_bbox = [string]$summaryRows[0].AFTER_BBOX
        changed = [string]$summaryRows[0].CHANGED
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'TMIRDIM_BATCH') {
    # TMirDim is a stateful native Tianzheng command.  A loop of command-s
    # calls inside one AutoLISP invocation can strand the first command at a
    # prompt even though the identical one-object call is verified.  Keep the
    # verified one-object protocol and dispatch each handle as its own top-level
    # CAD command; this mirrors human use and preserves the native object.
    if (-not (Test-Path -LiteralPath $trustedNativeAnnoMirrorProbe -PathType Leaf)) { throw 'TRUSTED_NATIVE_ANGLE_MIRROR_ONE_MISSING' }
    $handles = @($TargetHandles.Split(',') | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -eq 0) { throw 'NATIVE_ANGLE_MIRROR_BATCH_EMPTY' }
    if (@($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) { throw 'NATIVE_ANGLE_MIRROR_BATCH_HANDLE_INVALID' }
    if (@($handles | Select-Object -Unique).Count -ne $handles.Count) { throw 'NATIVE_ANGLE_MIRROR_BATCH_DUPLICATE_HANDLE' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'native_annotation_mirror_probe.lsp'
    Copy-Item -LiteralPath $trustedNativeAnnoMirrorProbe -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_native_angle_mirror_batch_summary.tsv'
    $detailsPath = 'C:\tmp\cx_native_angle_mirror_batch_details.tsv'
    $singleSummaryPath = 'C:\tmp\cx_native_annotation_mirror_summary.tsv'
    $singleDetailsPath = 'C:\tmp\cx_native_annotation_mirror_details.tsv'
    Remove-Item -LiteralPath $summaryPath,$detailsPath,$singleSummaryPath,$singleDetailsPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $loaded = $false
    $toggled = [Collections.Generic.List[string]]::new()
    $detailRows = [Collections.Generic.List[object]]::new()
    $batchStarted = Get-Date
    $invokeOne = {
        param([string]$Handle,[bool]$LoadDefinition)
        Remove-Item -LiteralPath $singleSummaryPath,$singleDetailsPath -Force -ErrorAction SilentlyContinue
        $sentAt = Get-Date
        $prefix = '(progn ' +
            '(setq cx:*nam-target-handle* "' + $Handle + '") ' +
            '(setq cx:*nam-expected-drawing* "' + $expectedDrawing + '") ' +
            '(setq cx:*nam-summary-path* "C:/tmp/cx_native_annotation_mirror_summary.tsv") ' +
            '(setq cx:*nam-details-path* "C:/tmp/cx_native_annotation_mirror_details.tsv") '
        if ($LoadDefinition) {
            $command = $prefix + '(load "C:/tmp/tianzheng_whitelist/native_annotation_mirror_probe.lsp"))' + "`r"
            # The command line may no longer own keyboard focus after the
            # preceding grip/bbox actions.  Queue the first load through the
            # exact owned AutoCAD document instead of posting characters to an
            # MDI child.  This does not use the physical mouse and is guarded
            # by HWND plus active-drawing checks.
            Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
        } else {
            $command = $prefix + '(c:CXNATIVEANNOMIRRORPROBE))' + "`r"
            Send-OwnedComCommand -CommandText $command
        }
        $oneDeadline = (Get-Date).AddSeconds([Math]::Max(10,[Math]::Min(30,$TimeoutSeconds)))
        $summaryItem = $null
        do {
            Start-Sleep -Milliseconds 100
            $summaryItem = Get-Item -LiteralPath $singleSummaryPath -ErrorAction SilentlyContinue
            if ($summaryItem -and $summaryItem.LastWriteTime -ge $sentAt.AddSeconds(-1)) { break }
            $live = Get-Process -Id $ProcessId -ErrorAction Stop
            if (-not $live.Responding) { throw "NATIVE_ANGLE_MIRROR_ONE_NOT_RESPONDING=$Handle" }
        } while ((Get-Date) -lt $oneDeadline)
        if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $sentAt.AddSeconds(-1)) { throw "NATIVE_ANGLE_MIRROR_ONE_TIMEOUT=$Handle" }
        $rows = @(Import-Csv -LiteralPath $singleSummaryPath -Delimiter "`t" -Encoding Default)
        if ($rows.Count -ne 1) { throw "NATIVE_ANGLE_MIRROR_ONE_SUMMARY_INVALID=$Handle" }
        $row = $rows[0]
        if ([string]$row.TARGET_HANDLE -cne $Handle) { throw "NATIVE_ANGLE_MIRROR_ONE_HANDLE_MISMATCH=$Handle" }
        if ([string]$row.BEFORE_CLASSES -notmatch 'TDbDimension2') { throw "NATIVE_ANGLE_MIRROR_ONE_NOT_ANGLE=$Handle" }
        if ([string]$row.STATUS -cne 'PASS' -or [string]$row.CHANGED -cne 'YES') {
            throw "NATIVE_ANGLE_MIRROR_ONE_FAILED=$Handle/$($row.DETAIL)"
        }
        return $row
    }
    try {
        foreach ($handle in $handles) {
            $row = & $invokeOne $handle (-not $loaded)
            $loaded = $true
            $toggled.Add($handle)
            $detailRows.Add([pscustomobject]@{
                HANDLE = $handle; STATUS = 'PASS'; DETAIL = [string]$row.DETAIL
                CHANGED = [string]$row.CHANGED; ELAPSED_MS = [int]$row.ELAPSED_MS
            })
        }
    } catch {
        $originalError = $_.Exception.Message
        $rollbackFailed = [Collections.Generic.List[string]]::new()
        $rollbackHandles = $toggled.ToArray()
        [array]::Reverse($rollbackHandles)
        foreach ($handle in $rollbackHandles) {
            try { [void](& $invokeOne $handle $false) } catch { $rollbackFailed.Add($handle) }
        }
        if ($rollbackFailed.Count -gt 0) {
            throw "NATIVE_ANGLE_MIRROR_BATCH_ROLLBACK_FAILED=$($rollbackFailed -join ',')/ORIGINAL=$originalError"
        }
        throw "NATIVE_ANGLE_MIRROR_BATCH_ROLLED_BACK=$originalError"
    }
    $cadElapsed = [int]((Get-Date) - $batchStarted).TotalMilliseconds
    $detailRows | Export-Csv -LiteralPath $detailsPath -Delimiter "`t" -NoTypeInformation -Encoding Default
    [IO.File]::WriteAllLines($summaryPath, @(
        "STATUS`tDETAIL`tREQUESTED`tPROCESSED`tPASSED`tFAILED`tELAPSED_MS`tCMDACTIVE`tCMDNAMES",
        "PASS`tTOP_LEVEL_SINGLE_DISPATCH_COMPLETE`t$($handles.Count)`t$($handles.Count)`t$($handles.Count)`t0`t$cadElapsed`t0`t"
    ), [Text.Encoding]::Default)
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'native_angle_mirror_batch_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'native_angle_mirror_batch_details.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = $cadElapsed
        requested = [int]$summaryRows[0].REQUESTED
        passed = [int]$summaryRows[0].PASSED
        failed = [int]$summaryRows[0].FAILED
        detail = [string]$summaryRows[0].DETAIL
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'TMIRDIM_NATIVE_ANY_ONE') {
    if (-not (Test-Path -LiteralPath $trustedNativeAnnoMirrorProbe -PathType Leaf)) { throw 'TRUSTED_NATIVE_ANNO_MIRROR_PROBE_MISSING' }
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'NATIVE_ANNO_MIRROR_TARGET_HANDLE_INVALID' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'native_annotation_mirror_probe.lsp'
    Copy-Item -LiteralPath $trustedNativeAnnoMirrorProbe -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_native_annotation_mirror_summary.tsv'
    $detailsPath = 'C:\tmp\cx_native_annotation_mirror_details.tsv'
    Remove-Item -LiteralPath $summaryPath,$detailsPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*nam-target-handle* "' + $TargetHandle.ToUpperInvariant() + '") ' +
        '(setq cx:*nam-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*nam-summary-path* "C:/tmp/cx_native_annotation_mirror_summary.tsv") ' +
        '(setq cx:*nam-details-path* "C:/tmp/cx_native_annotation_mirror_details.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/native_annotation_mirror_probe.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'NATIVE_ANNO_MIRROR_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'NATIVE_ANNO_MIRROR_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'NATIVE_ANNO_MIRROR_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'native_annotation_mirror_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'native_annotation_mirror_details.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        target_handle = [string]$summaryRows[0].TARGET_HANDLE
        detail = [string]$summaryRows[0].DETAIL
        before_classes = [string]$summaryRows[0].BEFORE_CLASSES
        after_classes = [string]$summaryRows[0].AFTER_CLASSES
        changed = [string]$summaryRows[0].CHANGED
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'ADJUST_PROMPT_PROBE') {
    if (-not (Test-Path -LiteralPath $trustedPromptProbe -PathType Leaf)) { throw 'TRUSTED_PROMPT_PROBE_MISSING' }
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'PROMPT_PROBE_TARGET_HANDLE_INVALID' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'tianzheng_adjust_command_prompt_probe.lsp'
    Copy-Item -LiteralPath $trustedPromptProbe -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_tz_adjust_prompt_summary.tsv'
    Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*prompt-command* "' + $ProbeCommand + '") ' +
        '(setq cx:*prompt-stage* "' + $ProbeStage + '") ' +
        '(setq cx:*prompt-target-handle* "' + $TargetHandle.ToUpperInvariant() + '") ' +
        '(setq cx:*prompt-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*prompt-summary-path* "C:/tmp/cx_tz_adjust_prompt_summary.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/tianzheng_adjust_command_prompt_probe.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'ADJUST_PROMPT_PROBE_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'ADJUST_PROMPT_PROBE_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'ADJUST_PROMPT_PROBE_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'adjust_prompt_summary.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        probe_command = [string]$summaryRows[0].COMMAND
        probe_stage = [string]$summaryRows[0].STAGE
        last_prompt = [string]$summaryRows[0].LASTPROMPT
        detail = [string]$summaryRows[0].DETAIL
        error_text = [string]$summaryRows[0].ERROR_TEXT
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'POLYLINE_STYLE_INVENTORY') {
    if (-not (Test-Path -LiteralPath $trustedPolylineInventory -PathType Leaf)) { throw 'TRUSTED_POLYLINE_INVENTORY_MISSING' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'inventory_polyline_styles_fast.lsp'
    Copy-Item -LiteralPath $trustedPolylineInventory -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_polyline_styles_summary.tsv'
    $detailsPath = 'C:\tmp\cx_polyline_styles.tsv'
    Remove-Item -LiteralPath $summaryPath,$detailsPath -Force -ErrorAction SilentlyContinue
    $command = '(progn ' +
        '(setq cx:*poly-style-output* "C:/tmp/cx_polyline_styles.tsv") ' +
        '(setq cx:*poly-style-summary* "C:/tmp/cx_polyline_styles_summary.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/inventory_polyline_styles_fast.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'POLYLINE_STYLE_INVENTORY_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'POLYLINE_STYLE_INVENTORY_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
    if ($summaryRows.Count -ne 1 -or $summaryRows[0].STATUS -cne 'PASS') { throw 'POLYLINE_STYLE_INVENTORY_FAILED' }
    if ([int]$summaryRows[0].DBMOD_BEFORE -ne [int]$summaryRows[0].DBMOD_AFTER) { throw 'POLYLINE_STYLE_INVENTORY_CHANGED_DBMOD' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'polyline_styles_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'polyline_styles.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        scanned = [int]$summaryRows[0].SCANNED
        arc_polylines = [int]$summaryRows[0].ARC_POLYLINES
        total_arcs = [int]$summaryRows[0].TOTAL_ARCS
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'EXPORT_TEST_SUBSET_WBLOCK') {
    if (-not (Test-Path -LiteralPath $trustedTestSubsetWblock -PathType Leaf)) { throw 'TRUSTED_TEST_SUBSET_WBLOCK_MISSING' }
    $selectedHandles = @($TargetHandles -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique)
    if ($selectedHandles.Count -eq 0 -or @($selectedHandles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -ne 0) {
        throw 'TEST_SUBSET_TARGET_HANDLES_INVALID'
    }
    if (-not [IO.Path]::IsPathFullyQualified($OutputPath) -or [IO.Path]::GetExtension($OutputPath) -ine '.dwg') {
        throw 'TEST_SUBSET_OUTPUT_PATH_INVALID'
    }
    $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
    if (Test-Path -LiteralPath $resolvedOutput) { throw 'TEST_SUBSET_OUTPUT_ALREADY_EXISTS' }
    $outputParent = Split-Path -Parent $resolvedOutput
    New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'export_test_subset_wblock.lsp'
    Copy-Item -LiteralPath $trustedTestSubsetWblock -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_test_subset_wblock_summary.tsv'
    Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    $handleLiteral = ($selectedHandles | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $normalizedOutput = $resolvedOutput.Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*test-subset-handles* ''(' + $handleLiteral + ')) ' +
        '(setq cx:*test-subset-output* "' + $normalizedOutput + '") ' +
        '(setq cx:*test-subset-report* "C:/tmp/cx_test_subset_wblock_summary.tsv") ' +
        '(setq cx:*test-subset-expected-drawing* "' + $expectedDrawing + '") ' +
        '(load "C:/tmp/tianzheng_whitelist/export_test_subset_wblock.lsp"))' + "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'TEST_SUBSET_WBLOCK_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'TEST_SUBSET_WBLOCK_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
    if ($summaryRows.Count -ne 1 -or [string]$summaryRows[0].STATUS -cne 'PASS') { throw 'TEST_SUBSET_WBLOCK_FAILED' }
    if ([int]$summaryRows[0].REQUESTED -ne $selectedHandles.Count -or [int]$summaryRows[0].RESOLVED -ne $selectedHandles.Count) {
        throw 'TEST_SUBSET_WBLOCK_COUNT_MISMATCH'
    }
    if (-not (Test-Path -LiteralPath $resolvedOutput -PathType Leaf)) { throw 'TEST_SUBSET_WBLOCK_OUTPUT_MISSING' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'test_subset_wblock_summary.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        requested = [int]$summaryRows[0].REQUESTED
        resolved = [int]$summaryRows[0].RESOLVED
        output_path = $resolvedOutput
        output_length = (Get-Item -LiteralPath $resolvedOutput).Length
        output_sha256 = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash
        source_dbmod_before = [int]$summaryRows[0].DBMOD_BEFORE
        source_dbmod_after = [int]$summaryRows[0].DBMOD_AFTER
        source_dbmod_unchanged = ([int]$summaryRows[0].DBMOD_BEFORE -eq [int]$summaryRows[0].DBMOD_AFTER)
    }
}
elseif ($Action -ceq 'CXHDBZ_PRESELECTED_BATCH') {
    $phaseId = 'P3_NATIVE_DIMENSION_RELAYOUT'
    $workflowId = 'CX-TDIM-TYPED-SELECT-AUTO-LAYOUT-V1'
    $workflowMode = 'validation'
    if (-not (Test-Path -LiteralPath $trustedCxhdbzCommand -PathType Leaf)) { throw 'TRUSTED_CXHDBZ_COMMAND_MISSING' }
    if (-not (Test-Path -LiteralPath $trustedFullBatch -PathType Leaf)) { throw 'TRUSTED_CXHDBZ_KERNEL_MISSING' }
    if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { throw 'CXHDBZ_REPORT_DIRECTORY_REQUIRED' }
    if ([string]::IsNullOrWhiteSpace($TaskSpecPath) -or -not (Test-Path -LiteralPath $TaskSpecPath -PathType Leaf)) {
        throw 'CXHDBZ_TASK_SPEC_MISSING'
    }
    if ([string]::IsNullOrWhiteSpace($TargetHandles)) { throw 'CXHDBZ_TARGET_HANDLES_REQUIRED' }

    $resolvedReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedReportDirectory.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CXHDBZ_REPORT_DIRECTORY_OUTSIDE_PROJECT'
    }
    New-Item -ItemType Directory -Path $resolvedReportDirectory -Force | Out-Null
    $resolvedSpec = [IO.Path]::GetFullPath($TaskSpecPath)
    if (-not $resolvedSpec.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CXHDBZ_TASK_SPEC_OUTSIDE_PROJECT'
    }
    $specText = [IO.File]::ReadAllText($resolvedSpec, [Text.Encoding]::ASCII)
    if ($specText -match '(?i)\((load|command|command-s|vl-|vla-|startapp|shell|eval|read)\b') {
        throw 'CXHDBZ_TASK_SPEC_CONTAINS_EXECUTABLE_FORM'
    }
    $specHandles = @([regex]::Matches($specText, '\("(?<handle>[0-9A-F]+)"\s+\(', 'IgnoreCase') |
        ForEach-Object { $_.Groups['handle'].Value.ToUpperInvariant() } | Select-Object -Unique)
    $expectedSegments = @([regex]::Matches($specText, '\("ARC"\s+\d+\)', 'IgnoreCase')).Count
    if ($specHandles.Count -eq 0 -or $expectedSegments -eq 0) { throw 'CXHDBZ_TASK_SPEC_SCHEMA_INVALID' }

    $selectedHandles = @($TargetHandles -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique)
    if (@($selectedHandles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -ne 0) { throw 'CXHDBZ_TARGET_HANDLE_INVALID' }
    if ($selectedHandles.Count -ne $specHandles.Count -or @(Compare-Object $selectedHandles $specHandles).Count -ne 0) {
        throw 'CXHDBZ_TARGET_HANDLES_DO_NOT_MATCH_TASK_SPEC'
    }

    $preRunSnapshotPath = Join-Path $resolvedReportDirectory 'pre_run_authority_snapshot.json'
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_project_loop.ps1') | Out-Null
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_no_blocked_workflow_references.ps1') | Out-Null
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_project_execution_contract.ps1') `
        -PhaseId $phaseId `
        -WorkflowId $workflowId `
        -Mode $workflowMode `
        -Entrypoint $trustedCxhdbzCommand `
        -ContextSnapshotOutputPath $preRunSnapshotPath | Out-Null
    $manifestResult = & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/new_cad_execution_manifest.ps1') `
        -PhaseId $phaseId `
        -WorkflowId $workflowId `
        -WorkflowMode $workflowMode `
        -Action $Action `
        -OwnerStatePath $OwnerStatePath `
        -Entrypoint $trustedCxhdbzCommand `
        -TaskSpecPath $resolvedSpec `
        -ReportDirectory $resolvedReportDirectory `
        -ProcessId $ProcessId `
        -WindowHandle ([long]$mainWindow) `
        -PreRunSnapshotPath $preRunSnapshotPath
    $executionManifestPath = [string]$manifestResult.manifest_path

    try {
        $stageDirectory = 'C:\tmp\tianzheng_whitelist'
        New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
        $stagedCommand = Join-Path $stageDirectory 'cx_tdimarc_batch_command.lsp'
        $stagedKernel = Join-Path $stageDirectory 'tdimarc_native_full_batch.lsp'
        Copy-Item -LiteralPath $trustedCxhdbzCommand -Destination $stagedCommand -Force
        Copy-Item -LiteralPath $trustedFullBatch -Destination $stagedKernel -Force
        $summaryPath = 'C:\tmp\cx_cxhdbz_preselected_summary.tsv'
        $detailsPath = 'C:\tmp\cx_cxhdbz_preselected_details.tsv'
        Remove-Item -LiteralPath $summaryPath,$detailsPath -Force -ErrorAction SilentlyContinue

        $handleLiteral = ($selectedHandles | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $command = '(progn ' +
            '(setq cx:*interactive-engine-path* "C:/tmp/tianzheng_whitelist/tdimarc_native_full_batch.lsp" ' +
            'cx:*interactive-summary-path* "C:/tmp/cx_cxhdbz_preselected_summary.tsv" ' +
            'cx:*interactive-details-path* "C:/tmp/cx_cxhdbz_preselected_details.tsv") ' +
            '(load "C:/tmp/tianzheng_whitelist/cx_tdimarc_batch_command.lsp") ' +
            '(setq cxoldpf (getvar "PICKFIRST") cxss (ssadd)) ' +
            '(setvar "PICKFIRST" 1) ' +
            '(foreach cxh ''(' + $handleLiteral + ') (setq cxe (handent cxh)) (if cxe (ssadd cxe cxss))) ' +
            '(sssetfirst nil cxss) (c:CXHDBZ) (sssetfirst nil nil) (setvar "PICKFIRST" cxoldpf))' + "`r"
        Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedCommand,$stagedKernel)

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $summaryItem = $null
        do {
            Start-Sleep -Milliseconds 200
            $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
            if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
            if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'CXHDBZ_NOT_RESPONDING' }
        } while ((Get-Date) -lt $deadline)
        if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'CXHDBZ_SUMMARY_TIMEOUT' }
        $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
        if ($summaryRows.Count -ne 1) { throw 'CXHDBZ_SUMMARY_INVALID' }
        $addedHandles = @(([string]$summaryRows[0].ADDED_HANDLES) -split ',' | Where-Object { $_ } | Select-Object -Unique)
        if ([string]$summaryRows[0].STATUS -cne 'PASS' -or
            [int]$summaryRows[0].TASK_COUNT -ne $specHandles.Count -or
            [int]$summaryRows[0].TARGET_SEGMENTS -ne $expectedSegments -or
            [int]$summaryRows[0].SUCCESS_COUNT -ne $expectedSegments -or
            $addedHandles.Count -ne $expectedSegments) {
            throw 'CXHDBZ_EXACT_COUNT_GATE_FAILED'
        }
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $resolvedReportDirectory 'cxhdbz_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $resolvedReportDirectory 'cxhdbz_details.tsv') -Force
        $specDestination = Join-Path $resolvedReportDirectory 'cxhdbz_gate_spec.lsp'
        if (-not $resolvedSpec.Equals([IO.Path]::GetFullPath($specDestination), [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $resolvedSpec -Destination $specDestination -Force
        }
        $result = [pscustomobject]@{
            status = 'PASS'; action = $Action; phase_id = $phaseId; workflow_id = $workflowId
            workflow_mode = $workflowMode; delivery_transport = 'OWNED_DOCUMENT_COM_QUEUE_ONE_CALL'
            process_id = $ProcessId; elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
            cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS; task_count = [int]$summaryRows[0].TASK_COUNT
            target_segments = [int]$summaryRows[0].TARGET_SEGMENTS; success_count = [int]$summaryRows[0].SUCCESS_COUNT
            added_handles = [string]$summaryRows[0].ADDED_HANDLES; failed = [string]$summaryRows[0].FAILED
            command_active = [int]$summaryRows[0].CMDACTIVE; command_names = [string]$summaryRows[0].CMDNAMES
            execution_manifest = $executionManifestPath
        }
        & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/complete_cad_execution_manifest.ps1') `
            -ManifestPath $executionManifestPath -Result $result | Out-Null
    }
    catch {
        $failedResult = [pscustomobject]@{
            status = 'FAIL'; action = $Action; phase_id = $phaseId; workflow_id = $workflowId
            workflow_mode = $workflowMode; process_id = $ProcessId
            elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
            detail = $_.Exception.Message; execution_manifest = $executionManifestPath
        }
        & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/complete_cad_execution_manifest.ps1') `
            -ManifestPath $executionManifestPath -Result $failedResult | Out-Null
        throw
    }
}
elseif ($Action -ceq 'TDIMARC_FULL_BATCH' -or $Action -ceq 'TDIMARC_FULL_BATCH_SOURCE_SERIAL' -or $Action -ceq 'TDIM_TYPED_SEGMENT_BATCH' -or $Action -ceq 'TDIM_TYPED_SEGMENT_SERIAL_BATCH' -or $Action -ceq 'TDIMARC_SOURCE_REPAIR' -or $Action -ceq 'TDIMARC_TARGETED_REPLACEMENT') {
    $targetedReplacementEntry = $trustedTargetedReplacement
    $targetedReplacementWorkflow = 'TZ-TDIMARC-TARGETED-REPLACEMENT-V2'
    if ($Action -ceq 'TDIMARC_TARGETED_REPLACEMENT' -and -not [string]::IsNullOrWhiteSpace($ExecutionContractPath) -and (Test-Path -LiteralPath $ExecutionContractPath -PathType Leaf)) {
        $contractHint = Get-Content -LiteralPath $ExecutionContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$contractHint.component.id -ceq 'CAD-DIM-ANGLE-652B5-COINCIDENT-GRIP-REPLACEMENT-V1') {
            $targetedReplacementEntry = $trustedTargetedReplacementV3
            $targetedReplacementWorkflow = 'TZ-TDIMARC-TARGETED-REPLACEMENT-V3'
        }
    }
    $trustedBatch = if ($Action -ceq 'TDIMARC_SOURCE_REPAIR') { $trustedSourceRepair } elseif ($Action -ceq 'TDIMARC_TARGETED_REPLACEMENT') { $targetedReplacementEntry } elseif ($Action -ceq 'TDIMARC_FULL_BATCH_SOURCE_SERIAL') { $trustedFullBatchSourceSerial } elseif ($Action -ceq 'TDIM_TYPED_SEGMENT_SERIAL_BATCH') { $trustedTypedSourceSerial } else { $trustedFullBatch }
    if (-not (Test-Path -LiteralPath $trustedBatch -PathType Leaf)) { throw 'TRUSTED_BATCH_ENGINE_MISSING' }
    $phaseId = if ($Action -ceq 'TDIM_TYPED_SEGMENT_BATCH') { 'P2_LINE_LENGTH_AND_TYPED_SWITCH' } elseif ($Action -in @('TDIM_TYPED_SEGMENT_SERIAL_BATCH','TDIMARC_SOURCE_REPAIR','TDIMARC_TARGETED_REPLACEMENT','TDIMARC_FULL_BATCH_SOURCE_SERIAL')) { 'P3_NATIVE_DIMENSION_RELAYOUT' } else { 'P1_ARC_ANGLE_FAST_COMPLETE' }
    $workflowId = if ($Action -ceq 'TDIM_TYPED_SEGMENT_BATCH') { 'TZ-TDIM-TYPED-SEGMENT-V1' } elseif ($Action -ceq 'TDIM_TYPED_SEGMENT_SERIAL_BATCH') { 'TZ-TDIM-TYPED-SEGMENT-SERIAL-V2' } elseif ($Action -ceq 'TDIMARC_SOURCE_REPAIR') { 'TZ-TDIMARC-SOURCE-REPAIR-V1' } elseif ($Action -ceq 'TDIMARC_TARGETED_REPLACEMENT') { $targetedReplacementWorkflow } elseif ($Action -ceq 'TDIMARC_FULL_BATCH_SOURCE_SERIAL') { 'TZ-TDIMARC-SOURCE-SERIAL-FULL-BATCH-V3' } else { 'TZ-TDIMARC-FULL-BATCH-V2' }
    $workflowMode = 'validation'
    if ([string]::IsNullOrWhiteSpace($ReportDirectory)) { throw 'TDIMARC_FULL_BATCH_REPORT_DIRECTORY_REQUIRED' }
    $resolvedReportDirectory = [IO.Path]::GetFullPath($ReportDirectory)
    $preRunSnapshotPath = Join-Path $resolvedReportDirectory 'pre_run_authority_snapshot.json'
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_project_loop.ps1') | Out-Null
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_no_blocked_workflow_references.ps1') | Out-Null
    $executionContract = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_project_execution_contract.ps1'
    $contractResult = & $executionContract `
        -PhaseId $phaseId `
        -WorkflowId $workflowId `
        -Mode $workflowMode `
        -Entrypoint $trustedBatch `
        -ContextSnapshotOutputPath $preRunSnapshotPath `
        -AllowFrozenUpstreamPrerequisite:($Action -in @('TDIMARC_FULL_BATCH','TDIM_TYPED_SEGMENT_BATCH'))
    $isFrozenUpstreamPrerequisite = [string]$contractResult.execution_role -ceq 'frozen_upstream_prerequisite'
    if (-not (Test-Path -LiteralPath $TaskSpecPath -PathType Leaf)) { throw 'TASK_SPEC_MISSING' }
    $resolvedSpec = [IO.Path]::GetFullPath($TaskSpecPath)
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    if (-not $resolvedSpec.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'TASK_SPEC_OUTSIDE_PROJECT'
    }
    $specText = [IO.File]::ReadAllText($resolvedSpec, [Text.Encoding]::ASCII)
    if ($specText -match '(?i)\((load|command|command-s|vl-|vla-|startapp|shell|eval|read)\b') {
        throw 'TASK_SPEC_CONTAINS_EXECUTABLE_FORM'
    }
    if ($specText -notmatch 'cx:\*full-batch-tasks\*' -or $specText -notmatch 'cx:\*full-batch-expected-drawing\*') {
        throw 'TASK_SPEC_SCHEMA_INVALID'
    }
    $manifestResult = & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/new_cad_execution_manifest.ps1') `
        -PhaseId $phaseId `
        -WorkflowId $workflowId `
        -WorkflowMode $workflowMode `
        -Action $Action `
        -OwnerStatePath $OwnerStatePath `
        -Entrypoint $trustedBatch `
        -TaskSpecPath $resolvedSpec `
        -ReportDirectory $ReportDirectory `
        -ProcessId $ProcessId `
        -WindowHandle ([long]$mainWindow) `
        -PreRunSnapshotPath $preRunSnapshotPath `
        -ExecutionContractPath $ExecutionContractPath `
        -AllowNonCurrentGoverningPhase:$isFrozenUpstreamPrerequisite
    $executionManifestPath = [string]$manifestResult.manifest_path
    try {
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedEngine = Join-Path $stageDirectory 'tdimarc_native_full_batch.lsp'
    $stagedSpec = Join-Path $stageDirectory 'tdimarc_native_full_batch_spec.lsp'
    Copy-Item -LiteralPath $resolvedSpec -Destination $stagedSpec -Force
    if ($Action -in @('TDIMARC_FULL_BATCH_SOURCE_SERIAL','TDIM_TYPED_SEGMENT_SERIAL_BATCH')) {
        if (-not (Test-Path -LiteralPath $trustedFullBatch -PathType Leaf)) { throw 'TRUSTED_FROZEN_BATCH_CORE_MISSING' }
        $stagedCore = Join-Path $stageDirectory 'tdimarc_native_full_batch_core_v2.lsp'
        $stagedAdapter = Join-Path $stageDirectory $(if ($Action -ceq 'TDIM_TYPED_SEGMENT_SERIAL_BATCH') { 'tdimarc_native_full_batch_source_serial_v4.lsp' } else { 'tdimarc_native_full_batch_source_serial_v3.lsp' })
        $coreText = [IO.File]::ReadAllText($trustedFullBatch, [Text.Encoding]::UTF8)
        $coreWithoutAutorun = [regex]::Replace($coreText, '(?ms)\r?\n\(c:CXTDIMARCFULLBATCH\)\s*\z', '')
        if ($coreWithoutAutorun.Length -eq $coreText.Length) { throw 'FROZEN_BATCH_CORE_AUTORUN_MARKER_NOT_FOUND' }
        $stagedCoreText = $coreWithoutAutorun
        $sourceSerialAliases = [ordered]@{
            '(defun cx:fb-isolate-entities' = '(defun cx:ss-v2-isolate-entities'
            '(defun cx:fb-run-one' = '(defun cx:ss-v2-run-one'
            '(defun cx:fb-run-line' = '(defun cx:ss-v2-run-line'
            '(defun cx:fb-unisolate-objects' = '(defun cx:ss-v2-unisolate-objects'
        }
        foreach ($declaration in $sourceSerialAliases.Keys) {
            $matchCount = ([regex]::Matches($stagedCoreText, [regex]::Escape($declaration))).Count
            if ($matchCount -ne 1) {
                throw "FROZEN_BATCH_CORE_ALIAS_DECLARATION_COUNT_INVALID:${declaration}:$matchCount"
            }
            $stagedCoreText = $stagedCoreText.Replace($declaration, $sourceSerialAliases[$declaration])
        }
        foreach ($aliasDeclaration in $sourceSerialAliases.Values) {
            $aliasCount = ([regex]::Matches($stagedCoreText, [regex]::Escape($aliasDeclaration))).Count
            if ($aliasCount -ne 1) {
                throw "STAGED_BATCH_CORE_ALIAS_DECLARATION_COUNT_INVALID:${aliasDeclaration}:$aliasCount"
            }
        }
        [IO.File]::WriteAllText($stagedCore, $stagedCoreText, (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath $trustedBatch -Destination $stagedAdapter -Force
        $command = '(progn (load "C:/tmp/tianzheng_whitelist/tdimarc_native_full_batch_spec.lsp") ' +
            '(load "C:/tmp/tianzheng_whitelist/tdimarc_native_full_batch_core_v2.lsp") ' +
            ('(load "C:/tmp/tianzheng_whitelist/{0}"))' -f [IO.Path]::GetFileName($stagedAdapter)) + "`r"
        $trustedScriptPaths = @($stagedSpec,$stagedCore,$stagedAdapter)
    }
    else {
        Copy-Item -LiteralPath $trustedBatch -Destination $stagedEngine -Force
        $command = '(progn (load "C:/tmp/tianzheng_whitelist/tdimarc_native_full_batch_spec.lsp") ' +
            '(load "C:/tmp/tianzheng_whitelist/tdimarc_native_full_batch.lsp"))' + "`r"
        $trustedScriptPaths = @($stagedSpec,$stagedEngine)
    }
    $scopeMatch = [regex]::Match($specText, 'cx_tdimarc_full_(road|shore|all)_summary\.tsv', 'IgnoreCase')
    if (-not $scopeMatch.Success) { throw 'TASK_SPEC_SCOPE_NOT_FOUND' }
    $scope = $scopeMatch.Groups[1].Value.ToLowerInvariant()
    $summaryPath = "C:\tmp\cx_tdimarc_full_${scope}_summary.tsv"
    $detailsPath = "C:\tmp\cx_tdimarc_full_${scope}_details.tsv"
    Remove-Item -LiteralPath $summaryPath,$detailsPath -Force -ErrorAction SilentlyContinue
    if ($Action -in @('TDIMARC_SOURCE_REPAIR','TDIMARC_TARGETED_REPLACEMENT','TDIMARC_FULL_BATCH_SOURCE_SERIAL','TDIM_TYPED_SEGMENT_SERIAL_BATCH') -or $UseOwnedComDelivery) {
        # Source repair is a one-candidate validation action. Bind delivery to the
        # exact owned AutoCAD document so MDI focus or delayed startup UI cannot
        # swallow the command. Full-batch validation may opt in to the same
        # exact-document queue when the default MDI character delivery is
        # factually observed to be lost before AutoCAD starts the command.
        Send-TrustedLspCommandCom -CommandText $command -ScriptPaths $trustedScriptPaths
    }
    else {
        Send-TrustedLspCommand -CommandText $command -ScriptPaths $trustedScriptPaths
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'TDIMARC_FULL_BATCH_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'TDIMARC_FULL_BATCH_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
    if ($summaryRows.Count -ne 1) { throw 'TDIMARC_FULL_BATCH_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory "tdimarc_full_${scope}_summary.tsv") -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory "tdimarc_full_${scope}_details.tsv") -Force
        $specDestination = [IO.Path]::GetFullPath((Join-Path $ReportDirectory "tdimarc_full_${scope}_spec.lsp"))
        if (-not $resolvedSpec.Equals($specDestination, [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $resolvedSpec -Destination $specDestination -Force
        }
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        phase_id = $phaseId
        workflow_id = $workflowId
        workflow_mode = $workflowMode
        scope = $scope.ToUpperInvariant()
        delivery_transport = $(if ($Action -in @('TDIMARC_SOURCE_REPAIR','TDIMARC_TARGETED_REPLACEMENT','TDIMARC_FULL_BATCH_SOURCE_SERIAL','TDIM_TYPED_SEGMENT_SERIAL_BATCH') -or $UseOwnedComDelivery) { 'OWNED_DOCUMENT_COM_QUEUE' } else { 'MDI_CHARACTER_POST' })
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        task_count = [int]$summaryRows[0].TASK_COUNT
        target_segments = [int]$summaryRows[0].TARGET_SEGMENTS
        success_count = [int]$summaryRows[0].SUCCESS_COUNT
        road_count = [int]$summaryRows[0].ROAD_COUNT
        shore_count = [int]$summaryRows[0].SHORE_COUNT
        added_handles = [string]$summaryRows[0].ADDED_HANDLES
        failed = [string]$summaryRows[0].FAILED
        cleanup_deleted = [string]$summaryRows[0].CLEANUP_DELETED
        clean_slate_deleted = [string]$summaryRows[0].CLEAN_SLATE_DELETED
        detail = [string]$summaryRows[0].DETAIL
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
        execution_manifest = $executionManifestPath
    }
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/complete_cad_execution_manifest.ps1') `
        -ManifestPath $executionManifestPath -Result $result | Out-Null
    }
    catch {
        $failedResult = [pscustomobject]@{
            status = 'FAIL'
            action = $Action
            phase_id = $phaseId
            workflow_id = $workflowId
            workflow_mode = $workflowMode
            process_id = $ProcessId
            elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
            detail = $_.Exception.Message
            execution_manifest = $executionManifestPath
        }
        & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/complete_cad_execution_manifest.ps1') `
            -ManifestPath $executionManifestPath -Result $failedResult | Out-Null
        throw
    }
}
elseif ($Action -ceq 'TDIMARC_V10_FIVE') {
    if (-not (Test-Path -LiteralPath $trustedTdimarcV10 -PathType Leaf)) { throw 'TRUSTED_TDIMARC_V10_MISSING' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'tdimarc_prompt_v10_batch_probe.lsp'
    Copy-Item -LiteralPath $trustedTdimarcV10 -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_tdimarc_v10_summary.tsv'
    $detailsPath = 'C:\tmp\cx_tdimarc_v10_details.tsv'
    Remove-Item -LiteralPath $summaryPath,$detailsPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*v10-source-handle* "18435D") ' +
        '(setq cx:*v10-segments* ''(0 2 3 4 6)) ' +
        '(setq cx:*v10-offset* 8.0) ' +
        '(setq cx:*v10-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*v10-summary-path* "C:/tmp/cx_tdimarc_v10_summary.tsv") ' +
        '(setq cx:*v10-details-path* "C:/tmp/cx_tdimarc_v10_details.tsv") ' +
        '(setq cx:*v10-save-on-success* nil) ' +
        '(load "C:/tmp/tianzheng_whitelist/tdimarc_prompt_v10_batch_probe.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'TDIMARC_V10_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'TDIMARC_V10_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t")
    if ($summaryRows.Count -ne 1) { throw 'TDIMARC_V10_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'tdimarc_v10_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'tdimarc_v10_details.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        success_count = [int]$summaryRows[0].SUCCESS_COUNT
        handles = [string]$summaryRows[0].ADDED_HANDLES
        detail = [string]$summaryRows[0].DETAIL
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'ADJUST_GROUP_PROBE') {
    if (-not (Test-Path -LiteralPath $trustedGroupProbe -PathType Leaf)) { throw 'TRUSTED_GROUP_PROBE_MISSING' }
    $handles = @($TargetHandles -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -lt 2 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) {
        throw 'GROUP_PROBE_TARGET_HANDLES_INVALID'
    }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'tianzheng_adjust_group_probe.lsp'
    Copy-Item -LiteralPath $trustedGroupProbe -Destination $stagedLisp -Force
    $summaryPath = 'C:\tmp\cx_tz_adjust_group_summary.tsv'
    Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $lispHandles = '(' + (($handles | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ')'
    $command = '(progn ' +
        '(setq cx:*group-command* "TDimAdjust") ' +
        '(setq cx:*group-target-handles* (quote ' + $lispHandles + ')) ' +
        '(setq cx:*group-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*group-summary-path* "C:/tmp/cx_tz_adjust_group_summary.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/tianzheng_adjust_group_probe.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'ADJUST_GROUP_PROBE_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'ADJUST_GROUP_PROBE_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'ADJUST_GROUP_PROBE_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'adjust_group_summary.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        probe_command = [string]$summaryRows[0].COMMAND
        target_handles = [string]$summaryRows[0].TARGET_HANDLES
        clone_handles = [string]$summaryRows[0].CLONE_HANDLES
        detail = [string]$summaryRows[0].DETAIL
        error_text = [string]$summaryRows[0].ERROR_TEXT
        native_before = [int]$summaryRows[0].NATIVE_BEFORE
        native_after = [int]$summaryRows[0].NATIVE_AFTER
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'AUDIT_NATIVE_DIM_BBOXES') {
    if (-not (Test-Path -LiteralPath $trustedDimensionBboxAudit -PathType Leaf)) { throw 'TRUSTED_DIMENSION_BBOX_AUDIT_MISSING' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'audit_tianzheng_dimension_bboxes.lsp'
    Copy-Item -LiteralPath $trustedDimensionBboxAudit -Destination $stagedLisp -Force
    $detailsPath = 'C:\tmp\cx_tz_dimension_bboxes.tsv'
    $summaryPath = 'C:\tmp\cx_tz_dimension_bbox_summary.tsv'
    Remove-Item -LiteralPath $detailsPath,$summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*bbox-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*bbox-details-path* "C:/tmp/cx_tz_dimension_bboxes.tsv") ' +
        '(setq cx:*bbox-summary-path* "C:/tmp/cx_tz_dimension_bbox_summary.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/audit_tianzheng_dimension_bboxes.lsp"))' + "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'DIMENSION_BBOX_AUDIT_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'DIMENSION_BBOX_AUDIT_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'DIMENSION_BBOX_AUDIT_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'dimension_bbox_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'dimension_bboxes.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        native_count = [int]$summaryRows[0].NATIVE_COUNT
        bbox_count = [int]$summaryRows[0].BBOX_COUNT
        detail = [string]$summaryRows[0].DETAIL
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'PROBE_NATIVE_DIM_EXPLODE') {
    if (-not (Test-Path -LiteralPath $trustedDimensionExplodeProbe -PathType Leaf)) { throw 'TRUSTED_DIMENSION_EXPLODE_PROBE_MISSING' }
    if ($TargetHandle -notmatch '^[0-9A-Fa-f]+$') { throw 'DIMENSION_EXPLODE_TARGET_HANDLE_INVALID' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'probe_tianzheng_dimension_explode.lsp'
    Copy-Item -LiteralPath $trustedDimensionExplodeProbe -Destination $stagedLisp -Force
    $detailsPath = 'C:\tmp\cx_tz_dimension_explode_details.tsv'
    $summaryPath = 'C:\tmp\cx_tz_dimension_explode_summary.tsv'
    Remove-Item -LiteralPath $detailsPath,$summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*explode-target-handle* "' + $TargetHandle.ToUpperInvariant() + '") ' +
        '(setq cx:*explode-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*explode-details-path* "C:/tmp/cx_tz_dimension_explode_details.tsv") ' +
        '(setq cx:*explode-summary-path* "C:/tmp/cx_tz_dimension_explode_summary.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/probe_tianzheng_dimension_explode.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'DIMENSION_EXPLODE_PROBE_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'DIMENSION_EXPLODE_PROBE_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'DIMENSION_EXPLODE_PROBE_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'dimension_explode_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'dimension_explode_details.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        target_handle = [string]$summaryRows[0].TARGET_HANDLE
        child_count = [int]$summaryRows[0].CHILD_COUNT
        text_count = [int]$summaryRows[0].TEXT_COUNT
        detail = [string]$summaryRows[0].DETAIL
        error_text = [string]$summaryRows[0].ERROR_TEXT
        space_before = [int]$summaryRows[0].SPACE_BEFORE
        space_after = [int]$summaryRows[0].SPACE_AFTER
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'AUDIT_NATIVE_DIM_TEXT_BBOXES') {
    if (-not (Test-Path -LiteralPath $trustedDimensionTextBboxAudit -PathType Leaf)) { throw 'TRUSTED_DIMENSION_TEXT_BBOX_AUDIT_MISSING' }
    $handles = @($TargetHandles -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -lt 1 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) {
        throw 'DIMENSION_TEXT_BBOX_TARGET_HANDLES_INVALID'
    }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'audit_tianzheng_dimension_text_bboxes.lsp'
    Copy-Item -LiteralPath $trustedDimensionTextBboxAudit -Destination $stagedLisp -Force
    $detailsPath = 'C:\tmp\cx_tz_dimension_text_bboxes.tsv'
    $summaryPath = 'C:\tmp\cx_tz_dimension_text_bbox_summary.tsv'
    $handlesPath = 'C:\tmp\cx_tz_dimension_text_bbox_handles.txt'
    Remove-Item -LiteralPath $detailsPath,$summaryPath,$handlesPath -Force -ErrorAction SilentlyContinue
    [IO.File]::WriteAllLines($handlesPath, $handles, [Text.Encoding]::ASCII)
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*text-bbox-target-handles* (quote ())) ' +
        '(setq cx:*text-bbox-handles-path* "C:/tmp/cx_tz_dimension_text_bbox_handles.txt") ' +
        '(setq cx:*text-bbox-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*text-bbox-details-path* "C:/tmp/cx_tz_dimension_text_bboxes.tsv") ' +
        '(setq cx:*text-bbox-summary-path* "C:/tmp/cx_tz_dimension_text_bbox_summary.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/audit_tianzheng_dimension_text_bboxes.lsp"))' + "`r"
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'DIMENSION_TEXT_BBOX_AUDIT_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem -or $summaryItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'DIMENSION_TEXT_BBOX_AUDIT_TIMEOUT' }
    $summaryRows = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)
    if ($summaryRows.Count -ne 1) { throw 'DIMENSION_TEXT_BBOX_AUDIT_SUMMARY_INVALID' }
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'dimension_text_bbox_summary.tsv') -Force
        Copy-Item -LiteralPath $detailsPath -Destination (Join-Path $ReportDirectory 'dimension_text_bboxes.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$summaryRows[0].STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        cad_elapsed_ms = [int]$summaryRows[0].ELAPSED_MS
        requested = [int]$summaryRows[0].REQUESTED
        passed = [int]$summaryRows[0].PASSED
        failed = [int]$summaryRows[0].FAILED
        text_count = [int]$summaryRows[0].TEXT_COUNT
        detail = [string]$summaryRows[0].DETAIL
        space_before = [int]$summaryRows[0].SPACE_BEFORE
        space_after = [int]$summaryRows[0].SPACE_AFTER
        command_active = [int]$summaryRows[0].CMDACTIVE
        command_names = [string]$summaryRows[0].CMDNAMES
    }
}
elseif ($Action -ceq 'AUDIT_MODELSPACE_TAIL') {
    if (-not (Test-Path -LiteralPath $trustedModelspaceTailAudit -PathType Leaf)) { throw 'TRUSTED_MODELSPACE_TAIL_AUDIT_MISSING' }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    $stagedLisp = Join-Path $stageDirectory 'audit_modelspace_tail.lsp'
    Copy-Item -LiteralPath $trustedModelspaceTailAudit -Destination $stagedLisp -Force
    $outputPath = 'C:\tmp\cx_modelspace_tail.tsv'
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $command = '(progn ' +
        '(setq cx:*tail-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*tail-output-path* "C:/tmp/cx_modelspace_tail.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/audit_modelspace_tail.lsp"))' + "`r"
    Send-TrustedLspCommand -CommandText $command -ScriptPaths @($stagedLisp)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $outputItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $outputItem = Get-Item -LiteralPath $outputPath -ErrorAction SilentlyContinue
        if ($outputItem -and $outputItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction Stop).Responding) { throw 'MODELSPACE_TAIL_AUDIT_NOT_RESPONDING' }
    } while ((Get-Date) -lt $deadline)
    if (-not $outputItem -or $outputItem.LastWriteTime -lt $started.AddSeconds(-1)) { throw 'MODELSPACE_TAIL_AUDIT_TIMEOUT' }
    $rows = @(Import-Csv -LiteralPath $outputPath -Delimiter "`t" -Encoding Default)
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $outputPath -Destination (Join-Path $ReportDirectory 'modelspace_tail.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = 'PASS'
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        row_count = $rows.Count
        last_handle = if ($rows.Count) { [string]$rows[-1].HANDLE } else { '' }
        last_object_name = if ($rows.Count) { [string]$rows[-1].OBJECT_NAME } else { '' }
    }
}
elseif ($Action -ceq 'CLEANUP_PROBE_STANDARD_DIMS') {
    if (-not (Test-Path -LiteralPath $trustedStandardDimensionCleanup -PathType Leaf)) { throw 'TRUSTED_STANDARD_DIMENSION_CLEANUP_MISSING' }
    $handles = @($TargetHandles -split ',' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($handles.Count -lt 1 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]+$' }).Count -gt 0) {
        throw 'STANDARD_DIMENSION_CLEANUP_HANDLES_INVALID'
    }
    $stageDirectory = 'C:\tmp\tianzheng_whitelist'
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    Copy-Item -LiteralPath $trustedStandardDimensionCleanup -Destination (Join-Path $stageDirectory 'cleanup_probe_standard_dimensions.lsp') -Force
    $summaryPath = 'C:\tmp\cx_cleanup_standard_dimensions.tsv'
    Remove-Item -LiteralPath $summaryPath -Force -ErrorAction SilentlyContinue
    $expectedDrawing = ([string]$owner.target_dwg).Replace('\','/')
    $lispHandles = '(' + (($handles | ForEach-Object { '"' + $_ + '"' }) -join ' ') + ')'
    $command = '(progn ' +
        '(setq cx:*cleanup-standard-handles* (quote ' + $lispHandles + ')) ' +
        '(setq cx:*cleanup-standard-expected-drawing* "' + $expectedDrawing + '") ' +
        '(setq cx:*cleanup-standard-summary-path* "C:/tmp/cx_cleanup_standard_dimensions.tsv") ' +
        '(load "C:/tmp/tianzheng_whitelist/cleanup_probe_standard_dimensions.lsp"))' + "`r"
    # Cleanup is a deterministic, parameter-heavy one-shot action.  Route it
    # through AutoCAD's owned-document command queue; per-character MDI posting
    # intermittently lost this command after a fully READY launch and left no
    # completion report.  Exact PID/HWND/document and trusted-script guards are
    # still enforced by Send-TrustedLspCommandCom.
    Send-TrustedLspCommandCom -CommandText $command -ScriptPaths @((Join-Path $stageDirectory 'cleanup_probe_standard_dimensions.lsp'))
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $summaryItem = $null
    do {
        Start-Sleep -Milliseconds 200
        $summaryItem = Get-Item -LiteralPath $summaryPath -ErrorAction SilentlyContinue
        if ($summaryItem -and $summaryItem.LastWriteTime -ge $started.AddSeconds(-1)) { break }
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { throw 'STANDARD_DIMENSION_CLEANUP_PROCESS_EXITED' }
    } while ((Get-Date) -lt $deadline)
    if (-not $summaryItem) { throw 'STANDARD_DIMENSION_CLEANUP_TIMEOUT' }
    $row = @(Import-Csv -LiteralPath $summaryPath -Delimiter "`t" -Encoding Default)[0]
    if ($ReportDirectory) {
        New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
        Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $ReportDirectory 'cleanup_standard_dimensions.tsv') -Force
    }
    $result = [pscustomobject]@{
        status = [string]$row.STATUS
        action = $Action
        process_id = $ProcessId
        elapsed_ms = [int]((Get-Date) - $started).TotalMilliseconds
        deleted = [int]$row.DELETED
        missing = [int]$row.MISSING
        rejected = [int]$row.REJECTED
        command_active = [int]$row.CMDACTIVE
        command_names = [string]$row.CMDNAMES
    }
}
else {
    throw 'UNHANDLED_WHITELIST_ACTION'
}

$result | ConvertTo-Json -Depth 4
