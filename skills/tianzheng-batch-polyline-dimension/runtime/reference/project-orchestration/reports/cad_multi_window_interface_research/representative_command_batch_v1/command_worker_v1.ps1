param([Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256,[Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][int]$LeaseControllerPid,[Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName,[switch]$ValidateOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v1/batch_contract.ps1')
$scope=Read-CadExactBBoundJsonV1 $ScopePath $ScopeSha256
$manifest=Read-CadExactBBoundJsonV1 $ManifestPath $ManifestSha256
$v=Assert-CadRepresentativeCommandBatchScopeV1 $scope $root
Assert-CadRepresentativeBatchManifestV1 $manifest $root
$ops=@($v.operations|Where-Object id -CEQ $OperationId);if($ops.Count-ne1){throw 'BATCH_WORKER_OPERATION'};$op=$ops[0];$owner=$v.identity.by_id[$op.owner]
$lib=Join-Path $root 'reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll'
if((Get-FileHash $lib).Hash-cne'FABE627922D36DBF3329A97F5B95F71B841D14B0767474D44A6A8E065AC532F3'){throw 'BATCH_JOB_DLL'}
$null=[Reflection.Assembly]::LoadFrom($lib);[CadCommandUiaV2.OwnHelperJob]::VerifyOwnMembership($JobName)
if([Threading.Thread]::CurrentThread.GetApartmentState()-ne'MTA'){throw 'BATCH_WORKER_MTA'}
if($ValidateOnly){@{status='PASS_OWNJOB_WORKER_ABI_NO_CAD';operation_id=$OperationId;cad_calls=0}|ConvertTo-Json -Compress;return}
Assert-CadRepresentativeBatchReadyV1 $scope $root $ScopeSha256 $ManifestSha256
$script:validated=$v.identity
$clock=[Diagnostics.Stopwatch]::StartNew();$events=[Collections.Generic.List[object]]::new();$state=[pscustomobject]@{bind_count=0};$send=[pscustomobject]@{entered=$false;returned=$false};$application=$null;$lookup=$null;$before=$null;$after=$null;$native=$null;$business=$null;$status='BLOCKED_BEFORE_SEND';$detail=$null
$receipt=Join-Path $v.run ('worker_'+$op.id+'.json');$readyPath=Join-Path $v.run ('ready_'+$op.id+'.json');$releasePath=Join-Path $v.run ('release_'+$op.id+'.json')
foreach($p in @($receipt,$readyPath,$releasePath,$op.signal_path)){if(Test-Path $p){throw 'BATCH_WORKER_REPLAY'}}
function SnapshotBatchOwners {
 Assert-ReadWorkerLeaseV1
 if((@(Get-Process -Name acad -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id|Sort-Object)-join',')-cne(@($v.identity.owners.process_id|Sort-Object)-join',')){throw 'BATCH_PROCESS_SET_CHANGED'}
 $all=@(foreach($o in $v.identity.owners){$x=Get-ReadWorkerSnapshotV1 $o;$x|Add-Member NoteProperty id $o.id;$x})
 Assert-CadProbeSnapshotsV3 $v.identity.owners $owner $all
 $all
}
function BindBatchDocument {
 if($op.owner-ceq'A'){Get-CadProbeRetainedABindingV4 $v.identity.owners $owner $application $state {SnapshotBatchOwners} {param($e)$events.Add($e)}}
 else{Get-CadProbeFileBindingV3 $v.identity.owners $owner $lookup $state {SnapshotBatchOwners} {param($e)$events.Add($e)}}
}
try {
 Assert-ReadWorkerLeaseV1
 Initialize-CadProbeBridgeV1
 if(-not('CadSingleBackgroundV1.Native'-as[type])){Add-Type -Path (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/single_background_input_v3/BackgroundNative.cs')}
 $null=SnapshotBatchOwners
 Assert-CadBatchProtectedFilesV1 $v.identity $root
 if($op.owner-ceq'A'){
  $seed=Get-ReadWorkerBindingV1 $owner
  if($seed.status-cne'PASS'-or$seed.intent-cne'Execute'){throw 'BATCH_A_INITIAL_STRICT_BINDING'}
  $application=$seed.application
 }else{
  Initialize-CadFileRotBackendV5
  $lookup=Invoke-CadFileRotLookupV5 $owner.document_full_path ([CadExactFileRotV5.Backend]::new()) $events {param($e)}
  if($lookup.status-cne'REGISTERED_OBJECT_OBTAINED_IDENTITY_UNVERIFIED'){throw 'BATCH_B_EXACT_FILE_LOOKUP'}
 }
 $binding=BindBatchDocument
 $before=@{full_path=[string]$binding.document.FullName;hwnd=[long]$binding.application.HWND;dbmod=[int]$binding.document.GetVariable('DBMOD');model_count=[int]$binding.document.ModelSpace.Count}
 if($op.owner-ceq'A'-and$before.dbmod-ne0){throw 'BATCH_A_NOT_CLEAN'}
 Write-CadPreparationJsonV1 $readyPath @{operation_id=$op.id;nonce=$op.nonce;worker_pid=$PID;status='BOUND_WAITING_RELEASE'}
 while(-not(Test-Path $releasePath)){Assert-ReadWorkerLeaseV1;if($clock.Elapsed.TotalSeconds-ge10){throw 'BATCH_RELEASE_TIMEOUT'};Start-Sleep -Milliseconds 20}
 $release=Get-Content $releasePath -Raw|ConvertFrom-Json -DateKind String
 if($release.operation_id-cne$op.id-or$release.nonce-cne$op.nonce){throw 'BATCH_RELEASE_IDENTITY'}
 Assert-DimensionRuntimeDataV5 $v.run $release
 Assert-CadRepresentativeBatchReadyV1 $scope $root $ScopeSha256 $ManifestSha256
 if((Get-FileHash $ScopePath).Hash-cne$ScopeSha256-or(Get-FileHash $ManifestPath).Hash-cne$ManifestSha256){throw 'BATCH_SCOPE_OR_MANIFEST_CHANGED'}
 $binding=BindBatchDocument
 $focus=ConvertTo-CadExactBFocusObservationV4 (Get-CadExactBFocusSampleV4 ([long]$owner.window_handle)) $owner;$events.Add($focus)
 if($op.owner-ceq'A'){
  $recipe=Get-CadBatchARecipeV1 $scope $op $root
  $expression=New-CadABNativeExpressionV8 $recipe $op $owner
  Write-CadPreparationJsonV1 (Join-Path $v.run ('send_reservation_'+$op.id+'.json')) @{run_id=$scope.run_id;operation_id=$op.id;nonce=$op.nonce;state='RESERVED_SEND_MAY_HAVE_ENTERED'}
  Invoke-CadBOneDocumentSendV3 $send $binding.document $expression
 }else{
  $session=[pscustomobject]@{root=$root;run=$v.run;scope=$scope;scope_hash=$ScopeSha256;operation=$op;identity=$v.identity;binding=$binding;send=$send}
  $expression=New-CadExactBFixedStageExpressionV2 $session
  $null=Invoke-CadExactBReservedSendV1 $session $expression
 }
 while($clock.Elapsed.TotalSeconds-lt14){
  Assert-ReadWorkerLeaseV1
  $errorPath=Join-Path $v.run ('reports/'+$op.id+'_error.txt')
  if(Test-Path $errorPath){throw ('BATCH_NATIVE_STAGE_ERROR:'+ [IO.File]::ReadAllText($errorPath,[Text.Encoding]::GetEncoding(936)))}
  $native=Read-CadBatchNativeV1 $scope $op $root
  if($null-ne$native-and$native.status-ceq'PASS'){break};Start-Sleep -Milliseconds 20
 }
 if($null-eq$native-or$native.status-cne'PASS'){throw 'BATCH_NATIVE_COMPLETION_UNPROVEN'}
 $binding=BindBatchDocument
 $after=@{full_path=[string]$binding.document.FullName;hwnd=[long]$binding.application.HWND;dbmod=[int]$binding.document.GetVariable('DBMOD');model_count=[int]$binding.document.ModelSpace.Count}
 if($after.full_path-ine$owner.document_full_path-or$after.hwnd-ne$before.hwnd-or$after.model_count-$before.model_count-ne$(if($op.owner-ceq'B'){$op.expected_model_delta}else{0})){throw 'BATCH_DOCUMENT_OR_COUNT_DRIFT'}
 if($op.owner-ceq'A'){
  if($after.dbmod-ne$before.dbmod){throw 'BATCH_A_READ_CHANGED_DBMOD'}
  $reader=Read-CadABReaderStageV8 $recipe $op
  $business=Read-CadBackgroundNativeReportV1 (Get-CadNativeOperationLensV8 $recipe $op) ([pscustomobject]@{owner=$owner;run=$v.run})
  if($business.summary.model_before-ne$before.model_count-or$business.summary.dbmod_before-ne$before.dbmod){throw 'BATCH_A_BUSINESS_BASELINE_CONFLICT'}
 }
 Assert-CadBatchProtectedFilesV1 $v.identity $root
 $status='PASS'
}catch{$detail=$_.Exception.ToString();$status=if($send.entered){'UNKNOWN_OR_FAILED_AFTER_SINGLE_SEND'}else{'BLOCKED_BEFORE_SEND'}}
Write-CadPreparationJsonV1 $receipt @{status=$status;run_id=$scope.run_id;scope_sha256=$ScopeSha256;operation_id=$op.id;nonce=$op.nonce;owner_id=$op.owner;post_call_count=$(if($send.entered){1}else{0});send_call_returned=$send.returned;native_evidence=$native;business_evidence=$business;before=$before;after=$after;events=$events.ToArray();detail=$detail;elapsed_ms=$clock.ElapsedMilliseconds;retry_count=0;activation_count=0;input_count=0}
if($status-cne'PASS'){exit 1}
