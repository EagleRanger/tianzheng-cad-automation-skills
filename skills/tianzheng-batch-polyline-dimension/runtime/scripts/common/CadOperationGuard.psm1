Set-StrictMode -Version Latest

function Enter-CadOperationGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [int]$TimeoutMilliseconds = 0,
        [switch]$AllowExistingAcad,
        [switch]$IgnorePause
    )

    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $pausePath = Join-Path $root 'CAD_OPERATIONS_PAUSED.json'
    if (-not $IgnorePause -and (Test-Path -LiteralPath $pausePath)) {
        $pause = Get-Content -LiteralPath $pausePath -Raw | ConvertFrom-Json
        throw "CAD_AUTOMATION_PAUSED=$($pause.reason)"
    }

    $existingAcad = @(Get-Process acad -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            Id = [int]$_.Id
            MainWindowHandle = [int64]$_.MainWindowHandle
            MainWindowTitle = [string]$_.MainWindowTitle
            StartTime = try { $_.StartTime.ToString('o') } catch { '' }
        }
    })
    if (-not $AllowExistingAcad -and $existingAcad.Count -gt 0) {
        $ids = ($existingAcad.Id -join ',')
        throw "EXISTING_ACAD_PROCESS_DETECTED=$ids"
    }

    $mutexName = 'Local\Codex.TianzhengCad.Exclusive.v1'
    $mutex = [Threading.Mutex]::new($false, $mutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne([Math]::Max(0, $TimeoutMilliseconds))
        } catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            $ownerPath = Join-Path $root '.cad-operation-owner.json'
            $owner = if (Test-Path -LiteralPath $ownerPath) {
                Get-Content -LiteralPath $ownerPath -Raw
            } else {
                'unknown'
            }
            throw "TIANZHENG_OPERATION_BUSY=$owner"
        }

        $ownerPath = Join-Path $root '.cad-operation-owner.json'
        $owner = [ordered]@{
            operation_id = $OperationId
            process_id = $PID
            acquired_at = (Get-Date).ToString('o')
            mutex_name = $mutexName
            baseline_acad = @($existingAcad)
        }
        $owner | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ownerPath -Encoding UTF8

        return [pscustomobject]@{
            Mutex = $mutex
            OwnerPath = $ownerPath
            OperationId = $OperationId
            ProcessId = $PID
            BaselineAcad = @($existingAcad)
        }
    } catch {
        if ($acquired) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        $mutex.Dispose()
        throw
    }
}

function Exit-CadOperationGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Guard)

    try {
        if (Test-Path -LiteralPath $Guard.OwnerPath) {
            $remove = $false
            try {
                $owner = Get-Content -LiteralPath $Guard.OwnerPath -Raw | ConvertFrom-Json
                $remove = ([int]$owner.process_id -eq [int]$Guard.ProcessId) -and
                    ([string]$owner.operation_id -eq [string]$Guard.OperationId)
            } catch {}
            if ($remove) { Remove-Item -LiteralPath $Guard.OwnerPath -Force }
        }
    } finally {
        try { $Guard.Mutex.ReleaseMutex() } catch {}
        try { $Guard.Mutex.Dispose() } catch {}
    }
}

Export-ModuleMember -Function Enter-CadOperationGuard, Exit-CadOperationGuard
