param([Parameter(Mandatory)][string]$ReadyHandoffPath,[switch]$PreflightOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'));. (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/dual_contract.ps1')
. (Join-Path $root 'reference/project-orchestration/reports/dimension_background_reproduction_v8/popup_snapshot_v3.ps1')
$ready=Get-Content $ReadyHandoffPath -Raw|ConvertFrom-Json -DateKind String
$sp=Resolve-CadExactBProjectPathV1 $root $ready.program.scope;$mp=Resolve-CadExactBProjectPathV1 $root $ready.program.manifest
$scope=Read-CadExactBBoundJsonV1 $sp $ready.program.scope_sha256;$manifest=Read-CadExactBBoundJsonV1 $mp $ready.program.manifest_sha256
$v=Assert-CadDualBusinessScopeV1 $scope $root;Assert-CadDualManifestV1 $manifest $root
$expected=$script:DualRelative+"invoke_dual.ps1 -ReadyHandoffPath '"+(Join-Path $root 'config/current_execution_handoff.json')+"'"
if($ready.governance.workflow_id-cne$scope.profile_id-or$ready.action.controller_template-cne$expected-or$ready.action.send_max_count-ne6-or$ready.action.plugin_load_max-ne0-or$ready.action.foreground_input_max-ne0-or$ready.issuer.thread_id-cne'RECEIVER_ID_REQUIRED'-or$ready.target.thread_id-cne'RECEIVER_ID_REQUIRED'-or$ready.acceptance.aesthetic_gate-or$ready.execution_envelope.sha256-cne(Get-FileHash (Join-Path $root $ready.execution_envelope.entry)).Hash){throw 'DUAL_DRAFT_BINDING'}
if($PreflightOnly){@{status='PASS_PRIVATE_OFFLINE_COMPOSITION__SHARED_ADMISSION_SEPARATE';operations=6;cad_calls=0;COM_calls=0;window_calls=0}|ConvertTo-Json -Compress;return}
Assert-CadDualReadyV1 $scope $root $ready.program.scope_sha256 $ready.program.manifest_sha256
if(Test-Path (Join-Path $v.run 'controller_receipt.json')){throw 'DUAL_CONTROLLER_REPLAY'}
Import-Module (Join-Path $root 'scripts/common/CadOperationGuard.psm1') -Force
$null=[Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot '../command_uia_inspection_v1/bin/CadCommandOwnHelperJobV2.dll'))
if(-not('CadSingleBackgroundV1.Native'-as[type])){Add-Type -Path (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reports/cad_multi_window_interface_research/single_background_input_v3/BackgroundNative.cs')}
$exe=$(if($env:CAD_POWERSHELL){[IO.Path]::GetFullPath($env:CAD_POWERSHELL)}else{Join-Path $env:ProgramFiles 'PowerShell/7/pwsh.exe'});$python=$(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
$rows=[Collections.Generic.List[object]]::new();$pairs=[Collections.Generic.List[object]]::new();$cleanupErrors=[Collections.Generic.List[string]]::new();$samples=[Collections.Generic.List[object]]::new();$clock=[Diagnostics.Stopwatch]::StartNew();$guard=$null;$detail=$null;$protection='UNVERIFIED';$stop=$false
function PumpDual {
 if($clock.Elapsed.TotalSeconds-ge120){throw 'DUAL_OVERALL_DEADLINE'}
 $samples.Add(@{elapsed_ms=$clock.Elapsed.TotalMilliseconds;A=(Get-CadExactBFocusSampleV4 $scope.owners[0].window_handle);B=(Get-CadExactBFocusSampleV4 $scope.owners[1].window_handle)})
 foreach($r in $rows){if(-not$r.disposed){try{$r.job.Pump();if($r.job.OutputLimit){$r.failure='OUTPUT_LIMIT'};if(-not$r.job.RootExited-and$r.clock.Elapsed.TotalSeconds-ge15){$r.failure='HELPER_HARD_DEADLINE'};if($r.failure-and-not$r.stop_attempted){$r.stop_attempted=$true;$r.job.StopOwnJob()}}catch{$r.failure='HELPER_PUMP_OR_STOP:'+ $_.Exception.Message}}}
}
function CleanupDualRow($Row) {
 if($Row.disposed){return};$errors=[Collections.Generic.List[string]]::new()
 try{
  if(-not($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof)){$Row.job.StopOwnJob();$drain=[Diagnostics.Stopwatch]::StartNew();while($drain.Elapsed.TotalSeconds-lt3){$Row.job.Pump();if($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof){break};Start-Sleep -Milliseconds 20}}
  if(-not($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof)){$errors.Add('UNSETTLED_AFTER_3S')}
 }catch{$errors.Add($_.Exception.Message)}finally{
  try{$Row.helper=@{pid=$Row.job.ProcessId;root_exited=$Row.job.RootExited;exit_code=$(if($Row.job.RootExited){$Row.job.ExitCode}else{$null});active=$Row.job.ActiveProcesses;stdout_eof=$Row.job.StdoutEof;stderr_eof=$Row.job.StderrEof;peak_bytes=$Row.job.PeakJobBytes;own_job_stop=$Row.job.OwnJobStopAttempted}}catch{$errors.Add('EVIDENCE:'+ $_.Exception.Message)}
  try{$Row.job.Dispose()}catch{$errors.Add('DISPOSE:'+ $_.Exception.Message)};$Row.disposed=$true
 }
 if($errors.Count){$message=$Row.operation.id+':'+($errors-join';');$cleanupErrors.Add($message);throw $message}
}
function ReadDualReceipt($Row){$p=Join-Path $v.run ('worker_'+$Row.operation.id+'.json');if(-not(Test-Path $p)){return @{state='MISSING';data=$null}};try{@{state='FILE_PRESENT';data=(Get-Content $p -Raw|ConvertFrom-Json -DateKind String)}}catch{@{state='UNREADABLE';data=$null}}}
function SettleDualRow($Row) {
 while(-not($Row.job.RootExited-and$Row.job.ActiveProcesses-eq0-and$Row.job.StdoutEof-and$Row.job.StderrEof)){PumpDual;if($Row.failure){throw $Row.failure};if($Row.clock.Elapsed.TotalSeconds-ge15){throw 'DUAL_HELPER_UNSETTLED_AT_DEADLINE'};Start-Sleep -Milliseconds 20}
 if($Row.failure-or$Row.job.ExitCode-ne0){throw ('DUAL_HELPER_FAILED:'+ $Row.failure)}
 $receipt=Wait-CadWorkerReceiptV1 -Path (Join-Path $v.run ('worker_'+$Row.operation.id+'.json')) -TimeoutMilliseconds 1000 -PollMilliseconds 25;$d=$receipt.data
 if($d.status-cne'PASS'-or$d.run_id-cne$scope.run_id-or$d.scope_sha256-cne$ready.program.scope_sha256-or$d.operation_id-cne$Row.operation.id-or$d.nonce-cne$Row.operation.nonce-or$d.post_call_count-ne1-or-not$d.send_call_returned){throw 'DUAL_RECEIPT_IDENTITY_OR_STATE'}
 $n=Read-CadDualNativeV1 $scope $Row.operation;if($null-eq$n){throw 'DUAL_PARENT_NATIVE_UNPROVEN'};if($Row.operation.stage-ceq'GENERATE'){$body=Read-CadDualNativeV1 $scope $Row.operation -GeneratorBody;if($null-eq$body){throw 'DUAL_PARENT_EXACT_BODY_UNPROVEN'};$n|Add-Member NoteProperty generator_body $body};$Row.validated_receipt=$d;$Row.native=$n;$d
}
function PrepareDualDataReceipt($Op) {
 $files=@(Get-ChildItem (Join-Path $Op.data_run 'reports') -File|Where-Object Extension -In @('.tsv','.lsp','.txt')|ForEach-Object{@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash}})
 $p=Join-Path $v.run ('data_receipt_'+$Op.id+'.json');Write-CadBatchJsonAtomicV2 $p $files;@{path=$p;sha256=(Get-FileHash $p).Hash}
}
try{
 $guard=Enter-CadOperationGuard -ProjectRoot $root -OperationId $scope.run_id -AllowExistingAcad -TimeoutMilliseconds 0
 foreach($plan in @(Get-CadDualBusinessPlanV1)){
  if($stop){$pairs.Add(@{pair=$plan.pair;stage=$plan.stage;status='SKIPPED_DEPENDENCY_OR_UNKNOWN__NO_SEND'});continue}
  $pairClock=[Diagnostics.Stopwatch]::StartNew();$active=[Collections.Generic.List[object]]::new();$ledger=$null;$overlap=$null;$outerOverlap=$null;$artifact=$null;$pairError=$null;$data=@{}
  try{
   foreach($o in $scope.owners){$popup=Read-DimOwnedPopupSnapshotV3 -Root $root -Owner $o;if($popup.popups.Count){throw 'DUAL_MODAL_BEFORE_BIND_NO_SEND'}}
   foreach($op in @($v.operations|Where-Object pair -EQ $plan.pair)){
    $data[$op.id]=PrepareDualDataReceipt $op
    $argsForWorker=@('-ScopePath',$sp,'-ScopeSha256',$ready.program.scope_sha256,'-ManifestPath',$mp,'-ManifestSha256',$ready.program.manifest_sha256,'-OperationId',$op.id,'-LeaseControllerPid',[string]$PID,'-LeaseControllerStartUtc',(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'))
    $job=[CadCommandUiaV2.OwnHelperJob]::Start($exe,(Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/command_worker_v1.ps1'),$argsForWorker,$PSScriptRoot)
    $row=[pscustomobject]@{operation=$op;job=$job;clock=[Diagnostics.Stopwatch]::StartNew();disposed=$false;stop_attempted=$false;failure=$null;helper=$null;validated_receipt=$null;native=$null};$rows.Add($row);$active.Add($row)
   }
   foreach($row in $active){$p=Join-Path $v.run ('ready_'+$row.operation.id+'.json');while($null-eq($b=Read-CadBatchControlV2 $p @('operation_id','nonce','worker_pid','status','run_id','scope_sha256','manifest_sha256'))){PumpDual;if($row.job.RootExited-or$row.clock.Elapsed.TotalSeconds-ge10){throw 'DUAL_READY_TIMEOUT'};Start-Sleep -Milliseconds 20};if($b.operation_id-cne$row.operation.id-or$b.nonce-cne$row.operation.nonce-or$b.worker_pid-ne$row.job.ProcessId-or$b.status-cne'BOUND_WAITING_RELEASE'-or$b.run_id-cne$scope.run_id-or$b.scope_sha256-cne$ready.program.scope_sha256-or$b.manifest_sha256-cne$ready.program.manifest_sha256){throw 'DUAL_READY_BARRIER_IDENTITY'}}
   Assert-CadDualReadyV1 $scope $root $ready.program.scope_sha256 $ready.program.manifest_sha256
   # Two complete READY files precede both releases. No executable or geometry
   # is compiled between these two same-directory atomic release publications.
   foreach($row in $active){$d=$data[$row.operation.id];Write-CadBatchJsonAtomicV2 (Join-Path $v.run ('release_'+$row.operation.id+'.json')) @{operation_id=$row.operation.id;nonce=$row.operation.nonce;data_receipt_path=$d.path;data_receipt_sha256=$d.sha256}}
  }catch{$pairError=$_.Exception.ToString()}finally{
   $ledger=Invoke-CadNativeReadIndependentSettlementV9 -Rows $active.ToArray() -Settle {param($r)SettleDualRow $r} -Cleanup {param($r)CleanupDualRow $r} -ReadReceipt {param($r)ReadDualReceipt $r} -ExpectedRunId $scope.run_id -ExpectedScopeSha256 $ready.program.scope_sha256
  }
  if(-not$pairError-and$active.Count-eq2-and$ledger.status-ceq'PASS_ALL_ISSUED_WORKERS_SETTLED'){
   $a=@($active|Where-Object {$_.operation.owner-ceq'A'})[0];$b=@($active|Where-Object {$_.operation.owner-ceq'B'})[0]
   $outerOverlap=Get-CadBatchPairOverlapV1 $a.native $b.native
   $overlap=if($plan.stage-ceq'GENERATE'){Get-CadBatchPairOverlapV1 $a.native.generator_body $b.native.generator_body}else{$outerOverlap}
   try{& $python -B (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..'))) 'reference/project-orchestration/reports/cad_multi_window_interface_research/dual_business_concurrency_v1/process_dual.py') $plan.process --run $v.run;if($LASTEXITCODE-ne0){throw ('DUAL_ARTIFACT_FAILED:'+ $plan.process)};$artifact='PASS_BOTH_INDEPENDENT_EFFECT_AUDITS'}catch{$pairError=$_.Exception.ToString()}
  }elseif(-not$pairError){$pairError='ISSUED_WORKERS_NOT_BOTH_SETTLED'}
  $pairs.Add(@{pair=$plan.pair;stage=$plan.stage;status=$(if($pairError){'PARTIAL_OR_UNKNOWN'}else{'PASS_BOTH_FUNCTIONS'});error=$pairError;settlement=$ledger;overlap=$overlap;outer_stage_overlap=$outerOverlap;generation_concurrency_interval_scope=$(if($plan.stage-ceq'GENERATE'){'EXACT_MATURE_GENERATOR_BODY_ONLY'}else{'NOT_A_GENERATION_CONCURRENCY_GATE'});effect_audit=$artifact;helpers=@($active|ForEach-Object{$_.helper});workers=@($active|ForEach-Object{@{operation_id=$_.operation.id;owner=$_.operation.owner;validated_receipt=$_.validated_receipt;validated_native=$_.native}});elapsed_ms=$pairClock.ElapsedMilliseconds})
  if($pairError){$stop=$true}
 }
}catch{$detail=$_.Exception.ToString()}finally{
 foreach($row in $rows){try{CleanupDualRow $row}catch{}}
 try{Assert-CadDualProtectedFilesV1 $scope $v.identity $root;$protection='UNCHANGED_ON_DISK'}catch{$protection=$_.Exception.Message}
 $complete=(@($pairs|Where-Object status -CEQ 'PASS_BOTH_FUNCTIONS').Count-eq3-and-not$detail-and-not$cleanupErrors.Count-and$protection-ceq'UNCHANGED_ON_DISK')
 $generation=@($pairs|Where-Object stage -CEQ GENERATE);$concurrent=($complete-and$generation.Count-eq1-and$generation[0].overlap.positive_native_intersection)
 $status=if($concurrent){'PASS_REAL_DUAL_BUSINESS_WITH_NATIVE_GENERATE_INTERSECTION'}elseif($complete){'PASS_BOTH_GENERATIONS__NO_NATIVE_GENERATE_INTERSECTION'}else{'PARTIAL_OR_UNKNOWN_DUAL_BUSINESS__NO_RETRY'}
 $report=@{schema_version=1;profile_id=$scope.profile_id;run_id=$scope.run_id;status=$status;detail=$detail;pairs=$pairs.ToArray();both_generation_function_complete=$complete;real_dual_business_concurrency_proven=$concurrent;generation_pair_native_intersection=$(if($generation.Count-eq1-and$generation[0].ContainsKey('overlap')){$generation[0].overlap}else{$null});protected_disk_files=$protection;cleanup_errors=$cleanupErrors.ToArray();focus_policy='OBSERVE_ONLY';foreground_samples=$samples.ToArray();continuous_background_proven=$false;serial_registration_input_evidence=$scope.owner_evidence.path;business_activation_count=0;business_input_count=0;business_input_scope='THIS_CONTROLLER_AND_ITS_WORKERS_ONLY';aesthetic_acceptance=$false;two_chat_control_proven=$false;retry_count=0;cad_close_count=0;cad_kill_count=0;elapsed_ms=$clock.ElapsedMilliseconds;cad_left_open=$true}
 Write-CadBatchJsonAtomicV2 (Join-Path $v.run 'controller_receipt.json') $report
 if($guard){Exit-CadOperationGuard -Guard $guard}
}
if($cleanupErrors.Count){throw 'DUAL_HELPER_CLEANUP_UNKNOWN'}
[pscustomobject]$report
