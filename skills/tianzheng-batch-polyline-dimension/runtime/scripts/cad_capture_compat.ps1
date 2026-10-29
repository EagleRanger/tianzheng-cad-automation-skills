param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$MetadataPath,

    [long]$WindowHandle = 0,

    [int]$ProcessId = 0,

    [string]$TitleContains = '',

    [ValidateSet('PrintWindow')]
    [string]$Backend = 'PrintWindow',

    [switch]$AllowDiversePrintWindowWithoutNearBlack,

    [switch]$AllowNonActivatingRestore,

    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class CadCaptureWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out Rect rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int command);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

}
'@

# Use physical pixels on mixed-DPI Windows 10 desktops.  Without this the
# window rectangle can be virtualized to 960x540 while AutoCAD renders at
# 1920x1080, producing a cropped upper-left capture.
[void][CadCaptureWin32]::SetProcessDpiAwarenessContext([IntPtr](-4))

function Get-VisibleWindows {
    $items = [Collections.Generic.List[object]]::new()
    $callback = [CadCaptureWin32+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        if (-not [CadCaptureWin32]::IsWindowVisible($hWnd)) { return $true }

        [uint32]$windowPid = 0
        [void][CadCaptureWin32]::GetWindowThreadProcessId($hWnd, [ref]$windowPid)
        $title = [Text.StringBuilder]::new(2048)
        [void][CadCaptureWin32]::GetWindowText($hWnd, $title, $title.Capacity)
        $rect = [CadCaptureWin32+Rect]::new()
        if (-not [CadCaptureWin32]::GetWindowRect($hWnd, [ref]$rect)) { return $true }

        $items.Add([pscustomobject]@{
            handle = $hWnd.ToInt64()
            process_id = [int]$windowPid
            title = $title.ToString()
            left = $rect.Left
            top = $rect.Top
            right = $rect.Right
            bottom = $rect.Bottom
            width = $rect.Right - $rect.Left
            height = $rect.Bottom - $rect.Top
        })
        return $true
    }
    [void][CadCaptureWin32]::EnumWindows($callback, [IntPtr]::Zero)
    return $items
}

function Get-TargetWindow {
    if ($WindowHandle -eq 0 -and $ProcessId -eq 0 -and [string]::IsNullOrWhiteSpace($TitleContains)) {
        throw 'TARGET_SELECTOR_REQUIRED'
    }

    # An owned HWND is the authoritative selector.  A minimized AutoCAD frame
    # remains a valid HWND but Windows moves it to (-32000,-32000) and exposes
    # only an icon-sized rectangle.  PrintWindow then returns a toolbar shell,
    # not the drawing canvas.  When explicitly authorized, restore that exact
    # owned frame without activation and prove it has a full window rectangle
    # before consuming the single screenshot attempt.
    if ($WindowHandle -ne 0) {
        $handle = [IntPtr]$WindowHandle
        if (-not [CadCaptureWin32]::IsWindow($handle)) {
            throw 'BACKGROUND_PRINTWINDOW_CAPTURE_UNAVAILABLE_NO_WINDOW_MUTATION=TARGET_HWND_INVALID'
        }
        [uint32]$windowPid = 0
        [void][CadCaptureWin32]::GetWindowThreadProcessId($handle, [ref]$windowPid)
        if ($ProcessId -ne 0 -and [int]$windowPid -ne $ProcessId) {
            throw "BACKGROUND_PRINTWINDOW_CAPTURE_UNAVAILABLE_NO_WINDOW_MUTATION=TARGET_HWND_PID_MISMATCH:actual=$windowPid;expected=$ProcessId"
        }
        $title = [Text.StringBuilder]::new(2048)
        [void][CadCaptureWin32]::GetWindowText($handle, $title, $title.Capacity)
        if (-not [string]::IsNullOrWhiteSpace($TitleContains) -and -not $title.ToString().Contains($TitleContains)) {
            throw 'BACKGROUND_PRINTWINDOW_CAPTURE_UNAVAILABLE_NO_WINDOW_MUTATION=TARGET_HWND_TITLE_MISMATCH'
        }
        $rect = [CadCaptureWin32+Rect]::new()
        if (-not [CadCaptureWin32]::GetWindowRect($handle, [ref]$rect)) {
            throw 'BACKGROUND_PRINTWINDOW_CAPTURE_UNAVAILABLE_NO_WINDOW_MUTATION=TARGET_HWND_RECT_UNAVAILABLE'
        }
        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        $wasIconic = [CadCaptureWin32]::IsIconic($handle)
        $looksLikeMinimizedShell = $wasIconic -or ($rect.Left -le -30000 -and $rect.Top -le -30000) -or $width -lt 640 -or $height -lt 480
        $restoredWithoutActivation = $false
        $foregroundBefore = [CadCaptureWin32]::GetForegroundWindow().ToInt64()
        if ($looksLikeMinimizedShell) {
            if (-not $AllowNonActivatingRestore) {
                throw "BACKGROUND_PRINTWINDOW_TARGET_NOT_FULL_FRAME=iconic:$wasIconic;rect:$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
            }
            # SW_SHOWNOACTIVATE: restore/show at the normal size without taking
            # keyboard or mouse focus from the user's current application.
            [void][CadCaptureWin32]::ShowWindowAsync($handle, 4)
            $restoreDeadline = (Get-Date).AddSeconds(4)
            do {
                Start-Sleep -Milliseconds 100
                $rect = [CadCaptureWin32+Rect]::new()
                if (-not [CadCaptureWin32]::GetWindowRect($handle, [ref]$rect)) { continue }
                $width = $rect.Right - $rect.Left
                $height = $rect.Bottom - $rect.Top
            } while ((Get-Date) -lt $restoreDeadline -and ([CadCaptureWin32]::IsIconic($handle) -or $width -lt 640 -or $height -lt 480))
            $foregroundAfterRestore = [CadCaptureWin32]::GetForegroundWindow().ToInt64()
            if ($foregroundAfterRestore -eq $handle.ToInt64() -and $foregroundBefore -ne $handle.ToInt64()) {
                throw 'BACKGROUND_PRINTWINDOW_NONACTIVATING_RESTORE_STOLE_FOREGROUND'
            }
            if ([CadCaptureWin32]::IsIconic($handle) -or $width -lt 640 -or $height -lt 480) {
                throw "BACKGROUND_PRINTWINDOW_NONACTIVATING_RESTORE_FAILED=rect:$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
            }
            $restoredWithoutActivation = $true
        }
        if ($width -lt 640 -or $height -lt 480) {
            throw "BACKGROUND_PRINTWINDOW_TARGET_NOT_FULL_FRAME=rect:$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)"
        }
        return [pscustomobject]@{
            handle = $WindowHandle
            process_id = [int]$windowPid
            title = $title.ToString()
            left = $rect.Left
            top = $rect.Top
            right = $rect.Right
            bottom = $rect.Bottom
            width = $width
            height = $height
            visible = [CadCaptureWin32]::IsWindowVisible($handle)
            was_iconic = $wasIconic
            nonactivating_restore_used = $restoredWithoutActivation
            foreground_before = $foregroundBefore
            foreground_after_restore = [CadCaptureWin32]::GetForegroundWindow().ToInt64()
        }
    }

    $candidates = @(Get-VisibleWindows | Where-Object {
        ($ProcessId -eq 0 -or $_.process_id -eq $ProcessId) -and
        ([string]::IsNullOrWhiteSpace($TitleContains) -or $_.title.Contains($TitleContains))
    })

    if ($candidates.Count -ne 1) {
        $summary = $candidates | Select-Object handle,process_id,title,width,height | ConvertTo-Json -Compress
        throw "TARGET_WINDOW_NOT_UNIQUE=count:$($candidates.Count);candidates:$summary"
    }
    return $candidates[0]
}

