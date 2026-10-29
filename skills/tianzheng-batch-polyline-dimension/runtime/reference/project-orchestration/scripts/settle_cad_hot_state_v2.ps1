param(
    [string]$NextCheckpoint = 'review_terminal_evidence__continue_if_authorized_work_remains__otherwise_complete_or_report_verified_blocker__new_READY_only__no_same_run_retry',
    [switch]$PassThru,
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
$nextCheckpointWasExplicit = $PSBoundParameters.ContainsKey('NextCheckpoint')
$projectRoot = if ($ProjectRoot) { [IO.Path]::GetFullPath($ProjectRoot) } else { [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')) }
$index = Get-Content -LiteralPath (Join-Path $projectRoot 'config\project_execution_index.json') -Raw -Encoding UTF8 | ConvertFrom-Json

function Read-Record([string]$RelativePath, [string]$Code) {
    $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
    if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "$($Code)_OUTSIDE_PROJECT" }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$($Code)_MISSING" }
    [pscustomobject]@{
        path = $path
        relative = $RelativePath.Replace('\','/')
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        value = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
    }
}
function Set-Property([object]$Object, [string]$Name, [object]$Value) {
    if ($null -ne $Object.PSObject.Properties[$Name]) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}
function Write-Atomic([string]$Path, [object]$Value) {
    $tmp = $Path + '.terminal_settlement_tmp'
    [IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$handoffRecord = Read-Record ([string]$index.current_execution_handoff) 'SETTLE_HANDOFF'
$returnRecord = Read-Record ([string]$index.current_execution_return) 'SETTLE_RETURN'
$bindingRecord = Read-Record ([string]$index.current_task_binding) 'SETTLE_BINDING'
$recoveryRecord = Read-Record ([string]$index.current_recovery_contract) 'SETTLE_RECOVERY'
$immutableRecord = Read-Record ([string]$returnRecord.value.immutable_return_path) 'SETTLE_IMMUTABLE_RETURN'
$handoff = $handoffRecord.value
$return = $returnRecord.value
$binding = $bindingRecord.value
$recovery = $recoveryRecord.value
$immutable = $immutableRecord.value

if ($immutableRecord.sha256 -cne [string]$return.immutable_return_sha256) { throw 'SETTLE_IMMUTABLE_RETURN_HASH_MISMATCH' }
foreach ($name in @('loop_id','handoff_id','run_id','status','terminal_state')) {
    if ([string]$immutable.$name -cne [string]$return.$name) { throw ('SETTLE_RETURN_FIELD_MISMATCH:' + $name) }
}
if ([string]$handoff.handoff_id -cne [string]$return.handoff_id -or [string]$handoff.run_id -cne [string]$return.run_id) { throw 'SETTLE_HANDOFF_RETURN_IDENTITY_MISMATCH' }
if ([string]$handoff.status -notin @('READY','TERMINAL_RETURNED')) { throw 'SETTLE_HANDOFF_STATUS_INVALID' }

$backupRoot = Join-Path $projectRoot ('runs\' + [string]$return.run_id + '\authority_backups')
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
foreach ($record in @($handoffRecord,$bindingRecord,$recoveryRecord)) {
    $backup = Join-Path $backupRoot (($record.relative.Replace('/','__')) + '.before_terminal_settlement')
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $record.path -Destination $backup }
}

$settledAt = (Get-Date).ToString('o')
Set-Property $handoff 'status' 'TERMINAL_RETURNED'
Set-Property $handoff 'settled_at' $settledAt
Set-Property $handoff 'terminal_return_path' ([string]$return.immutable_return_path)
Set-Property $handoff 'terminal_return_sha256' ([string]$return.immutable_return_sha256)
Set-Property $handoff 'terminal_state' ([string]$return.terminal_state)
Set-Property $handoff 'execution_authority_active' $false

# Preserve later source/user acceptance when settling the same immutable run again.
$acceptedCheckpoint = $null
if ($null -ne $recovery.PSObject.Properties['focus_lock'] -and $null -ne $recovery.focus_lock.PSObject.Properties['accepted_checkpoint']) { $acceptedCheckpoint = $recovery.focus_lock.accepted_checkpoint }
$acceptedCurrentRun = $null -ne $acceptedCheckpoint -and [string]$acceptedCheckpoint.run_id -ceq [string]$return.run_id -and [string]$acceptedCheckpoint.status -ceq 'USER_ACCEPTED_TEST_CHECKPOINT__NOT_PRODUCTION_DELIVERY'
$sourceReviewedCurrentRun = $false
if ($null -ne $recovery.PSObject.Properties['radius_stage_checkpoint'] -and $null -ne $recovery.radius_stage_checkpoint.PSObject.Properties['current_acceptance']) {
    $sourceCheckpoint = $recovery.radius_stage_checkpoint.current_acceptance
    $sourceReviewedCurrentRun = [string]$sourceCheckpoint.run_id -ceq [string]$return.run_id -and [string]$sourceCheckpoint.status -ceq 'SOURCE_REVIEWED_TEST_CHECKPOINT__NOT_PRODUCTION_DELIVERY'
}
$oldReturnNext = if ($null -ne $return.PSObject.Properties['next_legal_gate']) { [string]$return.next_legal_gate } else { '' }
if (($acceptedCurrentRun -or $sourceReviewedCurrentRun) -and (-not $nextCheckpointWasExplicit -or ($oldReturnNext -and $NextCheckpoint -ceq $oldReturnNext)) -and -not [string]::IsNullOrWhiteSpace([string]$recovery.next_checkpoint)) { $NextCheckpoint = [string]$recovery.next_checkpoint }
$binding.updated_at = $settledAt
Set-Property $binding 'latest_terminal_evidence' ([pscustomobject]@{
    status = [string]$return.terminal_state
    path = [string]$return.immutable_return_path
    sha256 = [string]$return.immutable_return_sha256
})
Set-Property $binding 'candidate_runtime_status' ('LATEST_TERMINAL_' + [string]$return.run_id + $(if ($acceptedCurrentRun) { '__USER_ACCEPTED_CHECKPOINT__FOLLOW_NEXT_CHECKPOINT' } elseif ($sourceReviewedCurrentRun) { '__SOURCE_REVIEWED_CHECKPOINT__FOLLOW_NEXT_CHECKPOINT' } else { '__PROJECT_REVIEW_REQUIRED' }))
Set-Property $binding 'next_gate' $NextCheckpoint

$recovery.updated_at = $settledAt
# A run receipt settles evidence, not the user's project objective.
$recovery.next_checkpoint = $NextCheckpoint
Set-Property $recovery 'latest_terminal_execution' ([pscustomobject]@{
    handoff_id = [string]$return.handoff_id
    run_id = [string]$return.run_id
    status = [string]$return.terminal_state
    path = [string]$return.immutable_return_path
    sha256 = [string]$return.immutable_return_sha256
    completed_at = [string]$return.completed_at
})
Set-Property $recovery 'record_chain_policy' ([string]$index.history_integrity_policy)

Write-Atomic $handoffRecord.path $handoff
Write-Atomic $bindingRecord.path $binding
Write-Atomic $recoveryRecord.path $recovery

$refresh = & (Join-Path $projectRoot 'scripts\refresh_cad_project_state.ps1')
$recordChain = & (Join-Path $projectRoot 'scripts\assert_cad_record_chain_integrity.ps1') -PassThru
$result = [pscustomobject]@{
    status = 'PASS'
    handoff_id = [string]$return.handoff_id
    run_id = [string]$return.run_id
    terminal_state = [string]$return.terminal_state
    handoff_status = [string]$handoff.status
    next_checkpoint = $NextCheckpoint
    refresh_status = [string]$refresh.status
    record_chain_status = [string]$recordChain.status
    business_rerun_authorized = $false
    native_task_store_modified = $false
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Depth 10 -Compress }
