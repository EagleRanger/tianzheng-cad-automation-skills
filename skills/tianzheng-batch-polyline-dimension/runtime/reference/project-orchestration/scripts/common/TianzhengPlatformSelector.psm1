Set-StrictMode -Version Latest

if (-not ('TzPlatformSelectorGate' -as [type])) {
    Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class TzPlatformSelectorGate {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumChildProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder value, int count);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, StringBuilder lParam);

    private const uint LB_GETCOUNT = 0x018B;
    private const uint LB_GETTEXT = 0x0189;
    private const uint LB_SETCURSEL = 0x0186;
    private const uint LB_GETCURSEL = 0x0188;
    private const uint BM_CLICK = 0x00F5;

    public static string Text(IntPtr hWnd) {
        var value = new StringBuilder(4096);
        GetWindowText(hWnd, value, value.Capacity);
        return value.ToString();
    }

    public static string ClassName(IntPtr hWnd) {
        var value = new StringBuilder(256);
        GetClassName(hWnd, value, value.Capacity);
        return value.ToString();
    }

    private static string ListItem(IntPtr list, int index) {
        var value = new StringBuilder(4096);
        SendMessage(list, LB_GETTEXT, new IntPtr(index), value);
        return value.ToString();
    }

    // Return values: 0=no matching dialog; 1=2021 selected and OK clicked;
    // negative values are a positively identified platform dialog that could
    // not be handled safely.
    public static int SelectAutoCad2021(uint pid) {
        IntPtr dialog = IntPtr.Zero;
        IntPtr list = IntPtr.Zero;
        IntPtr ok = IntPtr.Zero;
        int wanted = -1;

        EnumWindows(delegate(IntPtr top, IntPtr ignored) {
            uint actual;
            GetWindowThreadProcessId(top, out actual);
            if (actual != pid || !IsWindowVisible(top)) return true;

            IntPtr candidateList = IntPtr.Zero;
            IntPtr candidateOk = IntPtr.Zero;
            EnumChildWindows(top, delegate(IntPtr child, IntPtr childIgnored) {
                string cls = ClassName(child);
                if (cls == "ListBox") candidateList = child;
                if (cls == "Button" && GetDlgCtrlID(child) == 1) candidateOk = child;
                return true;
            }, IntPtr.Zero);
            if (candidateList == IntPtr.Zero || candidateOk == IntPtr.Zero) return true;

            int count = SendMessage(candidateList, LB_GETCOUNT, IntPtr.Zero, IntPtr.Zero).ToInt32();
            int candidateWanted = -1;
            bool hasCadPlatformList = false;
            for (int i = 0; i < count; i++) {
                string item = ListItem(candidateList, i);
                if (item.IndexOf("AutoCAD 2016", StringComparison.OrdinalIgnoreCase) >= 0) hasCadPlatformList = true;
                if (item.IndexOf("AutoCAD 2021", StringComparison.OrdinalIgnoreCase) >= 0) candidateWanted = i;
            }
            // Do not click an arbitrary dialog merely because it has a ListBox
            // and an IDOK button.  The known 2016/2021 platform pair is the
            // locale-independent identity of this T20 V10 startup gate.
            if (!hasCadPlatformList && Text(top).IndexOf("启动平台选择", StringComparison.OrdinalIgnoreCase) < 0) return true;

            dialog = top;
            list = candidateList;
            ok = candidateOk;
            wanted = candidateWanted;
            return false;
        }, IntPtr.Zero);

        if (dialog == IntPtr.Zero) return 0;
        if (wanted < 0) return -2;
        if (SendMessage(list, LB_SETCURSEL, new IntPtr(wanted), IntPtr.Zero).ToInt32() < 0) return -3;
        if (SendMessage(list, LB_GETCURSEL, IntPtr.Zero, IntPtr.Zero).ToInt32() != wanted) return -4;
        SendMessage(ok, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
        return 1;
    }
}
'@
}

function Add-TianzhengPlatformGateEvent {
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$Code = 0
    )
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($LogPath))
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $record = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        category = 'tianzheng_platform_selector'
        process_id = $ProcessId
        target_platform = 'AutoCAD 2021'
        status = $Status
        result_code = $Code
        physical_mouse_used = $false
        screen_coordinates_used = $false
    }
    [IO.File]::AppendAllText($LogPath, (($record | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Invoke-TianzhengPlatformSelection2021 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][string]$LogPath
    )
    $code = [TzPlatformSelectorGate]::SelectAutoCad2021([uint32]$ProcessId)
    if ($code -eq 1) {
        Add-TianzhengPlatformGateEvent -LogPath $LogPath -ProcessId $ProcessId -Status 'SELECTED_AND_CONFIRMED' -Code $code
    } elseif ($code -lt 0) {
        Add-TianzhengPlatformGateEvent -LogPath $LogPath -ProcessId $ProcessId -Status 'IDENTIFIED_BUT_FAILED' -Code $code
    }
    [pscustomobject]@{
        process_id = $ProcessId
        detected = ($code -ne 0)
        confirmed = ($code -eq 1)
        code = $code
    }
}

Export-ModuleMember -Function Invoke-TianzhengPlatformSelection2021