function Get-BitmapQuality {
    param([Drawing.Bitmap]$Bitmap)

    $stepX = [Math]::Max(1, [int][Math]::Floor($Bitmap.Width / 64.0))
    $stepY = [Math]::Max(1, [int][Math]::Floor($Bitmap.Height / 48.0))
    $colors = [Collections.Generic.HashSet[int]]::new()
    [double]$sum = 0
    [double]$sumSquared = 0
    [int]$samples = 0
    [int]$nearBlack = 0

    for ($y = 0; $y -lt $Bitmap.Height; $y += $stepY) {
        for ($x = 0; $x -lt $Bitmap.Width; $x += $stepX) {
            $pixel = $Bitmap.GetPixel($x, $y)
            $rgb = ($pixel.R -shl 16) -bor ($pixel.G -shl 8) -bor $pixel.B
            [void]$colors.Add($rgb)
            $luma = 0.2126 * $pixel.R + 0.7152 * $pixel.G + 0.0722 * $pixel.B
            $sum += $luma
            $sumSquared += $luma * $luma
            $samples++
            if ($luma -lt 3) { $nearBlack++ }
        }
    }

    $mean = if ($samples -gt 0) { $sum / $samples } else { 0 }
    $variance = if ($samples -gt 0) { [Math]::Max(0, ($sumSquared / $samples) - ($mean * $mean)) } else { 0 }
    $stddev = [Math]::Sqrt($variance)
    $blackRatio = if ($samples -gt 0) { $nearBlack / [double]$samples } else { 1 }
    $valid = $Bitmap.Width -ge 640 -and $Bitmap.Height -ge 480 -and $colors.Count -ge 12 -and $stddev -ge 3 -and $blackRatio -lt 0.995

    return [pscustomobject]@{
        valid = $valid
        sampled_pixels = $samples
        unique_sampled_colors = $colors.Count
        luminance_mean = [Math]::Round($mean, 3)
        luminance_stddev = [Math]::Round($stddev, 3)
        near_black_ratio = [Math]::Round($blackRatio, 5)
    }
}

