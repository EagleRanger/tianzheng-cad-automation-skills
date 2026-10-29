param(
    [switch]$ColdStart,
    [switch]$RecoveryAttempt,
    [switch]$RecentCadCleanup,
    [double]$AvailableMemoryMb = -1,
    [double]$TotalMemoryMb = -1,
    [double]$CadWorkingSetMb = -1,
    [double]$CadPrivateMemoryMb = -1,
    [int]$AcadProcessCount = -1,
    [int]$TgStartProcessCount = -1
)

$ErrorActionPreference = 'Stop'

if ($AvailableMemoryMb -lt 0 -or $TotalMemoryMb -lt 0) {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if ($AvailableMemoryMb -lt 0) { $AvailableMemoryMb = [double]$os.FreePhysicalMemory / 1024.0 }
        if ($TotalMemoryMb -lt 0) { $TotalMemoryMb = [double]$os.TotalVisibleMemorySize / 1024.0 }
    } catch {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $computerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
        if ($AvailableMemoryMb -lt 0) { $AvailableMemoryMb = [double]$computerInfo.AvailablePhysicalMemory / 1MB }
        if ($TotalMemoryMb -lt 0) { $TotalMemoryMb = [double]$computerInfo.TotalPhysicalMemory / 1MB }
    }
}
if ($TotalMemoryMb -le 0 -or $AvailableMemoryMb -lt 0 -or $AvailableMemoryMb -gt $TotalMemoryMb) {
    throw 'TIANZHENG_STARTUP_MEMORY_SAMPLE_INVALID'
}

$acad = @(Get-Process -Name acad -ErrorAction SilentlyContinue)
$tgstart = @(Get-Process -Name TGStart -ErrorAction SilentlyContinue)
if ($AcadProcessCount -lt 0) { $AcadProcessCount = $acad.Count }
if ($TgStartProcessCount -lt 0) { $TgStartProcessCount = $tgstart.Count }
if ($CadWorkingSetMb -lt 0) {
    $CadWorkingSetMb = 0.0
    foreach ($cadSample in @($acad + $tgstart)) { $CadWorkingSetMb += [double]$cadSample.WorkingSet64 / 1MB }
}
if ($CadPrivateMemoryMb -lt 0) {
    $CadPrivateMemoryMb = 0.0
    foreach ($cadSample in @($acad + $tgstart)) { $CadPrivateMemoryMb += [double]$cadSample.PrivateMemorySize64 / 1MB }
}
if ($AcadProcessCount -lt 0 -or $TgStartProcessCount -lt 0 -or $CadWorkingSetMb -lt 0 -or $CadPrivateMemoryMb -lt 0) {
    throw 'TIANZHENG_STARTUP_PROCESS_SAMPLE_INVALID'
}

$availableFraction = if ($TotalMemoryMb -gt 0) { $AvailableMemoryMb / $TotalMemoryMb } else { 0.0 }
$memoryPressureReasons = [Collections.Generic.List[string]]::new()
if ($AvailableMemoryMb -lt 4096) { $memoryPressureReasons.Add('AVAILABLE_MEMORY_BELOW_4096_MB') }
if ($availableFraction -lt 0.20) { $memoryPressureReasons.Add('AVAILABLE_MEMORY_BELOW_20_PERCENT') }
if ($CadWorkingSetMb -gt 4096) { $memoryPressureReasons.Add('CAD_WORKING_SET_ABOVE_4096_MB') }
if ($CadPrivateMemoryMb -gt 6144) { $memoryPressureReasons.Add('CAD_PRIVATE_MEMORY_ABOVE_6144_MB') }
if ($AcadProcessCount -gt 1) { $memoryPressureReasons.Add('MULTIPLE_ACAD_PROCESSES') }
if ($TgStartProcessCount -gt 1) { $memoryPressureReasons.Add('MULTIPLE_TGSTART_PROCESSES') }
if ($RecentCadCleanup) { $memoryPressureReasons.Add('RECENT_CAD_CLEANUP_REQUIRES_EXTENDED_RESTART_BUDGET') }

$tier = 'NORMAL'
$totalTimeout = 180
$noProgressTimeout = 180
$postCleanupQuiescence = 15
if ($ColdStart -or $memoryPressureReasons.Count -gt 0) {
    $tier = 'COLD_OR_MEMORY_PRESSURE'
    $totalTimeout = 300
    $noProgressTimeout = 300
    $postCleanupQuiescence = 30
}
if ($RecoveryAttempt) {
    $tier = 'RECOVERY'
    $totalTimeout = 420
    $noProgressTimeout = 420
    $postCleanupQuiescence = 45
}

[pscustomobject]@{
    schema_version = 1
    status = 'PASS'
    tier = $tier
    total_timeout_seconds = $totalTimeout
    hard_cap_seconds = $totalTimeout * 2
    no_progress_timeout_seconds = $noProgressTimeout
    post_cleanup_quiescence_seconds = $postCleanupQuiescence
    cold_start = [bool]$ColdStart
    recovery_attempt = [bool]$RecoveryAttempt
    recent_cad_cleanup = [bool]$RecentCadCleanup
    available_memory_mb = [math]::Round($AvailableMemoryMb, 1)
    total_memory_mb = [math]::Round($TotalMemoryMb, 1)
    available_memory_fraction = [math]::Round($availableFraction, 4)
    cad_working_set_mb = [math]::Round($CadWorkingSetMb, 1)
    cad_private_memory_mb = [math]::Round($CadPrivateMemoryMb, 1)
    system_memory_used_fraction = [math]::Round((1.0 - $availableFraction), 4)
    acad_process_count = $AcadProcessCount
    tgstart_process_count = $TgStartProcessCount
    memory_pressure = ($memoryPressureReasons.Count -gt 0)
    memory_pressure_reasons = @($memoryPressureReasons)
    progress_renews_no_progress_lease = $true
    progress_signals = @(
        'acad_process_set_changed',
        'tgstart_process_set_changed',
        'visible_window_signature_changed',
        'target_drawing_window_seen',
        'allowlisted_dialog_log_changed',
        'platform_2021_confirmed'
    )
} | ConvertTo-Json -Depth 6
