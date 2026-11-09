Set-StrictMode -Version Latest

function Get-NormalizedRootPrefix {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    return $full + [IO.Path]::DirectorySeparatorChar
}

function Assert-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ErrorCode
    )
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = Get-NormalizedRootPrefix -Path $Root
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorCode }
    return $full
}

function Get-TestDrawingHistoryEntries {
    param([Parameter(Mandatory = $true)][string]$LineageDirectory)

    $directory = [IO.Path]::GetFullPath($LineageDirectory)
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return @() }
    $entries = @()
    foreach ($manifestFile in @(Get-ChildItem -LiteralPath $directory -Filter '*.checkpoint.json' -File | Sort-Object Name)) {
        try { $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { throw "TEST_HISTORY_MANIFEST_INVALID=$($manifestFile.FullName)" }
        if ([int]$manifest.schema_version -ne 1 -or [string]::IsNullOrWhiteSpace([string]$manifest.snapshot_name)) {
            throw "TEST_HISTORY_MANIFEST_SCHEMA_INVALID=$($manifestFile.FullName)"
        }
        $snapshot = Assert-PathInsideRoot -Path (Join-Path $directory ([string]$manifest.snapshot_name)) -Root $directory -ErrorCode 'TEST_HISTORY_SNAPSHOT_OUTSIDE_LINEAGE'
        if ([IO.Path]::GetExtension($snapshot) -cne '.dwg') { throw "TEST_HISTORY_SNAPSHOT_EXTENSION_INVALID=$snapshot" }
        if (-not (Test-Path -LiteralPath $snapshot -PathType Leaf)) { throw "TEST_HISTORY_SNAPSHOT_MISSING=$snapshot" }
        $entries += [pscustomobject]@{
            manifest_path = $manifestFile.FullName
            snapshot_path = $snapshot
            created_at = [datetimeoffset]$manifest.created_at
            snapshot_sha256 = [string]$manifest.snapshot_sha256
            checkpoint_id = [string]$manifest.checkpoint_id
        }
    }
    return @($entries)
}

