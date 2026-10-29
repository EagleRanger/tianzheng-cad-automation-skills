Set-StrictMode -Version Latest

function Invoke-CadRejectedCallSettlementV1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Operation,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Z0-9_:-]+$')][string]$Label,
        [ValidateRange(1, 30000)][int]$TimeoutMilliseconds = 5000,
        [ValidateRange(1, 1000)][int]$PollMilliseconds = 100
    )

    $started = [Diagnostics.Stopwatch]::StartNew()
    $attempts = 0
    $rejectedCount = 0
    $lastRejectedHresult = $null

    while ($true) {
        $attempts++
        try {
            $value = & $Operation
            $started.Stop()
            return [pscustomobject]@{
                status = 'PASS'
                label = $Label
                value = $value
                attempts = $attempts
                rejected_count = $rejectedCount
                last_rejected_hresult = $lastRejectedHresult
                elapsed_ms = [int]$started.ElapsedMilliseconds
            }
        }
        catch {
            $signedHresult = [int]$_.Exception.HResult
            $unsignedHresult = [BitConverter]::ToUInt32([BitConverter]::GetBytes($signedHresult), 0)
            $hresultText = ('0x{0:X8}' -f $unsignedHresult)
            if ($unsignedHresult -notin @([uint32]2147549185, [uint32]2147549450)) {
                throw
            }

            $rejectedCount++
            $lastRejectedHresult = $hresultText
            if ($started.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
                $started.Stop()
                throw [TimeoutException]::new("CAD_COM_REJECTED_SETTLEMENT_TIMEOUT:${Label}:${hresultText}:ATTEMPTS=$attempts")
            }
            Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds, [Math]::Max(1, $TimeoutMilliseconds - [int]$started.ElapsedMilliseconds)))
        }
    }
}
