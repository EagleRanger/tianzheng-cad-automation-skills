# COM identity is controlling IUnknown within this one worker/apartment, not RCW
# reference identity. Never ReleaseComObject/FinalReleaseComObject a held RCW.
function Compare-CadIUnknownLeasesV1($Left,$Right,[scriptblock]$Acquire,[scriptblock]$Release) {
    $lp=[IntPtr]::Zero;$rp=[IntPtr]::Zero;$acquired=0;$releaseAttempts=0
    $same=$false;$verified=$false;$errorText=$null;$releaseErrors=@()
    try {
        $lp=[IntPtr](& $Acquire $Left)
        if($lp-eq[IntPtr]::Zero){throw 'LEFT_IUNKNOWN_NULL'};$acquired++
        $rp=[IntPtr](& $Acquire $Right)
        if($rp-eq[IntPtr]::Zero){throw 'RIGHT_IUNKNOWN_NULL'};$acquired++
        $same=($lp-eq$rp);$verified=$true
    } catch {$errorText=$_.Exception.Message}
    finally {
        # Two equal pointers still represent TWO acquired references. Release
        # once per successful acquisition; always attempt the other after error.
        foreach($pointer in @($rp,$lp)) {
            if($pointer-ne[IntPtr]::Zero){
                $releaseAttempts++
                try {$null=& $Release $pointer} catch {$releaseErrors+=@($_.Exception.Message)}
            }
        }
    }
    if($releaseErrors.Count){$verified=$false}
    [pscustomobject]@{same=$same;verified=$verified;kind='COM_IUNKNOWN';acquired=$acquired;release_attempts=$releaseAttempts;release_errors=$releaseErrors;error=$errorText;runtime_COM_evidence=$verified}
}
function Compare-CadRegisteredDocumentIdentityV1($Left,$Right,[switch]$OfflineManagedFixture) {
    $leftCom=[Runtime.InteropServices.Marshal]::IsComObject($Left)
    $rightCom=[Runtime.InteropServices.Marshal]::IsComObject($Right)
    if($leftCom-and$rightCom){
        Compare-CadIUnknownLeasesV1 $Left $Right {param($o)[Runtime.InteropServices.Marshal]::GetIUnknownForObject($o)} {param($p)[Runtime.InteropServices.Marshal]::Release($p)}
        return
    }
    if($OfflineManagedFixture-and-not$leftCom-and-not$rightCom){
        return [pscustomobject]@{same=[object]::ReferenceEquals($Left,$Right);verified=$true;kind='MANAGED_FIXTURE_ONLY';acquired=0;release_attempts=0;release_errors=@();error=$null;runtime_COM_evidence=$false}
    }
    [pscustomobject]@{same=$false;verified=$false;kind='COM_IDENTITY_UNAVAILABLE';acquired=0;release_attempts=0;release_errors=@();error='REGISTERED_DOCUMENT_NOT_COM';runtime_COM_evidence=$false}
}
