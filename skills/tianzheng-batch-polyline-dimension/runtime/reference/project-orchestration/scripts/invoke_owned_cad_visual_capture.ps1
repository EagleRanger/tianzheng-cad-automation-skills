param(
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$CacheDirectory,
    [string]$Label = 'cad',
    [string]$EvidenceKey = '',
    [ValidateRange(640,3840)][int]$ReviewMaxWidth = 1920,
    [ValidateRange(20,400)][int]$MaxCachedFrames = 40,
    [ValidateRange(134217728,4294967296)][long]$MaxCacheBytes = 536870912,
    [ValidateRange(60,100)][int]$ReviewJpegQuality = 90
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$captureProcess = Get-Process -Id $PID
$captureProcess.Refresh()
$workingSetBefore = [long]$captureProcess.WorkingSet64
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Resolve-ProjectPath([string]$Raw, [string]$Code, [switch]$MustExist) {
    $path = [IO.Path]::GetFullPath($Raw)
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Code}_OUTSIDE_PROJECT"
    }
    if ($MustExist -and -not (Test-Path -LiteralPath $path)) { throw "${Code}_MISSING" }
    return $path
}

function Write-JsonAtomic([string]$Path, $Payload) {
    $temporary = $Path + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Payload | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

$ownerPath = Resolve-ProjectPath $OwnerStatePath 'OWNER_STATE' -MustExist
$cache = Resolve-ProjectPath $CacheDirectory 'CACHE_DIRECTORY'
if (-not (Test-Path -LiteralPath $cache -PathType Container)) {
    New-Item -ItemType Directory -Path $cache | Out-Null
}

$latestPath = Join-Path $cache 'latest_capture.json'
$prior = if (Test-Path -LiteralPath $latestPath -PathType Leaf) {
    try { Get-Content -LiteralPath $latestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
} else { $null }
$priorCaptureValid = $false
if ($null -ne $prior -and (Test-Path -LiteralPath ([string]$prior.capture_metadata_path) -PathType Leaf)) {
    try {
        $priorMeta = Get-Content -LiteralPath ([string]$prior.capture_metadata_path) -Raw -Encoding UTF8 | ConvertFrom-Json
        $priorCaptureValid = [bool]$priorMeta.quality.valid -and [int]$priorMeta.window.width -ge 640 -and [int]$priorMeta.window.height -ge 480
    } catch { $priorCaptureValid = $false }
}

$owner = Get-Content -LiteralPath $ownerPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$owner.status -cne 'ready' -or [int]$owner.process_id -le 0 -or [long]$owner.main_window_handle -le 0) {
    throw 'OWNER_STATE_NOT_READY_FOR_CAPTURE'
}
if (-not (Get-Process -Id ([int]$owner.process_id) -ErrorAction SilentlyContinue)) {
    throw 'OWNED_CAD_PROCESS_NOT_RUNNING'
}

# A caller-supplied evidence key binds one semantic drawing/view checkpoint.
# Repeated consumers of that exact checkpoint reuse the encoded frame without
# allocating another full-window bitmap.  Callers must change the key whenever
# drawing content, annotation state, layout, or the intended review view changes.
if (-not [string]::IsNullOrWhiteSpace($EvidenceKey) -and $null -ne $prior -and
    $priorCaptureValid -and
    [string]$prior.evidence_key -ceq $EvidenceKey -and
    [int]$prior.process_id -eq [int]$owner.process_id -and
    [long]$prior.window_handle -eq [long]$owner.main_window_handle -and
    (Test-Path -LiteralPath ([string]$prior.raw_path) -PathType Leaf) -and
    (Test-Path -LiteralPath ([string]$prior.review_path) -PathType Leaf)) {
    $captureProcess.Refresh()
    [ordered]@{
        schema_version = 1
        status = 'PASS_CACHED_NO_CAPTURE'
        backend = 'CACHE'
        foreground_or_input_used = $false
        window_activation_used = $false
        window_show_restore_used = $false
        foreground_screen_copy_used = $false
        evidence_key = $EvidenceKey
        deduplicated_identical_frame = $true
        capture_skipped = $true
        process_id = [int]$owner.process_id
        window_handle = [long]$owner.main_window_handle
        raw_path = [string]$prior.raw_path
        raw_sha256 = [string]$prior.raw_sha256
        review_path = [string]$prior.review_path
        review_sha256 = [string]$prior.review_sha256
        elapsed_ms = [int][Math]::Round(((Get-Date) - $started).TotalMilliseconds)
        working_set_before_mb = [Math]::Round($workingSetBefore / 1MB, 2)
        peak_working_set_mb = [Math]::Round([long]$captureProcess.PeakWorkingSet64 / 1MB, 2)
    } | ConvertTo-Json -Depth 8
    return
}

$safeLabel = [regex]::Replace($Label, '[^A-Za-z0-9._-]+', '_').Trim('_')
if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = 'cad' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$base = "cad_capture_${stamp}_${safeLabel}"
$rawPath = Join-Path $cache ($base + '.png')
$captureMetaPath = Join-Path $cache ($base + '.capture.json')
$reviewPath = Join-Path $cache ($base + '.review.jpg')
$receiptPath = Join-Path $cache 'latest_capture_receipt.json'
$captureEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/cad_capture_compat.ps1'
$actionEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1'

# Establish a full owned frame before asking AutoCAD to redraw.  Regen while
# the frame is still minimized produces a valid full-window shell after restore
# but leaves the hardware drawing canvas blank.  PrepareOnly performs no pixel
# capture; the later PrintWindow remains the single screenshot attempt.
$prepareText = (& $captureEntry `
    -OutputPath $rawPath `
    -MetadataPath $captureMetaPath `
    -WindowHandle ([long]$owner.main_window_handle) `
    -ProcessId ([int]$owner.process_id) `
    -Backend PrintWindow `
    -AllowNonActivatingRestore `
    -PrepareOnly | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($prepareText)) { throw 'BACKGROUND_CAPTURE_PREPARE_RETURNED_NO_RECEIPT' }
$prepare = $prepareText | ConvertFrom-Json
if ([string]$prepare.status -cne 'PASS' -or [int]$prepare.width -lt 640 -or [int]$prepare.height -lt 480) {
    throw 'BACKGROUND_CAPTURE_PREPARE_NOT_FULL_FRAME'
}
if ([bool]$prepare.window_activation_used -or [bool]$prepare.foreground_screen_copy_used -or [bool]$prepare.mouse_or_keyboard_input_used) {
    throw 'BACKGROUND_CAPTURE_PREPARE_STOLE_FOREGROUND_OR_INPUT'
}
& $actionEntry `
    -ProcessId ([int]$owner.process_id) `
    -Action REGEN `
    -OwnerStatePath $ownerPath `
    -TimeoutSeconds 30 | Out-Null

$captureText = (& $captureEntry `
    -OutputPath $rawPath `
    -MetadataPath $captureMetaPath `
    -WindowHandle ([long]$owner.main_window_handle) `
    -ProcessId ([int]$owner.process_id) `
    -Backend PrintWindow `
    -AllowDiversePrintWindowWithoutNearBlack | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($captureText)) { throw 'BACKGROUND_CAPTURE_RETURNED_NO_RECEIPT' }
$captureResult = $captureText | ConvertFrom-Json
$captureResult.window_show_restore_used = [bool]$prepare.window_show_restore_used
$captureResult.window_nonactivating_restore_used = [bool]$prepare.window_nonactivating_restore_used
if ([string]$captureResult.status -cne 'PASS') { throw 'BACKGROUND_CAPTURE_FAILED' }
if ([bool]$captureResult.window_activation_used -or
    ([bool]$captureResult.window_show_restore_used -and -not [bool]$captureResult.window_nonactivating_restore_used) -or
    [bool]$captureResult.foreground_screen_copy_used -or
    [bool]$captureResult.mouse_or_keyboard_input_used) {
    throw 'BACKGROUND_CAPTURE_WINDOW_OR_INPUT_MUTATION_FORBIDDEN'
}

$rawHash = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash
$deduplicated = $false
if ($null -ne $prior -and [string]$prior.raw_sha256 -ceq $rawHash -and
    (Test-Path -LiteralPath ([string]$prior.raw_path) -PathType Leaf) -and
    (Test-Path -LiteralPath ([string]$prior.review_path) -PathType Leaf)) {
    # Delete only the just-created transient cache pair.  The prior identical
    # frame and all formal run evidence remain untouched.
    Remove-Item -LiteralPath $rawPath,$captureMetaPath -Force
    $rawPath = [string]$prior.raw_path
    $captureMetaPath = [string]$prior.capture_metadata_path
    $reviewPath = [string]$prior.review_path
    $deduplicated = $true
} else {
    Add-Type -AssemblyName System.Drawing
    $source = [Drawing.Image]::FromFile($rawPath)
    try {
        $scale = [Math]::Min(1.0, $ReviewMaxWidth / [double]$source.Width)
        $reviewWidth = [Math]::Max(1, [int][Math]::Round($source.Width * $scale))
        $reviewHeight = [Math]::Max(1, [int][Math]::Round($source.Height * $scale))
        $review = [Drawing.Bitmap]::new($reviewWidth, $reviewHeight, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($review)
            try {
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.DrawImage($source, 0, 0, $reviewWidth, $reviewHeight)
            } finally { $graphics.Dispose() }

            $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -ceq 'image/jpeg' | Select-Object -First 1
            $parameters = [Drawing.Imaging.EncoderParameters]::new(1)
            try {
                $parameters.Param[0] = [Drawing.Imaging.EncoderParameter]::new([Drawing.Imaging.Encoder]::Quality, [long]$ReviewJpegQuality)
                $review.Save($reviewPath, $codec, $parameters)
            } finally { $parameters.Dispose() }
        } finally { $review.Dispose() }
    } finally { $source.Dispose() }
}

$reviewHash = (Get-FileHash -LiteralPath $reviewPath -Algorithm SHA256).Hash
$index = [ordered]@{
    schema_version = 1
    updated_at = (Get-Date).ToString('o')
    process_id = [int]$owner.process_id
    window_handle = [long]$owner.main_window_handle
    target_dwg = [string]$owner.target_dwg
    evidence_key = $EvidenceKey
    raw_path = [IO.Path]::GetFullPath($rawPath)
    raw_sha256 = $rawHash
    capture_metadata_path = [IO.Path]::GetFullPath($captureMetaPath)
    review_path = [IO.Path]::GetFullPath($reviewPath)
    review_sha256 = $reviewHash
}
Write-JsonAtomic $latestPath $index

# Bounded transient cache: newest frames win, and the stricter of count/bytes
# applies.  Only files created by this entrypoint are candidates; formal run
# evidence outside this dedicated cache is never touched.
$frames = @(Get-ChildItem -LiteralPath $cache -Filter 'cad_capture_*.png' -File | Sort-Object LastWriteTimeUtc -Descending)
$kept = [Collections.Generic.List[string]]::new()
$removed = [Collections.Generic.List[string]]::new()
[long]$keptBytes = 0
foreach ($frame in $frames) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($frame.Name)
    $related = @(
        $frame.FullName,
        (Join-Path $cache ($stem + '.capture.json')),
        (Join-Path $cache ($stem + '.review.jpg')),
        (Join-Path $cache ($stem + '.receipt.json'))
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    $frameBytes = [long](($related | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum)
    if ($kept.Count -lt $MaxCachedFrames -and $keptBytes + $frameBytes -le $MaxCacheBytes) {
        [void]$kept.Add($frame.FullName)
        $keptBytes += $frameBytes
    } else {
        foreach ($item in $related) {
            Remove-Item -LiteralPath $item -Force
            [void]$removed.Add($item)
        }
    }
}

$captureProcess.Refresh()
$receipt = [ordered]@{
    schema_version = 1
    status = 'PASS'
    backend = 'PrintWindow'
    foreground_or_input_used = $false
    window_activation_used = $false
    window_show_restore_used = [bool]$captureResult.window_show_restore_used
    window_nonactivating_restore_used = [bool]$captureResult.window_nonactivating_restore_used
    full_frame_prepare_before_regen = $true
    regen_before_capture = $true
    foreground_before_prepare = [long]$prepare.foreground_before
    foreground_after_prepare = [long]$prepare.foreground_after_restore
    foreground_screen_copy_used = $false
    evidence_key = $EvidenceKey
    capture_skipped = $false
    deduplicated_identical_frame = $deduplicated
    process_id = [int]$owner.process_id
    window_handle = [long]$owner.main_window_handle
    raw_path = [IO.Path]::GetFullPath($rawPath)
    raw_sha256 = $rawHash
    review_path = [IO.Path]::GetFullPath($reviewPath)
    review_sha256 = $reviewHash
    elapsed_ms = [int][Math]::Round(((Get-Date) - $started).TotalMilliseconds)
    working_set_before_mb = [Math]::Round($workingSetBefore / 1MB, 2)
    peak_working_set_mb = [Math]::Round([long]$captureProcess.PeakWorkingSet64 / 1MB, 2)
    cache_policy = [ordered]@{
        maximum_frames = $MaxCachedFrames
        maximum_bytes = $MaxCacheBytes
        kept_frame_count = $kept.Count
        kept_bytes = $keptBytes
        removed_file_count = $removed.Count
    }
}
Write-JsonAtomic $receiptPath $receipt
$receipt | ConvertTo-Json -Depth 10
