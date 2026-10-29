. (Join-Path $PSScriptRoot '../lifecycle_v1/preparation_contract_v1.ps1')
. (Join-Path $PSScriptRoot '../v3/cad_multi_owner_preflight_contract_v3.ps1')
function Assert-CadBindingDiagnosticScopeV1($Scope,[string]$Root,[string]$RunDirectory) {
    if($Scope.schema_version-ne1-or$Scope.profile_id-cne'CAD-MULTI-OWNER-BINDING-DIAGNOSTIC-V1'-or$Scope.intent-cne'ReadDiagnostics'){throw 'DIAG_SCOPE_IDENTITY'}
    if($Scope.run_id-cnotmatch'^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$'){throw 'DIAG_RUN_ID'}
    $run=Assert-CadPreparationPathV1 $RunDirectory $Root
    if($run-ine(Join-Path $Root ('runs/'+$Scope.run_id))){throw 'DIAG_RUN_PATH'}
    $v=Assert-CadMultiOwnerPreflightScopeV1 ([pscustomobject]@{schema_version=1;profile_id='CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1';intent='Read';run_id=$Scope.run_id;owners=$Scope.owners;sequence=@('A','B','A')}) $Root
    if($v.owners.Count-ne2){throw 'DIAG_TWO_OWNERS_REQUIRED'}
    foreach($prefix in @('prior_get_return','prior_get_scope','prior_probe_return')){
        $path=Assert-CadPreparationPathV1 ([string]$Scope.($prefix+'_path')) $Root;$hash=[string]$Scope.($prefix+'_sha256')
        if($hash-cnotmatch'^[A-F0-9]{64}$'-or(Get-FileHash -LiteralPath $path).Hash-cne$hash){throw ('DIAG_PREDECESSOR_HASH:'+ $prefix)}
    }
    $r=Read-CadPreparationScopeV1 $Scope.prior_get_return_path;$s=Read-CadPreparationScopeV1 $Scope.prior_get_scope_path;$p=Read-CadPreparationScopeV1 $Scope.prior_probe_return_path
    if($r.workflow_id-cne'CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1'-or$r.run_id-cne$s.run_id-or$r.controller_report.scope_sha256-cne$Scope.prior_get_scope_sha256-or$Scope.prior_get_return_path-ine(Join-Path $Root ('runs/'+$r.run_id+'/execution_return.json'))){throw 'DIAG_GET_PREDECESSOR_IDENTITY'}
    if($p.workflow_id-cne'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1'-or$p.status-cne'UNKNOWN'-or$Scope.prior_probe_return_path-ine(Join-Path $Root ('runs/'+$p.run_id+'/execution_return.json'))){throw 'DIAG_PROBE_PREDECESSOR_IDENTITY'}
    if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($s.owners|ConvertTo-Json -Depth 8 -Compress)){throw 'DIAG_PREDECESSOR_OWNER_CHANGED'}
    if(($Scope.owners|ConvertTo-Json -Depth 8 -Compress)-cne($p.controller_report.scope_owners|ConvertTo-Json -Depth 8 -Compress)){throw 'DIAG_PROBE_OWNER_CHANGED'}
    [pscustomobject]@{run=$run;run_id=$Scope.run_id;identity=$v;binding_timeout_seconds=20;capture_timeout_seconds=12;order=@('B','A')}
}
function Assert-CadBindingDiagnosticDependenciesV1([string]$Directory,[string]$Root) {
    $m=Read-CadPreparationScopeV1 (Join-Path $Directory 'candidate_manifest.json')
    if($m.id-cne'CAD-MULTI-OWNER-BINDING-DIAGNOSTIC-V1'){throw 'DIAG_MANIFEST_IDENTITY'}
    foreach($f in $m.files){$path=Assert-CadPreparationPathV1 (Join-Path $Root $f.path) $Root;if((Get-FileHash -LiteralPath $path).Hash-cne$f.sha256){throw ('DIAG_DEPENDENCY_CHANGED:'+ $f.path)}}
}
function Assert-CadBindingDiagnosticSnapshotV1($Owner,$Snapshot) {
    foreach($name in @('process_id','window_handle')){if((ConvertTo-CadTargetV1Integer $Owner.$name)-ne(ConvertTo-CadTargetV1Integer $Snapshot.$name)){throw ('DIAG_OS_IDENTITY:'+ $name)}}
    if((ConvertTo-CadTargetV1Integer $Snapshot.window_process_id)-ne(ConvertTo-CadTargetV1Integer $Owner.process_id)-or$Snapshot.window_valid-isnot[bool]-or-not$Snapshot.window_valid){throw 'DIAG_OS_WINDOW_OWNER'}
    if((ConvertTo-CadTargetV1StartTicks $Snapshot.process_start_time_utc)-ne(ConvertTo-CadTargetV1StartTicks $Owner.process_start_time_utc)-or-not(Test-CadTargetV1PathEqual $Snapshot.process_image_path $Owner.process_image_path)){throw 'DIAG_OS_PROCESS_REUSED'}
}
function Get-CadDiagnosticExceptionChainV1($Exception) {
    $items=@();$current=$Exception
    for($i=0;$null-ne$current-and$i-lt8;$i++){$code=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$current.HResult),0);$items+=[pscustomobject]@{type=$current.GetType().FullName;message=$current.Message;hresult=('{0:X8}'-f$code)};$current=$current.InnerException}
    $items
}
function Get-CadDiagnosticPropertyV1($Instance,[string]$Name) {
    if($null-eq$Instance){throw 'DIAG_NULL_PROPERTY_INSTANCE'}
    # PowerShell's adapted property access may surface a throwing getter as
    # null. Explicit dispatch makes the original invocation exception visible.
    $value=$Instance.GetType().InvokeMember($Name,([Reflection.BindingFlags]::GetProperty-bor[Reflection.BindingFlags]::Public-bor[Reflection.BindingFlags]::Instance),$null,$Instance,$null)
    # Preserve collection identity; enumeration must happen inside its own
    # durable stage, not implicitly while returning a property result.
    return ,$value
}
function Get-CadDiagnosticHwndV1($Instance) {
    $value=Get-CadDiagnosticPropertyV1 $Instance 'HWND'
    if($null-eq$value){throw 'DIAG_NULL_HWND'}
    [long]$value
}
function Invoke-CadBindingDiagnosticFactsV1($Entries,$Owner,$Snapshot,[scriptblock]$Trace) {
    Assert-CadBindingDiagnosticSnapshotV1 $Owner $Snapshot
    $facts=[Collections.Generic.List[object]]::new()
    function ReadDiag([string]$Label,[scriptblock]$Read) {
        & $Trace ([ordered]@{stage='GET_ENTER';owner=$Owner.id;label=$Label})
        try{$value=& $Read;& $Trace ([ordered]@{stage='GET_RETURN';owner=$Owner.id;label=$Label});[pscustomobject]@{ok=$true;value=$value;error=$null;hresult=$null}}
        catch{$chain=@(Get-CadDiagnosticExceptionChainV1 $_.Exception);$e=[pscustomobject]@{ok=$false;value=$null;error=$_.Exception.Message;hresult=$chain[0].hresult;exception_chain=$chain};& $Trace ([ordered]@{stage='GET_ERROR';owner=$Owner.id;label=$Label;error=$e.error;hresult=$e.hresult;exception_chain=$chain});$e}
    }
    $index=0
    foreach($entry in $Entries){
        $row=[ordered]@{index=$index;moniker=[string]$entry.Name;rot_get_error=$entry.Error;rot_get_hresult=$entry.HResult;rot_get_exception_chain=$entry.ErrorChain;direct_hwnd=$null;application_hwnd=$null;hwnd_errors=@();exact_owner=$false;active_full_path=$null;document_paths=@();read_errors=@()};$index++
        if($null-eq$entry.Instance){$facts.Add([pscustomobject]$row);continue}
        $instance=$entry.Instance;$app=$instance
        $g=ReadDiag ('entry'+$row.index+'.HWND') {Get-CadDiagnosticHwndV1 $instance}
        if($g.ok){$row.direct_hwnd=[long]$g.value}else{$row.hwnd_errors+=@($g|Select-Object error,hresult,exception_chain)}
        if(-not$g.ok-or[long]$g.value-ne[long]$Owner.window_handle){
            $a=ReadDiag ('entry'+$row.index+'.Application') {Get-CadDiagnosticPropertyV1 $instance 'Application'}
            if($a.ok-and$null-ne$a.value){$app=$a.value;$g=ReadDiag ('entry'+$row.index+'.Application.HWND') {Get-CadDiagnosticHwndV1 $app};if($g.ok){$row.application_hwnd=[long]$g.value}else{$row.hwnd_errors+=@($g|Select-Object error,hresult,exception_chain)}}else{$row.hwnd_errors+=@($a|Select-Object error,hresult,exception_chain);$g=[pscustomobject]@{ok=$false;value=$null}}
        }
        if(-not$g.ok-or[long]$g.value-ne[long]$Owner.window_handle){$facts.Add([pscustomobject]$row);continue}
        $row.exact_owner=$true
        $active=ReadDiag ('entry'+$row.index+'.ActiveDocument') {Get-CadDiagnosticPropertyV1 $app 'ActiveDocument'}
        if($active.ok-and$null-ne$active.value){$doc=$active.value;$full=ReadDiag ('entry'+$row.index+'.ActiveDocument.FullName') {Get-CadDiagnosticPropertyV1 $doc 'FullName'};if($full.ok){$row.active_full_path=[string]$full.value}else{$row.read_errors+=@($full|Select-Object error,hresult,exception_chain)}}else{$row.read_errors+=@($active|Select-Object error,hresult,exception_chain)}
        $collection=ReadDiag ('entry'+$row.index+'.Documents') {Get-CadDiagnosticPropertyV1 $app 'Documents'}
        if($collection.ok){
            $dindex=0
            & $Trace ([ordered]@{stage='DOCUMENT_ENUM_ENTER';owner=$Owner.id;index=$row.index})
            try{
                foreach($docItem in $collection.value){$full=ReadDiag ('entry'+$row.index+'.Documents['+$dindex+'].FullName') {Get-CadDiagnosticPropertyV1 $docItem 'FullName'};$dindex++;if($full.ok){$row.document_paths+=@([string]$full.value)}else{$row.read_errors+=@($full|Select-Object error,hresult,exception_chain)}}
                & $Trace ([ordered]@{stage='DOCUMENT_ENUM_RETURN';owner=$Owner.id;index=$row.index;count=$dindex})
            }catch{
                $chain=@(Get-CadDiagnosticExceptionChainV1 $_.Exception);$row.read_errors+=@([pscustomobject]@{error=$_.Exception.Message;hresult=$chain[0].hresult;exception_chain=$chain})
                & $Trace ([ordered]@{stage='DOCUMENT_ENUM_ERROR';owner=$Owner.id;index=$row.index;count=$dindex;exception_chain=$chain})
            }
        }else{$row.read_errors+=@($collection|Select-Object error,hresult,exception_chain)}
        $facts.Add([pscustomobject]$row)
    }
    # Diagnose the exposed identity surface only. Never call the strict selector
    # a second time with untraced getters, never return a COM action binding.
    $exact=@($facts|Where-Object exact_owner)
    $pathMatches=@($exact|Where-Object {$_.active_full_path-ieq$Owner.document_full_path-or$Owner.document_full_path-in$_.document_paths})
    $classification=if($exact.Count-eq0){'NO_MATCHING_HWND_IN_SUCCESSFUL_IDENTITY_READS'}elseif($pathMatches.Count-eq0){'EXACT_HWND_OBSERVED_BUT_EXPECTED_PATH_NOT_OBSERVED'}else{'EXACT_HWND_AND_PATH_OBSERVED_NOT_ACTION_ADMISSION'}
    [pscustomobject]@{owner=$Owner.id;snapshot=$Snapshot;facts=$facts.ToArray();classification=$classification;exact_owner_entry_count=$exact.Count;matching_path_entry_count=$pathMatches.Count;strict_binding_retried=$false;native_idle_proven=$false;command_send_count=0}
}