function New-TestDrawingCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDrawing,
        [Parameter(Mandatory = $true)][string]$HistoryRoot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$LineageId,
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$')][string]$Label = 'iteration',
        [ValidateRange(1,100)][int]$Retention = 10,
        [string]$NativeSaveReceipt = '',
        [string]$OwnedStateAuditReceipt = '',
        [ValidatePattern('^$|^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$RunId = '',
        [string]$CheckpointReceiptPath = '',
        [switch]$PreserveAll
    )

    $working = [IO.Path]::GetFullPath($WorkingDrawing)
    if ([IO.Path]::GetExtension($working) -cne '.dwg' -or -not (Test-Path -LiteralPath $working -PathType Leaf)) {
        throw 'TEST_HISTORY_WORKING_DWG_INVALID'
    }
    $root = [IO.Path]::GetFullPath($HistoryRoot)
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $lineage = Assert-PathInsideRoot -Path (Join-Path $root $LineageId) -Root $root -ErrorCode 'TEST_HISTORY_LINEAGE_OUTSIDE_ROOT'
    New-Item -ItemType Directory -Path $lineage -Force | Out-Null
    $lineagePrefix = Get-NormalizedRootPrefix -Path $lineage
    if ($working.StartsWith($lineagePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'TEST_HISTORY_WORKING_DWG_INSIDE_HISTORY'
    }

    $workingHash = (Get-FileHash -LiteralPath $working -Algorithm SHA256).Hash
    $existing = @(Get-TestDrawingHistoryEntries -LineageDirectory $lineage | Sort-Object created_at, checkpoint_id)
    if ($existing.Count -gt 0 -and $existing[-1].snapshot_sha256 -ceq $workingHash) {
        if ($RunId -or $CheckpointReceiptPath) {
            $existingCheckpoint = $existing[-1]
            $statePath = Join-Path $lineage 'lineage_state.json'
            $state = if (Test-Path -LiteralPath $statePath -PathType Leaf) { Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{schema_version=1;lineage_id=$LineageId} }
            $state | Add-Member -NotePropertyName updated_at -NotePropertyValue (Get-Date).ToString('o') -Force
            $state | Add-Member -NotePropertyName last_save_event -NotePropertyValue ([ordered]@{
                status = 'NO_CHANGE'
                run_id = $RunId
                recorded_at = (Get-Date).ToString('o')
                output_path = $working
                output_sha256 = $workingHash
                checkpoint_path = $existingCheckpoint.snapshot_path
                checkpoint_manifest = $existingCheckpoint.manifest_path
                checkpoint_receipt_path = if ($CheckpointReceiptPath) { [IO.Path]::GetFullPath($CheckpointReceiptPath) } else { $null }
            }) -Force
            $stateTemporary = $statePath + '.tmp'
            [IO.File]::WriteAllText($stateTemporary, ($state | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
            Move-Item -LiteralPath $stateTemporary -Destination $statePath -Force
        }
        return [pscustomobject]@{
            status = 'NO_CHANGE'
            working_dwg = $working
            working_sha256 = $workingHash
            lineage_directory = $lineage
            retained_count = $existing.Count
            retention = $Retention
            checkpoint_path = $null
            manifest_path = $null
            deleted = @()
        }
    }

    $created = [datetimeoffset]::Now
    $checkpointId = '{0}_{1}_{2}' -f $created.ToString('yyyyMMdd_HHmmss_fff'), $Label, $workingHash.Substring(0,8)
    $snapshotName = $checkpointId + '.dwg'
    $manifestName = $checkpointId + '.checkpoint.json'
    $snapshot = Assert-PathInsideRoot -Path (Join-Path $lineage $snapshotName) -Root $lineage -ErrorCode 'TEST_HISTORY_SNAPSHOT_OUTSIDE_LINEAGE'
    $manifestPath = Assert-PathInsideRoot -Path (Join-Path $lineage $manifestName) -Root $lineage -ErrorCode 'TEST_HISTORY_MANIFEST_OUTSIDE_LINEAGE'
    if ((Test-Path -LiteralPath $snapshot -PathType Leaf) -or (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'TEST_HISTORY_CHECKPOINT_COLLISION'
    }

    $snapshotTemporary = $snapshot + '.tmp'
    Copy-Item -LiteralPath $working -Destination $snapshotTemporary
    $snapshotHash = (Get-FileHash -LiteralPath $snapshotTemporary -Algorithm SHA256).Hash
    if ($snapshotHash -cne $workingHash) {
        Remove-Item -LiteralPath $snapshotTemporary -Force -ErrorAction SilentlyContinue
        throw 'TEST_HISTORY_SNAPSHOT_HASH_MISMATCH'
    }
    Move-Item -LiteralPath $snapshotTemporary -Destination $snapshot

    $manifest = [ordered]@{
        schema_version = 1
        checkpoint_id = $checkpointId
        created_at = $created.ToString('o')
        lineage_id = $LineageId
        label = $Label
        working_dwg = $working
        working_sha256 = $workingHash
        snapshot_name = $snapshotName
        snapshot_sha256 = $snapshotHash
        native_save_receipt = if ($NativeSaveReceipt) { [IO.Path]::GetFullPath($NativeSaveReceipt) } else { $null }
        owned_state_audit_receipt = if ($OwnedStateAuditReceipt) { [IO.Path]::GetFullPath($OwnedStateAuditReceipt) } else { $null }
        retention = $Retention
    }
    if ($RunId) { $manifest.run_id = $RunId }
    if ($CheckpointReceiptPath) { $manifest.checkpoint_receipt_path = [IO.Path]::GetFullPath($CheckpointReceiptPath) }
    $manifestTemporary = $manifestPath + '.tmp'
    [IO.File]::WriteAllText($manifestTemporary, ($manifest | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $manifestTemporary -Destination $manifestPath

    $entries = @(Get-TestDrawingHistoryEntries -LineageDirectory $lineage | Sort-Object created_at, checkpoint_id)
    $deleted = @()
    $overflow = if ($PreserveAll) { 0 } else { [Math]::Max(0, $entries.Count - $Retention) }
    foreach ($entry in @($entries | Select-Object -First $overflow)) {
        $oldManifest = Assert-PathInsideRoot -Path $entry.manifest_path -Root $lineage -ErrorCode 'TEST_HISTORY_PRUNE_MANIFEST_OUTSIDE_LINEAGE'
        $oldSnapshot = Assert-PathInsideRoot -Path $entry.snapshot_path -Root $lineage -ErrorCode 'TEST_HISTORY_PRUNE_SNAPSHOT_OUTSIDE_LINEAGE'
        if ($oldSnapshot.Equals($working, [StringComparison]::OrdinalIgnoreCase)) { throw 'TEST_HISTORY_REFUSED_TO_DELETE_WORKING_DWG' }
        if ([IO.Path]::GetExtension($oldSnapshot) -cne '.dwg' -or -not $oldManifest.EndsWith('.checkpoint.json', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'TEST_HISTORY_PRUNE_TARGET_INVALID'
        }
        Remove-Item -LiteralPath $oldManifest -Force
        Remove-Item -LiteralPath $oldSnapshot -Force
        $deleted += [pscustomobject]@{ checkpoint_id=$entry.checkpoint_id; snapshot_path=$oldSnapshot; manifest_path=$oldManifest }
    }

    $retained = @(Get-TestDrawingHistoryEntries -LineageDirectory $lineage | Sort-Object created_at, checkpoint_id)
    $state = [ordered]@{
        schema_version = 1
        updated_at = (Get-Date).ToString('o')
        lineage_id = $LineageId
        working_dwg = $working
        latest_checkpoint_id = $checkpointId
        latest_snapshot = $snapshot
        latest_sha256 = $snapshotHash
        retention = $Retention
        preserve_all = [bool]$PreserveAll
        retained_count = $retained.Count
    }
    if ($RunId -or $CheckpointReceiptPath) {
        $state.last_save_event = [ordered]@{
            status = 'PASS'
            run_id = $RunId
            recorded_at = (Get-Date).ToString('o')
            output_path = $working
            output_sha256 = $workingHash
            checkpoint_path = $snapshot
            checkpoint_manifest = $manifestPath
            checkpoint_receipt_path = if ($CheckpointReceiptPath) { [IO.Path]::GetFullPath($CheckpointReceiptPath) } else { $null }
        }
    }
    $statePath = Join-Path $lineage 'lineage_state.json'
    $stateTemporary = $statePath + '.tmp'
    [IO.File]::WriteAllText($stateTemporary, ($state | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $stateTemporary -Destination $statePath -Force

    return [pscustomobject]@{
        status = 'PASS'
        working_dwg = $working
        working_sha256 = $workingHash
        lineage_directory = $lineage
        retained_count = $retained.Count
        retention = $Retention
        preserve_all = [bool]$PreserveAll
        checkpoint_path = $snapshot
        manifest_path = $manifestPath
        deleted = @($deleted)
    }
}

Export-ModuleMember -Function Get-TestDrawingHistoryEntries,New-TestDrawingCheckpoint
