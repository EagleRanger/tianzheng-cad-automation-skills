param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [Parameter(Mandatory = $true)][string]$OwnerStatePath,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$LineageId,
    [ValidateSet('Preview','Candidate','Final')][string]$StageKind = 'Candidate',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$')][string]$Label = 'stage',
    [ValidateRange(1,100)][int]$Retention = 10,
    [long]$WindowHandle = 0,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$runsRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'runs')).TrimEnd('\') + '\'
$report = [IO.Path]::GetFullPath($ReportDirectory)
if (-not $report.StartsWith($runsRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'STAGE_TRANSITION_REPORT_OUTSIDE_RUNS' }
if (Test-Path -LiteralPath (Join-Path $report 'stage_transition_receipt.json') -PathType Leaf) { throw 'STAGE_TRANSITION_RECEIPT_ALREADY_EXISTS' }
New-Item -ItemType Directory -Path $report -Force | Out-Null

$checkpointEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/save_owned_test_drawing_checkpoint.ps1'
$assertEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_owned_stage_checkpoint.ps1'
$checkpointDir = Join-Path $report 'checkpoint'
$checkpointText = (& $checkpointEntry -ProcessId $ProcessId -OwnerStatePath $OwnerStatePath -ReportDirectory $checkpointDir -LineageId $LineageId -Label $Label -Retention $Retention -WindowHandle $WindowHandle -TimeoutSeconds $TimeoutSeconds | Out-String).Trim()
if ([string]::IsNullOrWhiteSpace($checkpointText)) { throw 'STAGE_TRANSITION_CHECKPOINT_EMPTY' }
$checkpoint = $checkpointText | ConvertFrom-Json
$checkpointReceipt = Join-Path $checkpointDir 'test_drawing_checkpoint.json'
$verified = & $assertEntry -OwnerStatePath $OwnerStatePath -CheckpointReceiptPath $checkpointReceipt -ExpectedRetention $Retention -PassThru

$result = [ordered]@{
    schema_version = 1
    status = if ($StageKind -ceq 'Final') { 'PENDING_FINAL_ACCEPTANCE' } else { 'PASS' }
    stage_kind = $StageKind
    completed_at = (Get-Date).ToString('o')
    process_id = $ProcessId
    working_dwg = $verified.working_dwg
    working_sha256 = $verified.working_sha256
    checkpoint_status = $verified.checkpoint_status
    checkpoint_receipt = $checkpointReceipt
    recoverable_snapshot = $verified.recoverable_snapshot
    retention = $Retention
    retained_count = $verified.retained_count
    next_mutation_allowed = $true
    final_acceptance_required = ($StageKind -ceq 'Final')
    final_acceptance_gates = if ($StageKind -ceq 'Final') { @('native_object_audit','visual_audit','save_close_reopen_audit') } else { @() }
}
$resultPath = Join-Path $report 'stage_transition_receipt.json'
$temporary = $resultPath + '.tmp'
[IO.File]::WriteAllText($temporary, ($result | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $resultPath -Force
$result | ConvertTo-Json -Depth 8
