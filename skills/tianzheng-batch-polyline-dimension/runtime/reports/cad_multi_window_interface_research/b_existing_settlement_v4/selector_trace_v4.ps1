# Same frozen V2 admission semantics and getter sequence; diagnostic sink only.
# No blank-path skip, alternate identity, second bind, CAD mutation or native call.
function Select-CadExactTargetTraceV4 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Snapshot,
        [ValidateSet('Bind','Read','Execute')][string]$Intent = 'Bind',
        [Parameter(Mandatory)][scriptblock]$TraceSink
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
            $activeRawFull = [string]$active.FullName
            $null=& $TraceSink @{stage='ACTIVE_DOCUMENT_FULLNAME';raw_full_path=$activeRawFull;application_hwnd=$hwnd;moniker=$moniker}
            $activeFull = ConvertTo-CadTargetV1FullPath $activeRawFull -Drawing
            $activePath = $activeFull
            $documents = $application.Documents
            if ($null -eq $documents) { throw 'DOCUMENT_COLLECTION_UNREADABLE' }
            $uniqueDocs = [Collections.Generic.List[object]]::new()
            $documentIndex=0
            foreach ($item in $documents) {
                $documentIndex++;if($documentIndex-gt32){throw 'TRACE_DOCUMENT_LIMIT'}
                if ($null -eq $item) { throw 'DOCUMENT_IDENTITY_UNREADABLE' }
                $itemRawFull = [string]$item.FullName
                $null=& $TraceSink @{stage='DOCUMENT_COLLECTION_FULLNAME';document_index=$documentIndex;raw_full_path=$itemRawFull;application_hwnd=$hwnd}
                $itemFull = ConvertTo-CadTargetV1FullPath $itemRawFull -Drawing
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
        $null=& $TraceSink @{stage='SELECTOR_ERROR';code=$code;script_stack=$_.ScriptStackTrace}
        $selectedApplication = $null; $selectedDocument = $null
    }
    [pscustomobject]@{
        status=$status;code=$code;intent=$Intent;level='ADMISSION_ONLY'
        application=$selectedApplication;document=$selectedDocument;observed=$observed.ToArray()
        enumerated_count=$Entries.Count;action_count=0;fallback_count=0
        live_execution_proven=$false;concurrent_execution_allowed=$false
    }
}
