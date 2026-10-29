# Private candidate. Caller must retain the exact nonactivating file lookup result.
# No lookup, registration, input, focus, send, or lifecycle operation lives here.
. (Join-Path $PSScriptRoot 'com_identity_v1.ps1')
function Select-CadFileDocumentV8 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)]$Lookup,
        [Parameter(Mandatory)][string]$FullPath,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][scriptblock]$TraceSink,
        [switch]$OfflineManagedFixture
    )
    $stage='PRECONDITIONS';$strict=$null;$application=$null;$status='BLOCKED';$code='UNINITIALIZED'
    try {
        Assert-CadBindingDiagnosticSnapshotV1 $Expected $Snapshot
        foreach($flag in @('window_enabled','responding','serial_lease_held')) {
            if($Snapshot.$flag -isnot [bool] -or -not $Snapshot.$flag){throw ('NOT_READY:'+ $flag)}
        }
        if($Snapshot.modal_state -cne 'NONE'){throw 'MODAL_PRESENT_OR_UNKNOWN'}
        if($Lookup.status -cne 'REGISTERED_OBJECT_OBTAINED_IDENTITY_UNVERIFIED' -or $Lookup.counts.is_running -ne 1 -or $Lookup.counts.get_object -ne 1 -or -not $Lookup.owned_name_and_table_released){throw 'FILE_DOCUMENT_LOOKUP_NOT_SETTLED'}
        if($Lookup.entry.Name -cne $FullPath -or -not [object]::ReferenceEquals($Document,$Lookup.entry.Instance) -or -not(Test-CadTargetV1PathEqual (ConvertTo-CadTargetV1FullPath $FullPath -Drawing) (ConvertTo-CadTargetV1FullPath $Expected.document_full_path -Drawing))){throw 'FILE_DOCUMENT_ACQUIRED_OBJECT_OR_PATH_CHANGED'}
        # Explicit shape, not an inference from Document.HWND or moniker text.
        $stage='DOCUMENT_APPLICATION'
        $null=& $TraceSink @{stage=$stage+'_ENTER'}
        $application=Get-CadDiagnosticPropertyV1 $Document 'Application'
        $null=& $TraceSink @{stage=$stage+'_RETURN';is_null=($null -eq $application)}
        if($null -eq $application){throw 'REGISTERED_DOCUMENT_APPLICATION_NULL'}
        $stage='DOCUMENT_APPLICATION_HWND'
        $null=& $TraceSink @{stage=$stage+'_ENTER'}
        $hwndRaw=Get-CadDiagnosticPropertyV1 $application 'HWND'
        $null=& $TraceSink @{stage=$stage+'_RETURN';raw_is_null=($null -eq $hwndRaw);raw_value=$hwndRaw}
        if($null -eq $hwndRaw -or (ConvertTo-CadTargetV1Integer $hwndRaw) -ne (ConvertTo-CadTargetV1Integer $Expected.window_handle)){throw 'REGISTERED_DOCUMENT_APPLICATION_OWNER_MISMATCH'}
        $stage='REGISTERED_DOCUMENT_FULLNAME'
        $null=& $TraceSink @{stage=$stage+'_ENTER'}
        $pathRaw=Get-CadDiagnosticPropertyV1 $Document 'FullName'
        $null=& $TraceSink @{stage=$stage+'_RETURN';raw_full_path=$pathRaw}
        $path=ConvertTo-CadTargetV1FullPath $pathRaw -Drawing
        $wantedPath=ConvertTo-CadTargetV1FullPath $Expected.document_full_path -Drawing
        if(-not(Test-CadTargetV1PathEqual $path $wantedPath)){throw 'REGISTERED_DOCUMENT_PATH_MISMATCH'}
        # Preserve the original unique-document, active-document, native-idle,
        # CMDACTIVE/CMDNAMES and post-read identity checks, unchanged.
        $stage='FROZEN_STRICT_APPLICATION_ADMISSION'
        $strict=Select-CadExactTargetTraceV4 -Entries @([pscustomobject]@{Name=$FullPath;Instance=$application}) -Expected $Expected -Snapshot $Snapshot -Intent Read -TraceSink $TraceSink
        if($strict.status -cne 'PASS'){throw ('STRICT:'+ $strict.code)}
        # Different CLR wrappers are not proof of a different CAD document.
        # Compare controlling IUnknown, balancing only our acquired references.
        $stage='REGISTERED_DOCUMENT_COM_IDENTITY'
        $identity=Compare-CadRegisteredDocumentIdentityV1 $Document $strict.document -OfflineManagedFixture:$OfflineManagedFixture
        $null=& $TraceSink @{stage=$stage;result=$identity}
        if(-not$identity.verified){throw 'REGISTERED_DOCUMENT_COM_IDENTITY_UNVERIFIED'}
        if(-not$identity.same){throw 'REGISTERED_DOCUMENT_COM_IDENTITY_DIFFERS'}
        $status='PASS';$code='EXACT_REGISTERED_DOCUMENT_ADMITTED'
    } catch {
        $code=$_.Exception.Message
        $null=& $TraceSink @{stage='REGISTERED_DOCUMENT_ERROR';failed_stage=$stage;code=$code;exception_chain=@(Get-CadDiagnosticExceptionChainV1 $_.Exception)}
        $application=$null;$strict=$null
    }
    [pscustomobject]@{
        status=$status;code=$code;intent='Read';level='EXACT_FILE_DOCUMENT_IDENTITY_ONLY'
        application=$application;document=$(if($status -ceq 'PASS'){$Document}else{$null})
        strict=$strict;lookup_count=0;send_count=0;focus_count=0
        observed=$(if($null-ne$strict){$strict.observed}else{@()});live_root_cause_proven=$false;send_authorized=$false
    }
}
