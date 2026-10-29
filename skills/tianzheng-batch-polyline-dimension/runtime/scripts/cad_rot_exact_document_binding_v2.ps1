Set-StrictMode -Version Latest

function Select-CadRotExactDocumentV2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][long]$WindowHandle,
        [Parameter(Mandatory = $true)][string]$DocumentName,
        [Parameter(Mandatory = $true)][string]$OwnerMainWindowTitle
    )

    $observed = [System.Collections.Generic.List[object]]::new()
    $exactApplication = $null
    $exactDocument = $null
    $identityMethod = $null
    foreach ($entry in $Entries) {
        $moniker = try { [string]$entry.Name } catch { '' }
        $application = try { $entry.Instance } catch { $null }
        if ($null -eq $application) {
            $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$null;active_name=$null;active_full_name=$null;documents=@();identity_method=$null;stage='NULL_INSTANCE'})
            continue
        }

        $candidateHwnd = $null
        try { $candidateHwnd = [long]$application.HWND } catch {}
        if ($null -eq $candidateHwnd) {
            $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$null;active_name=$null;active_full_name=$null;documents=@();identity_method=$null;stage='HWND_UNREADABLE'})
            continue
        }
        if ($candidateHwnd -ne $WindowHandle) {
            $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$candidateHwnd;active_name=$null;active_full_name=$null;documents=@();identity_method=$null;stage='HWND_DIFFERENT'})
            continue
        }

        $active = $null; $activeName = ''; $activeFullName = ''
        try { $active = $application.ActiveDocument } catch {}
        if ($null -ne $active) {
            try { $activeName = [string]$active.Name } catch {}
            try { $activeFullName = [string]$active.FullName } catch {}
        }
        if ($null -eq $active) {
            $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$candidateHwnd;active_name=$null;active_full_name=$null;documents=@();identity_method=$null;stage='ACTIVE_DOCUMENT_UNREADABLE'})
            continue
        }

        $candidate = $null
        if ($activeName -ceq $DocumentName) {
            $candidate = $active; $identityMethod = 'ACTIVE_DOCUMENT_NAME'
        }
        elseif (-not [string]::IsNullOrWhiteSpace($activeFullName) -and
                [IO.Path]::GetFileName($activeFullName) -ceq $DocumentName) {
            $candidate = $active; $identityMethod = 'ACTIVE_DOCUMENT_FULLNAME_LEAF'
        }

        $documentEvidence = [System.Collections.Generic.List[object]]::new()
        $collectionMatches = [System.Collections.Generic.List[object]]::new()
        $nonEmptyCollectionIdentityCount = 0
        if ($null -eq $candidate) {
            try {
                foreach ($item in $application.Documents) {
                    $itemName = ''; $itemFullName = ''
                    try { $itemName = [string]$item.Name } catch {}
                    try { $itemFullName = [string]$item.FullName } catch {}
                    if (-not [string]::IsNullOrWhiteSpace($itemName) -or -not [string]::IsNullOrWhiteSpace($itemFullName)) { $nonEmptyCollectionIdentityCount++ }
                    $match = $itemName -ceq $DocumentName -or
                        (-not [string]::IsNullOrWhiteSpace($itemFullName) -and [IO.Path]::GetFileName($itemFullName) -ceq $DocumentName)
                    $documentEvidence.Add([pscustomobject]@{name=$itemName;full_name=$itemFullName;match=$match})
                    if ($match) { $collectionMatches.Add($item) }
                }
            } catch {}
            if ($collectionMatches.Count -eq 1) {
                $candidate = $collectionMatches[0]; $identityMethod = 'EXACT_APPLICATION_DOCUMENTS_COLLECTION'
            }
            elseif ($collectionMatches.Count -gt 1) {
                $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$candidateHwnd;active_name=$activeName;active_full_name=$activeFullName;documents=@($documentEvidence);identity_method=$null;stage='DOCUMENT_COLLECTION_AMBIGUOUS'})
                continue
            }
        }

        if ($null -eq $candidate -and [string]::IsNullOrWhiteSpace($activeName) -and
            [string]::IsNullOrWhiteSpace($activeFullName) -and $nonEmptyCollectionIdentityCount -eq 0) {
            $exactTitleToken = '[' + $DocumentName + ']'
            if ($OwnerMainWindowTitle.IndexOf($exactTitleToken,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $candidate = $active; $identityMethod = 'EXACT_HWND_OWNER_TITLE_WHEN_ALL_COM_DOCUMENT_IDENTITIES_EMPTY'
            }
        }

        if ($null -eq $candidate) {
            $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$candidateHwnd;active_name=$activeName;active_full_name=$activeFullName;documents=@($documentEvidence);identity_method=$null;stage='DOCUMENT_DIFFERENT'})
            continue
        }

        $observed.Add([pscustomobject]@{moniker=$moniker;hwnd=$candidateHwnd;active_name=$activeName;active_full_name=$activeFullName;documents=@($documentEvidence);identity_method=$identityMethod;stage='EXACT_MATCH'})
        $exactApplication = $application
        $exactDocument = $candidate
        break
    }

    [pscustomobject]@{
        status = if ($null -ne $exactDocument) { 'PASS' } else { 'NOT_FOUND' }
        application = $exactApplication
        document = $exactDocument
        identity_method = $identityMethod
        observed = @($observed)
        enumerated_count = $Entries.Count
        exact_hwnd_count = @($observed | Where-Object { $_.hwnd -eq $WindowHandle }).Count
    }
}
