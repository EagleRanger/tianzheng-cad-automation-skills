param(
    [ValidateRange(5,300)][int]$TimeoutSeconds = 90,
    [ValidateRange(1,10)][int]$SampleIntervalSeconds = 2,
    [ValidateRange(2,10)][int]$StableSampleCount = 3,
    [ValidateRange(16,2048)][double]$AvailableMemoryJitterMb = 256,
    [string]$ObservationSequencePath = ''
)

$ErrorActionPreference = 'Stop'

function Get-LiveObservation {
    $availableMemoryMb = 0.0
    $totalMemoryMb = 0.0
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $availableMemoryMb = [double]$os.FreePhysicalMemory / 1024.0
        $totalMemoryMb = [double]$os.TotalVisibleMemorySize / 1024.0
    } catch {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $computerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
        $availableMemoryMb = [double]$computerInfo.AvailablePhysicalMemory / 1MB
        $totalMemoryMb = [double]$computerInfo.TotalPhysicalMemory / 1MB
    }
    $cad = @(Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue)
    $workingSetMb = 0.0; $privateMemoryMb = 0.0
    foreach ($cadSample in $cad) {
        $workingSetMb += [double]$cadSample.WorkingSet64 / 1MB
        $privateMemoryMb += [double]$cadSample.PrivateMemorySize64 / 1MB
    }
    [pscustomobject]@{
        observed_at = (Get-Date).ToString('o')
        available_memory_mb = $availableMemoryMb
        total_memory_mb = $totalMemoryMb
        cad_working_set_mb = $workingSetMb
        cad_private_memory_mb = $privateMemoryMb
        acad_process_count = @($cad | Where-Object ProcessName -eq 'acad').Count
        tgstart_process_count = @($cad | Where-Object ProcessName -eq 'TGStart').Count
    }
}

$testSequence = @()
if (-not [string]::IsNullOrWhiteSpace($ObservationSequencePath)) {
    $parsedSequence = Get-Content -LiteralPath $ObservationSequencePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $testSequence = @($parsedSequence | ForEach-Object { $_ })
    if ($testSequence.Count -eq 0) { throw 'TIANZHENG_RESOURCE_OBSERVATION_SEQUENCE_EMPTY' }
}

$observations = [Collections.Generic.List[object]]::new()
$stable = 0
$lastAvailable = $null
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$testIndex = 0
while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    $sample = if ($testSequence.Count -gt 0) {
        $value = $testSequence[[Math]::Min($testIndex, $testSequence.Count - 1)]
        $testIndex++
        $value
    } else { Get-LiveObservation }
    $observations.Add($sample)

    $processesGone = ([int]$sample.acad_process_count -eq 0 -and [int]$sample.tgstart_process_count -eq 0)
    $cadMemoryReleased = ([double]$sample.cad_working_set_mb -le 32 -and [double]$sample.cad_private_memory_mb -le 32)
    $memoryStable = ($null -ne $lastAvailable -and [math]::Abs([double]$sample.available_memory_mb - [double]$lastAvailable) -le $AvailableMemoryJitterMb)
    if ($processesGone -and $cadMemoryReleased -and $memoryStable) { $stable++ } else { $stable = 0 }
    $lastAvailable = [double]$sample.available_memory_mb
    if ($stable -ge $StableSampleCount) { break }
    if ($testSequence.Count -gt 0 -and $testIndex -ge $testSequence.Count -and $stable -lt $StableSampleCount) { break }
    Start-Sleep -Seconds $SampleIntervalSeconds
}

$last = $observations[-1]
$ready = ($stable -ge $StableSampleCount)
$availableFraction = [double]$last.available_memory_mb / [double]$last.total_memory_mb
$pressure = ([double]$last.available_memory_mb -lt 4096 -or $availableFraction -lt 0.20)
$result = [pscustomobject]@{
    schema_version = 1
    status = if ($ready) { 'PASS' } else { 'TIMEOUT' }
    ready_to_restart = $ready
    elapsed_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    sample_count = $observations.Count
    stable_sample_count = $stable
    available_memory_mb = [math]::Round([double]$last.available_memory_mb, 1)
    total_memory_mb = [math]::Round([double]$last.total_memory_mb, 1)
    available_memory_fraction = [math]::Round($availableFraction, 4)
    cad_working_set_mb = [math]::Round([double]$last.cad_working_set_mb, 1)
    cad_private_memory_mb = [math]::Round([double]$last.cad_private_memory_mb, 1)
    acad_process_count = [int]$last.acad_process_count
    tgstart_process_count = [int]$last.tgstart_process_count
    memory_pressure = $pressure
    observations = @($observations)
}
$result | ConvertTo-Json -Depth 8
