param(
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$CheckpointReceiptPath,
    [ValidateRange(1,100)][int]$ExpectedRetention = 10,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'

function Resolve-ProjectFile {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ErrorCode)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorCode }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw ($ErrorCode + '_MISSING') }
    return $full
}

$ownerPath = Resolve-ProjectFile -Path $OwnerStatePath -ErrorCode 'STAGE_CHECKPOINT_OWNER_OUTSIDE_RUNS'
$receiptPath = Resolve-ProjectFile -Path $CheckpointReceiptPath -ErrorCode 'STAGE_CHECKPOINT_RECEIPT_OUTSIDE_RUNS'
$owner = Get-Content -LiteralPath $ownerPath -Raw -Encoding UTF8 | ConvertFrom-Json
$receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json

$working = [IO.Path]::GetFullPath([string]$owner.target_dwg)
if (-not $working.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'STAGE_CHECKPOINT_WORKING_DWG_OUTSIDE_RUNS' }
if (-not (Test-Path -LiteralPath $working -PathType Leaf)) { throw 'STAGE_CHECKPOINT_WORKING_DWG_MISSING' }
if ([IO.Path]::GetFullPath([string]$receipt.working_dwg) -cne $working) { throw 'STAGE_CHECKPOINT_WORKING_DWG_MISMATCH' }
if ([string]$receipt.status -notin @('PASS','NO_CHANGE')) { throw "STAGE_CHECKPOINT_STATUS_INVALID=$($receipt.status)" }
if ([int]$receipt.dbmod_after -ne 0) { throw 'STAGE_CHECKPOINT_DBMOD_NOT_ZERO' }
if ([int]$receipt.retention -ne $ExpectedRetention) { throw 'STAGE_CHECKPOINT_RETENTION_MISMATCH' }
if ([int]$receipt.retained_count -gt $ExpectedRetention) { throw 'STAGE_CHECKPOINT_RETENTION_OVERFLOW' }
if ([string]::IsNullOrWhiteSpace([string]$receipt.working_sha256)) { throw 'STAGE_CHECKPOINT_WORKING_HASH_MISSING' }

$workingHash = $null
try { $workingHash = (Get-FileHash -LiteralPath $working -Algorithm SHA256 -ErrorAction Stop).Hash }
catch {
    # A live T20 document can legitimately deny filesystem read sharing.  In
    # that case validate the native SAVE copy plus a fresh clean/idle document
    # audit instead of weakening the checkpoint gate or closing the drawing.
    $liveCopy = Resolve-ProjectFile -Path ([string]$receipt.live_copy) -ErrorCode 'STAGE_CHECKPOINT_LIVE_COPY_OUTSIDE_RUNS'
    $liveCopyHash = (Get-FileHash -LiteralPath $liveCopy -Algorithm SHA256).Hash
    if ($liveCopyHash -cne [string]$receipt.working_sha256) { throw 'STAGE_CHECKPOINT_LIVE_COPY_HASH_DRIFT' }
    if ($owner.status -cne 'ready' -or [int]$owner.process_id -le 0) { throw 'STAGE_CHECKPOINT_LIVE_OWNER_NOT_READY' }
    $dispatcher = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1'
    $auditPath = Join-Path (Split-Path -Parent $receiptPath) 'checkpoint_assert_live_state.tsv'
    $ownedWindow = if ($null -ne $owner.main_window_handle) { [long]$owner.main_window_handle } else { [long]$owner.window_handle }
    if ($ownedWindow -le 0) { throw 'STAGE_CHECKPOINT_LIVE_WINDOW_MISSING' }
    $auditText = (& $dispatcher -ProcessId ([int]$owner.process_id) -OwnerStatePath $ownerPath `
        -WindowHandle $ownedWindow -Action AUDIT_OWNED_STATE -ReportPath $auditPath -TimeoutSeconds 60 | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($auditText)) { throw 'STAGE_CHECKPOINT_LIVE_AUDIT_EMPTY' }
    $audit = $auditText | ConvertFrom-Json
    if ($audit.status -cne 'PASS' -or [int]$audit.dbmod -ne 0 -or [int]$audit.command_active -ne 0 -or `
        -not [string]::IsNullOrWhiteSpace([string]$audit.command_names)) { throw 'STAGE_CHECKPOINT_LIVE_AUDIT_NOT_CLEAN' }
    $workingHash = $liveCopyHash
}
if ($workingHash -cne [string]$receipt.working_sha256) { throw 'STAGE_CHECKPOINT_WORKING_HASH_DRIFT' }

$snapshot = $null
if ([string]$receipt.status -ceq 'PASS') {
    $snapshot = Resolve-ProjectFile -Path ([string]$receipt.checkpoint_path) -ErrorCode 'STAGE_CHECKPOINT_SNAPSHOT_OUTSIDE_RUNS'
    $snapshotHash = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash
    if ($snapshotHash -cne $workingHash) { throw 'STAGE_CHECKPOINT_SNAPSHOT_HASH_MISMATCH' }
} else {
    $lineageDirectory = [IO.Path]::GetFullPath([string]$receipt.lineage_directory)
    if (-not $lineageDirectory.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'STAGE_CHECKPOINT_LINEAGE_OUTSIDE_RUNS' }
    $statePath = Join-Path $lineageDirectory 'lineage_state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'STAGE_CHECKPOINT_LINEAGE_STATE_MISSING' }
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$state.latest_sha256 -cne $workingHash) { throw 'STAGE_CHECKPOINT_NO_CHANGE_WITHOUT_MATCHING_HISTORY' }
    $snapshot = Resolve-ProjectFile -Path ([string]$state.latest_snapshot) -ErrorCode 'STAGE_CHECKPOINT_LATEST_SNAPSHOT_OUTSIDE_RUNS'
}

$result = [pscustomobject]@{
    status = 'PASS'
    working_dwg = $working
    working_sha256 = $workingHash
    checkpoint_status = [string]$receipt.status
    checkpoint_receipt = $receiptPath
    recoverable_snapshot = $snapshot
    retained_count = [int]$receipt.retained_count
    retention = [int]$receipt.retention
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Depth 6 -Compress }
