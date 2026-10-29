. (Join-Path $PSScriptRoot '../v2/cad_exact_target_candidate_v2.ps1')

# Keep wire identity as text; pwsh's default JSON parser promotes ISO strings to
# DateTime and string coercion then changes their representation/culture.
function Read-CadMultiOwnerScopeJsonV2([string]$Path) {
    if (-not (Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { throw 'SCOPE_READER_REQUIRES_DATEKIND_STRING_SUPPORT' }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
}

function Assert-CadMultiOwnerPreflightScopeV1($Scope, [string]$ProjectRoot) {
    if ((Get-CadTargetV1Field $Scope 'schema_version') -cne 1 -or
        [string](Get-CadTargetV1Field $Scope 'profile_id') -cne 'CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1' -or
        [string](Get-CadTargetV1Field $Scope 'intent') -cne 'Read') { throw 'INVALID_READ_ONLY_PROFILE' }
    $runId = [string](Get-CadTargetV1Field $Scope 'run_id')
    if ($runId -notmatch '^[A-Za-z0-9_-]{1,100}$') { throw 'INVALID_RUN_ID' }
    $owners = @(Get-CadTargetV1Field $Scope 'owners')
    if ($owners.Count -notin @(1,2)) { throw 'OWNER_COUNT_MUST_BE_ONE_OR_TWO' }
    $prefix = [IO.Path]::GetFullPath($ProjectRoot) + [IO.Path]::DirectorySeparatorChar
    $ids = @{}; $pids = @{}; $paths = @{}
    foreach ($owner in $owners) {
        $id = [string](Get-CadTargetV1Field $owner 'id')
        $expectedId = if ($ids.Count -eq 0) { 'A' } else { 'B' }
        if ($id -cne $expectedId) { throw 'OWNERS_MUST_BE_ORDERED_A_THEN_B' }
        if ([string](Get-CadTargetV1Field $owner 'scope_kind') -cne 'AUTHORIZED_ISOLATED_TEST_COPY') { throw 'OWNER_NOT_AUTHORIZED_TEST_COPY' }
        $ownerPid = ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $owner 'process_id')
        $hwnd = ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $owner 'window_handle')
        if ($ownerPid -le 0 -or $ownerPid -gt [int]::MaxValue -or $hwnd -le 0 -or $pids.ContainsKey([string]$ownerPid)) { throw 'OWNERS_MUST_BE_DISTINCT_PROCESSES' }
        $null = ConvertTo-CadTargetV1StartTicks (Get-CadTargetV1Field $owner 'process_start_time_utc')
        $image = ConvertTo-CadTargetV1FullPath (Get-CadTargetV1Field $owner 'process_image_path')
        if ([IO.Path]::GetFileName($image) -ine 'acad.exe') { throw 'OWNER_NOT_ACAD' }
        $drawing = ConvertTo-CadTargetV1FullPath (Get-CadTargetV1Field $owner 'document_full_path') -Drawing
        if (-not $drawing.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $paths.ContainsKey($drawing)) { throw 'TEST_DRAWING_OUTSIDE_PROJECT_OR_DUPLICATED' }
        if ([string](Get-CadTargetV1Field $owner 'protected_sha256') -notmatch '^[A-Fa-f0-9]{64}$') { throw 'INVALID_PROTECTION_HASH' }
        $ids[$id] = $owner; $pids[[string]$ownerPid] = $true; $paths[$drawing] = $true
    }
    $sequence = @(Get-CadTargetV1Field $Scope 'sequence')
    $wanted = if ($owners.Count -eq 1) { 'A' } else { 'A,B,A' }
    if (($sequence -join ',') -cne $wanted) { throw 'SEQUENCE_MUST_BE_A_OR_ABA' }
    [pscustomobject]@{run_id=$runId;owners=$owners;by_id=$ids;sequence=$sequence}
}

function Assert-CadMultiOwnerProtectedHashesV1($Validated) {
    foreach ($owner in $Validated.owners) {
        $path = ConvertTo-CadTargetV1FullPath $owner.document_full_path -Drawing
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (& (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/get_shared_file_sha256_v1.ps1') -Path $path) -ine $owner.protected_sha256) { throw "PROTECTED_DRAWING_HASH_MISMATCH:$($owner.id)" }
    }
}

# The worker and fake-object tests share this exact getter-only short sequence.
# Bind supplies a freshly admitted Read binding, never an application selected by name.
function Invoke-CadMultiOwnerReadSequenceV1($Validated, [scriptblock]$Bind, $Rows, $Events) {
    foreach ($id in $Validated.sequence) {
        $owner = $Validated.by_id[$id]; $values = [ordered]@{}
        foreach ($getter in @('FullName','Name','CMDNAMES','CMDACTIVE','DBMOD','ModelSpace.Count')) {
            $binding = & $Bind $owner
            if ($binding.status -cne 'PASS' -or $binding.intent -cne 'Read') { throw 'SEQUENCE_REQUIRES_FRESH_READ_BINDING' }
            $event = [ordered]@{owner=$id;getter=$getter;at=[DateTime]::UtcNow.ToString('o');status='ENTERED';value=$null;error=$null}
            $Events.Add($event)
            try {
                $value = switch ($getter) {
                    'FullName' { $binding.document.FullName }
                    'Name' { $binding.document.Name }
                    'CMDNAMES' { $binding.document.GetVariable('CMDNAMES') }
                    'CMDACTIVE' { $binding.document.GetVariable('CMDACTIVE') }
                    'DBMOD' { $binding.document.GetVariable('DBMOD') }
                    'ModelSpace.Count' { $binding.document.ModelSpace.Count }
                }
                if ($null -eq $value) { throw "NULL_GETTER:$id/$getter" }
                if ($getter -in @('CMDACTIVE','DBMOD','ModelSpace.Count')) { $value = ConvertTo-CadTargetV1Integer $value }
                if ($getter -eq 'FullName' -and -not (Test-CadTargetV1PathEqual (ConvertTo-CadTargetV1FullPath $value -Drawing) (ConvertTo-CadTargetV1FullPath $owner.document_full_path -Drawing))) { throw 'GETTER_FULL_PATH_CHANGED' }
                if ($getter -eq 'Name' -and [string]::IsNullOrWhiteSpace([string]$value)) { throw 'EMPTY_DOCUMENT_NAME' }
                if ($getter -eq 'CMDNAMES' -and ($value -isnot [string] -or -not [string]::IsNullOrWhiteSpace($value))) { throw 'CMDNAMES_CHANGED_TO_BUSY' }
                if ($getter -eq 'CMDACTIVE' -and $value -ne 0) { throw 'CMDACTIVE_CHANGED_TO_BUSY' }
                $event.status = 'RETURNED'; $event.value = $value; $values[$getter] = $value
                $after = & $Bind $owner
                if ($after.status -cne 'PASS' -or $after.intent -cne 'Read') { throw 'IDENTITY_CHANGED_AFTER_GETTER' }
            } catch { $event.status='FAILED';$event.error=$_.Exception.Message;throw }
        }
        $Rows.Add([pscustomobject]@{owner=$id;values=$values;binding='PID_START_IMAGE_HWND_OS_PID_FULL_PATH';at=[DateTime]::UtcNow.ToString('o')})
    }
}
