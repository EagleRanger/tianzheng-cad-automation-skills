# Private offline candidate. Not wired into the shared CAD worker or READY route.
# Admission does not imply an action occurred or that a second instance is safe.
Set-StrictMode -Version Latest

function Get-CadTargetV1Field($Value, [string]$Name) {
    if ($null -eq $Value -or $null -eq $Value.PSObject.Properties[$Name]) { throw "MISSING_FIELD:$Name" }
    $Value.$Name
}

function ConvertTo-CadTargetV1FullPath([string]$Value, [switch]$Drawing) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'EMPTY_FULL_PATH' }
    $valuePath = $Value.Replace('/', '\')
    if ($valuePath -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+\\)' -or
        $valuePath.StartsWith('\\?\') -or $valuePath.StartsWith('\\.\') -or
        $valuePath -match '[*?\x00-\x1f]' -or $valuePath.Substring(2).Contains(':')) { throw 'INVALID_ABSOLUTE_PATH' }
    foreach ($segment in $valuePath.Split('\')) {
        if ($segment -notin @('', '.', '..') -and ($segment.EndsWith(' ') -or $segment.EndsWith('.'))) { throw 'WIN32_PATH_ALIAS_REJECTED' }
    }
    $full = [IO.Path]::GetFullPath($valuePath)
    if ($Drawing -and [IO.Path]::GetExtension($full) -ine '.dwg') { throw 'NOT_A_DWG_PATH' }
    $full
}

function ConvertTo-CadTargetV1StartTicks([string]$Value) {
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$') { throw 'PROCESS_START_TIME_REQUIRES_ISO_TIMEZONE' }
    ([DateTimeOffset]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime.Ticks
}

function ConvertTo-CadTargetV1Integer($Value) {
    if ($null -eq $Value -or [string]$Value -notmatch '^\d+$') { throw 'NON_INTEGER_IDENTITY_OR_STATE' }
    [long]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Test-CadTargetV1PathEqual([string]$Left, [string]$Right) {
    [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
}

function Select-CadExactTargetCandidateV1 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Snapshot,
        [ValidateSet('Bind','Read','Execute')][string]$Intent = 'Bind'
    )
    $observed = [Collections.Generic.List[object]]::new()
    $selectedApplication = $null; $selectedDocument = $null; $activePath = ''
    $code = 'UNINITIALIZED'; $status = 'BLOCKED'
    try {
        $expectedPid = ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $Expected 'process_id')
        $expectedHwnd = ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $Expected 'window_handle')
        if ($expectedPid -le 0 -or $expectedPid -gt [int]::MaxValue -or $expectedHwnd -le 0) { throw 'INVALID_OWNER_TUPLE' }
        $expectedStart = ConvertTo-CadTargetV1StartTicks (Get-CadTargetV1Field $Expected 'process_start_time_utc')
        $expectedImage = ConvertTo-CadTargetV1FullPath (Get-CadTargetV1Field $Expected 'process_image_path')
        $expectedPath = ConvertTo-CadTargetV1FullPath (Get-CadTargetV1Field $Expected 'document_full_path') -Drawing
        if ((ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $Snapshot 'process_id')) -ne $expectedPid -or
            (ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $Snapshot 'window_handle')) -ne $expectedHwnd -or
            (ConvertTo-CadTargetV1Integer (Get-CadTargetV1Field $Snapshot 'window_process_id')) -ne $expectedPid) { throw 'OWNER_PID_HWND_MISMATCH' }
        if ((ConvertTo-CadTargetV1StartTicks (Get-CadTargetV1Field $Snapshot 'process_start_time_utc')) -ne $expectedStart) { throw 'PROCESS_START_MISMATCH' }
        if (-not (Test-CadTargetV1PathEqual $expectedImage (ConvertTo-CadTargetV1FullPath (Get-CadTargetV1Field $Snapshot 'process_image_path')))) { throw 'PROCESS_IMAGE_MISMATCH' }
        $windowValid = Get-CadTargetV1Field $Snapshot 'window_valid'
        if ($windowValid -isnot [bool] -or -not $windowValid) { throw 'OWNER_HWND_INVALID' }

        # Complete the provided enumeration: never stop at the first alias or leaf name.
        $matches = [Collections.Generic.List[object]]::new()
        $applications = [Collections.Generic.List[object]]::new()
        foreach ($entry in $Entries) {
            $instance = try { $entry.Instance } catch { $null }
            $moniker = try { [string]$entry.Name } catch { '' }
            if ($null -eq $instance) { continue }
            $application = $instance
            $hwnd = try { [long]$application.HWND } catch { 0 }
            # ROT can expose a Document rather than an Application. Never trust its moniker text.
            if ($hwnd -ne $expectedHwnd) {
                # A Document may have its own child HWND. Application is a getter,
                # not permission to inspect another application's document collection.
                try { $application = $instance.Application; $hwnd = [long]$application.HWND } catch { $hwnd = 0 }
            }
            $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$hwnd;target=($hwnd -eq $expectedHwnd)})
            if ($hwnd -ne $expectedHwnd) { continue }
            $alreadySeen = $false
            foreach ($seen in $applications) { if ([object]::ReferenceEquals($seen, $application)) { $alreadySeen = $true; break } }
            if ($alreadySeen) { continue }
            if ($applications.Count -gt 0) { throw 'AMBIGUOUS_APPLICATION_PROXY' }
            $applications.Add($application)
            $active = $application.ActiveDocument
            if ($null -eq $active) { throw 'ACTIVE_DOCUMENT_UNREADABLE' }
            $activeFull = ConvertTo-CadTargetV1FullPath ([string]$active.FullName) -Drawing
            $activePath = $activeFull
            $documents = $application.Documents
            if ($null -eq $documents) { throw 'DOCUMENT_COLLECTION_UNREADABLE' }
            $uniqueDocs = [Collections.Generic.List[object]]::new()
            foreach ($item in $documents) {
                if ($null -eq $item) { throw 'DOCUMENT_IDENTITY_UNREADABLE' }
                $itemFull = ConvertTo-CadTargetV1FullPath ([string]$item.FullName) -Drawing
                $seenDocument = $false
                foreach ($seen in $uniqueDocs) { if ([object]::ReferenceEquals($seen, $item)) { $seenDocument = $true; break } }
                if ($seenDocument) { continue }
                $uniqueDocs.Add($item)
                if (Test-CadTargetV1PathEqual $expectedPath $itemFull) { $matches.Add([pscustomobject]@{application=$application;document=$item}) }
            }
            if (Test-CadTargetV1PathEqual $expectedPath $activeFull) {
                $activeSeen = $false
                foreach ($match in $matches) { if ([object]::ReferenceEquals($match.document, $active)) { $activeSeen = $true; break } }
                if (-not $activeSeen) { $matches.Add([pscustomobject]@{application=$application;document=$active}) }
            }
        }
        if ($matches.Count -eq 0) { throw 'EXACT_FULL_PATH_NOT_FOUND' }
        if ($matches.Count -ne 1) { throw 'AMBIGUOUS_DOCUMENT_PROXY' }
        $selectedApplication = $matches[0].application; $selectedDocument = $matches[0].document
        if ($Intent -ne 'Bind') {
            foreach ($field in @('window_enabled','responding','serial_lease_held')) {
                $flag = Get-CadTargetV1Field $Snapshot $field
                if ($flag -isnot [bool] -or -not $flag) { throw "NOT_READY:$field" }
            }
            if ([string](Get-CadTargetV1Field $Snapshot 'modal_state') -cne 'NONE') { throw 'MODAL_PRESENT_OR_UNKNOWN' }
            if (-not (Test-CadTargetV1PathEqual $activePath $expectedPath)) { throw 'TARGET_DOCUMENT_NOT_ACTIVE' }
            $quiescent = $selectedApplication.GetAcadState().IsQuiescent
            if ($quiescent -isnot [bool] -or -not $quiescent) { throw 'APPLICATION_NOT_QUIESCENT' }
            $commandNamesRaw = $selectedDocument.GetVariable('CMDNAMES')
            if ($null -eq $commandNamesRaw -or $commandNamesRaw -isnot [string]) { throw 'COMMAND_NAMES_UNREADABLE' }
            $commandNames = [string]$commandNamesRaw
            $commandActiveRaw = $selectedDocument.GetVariable('CMDACTIVE')
            if ($null -eq $commandActiveRaw -or [string]::IsNullOrWhiteSpace([string]$commandActiveRaw)) { throw 'COMMAND_STATE_UNREADABLE' }
            $commandActive = ConvertTo-CadTargetV1Integer $commandActiveRaw
            if ($commandActive -ne 0 -or -not [string]::IsNullOrWhiteSpace($commandNames)) { throw 'COMMAND_NOT_IDLE' }
            # Re-read COM identity immediately after readiness getters. An executor must
            # additionally refresh the OS tuple immediately before its own permitted call.
            if ([long]$selectedApplication.HWND -ne $expectedHwnd -or
                -not (Test-CadTargetV1PathEqual $expectedPath (ConvertTo-CadTargetV1FullPath ([string]$selectedDocument.FullName) -Drawing)) -or
                -not (Test-CadTargetV1PathEqual $expectedPath (ConvertTo-CadTargetV1FullPath ([string]$selectedApplication.ActiveDocument.FullName) -Drawing))) { throw 'COM_IDENTITY_CHANGED_DURING_ADMISSION' }
        }
        $status = 'PASS'; $code = 'EXACT_TARGET_ADMITTED'
    } catch {
        $code = $_.Exception.Message
        $selectedApplication = $null; $selectedDocument = $null
    }
    [pscustomobject]@{
        status=$status;code=$code;intent=$Intent;level='ADMISSION_ONLY'
        application=$selectedApplication;document=$selectedDocument;observed=$observed.ToArray()
        enumerated_count=$Entries.Count;action_count=0;fallback_count=0
        live_execution_proven=$false;concurrent_execution_allowed=$false
    }
}
