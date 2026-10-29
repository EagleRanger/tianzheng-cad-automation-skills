param([Parameter(Mandatory)][string]$ReadyHandoffPath,[switch]$PreflightOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))
. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v2/batch_contract.ps1')
. (Join-Path $root 'reference/project-orchestration/reports/dimension_background_reproduction_v8/popup_snapshot_v3.ps1')
$ready=Get-Content $ReadyHandoffPath -Raw|ConvertFrom-Json -DateKind String
$sp=Resolve-CadExactBProjectPathV1 $root $ready.program.scope;$mp=Resolve-CadExactBProjectPathV1 $root $ready.program.manifest
$scope=Read-CadExactBBoundJsonV1 $sp $ready.program.scope_sha256;$manifest=Read-CadExactBBoundJsonV1 $mp $ready.program.manifest_sha256
$v=Assert-CadRepresentativeCommandBatchScopeV2 $scope $root
Assert-CadRepresentativeBatchManifestV2 $manifest $root
Assert-CadRepresentativeBatchDraftV2 $ready $scope $root
if($PreflightOnly){@{status='PASS_PRIVATE_OFFLINE_COMPOSITION__SHARED_ADMISSION_SEPARATE';operations=$v.operations.Count;cad_calls=0}|ConvertTo-Json -Compress;return}
Assert-CadRepresentativeBatchReadyV2 $scope $root $ready.program.scope_sha256 $ready.program.manifest_sha256
if(Test-Path (Join-Path $v.run 'controller_receipt.json')){throw 'BATCH_CONTROLLER_REPLAY'}
Import-Module (Join-Path $root 'scripts/common/CadOperationGuard.psm1') -Force
$null=[Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot '../command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll'))
if(-not('CadSingleBackgroundV1.Native'-as[type])){Add-Type -Path (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/single_background_input_v3/BackgroundNative.cs')}
$exe=$(if($env:CAD_POWERSHELL){[IO.Path]::GetFullPath($env:CAD_POWERSHELL)}else{Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'})
$python=$(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
$rows=[Collections.Generic.List[object]]::new();$pairs=[Collections.Generic.List[object]]::new();$cleanupErrors=[Collections.Generic.List[string]]::new();$samples=[Collections.Generic.List[object]]::new();$clock=[Diagnostics.Stopwatch]::StartNew();$guard=$null;$detail=$null;$protection='UNVERIFIED';$stop=$false
function BatchJson([string]$Path,$Data){Write-CadBatchJsonAtomicV2 $Path $Data}
function PumpBatch {
 if($clock.Elapsed.TotalSeconds-ge180){throw 'BATCH_OVERALL_DEADLINE'}
 $samples.Add(@{elapsed_ms=$clock.Elapsed.TotalMilliseconds;A=(Get-CadExactBFocusSampleV4 $scope.owners[0].window_handle);B=(Get-CadExactBFocusSampleV4 $scope.owners[1].window_handle)})
 foreach($row in $rows){if(-not$row.disposed){
  try{$row.job.Pump();if($row.job.OutputLimit){$row.failure='OUTPUT_LIMIT'};if(-not$row.job.RootExited-and$row.clock.Elapsed.TotalSeconds-ge15){$row.failure='HELPER_HARD_DEADLINE'};if($row.failure-and-not$row.stop_attempted){$row.stop_attempted=$true;$row.job.StopOwnJob()}}
  catch{$row.failure='HELPER_PUMP_OR_STOP:'+ $_.Exception.Message}
 }}
}
function CleanupBatchRow($Row) {
 if($Row.disposed){return}
 $errors=[Collections.Generic.List[string]]::new()
 try{
  if(-not($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof)){
   $Row.job.StopOwnJob();$drain=[Diagnostics.Stopwatch]::StartNew()
   while($drain.Elapsed.TotalSeconds-lt3){$Row.job.Pump();if($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof){break};Start-Sleep -Milliseconds 20}
  }
  if(-not($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof)){$errors.Add('UNSETTLED_AFTER_3S')}
 }catch{$errors.Add($_.Exception.Message)}
 finally{
  try{$Row.helper=@{pid=$Row.job.ProcessId;root_exited=$Row.job.RootExited;exit_code=$(if($Row.job.RootExited){$Row.job.ExitCode}else{$null});active=$Row.job.ActiveProcesses;stdout_eof=$Row.job.StdoutEof;stderr_eof=$Row.job.StderrEof;peak_bytes=$Row.job.PeakJobBytes;own_job_stop=$Row.job.OwnJobStopAttempted}}catch{$errors.Add('EVIDENCE:'+ $_.Exception.Message)}
  try{$Row.job.Dispose()}catch{$errors.Add('DISPOSE:'+ $_.Exception.Message)};$Row.disposed=$true
 }
 if($errors.Count){$message=$Row.operation.id+':'+($errors-join';');$cleanupErrors.Add($message);throw $message}
}
function ReadBatchReceipt($Row) {
 $path=Join-Path $v.run ('worker_'+$Row.operation.id+'.json')
 if(-not(Test-Path $path)){return @{state='MISSING';data=$null}}
 try{@{state='FILE_PRESENT';data=(Get-Content $path -Raw|ConvertFrom-Json -DateKind String)}}catch{@{state='UNREADABLE';data=$null}}
}
function SettleBatchRow($Row) {
 while(-not($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof)){
  PumpBatch;if($Row.failure){throw $Row.failure};if($Row.clock.Elapsed.TotalSeconds-ge15){throw 'BATCH_HELPER_UNSETTLED_AT_DEADLINE'};Start-Sleep -Milliseconds 20
 }
 if($Row.failure-or$Row.job.ExitCode-ne0){throw ('BATCH_HELPER_FAILED:'+ $Row.failure)}
 $receipt=Wait-CadWorkerReceiptV1 -Path (Join-Path $v.run ('worker_'+$Row.operation.id+'.json')) -TimeoutMilliseconds 1000 -PollMilliseconds 25
 $d=$receipt.data
 if($d.status-cne'PASS'-or$d.run_id-cne$scope.run_id-or$d.scope_sha256-cne$ready.program.scope_sha256-or$d.operation_id-cne$Row.operation.id-or$d.nonce-cne$Row.operation.nonce-or$d.post_call_count-ne1-or-not$d.send_call_returned){throw 'BATCH_RECEIPT_IDENTITY_OR_STATE'}
 $n=Read-CadBatchNativeV1 $scope $Row.operation $root
 if($null-eq$n-or$n.status-cne'PASS'){throw 'BATCH_PARENT_NATIVE_UNPROVEN'}
 $Row.validated_receipt=$d;$Row.native=$n;$d
}
function PrepareBatchDataReceipt([int]$Number) {
 $files=@(Get-ChildItem (Join-Path $v.run 'reports') -File|Where-Object Extension -In @('.tsv','.lsp','.txt')|ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash}})
 $path=Join-Path $v.run ('data_receipt_'+$Number+'.json');BatchJson $path $files
 @{path=$path;sha256=(Get-FileHash $path).Hash}
}
try {
 $guard=Enter-CadOperationGuard -ProjectRoot $root -OperationId $scope.run_id -AllowExistingAcad -TimeoutMilliseconds 0
 foreach($plan in @(Get-CadRepresentativeBatchPlanV1|Where-Object pair -GE $scope.resume_from_pair)){
  if($stop){$pairs.Add(@{pair=$plan.pair;category=$plan.category;status='SKIPPED_DEPENDENCY_OR_UNKNOWN__NO_SEND'});continue}
  $pairClock=[Diagnostics.Stopwatch]::StartNew();$active=[Collections.Generic.List[object]]::new();$ledger=$null;$overlap=$null;$artifact=$null;$pairError=$null
  try{
   $data=PrepareBatchDataReceipt $plan.pair
   foreach($o in $scope.owners){$popup=Read-DimOwnedPopupSnapshotV3 -Root $root -Owner $o;if($popup.popups.Count){throw 'BATCH_MODAL_BEFORE_BIND_NO_SEND'}}
   foreach($op in @($v.operations|Where-Object pair -EQ $plan.pair)){
    $workerArgs=@('-ScopePath',$sp,'-ScopeSha256',$ready.program.scope_sha256,'-ManifestPath',$mp,'-ManifestSha256',$ready.program.manifest_sha256,'-OperationId',$op.id,'-LeaseControllerPid',[string]$PID,'-LeaseControllerStartUtc',(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'))
    $job=[CadCommandUiaV2.OwnHelperJob]::Start($exe,(Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v2/command_worker_v1.ps1'),$workerArgs,$PSScriptRoot)
    $row=[pscustomobject]@{operation=$op;job=$job;clock=[Diagnostics.Stopwatch]::StartNew();disposed=$false;stop_attempted=$false;failure=$null;helper=$null;validated_receipt=$null;native=$null};$rows.Add($row);$active.Add($row)
   }
   foreach($row in $active){
    $p=Join-Path $v.run ('ready_'+$row.operation.id+'.json')
    while($null-eq($bound=Read-CadBatchControlV2 $p @('operation_id','nonce','worker_pid','status'))){PumpBatch;if($row.job.RootExited-or$row.clock.Elapsed.TotalSeconds-ge10){throw 'BATCH_DUAL_READY_TIMEOUT'};Start-Sleep -Milliseconds 20}
    if($bound.operation_id-cne$row.operation.id-or$bound.nonce-cne$row.operation.nonce-or$bound.worker_pid-ne$row.job.ProcessId-or$bound.status-cne'BOUND_WAITING_RELEASE'){throw 'BATCH_READY_BARRIER_IDENTITY'}
   }
   foreach($row in $active){BatchJson (Join-Path $v.run ('release_'+$row.operation.id+'.json')) @{operation_id=$row.operation.id;nonce=$row.operation.nonce;data_receipt_path=$data.path;data_receipt_sha256=$data.sha256}}
  }catch{$pairError=$_.Exception.ToString()}
  finally{
   $ledger=Invoke-CadNativeReadIndependentSettlementV9 -Rows $active.ToArray() -Settle {param($r)SettleBatchRow $r} -Cleanup {param($r)CleanupBatchRow $r} -ReadReceipt {param($r)ReadBatchReceipt $r} -ExpectedRunId $scope.run_id -ExpectedScopeSha256 $ready.program.scope_sha256
  }
  if(-not$pairError-and$active.Count-eq2-and$ledger.status-ceq'PASS_ALL_ISSUED_WORKERS_SETTLED'){
   $a=@($active|Where-Object {$_.operation.owner-ceq'A'})[0];$b=@($active|Where-Object {$_.operation.owner-ceq'B'})[0]
   $overlap=Get-CadBatchPairOverlapV1 $a.native $b.native
   try{&$python (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/representative_command_batch_v2/process_batch.py') $plan.process --run $v.run;if($LASTEXITCODE-ne0){throw ('BATCH_ARTIFACT_FAILED:'+ $plan.process)};$artifact='PASS_REAL_EFFECT_AUDIT'}catch{$pairError=$_.Exception.ToString()}
  }elseif(-not$pairError){$pairError='ISSUED_WORKERS_NOT_BOTH_SETTLED'}
  $pairStatus=if($pairError){'PARTIAL_OR_UNKNOWN'}elseif($overlap.positive_native_intersection){'PASS_FUNCTION_AND_POSITIVE_NATIVE_INTERSECTION'}else{'PASS_FUNCTION__NO_NATIVE_INTERSECTION'}
  $pairs.Add(@{pair=$plan.pair;category=$plan.category;status=$pairStatus;error=$pairError;settlement=$ledger;overlap=$overlap;effect_audit=$artifact;helpers=@($active|ForEach-Object{$_.helper});elapsed_ms=$pairClock.ElapsedMilliseconds})
  # A native/identity/protection failure makes later B mutations unsafe. A
  # completed preview with an output-only failure does not block a safe save.
  if($pairError-and-not($plan.stage-ceq'VISUAL'-and$ledger.status-ceq'PASS_ALL_ISSUED_WORKERS_SETTLED')){$stop=$true}
 }
}catch{$detail=$_.Exception.ToString()}
finally {
 foreach($row in $rows){try{CleanupBatchRow $row}catch{}}
 try{Assert-CadBatchProtectedFilesV1 $v.identity $root;$protection='UNCHANGED_ON_DISK'}catch{$protection=$_.Exception.Message}
 $all=@($pairs|Where-Object {$_.status-clike'PASS_FUNCTION*'}).Count-eq5
 $overlapCount=@($pairs|Where-Object {$_.status-ceq'PASS_FUNCTION_AND_POSITIVE_NATIVE_INTERSECTION'}).Count
 $status=if($detail-or$cleanupErrors.Count-or$protection-cne'UNCHANGED_ON_DISK'){'PARTIAL_OR_UNKNOWN_BATCH'}elseif($all-and$overlapCount-eq5){'PASS_REPRESENTATIVE_SUFFIX_AND_ALL_NATIVE_INTERSECTIONS__PREFIX_RETAINED'}elseif($all){'PASS_REPRESENTATIVE_SUFFIX_FUNCTIONS__PARTIAL_NATIVE_INTERSECTIONS'}else{'PARTIAL_REPRESENTATIVE_COMMAND_COVERAGE'}
 $samplePath=Join-Path $v.run 'foreground_samples.jsonl';$stream=[IO.StreamWriter]::new($samplePath,$false,[Text.UTF8Encoding]::new($false));try{foreach($sample in $samples){$stream.WriteLine(($sample|ConvertTo-Json -Depth 5 -Compress))}}finally{$stream.Dispose()}
 $report=@{schema_version=2;accepted_prefix_run=$scope.resume_source_run_id;accepted_prefix_pairs=2;accepted_prefix_sends=4;accepted_prefix_overlap_ms=16;frozen_generated_handles=$scope.frozen_new_handles;new_generation_count=0;profile_id=$scope.profile_id;run_id=$scope.run_id;status=$status;detail=$detail;pairs=$pairs.ToArray();function_pass_count=@($pairs|Where-Object {$_.status-clike'PASS_FUNCTION*'}).Count;positive_native_intersection_count=$overlapCount;protected_disk_files=$protection;cleanup_errors=$cleanupErrors.ToArray();focus_policy='OBSERVE_ONLY';foreground_samples=$samples.Count;continuous_background_proven=$false;aesthetic_acceptance=$false;two_chat_control_proven=$false;retry_count=0;cad_close_count=0;cad_kill_count=0;elapsed_ms=$clock.ElapsedMilliseconds;cad_left_open=$true}
 BatchJson (Join-Path $v.run 'controller_receipt.json') $report
 if($guard){Exit-CadOperationGuard -Guard $guard}
}
if($cleanupErrors.Count){throw 'BATCH_HELPER_CLEANUP_UNKNOWN'}
[pscustomobject]$report
