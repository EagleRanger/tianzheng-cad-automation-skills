param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [string]$LineageId = '',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$')][string]$Label = 'iteration',
    [ValidateRange(1,100)][int]$Retention = 10,
    [long]$WindowHandle = 0,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'
$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'TEST_CHECKPOINT_REPORT_OUTSIDE_RUNS' }
New-Item -ItemType Directory -Path $report -Force | Out-Null

$ownerPath = [IO.Path]::GetFullPath($OwnerStatePath)
$owner = Get-Content -LiteralPath $ownerPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($owner.status -cne 'ready' -or [int]$owner.process_id -ne $ProcessId) { throw 'TEST_CHECKPOINT_OWNER_STATE_MISMATCH' }
$working = [IO.Path]::GetFullPath([string]$owner.target_dwg)
if (-not $working.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'TEST_CHECKPOINT_REQUIRES_ISOLATED_DWG_UNDER_RUNS' }
if ([IO.Path]::GetExtension($working) -cne '.dwg' -or -not (Test-Path -LiteralPath $working -PathType Leaf)) {
    throw 'TEST_CHECKPOINT_WORKING_DWG_INVALID'
}

if ([string]::IsNullOrWhiteSpace($LineageId)) {
    $base = [regex]::Replace([IO.Path]::GetFileNameWithoutExtension($working), '[^A-Za-z0-9._-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'isolated_test_drawing' }
    $seed = if ($owner.target_sha256) { ([string]$owner.target_sha256).Substring(0, [Math]::Min(12, ([string]$owner.target_sha256).Length)) } else { 'nohash' }
    $LineageId = (($base + '_' + $seed).Substring(0, [Math]::Min(80, ($base + '_' + $seed).Length)))
}
if ($LineageId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { throw 'TEST_CHECKPOINT_LINEAGE_ID_INVALID' }

$dispatcher = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1'
$preAuditPath = Join-Path $report 'checkpoint_pre_save_state.tsv'
$postAuditPath = Join-Path $report 'checkpoint_post_save_state.tsv'
$saveReceiptPath = Join-Path $report 'checkpoint_native_save.json'
$receiptPath = Join-Path $report 'test_drawing_checkpoint.json'

function Invoke-WhitelistJson {
    param([Parameter(Mandatory = $true)][hashtable]$Arguments)
    $text = (& $dispatcher @Arguments | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'TEST_CHECKPOINT_WHITELIST_EMPTY_RESULT' }
    return $text | ConvertFrom-Json
}

$common = @{ ProcessId=$ProcessId; OwnerStatePath=$ownerPath; WindowHandle=$WindowHandle; TimeoutSeconds=$TimeoutSeconds }
$preArgs = @{} + $common
$preArgs.Action = 'AUDIT_OWNED_STATE'
$preArgs.ReportPath = $preAuditPath
$pre = Invoke-WhitelistJson -Arguments $preArgs
if ($pre.status -cne 'PASS' -or [int]$pre.command_active -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$pre.command_names)) {
    throw 'TEST_CHECKPOINT_PRE_SAVE_NOT_IDLE'
}

$save = $null
if ([int]$pre.dbmod -ne 0) {
    $saveArgs = @{} + $common
    $saveArgs.Action = 'QSAVE_OWNED'
    $save = Invoke-WhitelistJson -Arguments $saveArgs
    if ($save.status -cne 'PASS') { throw 'TEST_CHECKPOINT_NATIVE_SAVE_FAILED' }
    [IO.File]::WriteAllText($saveReceiptPath, ($save | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}

$postArgs = @{} + $common
$postArgs.Action = 'AUDIT_OWNED_STATE'
$postArgs.ReportPath = $postAuditPath
$post = Invoke-WhitelistJson -Arguments $postArgs
if ($post.status -cne 'PASS' -or [int]$post.dbmod -ne 0 -or [int]$post.command_active -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$post.command_names)) {
    throw 'TEST_CHECKPOINT_POST_SAVE_NOT_CLEAN'
}

# T20/AutoCAD can keep the live DWG locked without read sharing even after a
# clean QSAVE.  Ask AutoCAD itself to create a native intermediate copy with
# SAVE; unlike SAVEAS this keeps the owned working drawing current.
$liveCopyPath = Join-Path $report 'checkpoint_live_copy.dwg'
if (Test-Path -LiteralPath $liveCopyPath) { throw 'TEST_CHECKPOINT_LIVE_COPY_ALREADY_EXISTS' }
$copyArgs = @{} + $common
$copyArgs.Action = 'SAVE_COPY_OWNED'
$copyArgs.OutputPath = $liveCopyPath
$liveCopy = Invoke-WhitelistJson -Arguments $copyArgs
if ($liveCopy.status -cne 'PASS' -or -not (Test-Path -LiteralPath $liveCopyPath -PathType Leaf)) {
    throw 'TEST_CHECKPOINT_LIVE_COPY_FAILED'
}
$liveCopyReceiptPath = Join-Path $report 'checkpoint_live_copy.json'
[IO.File]::WriteAllText($liveCopyReceiptPath, ($liveCopy | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))

Import-Module (Join-Path $PSScriptRoot 'common\TestDrawingHistory.psm1') -Force
$historyRoot = Join-Path $runsRoot '_test_drawing_history'
$checkpoint = New-TestDrawingCheckpoint `
    -WorkingDrawing $liveCopyPath `
    -HistoryRoot $historyRoot `
    -LineageId $LineageId `
    -Label $Label `
    -Retention $Retention `
    -NativeSaveReceipt $(if ($save) { $saveReceiptPath } else { '' }) `
    -OwnedStateAuditReceipt $postAuditPath

$receipt = [ordered]@{
    schema_version = 2
    status = [string]$checkpoint.status
    created_at = (Get-Date).ToString('o')
    process_id = $ProcessId
    working_dwg = $working
    working_sha256 = [string]$checkpoint.working_sha256
    live_copy = $liveCopyPath
    live_copy_receipt = $liveCopyReceiptPath
    qsave_performed = ($null -ne $save)
    dbmod_before = [int]$pre.dbmod
    dbmod_after = [int]$post.dbmod
    lineage_id = $LineageId
    retention = $Retention
    retained_count = [int]$checkpoint.retained_count
    checkpoint_path = $checkpoint.checkpoint_path
    checkpoint_manifest = $checkpoint.manifest_path
    lineage_directory = [string]$checkpoint.lineage_directory
    deleted = @($checkpoint.deleted)
    pre_save_audit = $preAuditPath
    post_save_audit = $postAuditPath
    native_save_receipt = if ($save) { $saveReceiptPath } else { $null }
}
$temporary = $receiptPath + '.tmp'
[IO.File]::WriteAllText($temporary, ($receipt | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $receiptPath -Force
$receipt | ConvertTo-Json -Depth 10