function Invoke-PrintWindowCapture {
    param($Window)

    $bitmap = [Drawing.Bitmap]::new($Window.width, $Window.height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.Clear([Drawing.Color]::Magenta)
        $hdc = $graphics.GetHdc()
        try {
            $ok = [CadCaptureWin32]::PrintWindow([IntPtr]$Window.handle, $hdc, 2)
        }
        finally {
            $graphics.ReleaseHdc($hdc)
        }
    }
    finally {
        $graphics.Dispose()
    }

    $quality = Get-BitmapQuality -Bitmap $bitmap
    return [pscustomobject]@{ backend='PrintWindow'; api_success=[bool]$ok; quality=$quality; bitmap=$bitmap }
}

$target = Get-TargetWindow
if ($PrepareOnly) {
    [pscustomobject]@{
        status = 'PASS'
        prepare_only = $true
        window_activation_used = $false
        window_show_restore_used = [bool]$target.nonactivating_restore_used
        window_nonactivating_restore_used = [bool]$target.nonactivating_restore_used
        foreground_screen_copy_used = $false
        mouse_or_keyboard_input_used = $false
        window_handle = $target.handle
        window_title = $target.title
        width = $target.width
        height = $target.height
        foreground_before = [long]$target.foreground_before
        foreground_after_restore = [long]$target.foreground_after_restore
    } | ConvertTo-Json -Compress
    return
}
$attempts = [Collections.Generic.List[object]]::new()
$selected = $null

foreach ($candidateBackend in @('PrintWindow')) {
    $capture = $null
    try {
        $capture = Invoke-PrintWindowCapture -Window $target
        $attempts.Add([pscustomobject]@{
            backend = $capture.backend
            api_success = $capture.api_success
            quality = $capture.quality
            error = $null
        })
        # Color diversity alone is not sufficient: a 314x50 minimized toolbar
        # can be colorful while containing no CAD canvas.  Only the full-frame
        # quality predicate may accept a capture.
        if ($capture.api_success -and $capture.quality.valid) {
            $selected = $capture
            break
        }
        $capture.bitmap.Dispose()
    }
    catch {
        if ($null -ne $capture -and $null -ne $capture.bitmap) { $capture.bitmap.Dispose() }
        $attempts.Add([pscustomobject]@{
            backend = $candidateBackend
            api_success = $false
            quality = $null
            error = $_.Exception.Message
        })
    }
}

if ($null -eq $selected) {
    throw "BACKGROUND_PRINTWINDOW_CAPTURE_UNAVAILABLE_NO_WINDOW_MUTATION=$($attempts | ConvertTo-Json -Compress -Depth 6)"
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    [void](New-Item -ItemType Directory -Path $outputDirectory)
}

try {
    $selected.bitmap.Save($resolvedOutput, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $selected.bitmap.Dispose()
}

if ([string]::IsNullOrWhiteSpace($MetadataPath)) {
    $MetadataPath = [IO.Path]::ChangeExtension($resolvedOutput, '.capture.json')
}
$resolvedMetadata = [IO.Path]::GetFullPath($MetadataPath)
$metadataDirectory = Split-Path -Parent $resolvedMetadata
if (-not (Test-Path -LiteralPath $metadataDirectory)) {
    [void](New-Item -ItemType Directory -Path $metadataDirectory)
}

$sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedOutput).Hash
$metadata = [ordered]@{
    schema_version = 1
    status = 'PASS'
    captured_at_utc = [DateTime]::UtcNow.ToString('o')
    backend_requested = $Backend
    backend_used = $selected.backend
    window_activation_used = $false
    window_show_restore_used = [bool]$target.nonactivating_restore_used
    window_nonactivating_restore_used = [bool]$target.nonactivating_restore_used
    foreground_screen_copy_used = $false
    mouse_or_keyboard_input_used = $false
    window = [ordered]@{
        handle = $target.handle
        process_id = $target.process_id
        title = $target.title
        left = $target.left
        top = $target.top
        right = $target.right
        bottom = $target.bottom
        width = $target.width
        height = $target.height
        was_iconic = [bool]$target.was_iconic
        nonactivating_restore_used = [bool]$target.nonactivating_restore_used
        foreground_before = [long]$target.foreground_before
        foreground_after_restore = [long]$target.foreground_after_restore
    }
    coordinate_mapping = [ordered]@{
        screenshot_origin_is_window_top_left = $true
        screen_x = 'window.left + screenshot.x'
        screen_y = 'window.top + screenshot.y'
    }
    output_path = $resolvedOutput
    output_sha256 = $sha256
    quality = $selected.quality
    attempts = $attempts
}

$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedMetadata -Encoding UTF8

[pscustomobject]@{
    status = 'PASS'
    backend = $selected.backend
    window_activation_used = $false
    window_show_restore_used = [bool]$target.nonactivating_restore_used
    window_nonactivating_restore_used = [bool]$target.nonactivating_restore_used
    foreground_screen_copy_used = $false
    mouse_or_keyboard_input_used = $false
    window_handle = $target.handle
    window_title = $target.title
    width = $target.width
    height = $target.height
    output = $resolvedOutput
    metadata = $resolvedMetadata
    sha256 = $sha256
} | ConvertTo-Json -Compress
