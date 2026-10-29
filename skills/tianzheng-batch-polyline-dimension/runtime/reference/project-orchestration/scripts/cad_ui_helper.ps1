param(
    [ValidateSet('List','ListRaw','ListAllRaw','ListChildrenRaw','Activate','Maximize','Send','SendKeysOnly','PasteText','ClickAt','DragAt','ClickButton','ClickHandle','DialogOk','CloseHandle','SetTextHandle','ComboItems','ComboSelect','ListItems','ListSelect','Screenshot','ScreenshotHandle')]
    [string]$Action = 'List',
    [int]$ProcessId = 0,
    [string]$TitleContains = '',
    [string]$Keys = '',
    [string]$ButtonText = '',
    [string]$OutputPath = '',
    [long]$WindowHandle = 0,
    [string]$Text = '',
    [int]$Index = -1,
    [int]$X = 0,
    [int]$Y = 0,
    [int]$X2 = 0,
    [int]$Y2 = 0
)

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class CadWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowEnabled(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(IntPtr hWnd, uint command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string className, string windowText);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")]
    public static extern IntPtr SendMessageText(IntPtr hWnd, uint message, IntPtr wParam, StringBuilder lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SetWindowText(IntPtr hWnd, string text);
}
"@

function Get-CadWindows {
    $items = [System.Collections.Generic.List[object]]::new()
    $callback = [CadWin32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        [uint32]$windowPid = 0
        [void][CadWin32]::GetWindowThreadProcessId($hWnd, [ref]$windowPid)
        if (($ProcessId -eq 0 -or $windowPid -eq $ProcessId) -and [CadWin32]::IsWindowVisible($hWnd)) {
            $title = [System.Text.StringBuilder]::new(1024)
            $class = [System.Text.StringBuilder]::new(256)
            [void][CadWin32]::GetWindowText($hWnd, $title, $title.Capacity)
            [void][CadWin32]::GetClassName($hWnd, $class, $class.Capacity)
            if ([string]::IsNullOrEmpty($TitleContains) -or $title.ToString().Contains($TitleContains)) {
                $rect = [CadWin32+Rect]::new()
                [void][CadWin32]::GetWindowRect($hWnd, [ref]$rect)
                $items.Add([pscustomobject]@{
                    Handle = $hWnd.ToInt64()
                    ProcessId = $windowPid
                    Class = $class.ToString()
                    Title = $title.ToString()
                    Left = $rect.Left
                    Top = $rect.Top
                    Right = $rect.Right
                    Bottom = $rect.Bottom
                    Width = $rect.Right - $rect.Left
                    Height = $rect.Bottom - $rect.Top
                })
            }
        }
        return $true
    }
    [void][CadWin32]::EnumWindows($callback, [IntPtr]::Zero)
    return $items
}

function Get-AllCadWindows {
    $items = [System.Collections.Generic.List[object]]::new()
    $callback = [CadWin32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        [uint32]$windowPid = 0
        [void][CadWin32]::GetWindowThreadProcessId($hWnd, [ref]$windowPid)
        if ($ProcessId -eq 0 -or $windowPid -eq $ProcessId) {
            $title = [System.Text.StringBuilder]::new(1024)
            $class = [System.Text.StringBuilder]::new(256)
            [void][CadWin32]::GetWindowText($hWnd, $title, $title.Capacity)
            [void][CadWin32]::GetClassName($hWnd, $class, $class.Capacity)
            $items.Add([pscustomobject]@{
                Handle = $hWnd.ToInt64()
                ProcessId = $windowPid
                Visible = [CadWin32]::IsWindowVisible($hWnd)
                Enabled = [CadWin32]::IsWindowEnabled($hWnd)
                Owner = [CadWin32]::GetWindow($hWnd, 4).ToInt64()
                Class = $class.ToString()
                Title = $title.ToString()
            })
        }
        return $true
    }
    [void][CadWin32]::EnumWindows($callback, [IntPtr]::Zero)
    return $items
}

function Get-TargetWindow {
    $windows = @(Get-CadWindows)
    if ($windows.Count -eq 0) { throw "No visible window found for PID $ProcessId" }
    return $windows[0]
}

switch ($Action) {
    'List' {
        Get-CadWindows | Format-Table -AutoSize
    }
    'ListRaw' {
        Get-CadWindows
    }
    'ListAllRaw' {
        Get-AllCadWindows
    }
    'ListChildrenRaw' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        $items = [System.Collections.Generic.List[object]]::new()
        $callback = [CadWin32+EnumWindowsProc]{
            param([IntPtr]$hWnd, [IntPtr]$lParam)
            $title = [System.Text.StringBuilder]::new(1024)
            $class = [System.Text.StringBuilder]::new(256)
            [void][CadWin32]::GetWindowText($hWnd, $title, $title.Capacity)
            [void][CadWin32]::GetClassName($hWnd, $class, $class.Capacity)
            $items.Add([pscustomobject]@{
                Handle = $hWnd.ToInt64()
                Class = $class.ToString()
                Title = $title.ToString()
            })
            return $true
        }
        [void][CadWin32]::EnumChildWindows([IntPtr]$WindowHandle, $callback, [IntPtr]::Zero)
        $items
    }
    'Activate' {
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 9)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        $window
    }
    'Maximize' {
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 3)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        [void][CadWin32]::SetWindowPos([IntPtr]$window.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0043)
        Start-Sleep -Milliseconds 150
        [void][CadWin32]::SetWindowPos([IntPtr]$window.Handle, [IntPtr](-2), 0, 0, 0, 0, 0x0043)
        $window
    }
    'Send' {
        Add-Type -AssemblyName System.Windows.Forms
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 3)
        [void][CadWin32]::SetWindowPos([IntPtr]$window.Handle, [IntPtr](-1), 0, 0, 0, 0, 0x0043)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        $rect = [CadWin32+Rect]::new()
        [void][CadWin32]::GetWindowRect([IntPtr]$window.Handle, [ref]$rect)
        $clickX = [int]($rect.Left + (($rect.Right - $rect.Left) * 0.72))
        $clickY = [int]($rect.Top + (($rect.Bottom - $rect.Top) * 0.28))
        [void][CadWin32]::SetCursorPos($clickX, $clickY)
        [CadWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [CadWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 500
        [System.Windows.Forms.SendKeys]::SendWait($Keys)
        Start-Sleep -Milliseconds 400
        [void][CadWin32]::SetWindowPos([IntPtr]$window.Handle, [IntPtr](-2), 0, 0, 0, 0, 0x0043)
    }
    'SendKeysOnly' {
        Add-Type -AssemblyName System.Windows.Forms
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 9)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        Start-Sleep -Milliseconds 250
        [System.Windows.Forms.SendKeys]::SendWait($Keys)
        Start-Sleep -Milliseconds 350
    }
    'PasteText' {
        Add-Type -AssemblyName System.Windows.Forms
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 9)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        Start-Sleep -Milliseconds 250
        [System.Windows.Forms.Clipboard]::SetText($Text)
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 250
    }
    'ClickAt' {
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 9)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        Start-Sleep -Milliseconds 200
        [void][CadWin32]::SetCursorPos($X, $Y)
        [CadWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [CadWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 250
    }
    'DragAt' {
        $window = Get-TargetWindow
        [void][CadWin32]::ShowWindow([IntPtr]$window.Handle, 9)
        [void][CadWin32]::SetForegroundWindow([IntPtr]$window.Handle)
        Start-Sleep -Milliseconds 200
        [void][CadWin32]::SetCursorPos($X, $Y)
        [CadWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 200
        $steps = 12
        for ($step = 1; $step -le $steps; $step++) {
            $px = [int]($X + (($X2 - $X) * $step / $steps))
            $py = [int]($Y + (($Y2 - $Y) * $step / $steps))
            [void][CadWin32]::SetCursorPos($px, $py)
            Start-Sleep -Milliseconds 35
        }
        [CadWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 300
    }
    'ClickButton' {
        if ([string]::IsNullOrWhiteSpace($ButtonText)) { throw 'ButtonText is required' }
        $window = Get-TargetWindow
        $button = [CadWin32]::FindWindowEx([IntPtr]$window.Handle, [IntPtr]::Zero, 'Button', $ButtonText)
        if ($button -eq [IntPtr]::Zero) { throw "Button not found: $ButtonText" }
        [void][CadWin32]::SendMessage($button, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    'ClickHandle' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        [void][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    'DialogOk' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        [void][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x0111, [IntPtr]1, [IntPtr]::Zero)
    }
    'CloseHandle' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        [void][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    }
    'SetTextHandle' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        if (-not [CadWin32]::SetWindowText([IntPtr]$WindowHandle, $Text)) { throw 'SetWindowText failed' }
    }
    'ComboItems' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        $count = [int][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x0146, [IntPtr]::Zero, [IntPtr]::Zero)
        $selected = [int][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x0147, [IntPtr]::Zero, [IntPtr]::Zero)
        for ($itemIndex = 0; $itemIndex -lt $count; $itemIndex++) {
            $buffer = [System.Text.StringBuilder]::new(1024)
            [void][CadWin32]::SendMessageText([IntPtr]$WindowHandle, 0x0148, [IntPtr]$itemIndex, $buffer)
            [pscustomobject]@{ Index = $itemIndex; Selected = ($itemIndex -eq $selected); Text = $buffer.ToString() }
        }
    }
    'ComboSelect' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        if ($Index -lt 0) { throw 'Index must be non-negative' }
        [void][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x014E, [IntPtr]$Index, [IntPtr]::Zero)
        [void][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x014F, [IntPtr]$Index, [IntPtr]::Zero)
    }
    'ListItems' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        $count = [int][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x018B, [IntPtr]::Zero, [IntPtr]::Zero)
        $selected = [int][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x0188, [IntPtr]::Zero, [IntPtr]::Zero)
        for ($itemIndex = 0; $itemIndex -lt $count; $itemIndex++) {
            $buffer = [System.Text.StringBuilder]::new(4096)
            [void][CadWin32]::SendMessageText([IntPtr]$WindowHandle, 0x0189, [IntPtr]$itemIndex, $buffer)
            [pscustomobject]@{ Index = $itemIndex; Selected = ($itemIndex -eq $selected); Text = $buffer.ToString() }
        }
    }
    'ListSelect' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        if ($Index -lt 0) { throw 'Index must be non-negative' }
        $result = [int][CadWin32]::SendMessage([IntPtr]$WindowHandle, 0x0186, [IntPtr]$Index, [IntPtr]::Zero)
        if ($result -lt 0) { throw "List selection failed: $Index" }
        [pscustomobject]@{ Index = $Index; Selected = $true }
    }
    'Screenshot' {
        if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'OutputPath is required' }
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Windows.Forms
        $targetHandle = [IntPtr]::Zero
        if ($ProcessId -ne 0 -or -not [string]::IsNullOrEmpty($TitleContains)) {
            $window = Get-TargetWindow
            $targetHandle = [IntPtr]$window.Handle
            $rect = [CadWin32+Rect]::new()
            if (-not [CadWin32]::GetWindowRect([IntPtr]$window.Handle, [ref]$rect)) {
                throw 'Unable to read target window bounds'
            }
            $bounds = [System.Drawing.Rectangle]::FromLTRB($rect.Left, $rect.Top, $rect.Right, $rect.Bottom)
        }
        else {
            $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
        }
        $bitmap = [System.Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            if ($targetHandle -ne [IntPtr]::Zero) {
                $hdc = $graphics.GetHdc()
                try {
                    $printed = [CadWin32]::PrintWindow($targetHandle, $hdc, 2)
                }
                finally {
                    $graphics.ReleaseHdc($hdc)
                }
                if (-not $printed) {
                    $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
                }
            }
            else {
                $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
            }
            $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
        Get-Item -LiteralPath $OutputPath | Select-Object FullName,Length
    }
    'ScreenshotHandle' {
        if ($WindowHandle -eq 0) { throw 'WindowHandle is required' }
        if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw 'OutputPath is required' }
        Add-Type -AssemblyName System.Drawing
        $rect = [CadWin32+Rect]::new()
        if (-not [CadWin32]::GetWindowRect([IntPtr]$WindowHandle, [ref]$rect)) { throw 'Unable to read exact window bounds' }
        $width=$rect.Right-$rect.Left;$height=$rect.Bottom-$rect.Top;if($width-le0-or$height-le0){throw 'Exact window bounds invalid'}
        $bitmap=[System.Drawing.Bitmap]::new($width,$height);$graphics=[System.Drawing.Graphics]::FromImage($bitmap)
        try{$hdc=$graphics.GetHdc();try{$printed=[CadWin32]::PrintWindow([IntPtr]$WindowHandle,$hdc,2)}finally{$graphics.ReleaseHdc($hdc)};if(-not$printed){throw 'Exact PrintWindow failed'};$bitmap.Save($OutputPath,[System.Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
        Get-Item -LiteralPath $OutputPath | Select-Object FullName,Length
    }
}
