param([Parameter(Mandatory)][string]$ScopePath,[Parameter(Mandatory)][string]$ScopeSha256,[Parameter(Mandatory)][string]$ManifestPath,[Parameter(Mandatory)][string]$ManifestSha256,[Parameter(Mandatory)][string]$OperationId,[Parameter(Mandatory)][int]$LeaseControllerPid,[Parameter(Mandatory)][string]$LeaseControllerStartUtc,[Parameter(Mandatory)][string]$JobName,[switch]$ValidateOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/dual_contract.ps1')
$scope=Read-CadExactBBoundJsonV1 $ScopePath $ScopeSha256;$manifest=Read-CadExactBBoundJsonV1 $ManifestPath $ManifestSha256
$v=Assert-CadDualBusinessScopeV1 $scope $root;Assert-CadDualManifestV1 $manifest $root
$ops=@($v.operations|Where-Object id -CEQ $OperationId);if($ops.Count-ne1){throw 'DUAL_WORKER_OPERATION'};$op=$ops[0];$owner=$v.identity.by_id[$op.owner]
$lib=Join-Path $root 'reports/cad_multi_window_interface_research/command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll'
if((Get-FileHash $lib).Hash-cne'FABE627922D36DBF3329A97F5B95F71B841D14B0767474D44A6A8E065AC532F3'){throw 'DUAL_JOB_DLL'}
$null=[Reflection.Assembly]::LoadFrom($lib);[CadCommandUiaV2.OwnHelperJob]::VerifyOwnMembership($JobName)
if([Threading.Thread]::CurrentThread.GetApartmentState()-ne'MTA'){throw 'DUAL_WORKER_MTA'}
if($ValidateOnly){foreach($name in @('Get-CadDiagnosticPropertyV1','Initialize-CadFileRotBackendV5','Invoke-CadFileRotLookupV5','Get-CadProbeFileBindingV3','Get-CadProbeRetainedABindingV4','Get-ReadWorkerBindingV1','Assert-ReadWorkerLeaseV1','Invoke-CadBOneDocumentSendV3','Write-CadBatchJsonAtomicV2','Read-CadBatchControlV2','Invoke-CadNativeReadIndependentSettlementV9')){if(-not(Get-Command $name -ErrorAction SilentlyContinue)){throw ('DUAL_RUNTIME_FUNCTION_MISSING:'+ $name)}};@{status='PASS_OWNJOB_WORKER_ABI_NO_CAD';operation_id=$OperationId;cad_calls=0;COM_calls=0;window_calls=0;actual_runtime_imports_verified=$true}|ConvertTo-Json -Compress;return}
Assert-CadDualReadyV1 $scope $root $ScopeSha256 $ManifestSha256
$script:validated=$v.identity;$clock=[Diagnostics.Stopwatch]::StartNew();$events=[Collections.Generic.List[object]]::new();$state=[pscustomobject]@{bind_count=0};$send=[pscustomobject]@{entered=$false;returned=$false};$application=$null;$lookup=$null;$before=$null;$after=$null;$native=$null;$status='BLOCKED_BEFORE_SEND';$detail=$null
$receipt=Join-Path $v.run ('worker_'+$op.id+'.json');$readyPath=Join-Path $v.run ('ready_'+$op.id+'.json');$releasePath=Join-Path $v.run ('release_'+$op.id+'.json');$reservation=Join-Path $v.run ('send_reservation_'+$op.id+'.json')
foreach($p in @($receipt,$readyPath,$releasePath,$op.signal_path,$op.business_signal_path,$reservation)){if(Test-Path $p){throw 'DUAL_WORKER_REPLAY'}}
function SnapshotDualOwners {
 Assert-ReadWorkerLeaseV1
 if((@(Get-Process -Name acad -ErrorAction SilentlyContinue|Select-Object -ExpandProperty Id|Sort-Object)-join',')-cne(@($v.identity.owners.process_id|Sort-Object)-join',')){throw 'DUAL_PROCESS_SET_CHANGED'}
 $all=@(foreach($o in $v.identity.owners){$x=Get-ReadWorkerSnapshotV1 $o;$x|Add-Member NoteProperty id $o.id;$x});Assert-CadProbeSnapshotsV3 $v.identity.owners $owner $all;$all
}
function BindDualDocument {
 if($op.owner-ceq'A'){Get-CadProbeRetainedABindingV4 $v.identity.owners $owner $application $state {SnapshotDualOwners} {param($e)$events.Add($e)}}
 else{Get-CadProbeFileBindingV3 $v.identity.owners $owner $lookup $state {SnapshotDualOwners} {param($e)$events.Add($e)}}
}
try{
 Assert-ReadWorkerLeaseV1;Initialize-CadProbeBridgeV1
 if(-not('CadSingleBackgroundV1.Native'-as[type])){Add-Type -Path (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/single_background_input_v3/BackgroundNative.cs')}
 $null=SnapshotDualOwners;Assert-CadDualProtectedFilesV1 $scope $v.identity $root
 if($op.owner-ceq'A'){$seed=Get-ReadWorkerBindingV1 $owner;if($seed.status-cne'PASS'-or$seed.intent-cne'Execute'){throw 'DUAL_A_INITIAL_BIND'};$application=$seed.application}
 else{Initialize-CadFileRotBackendV5;$lookup=Invoke-CadFileRotLookupV5 $owner.document_full_path ([CadExactFileRotV5.Backend]::new()) $events {param($e)};if($lookup.status-cne'REGISTERED_OBJECT_OBTAINED_IDENTITY_UNVERIFIED'){throw 'DUAL_B_EXACT_FILE_LOOKUP'}}
 $binding=BindDualDocument
 $before=@{full_path=[string]$binding.document.FullName;hwnd=[long]$binding.application.HWND;dbmod=[int]$binding.document.GetVariable('DBMOD');model_count=[int]$binding.document.ModelSpace.Count}
 if($before.full_path-ine$owner.document_full_path-or$before.hwnd-ne[long]$owner.window_handle){throw 'DUAL_PRE_BOUND_IDENTITY'}
 $expression=New-CadDualExpressionV1 $scope $op $owner $root
 Write-CadBatchJsonAtomicV2 $readyPath @{run_id=$scope.run_id;scope_sha256=$ScopeSha256;manifest_sha256=$ManifestSha256;operation_id=$op.id;nonce=$op.nonce;worker_pid=$PID;status='BOUND_WAITING_RELEASE';before=$before}
 while($null-eq($release=Read-CadBatchControlV2 $releasePath @('operation_id','nonce','data_receipt_path','data_receipt_sha256'))){Assert-ReadWorkerLeaseV1;if($clock.Elapsed.TotalSeconds-ge10){throw 'DUAL_RELEASE_TIMEOUT'};Start-Sleep -Milliseconds 20}
 if($release.operation_id-cne$op.id-or$release.nonce-cne$op.nonce){throw 'DUAL_RELEASE_IDENTITY'}
 # Preparation/hash/strict COM binding completed before both READYs. The send
 # boundary retains lease, immutable hashes, task data and fresh exact OS tuple;
 # the actual CAD body independently guards HWND and full active document path.
 Assert-DimensionRuntimeDataV5 $op.data_run $release
 if((Get-FileHash $ScopePath).Hash-cne$ScopeSha256-or(Get-FileHash $ManifestPath).Hash-cne$ManifestSha256){throw 'DUAL_BOUND_INPUT_CHANGED'}
 $null=SnapshotDualOwners
 $events.Add((ConvertTo-CadExactBFocusObservationV4 (Get-CadExactBFocusSampleV4 ([long]$owner.window_handle)) $owner))
 Write-CadBatchJsonAtomicV2 $reservation @{run_id=$scope.run_id;operation_id=$op.id;nonce=$op.nonce;state='RESERVED_SEND_MAY_HAVE_ENTERED';worker_pid=$PID}
 Invoke-CadBOneDocumentSendV3 $send $binding.document $expression
 while($clock.Elapsed.TotalSeconds-lt14){Assert-ReadWorkerLeaseV1;$errorPath=Join-Path $op.data_run ('reports/'+$op.id+'_error.txt');if(Test-Path $errorPath){throw ('DUAL_NATIVE_ERROR:'+ [IO.File]::ReadAllText($errorPath,[Text.Encoding]::GetEncoding(936)))};$native=Read-CadDualNativeV1 $scope $op;if($native){break};Start-Sleep -Milliseconds 20}
 if($null-eq$native){throw 'DUAL_NATIVE_COMPLETION_UNPROVEN'}
 if($op.stage-ceq'GENERATE'){$body=Read-CadDualNativeV1 $scope $op -GeneratorBody;if($null-eq$body){throw 'DUAL_EXACT_GENERATOR_BODY_INTERVAL_UNPROVEN'};$native|Add-Member NoteProperty generator_body $body}
 $binding=BindDualDocument
 $after=@{full_path=[string]$binding.document.FullName;hwnd=[long]$binding.application.HWND;dbmod=[int]$binding.document.GetVariable('DBMOD');model_count=[int]$binding.document.ModelSpace.Count}
 if($after.full_path-ine$owner.document_full_path-or$after.hwnd-ne$before.hwnd-or$after.model_count-$before.model_count-ne$op.expected_model_delta-or$native.ack.model_count-ne$before.model_count-or$native.complete.model_count-ne$after.model_count-or($op.stage-cne'GENERATE'-and$after.dbmod-ne$before.dbmod)){throw 'DUAL_DOCUMENT_COUNT_OR_DBMOD_DRIFT'}
 Assert-CadDualProtectedFilesV1 $scope $v.identity $root;$status='PASS'
}catch{$detail=$_.Exception.ToString();$status=if($send.entered){'UNKNOWN_OR_FAILED_AFTER_SINGLE_SEND'}else{'BLOCKED_BEFORE_SEND'}}
Write-CadBatchJsonAtomicV2 $receipt @{status=$status;run_id=$scope.run_id;scope_sha256=$ScopeSha256;operation_id=$op.id;nonce=$op.nonce;owner_id=$op.owner;post_call_count=$(if($send.entered){1}else{0});send_call_returned=$send.returned;native_evidence=$native;before=$before;after=$after;events=$events.ToArray();detail=$detail;elapsed_ms=$clock.ElapsedMilliseconds;retry_count=0;activation_count=0;input_count=0;input_evidence_scope='THIS_BUSINESS_WORKER_ONLY__SERIAL_REGISTRATION_SEPARATE'}
if($status-cne'PASS'){exit 1}
