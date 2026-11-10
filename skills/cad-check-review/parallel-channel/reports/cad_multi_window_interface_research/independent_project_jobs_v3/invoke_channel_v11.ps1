param([Parameter(Mandatory)][string]$ReadyHandoffPath,[switch]$PreflightOnly)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'channel_contract_v11.ps1')
$root=Resolve-FixedV3Root (Join-Path $PSScriptRoot '../../..')
$ready=Get-Content -LiteralPath $ReadyHandoffPath -Raw|ConvertFrom-Json -DateKind String
$scope=Read-FixedV3Json (Resolve-FixedV3Path $root $ready.program.scope) $ready.program.scope_sha256
$manifest=Read-FixedV3Json (Resolve-FixedV3Path $root $ready.program.manifest) $ready.program.manifest_sha256
$v=Assert-CadIndependentProjectScopeV3 $scope $root;Assert-CadIndependentProjectManifestV3 $manifest $root
if($ready.issuer.thread_id-cne'RECEIVER_SOURCE_A'-or$ready.target.thread_id-cne'RECEIVER_SOURCE_B'-or$ready.governance.workflow_id-cne$scope.profile_id-or$ready.action.controller_call_max-ne1-or$ready.action.foreground_input_max-ne0){throw 'FIXED_V3_DRAFT_AUTHORITY'}
if($PreflightOnly){[pscustomobject]@{status='PASS_PRIVATE_OFFLINE_COMPOSITION';native_task_max=2;cad_calls=0;COM_calls=0;window_calls=0};return}
Assert-FixedV3Ready $scope $ready $root
if(Test-Path -LiteralPath (Join-Path $v.run 'controller_receipt.json')){throw 'FIXED_V3_CONTROLLER_REPLAY'}
Import-Module (Join-Path $root 'scripts/common/CadOperationGuard.psm1') -Force
. (Join-Path $PSScriptRoot 'launch_channel_v11.ps1')
$null=[Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'bin/OwnStartupJobV4.dll'))
$caps=$scope.capability_bounds;$clock=[Diagnostics.Stopwatch]::StartNew();$hosts=@{};$caseRows=[Collections.Generic.List[object]]::new();$nativeRows=[Collections.Generic.List[object]]::new()
$preexisting=@(Get-Process acad -ErrorAction SilentlyContinue|ForEach-Object{@{pid=$_.Id;created=$_.StartTime.ToFileTimeUtc();image=$_.Path;working_set_bytes=$_.WorkingSet64}})
$guard=$null;$errorDetail=$null;$sourceProtection='UNVERIFIED';$cleanup=[Collections.Generic.List[string]]::new();$globalStop=$null;$globalStopClock=$null
# Unused legacy Python assignment removed: this native V11 path has no Python dependency.
function Assert-FixedV3Original {
 if((Get-FileHash -LiteralPath (Join-Path $root $scope.source.path)).Hash-cne$scope.source.sha256){throw 'FIXED_V3_ORIGINAL_CHANGED'}
 if($clock.Elapsed.TotalSeconds-ge$caps.overall_timeout_seconds){throw 'FIXED_V3_OVERALL_DEADLINE'}
}
function Set-FixedV3Global([string]$Reason){if(-not$script:globalStop){$script:globalStop=$Reason;$script:globalStopClock=[Diagnostics.Stopwatch]::StartNew()}}
function Assert-FixedV3Host($HostState){
 $p=Get-Process -Id $HostState.receipt.pid -ErrorAction Stop
 if($p.StartTime.ToFileTimeUtc()-ne$HostState.receipt.created-or$p.Path-ine$HostState.receipt.image-or@($preexisting|Where-Object pid -EQ $p.Id).Count){throw 'FIXED_V3_ACTUAL_HOST_IDENTITY'}
}
function Get-FixedV3Host([string]$Id){
 if($hosts.ContainsKey($Id)){Assert-FixedV3Host $hosts[$Id];return $hosts[$Id]}
 Assert-FixedV3Original
 $free=(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory*1024
 if($free-lt3GB){throw 'FIXED_V3_MEMORY_PREPARATION_BLOCKED'}
 if($hosts.Count-ge$caps.cad_launch_max_count){throw 'FIXED_V3_HOST_LIMIT'}
 $plan=@($scope.hosts|Where-Object id -CEQ $Id)[0];$boot=Read-FixedV3Json $plan.boot_path $plan.boot_sha256
 if([DateTimeOffset]::UtcNow.AddSeconds(30)-ge[DateTimeOffset]::Parse($boot.expires_utc)){throw 'FIXED_V3_BOOT_EXPIRED_BEFORE_LAUNCH'}
 $state=Start-FixedV3Host $boot $plan.boot_path $plan.boot_sha256 $root;$hosts[$Id]=$state
 $tip=$null
 try{
 $pwsh=(Get-Command pwsh -ErrorAction Stop).Source
 $tip=[CadResearchStartupJobV4.OwnHelperJob]::Start($pwsh,(Join-Path $PSScriptRoot 'startup_tip_worker_v4.ps1'),@('-Desktop',$state.receipt.desktop,'-TargetPid',[string]$state.receipt.pid,'-TargetCreated',[string]$state.receipt.created,'-Session',$state.session),$root,$state.receipt.desktop)
 while($state.clock.Elapsed.TotalSeconds-lt[Math]::Min(30,$caps.owner_preparation_timeout_seconds)){
  $tip.Pump();if($tip.OutputLimit){throw 'STARTUP_HELPER_OUTPUT_LIMIT'}
  Assert-FixedV3Original;Assert-FixedV3Host $state
  $failed=@(Get-ChildItem -LiteralPath $state.session -Filter 'boot_failed_*.json' -File);if($failed.Count){throw ('FIXED_V3_NATIVE_BOOT_FAILED:'+ [IO.File]::ReadAllText($failed[0].FullName))}
  $p=Join-Path $state.session 'native_ready.json'
  if(Test-Path -LiteralPath $p){
   $n=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -DateKind String
   if($n.status-cne'READY_NATIVE_QUEUE'-or$n.run_id-cne$scope.run_id-or$n.owner-cne$Id-or$n.pid-ne$state.receipt.pid-or$n.created-ne$state.receipt.created-or$n.image-ine$state.receipt.image-or$n.hwnd-eq0-or$n.module_sha256-cne$boot.module_sha256){throw 'FIXED_V3_NATIVE_READY_IDENTITY'}
   $state.native=$n;return $state
  }
  if($tip.RootExited){throw ('STARTUP_HELPER_EXITED_BEFORE_READY:'+ $tip.Stderr)}
  Start-Sleep -Milliseconds 100
 }
 throw 'FIXED_V3_BACKGROUND_BOOT_NOT_READY__NO_FOREGROUND_FALLBACK'
 }finally{
  if($tip){
   $drain=[Diagnostics.Stopwatch]::StartNew();while($drain.Elapsed.TotalSeconds-lt3){$tip.Pump();if($tip.RootExited-and$tip.ActiveProcesses-eq0-and$tip.StdoutEof-and$tip.StderrEof){break};Start-Sleep -Milliseconds 20}
   if(-not$tip.RootExited-or$tip.ActiveProcesses-ne0){$tip.StopOwnJob();$drain.Restart();while($drain.Elapsed.TotalSeconds-lt3){$tip.Pump();if($tip.RootExited-and$tip.ActiveProcesses-eq0-and$tip.StdoutEof-and$tip.StderrEof){break};Start-Sleep -Milliseconds 20}}
   Write-FixedV3NewJson (Join-Path $state.session 'startup_helper_settlement.json') @{pid=$tip.ProcessId;root_exited=$tip.RootExited;active=$tip.ActiveProcesses;stdout_eof=$tip.StdoutEof;stderr_eof=$tip.StderrEof;job_bound_before_resume=$tip.JobBoundBeforeResume;stop_attempted=$tip.OwnJobStopAttempted;stderr=$tip.Stderr}
   $settled=$tip.RootExited-and$tip.ActiveProcesses-eq0-and$tip.StdoutEof-and$tip.StderrEof;$tip.Dispose();if(-not$settled){throw 'STARTUP_HELPER_UNSETTLED'}
  }
 }
}
$results=@{};$routing=$null;$slots=@()
try{
 $guard=Enter-CadOperationGuard -ProjectRoot $root -OperationId $scope.run_id -AllowExistingAcad -TimeoutMilliseconds 0
 foreach($id in @('A','B')){$null=Get-FixedV3Host $id}
 $slots=@(foreach($id in @('A','B')){
  $h=$hosts[$id];foreach($plan in @($scope.requests|Where-Object owner -CEQ $id)){
  @{owner=$id;sequence=$plan.sequence;source_thread_id=$plan.source_thread_id;request_id=$plan.request_id;nonce=$plan.nonce;operation='KNOWN_WRITE_BATCH';pid=$h.native.pid;created=$h.native.created;hwnd=$h.native.hwnd;document=$h.boot.cases[0].work;session=$h.session;boot_expires_utc=$h.boot.expires_utc;task_path=(Join-Path $h.session ('tasks/'+$plan.request_id+'.task.json'));queue_path=(Join-Path $h.session 'request.json')}
 }} )
 $routing=@{status='READY_EXACT_SOURCE_SLOTS';run_id=$scope.run_id;slots=$slots;source_thread_id=$scope.source_thread_id;utc=[DateTimeOffset]::UtcNow.ToString('o')}
 Write-FixedV3NewJson (Join-Path $v.run 'channel_ready.json') $routing
 $wait=[Diagnostics.Stopwatch]::StartNew()
 while($wait.Elapsed.TotalSeconds-lt150){
  if(-not(Test-Path (Join-Path $v.run 'first_release.json'))){
   $readyIntents=@(foreach($id in @('A','B')){Join-Path $hosts[$id].session 'origin_intent_1.json'})
   if(@($readyIntents|Where-Object{Test-Path $_}).Count-eq2){
    $valid=$true;foreach($slot in @($slots|Where-Object sequence -EQ 1)){$i=Get-Content -LiteralPath (Join-Path $slot.session 'origin_intent_1.json') -Raw|ConvertFrom-Json;if($i.owner-cne$slot.owner-or$i.request_id-cne$slot.request_id-or$i.nonce-cne$slot.nonce-or$i.source_thread_id-cne$slot.source_thread_id){$valid=$false}}
    if(-not$valid){throw 'CHANNEL_FIRST_RELEASE_INTENT_MISMATCH'}
    Write-FixedV3NewJson (Join-Path $v.run 'first_release.json') @{run_id=$scope.run_id;status='BOTH_REAL_ORIGIN_INTENTS_BOUND';utc=[DateTimeOffset]::UtcNow.ToString('o')}
   }
  }
  Assert-FixedV3Original
  foreach($slot in $slots){
   $key=$slot.owner+':'+$slot.sequence;if($results.ContainsKey($key)){continue}
   $h=$hosts[$slot.owner]
   try{
    Assert-FixedV3Host $h
    $p=Join-Path $slot.session ($slot.request_id+'.result.json')
    if(Test-Path -LiteralPath $p){
     $r=Get-Content -LiteralPath $p -Raw|ConvertFrom-Json -DateKind String
     if($r.run_id-cne$scope.run_id-or$r.request_id-cne$slot.request_id-or$r.nonce-cne$slot.nonce-or$r.source_thread_id-cne$slot.source_thread_id-or$r.owner-cne$slot.owner-or$r.pid-ne$slot.pid-or$r.created-ne$slot.created-or$r.hwnd-ne$slot.hwnd-or$r.document-ine$slot.document-or$r.operation-cne$slot.operation-or$r.sequence-ne$slot.sequence-or$r.task_sha256-cne(Get-FileHash $slot.task_path).Hash){throw 'CHANNEL_RESULT_ROUTE_MISMATCH'}
     if($r.status-ceq'COMPLETED'){
      if($r.write_entity_count-ne1024-or$r.after-$r.before-ne1024-or@($r.write_batches).Count-ne64-or$r.checkpoint.path-ine$h.boot.cases[0].checkpoint-or$r.checkpoint.entity_count-ne1024-or$r.checkpoint.readback-cne'INDEPENDENT_DATABASE_EXACT_1024_NATIVE_LINES_AND_HANDLES'-or(Get-FileHash -LiteralPath $r.checkpoint.path).Hash-cne$r.checkpoint.sha256){throw 'CHANNEL_SAVED_NATIVE_WRITE_MISMATCH'}
     }
     $returnDir=Join-Path $v.run ('returns/'+$slot.source_thread_id);$null=New-Item -ItemType Directory -Path $returnDir -Force
     $returned=Join-Path $returnDir ($slot.request_id+'.json');[IO.File]::Copy($p,$returned,$false)
     $results[$key]=@{owner=$slot.owner;sequence=$slot.sequence;status=$r.status;native_result=$r;result_path=$returned;result_sha256=(Get-FileHash $returned).Hash;origin_submission=(Join-Path $slot.session ($slot.request_id+'.origin_submission.json'))}
    }elseif(@(Get-ChildItem -LiteralPath $h.session -Filter 'intake_failed_*.json' -File).Count){throw 'CHANNEL_INTAKE_FAILURE_NO_RESEND'}
   }catch{$results[$key]=@{owner=$slot.owner;sequence=$slot.sequence;status='UNKNOWN_NO_RESEND';error=$_.Exception.ToString()}}
  }
  $receivedCount=@($slots|Where-Object {Test-Path -LiteralPath (Join-Path $_.session ($_.request_id+'.origin_received.json'))}).Count
  if($results.Count-eq2-and($receivedCount-eq2-or@($results.Values|Where-Object status -CNE 'COMPLETED').Count)){break}
  Start-Sleep -Milliseconds 40
 }
 foreach($slot in $slots){$key=$slot.owner+':'+$slot.sequence;if(-not$results.ContainsKey($key)){$results[$key]=@{owner=$slot.owner;sequence=$slot.sequence;status='UNKNOWN_NO_RESEND';error='CHANNEL_BOUNDED_RESULT_TIMEOUT'}}}
}catch{$errorDetail=$_.Exception.ToString()}
finally{
 $sourceProtection=if((Get-FileHash -LiteralPath (Join-Path $root $scope.source.path)).Hash-ceq$scope.source.sha256){'UNCHANGED_ON_DISK'}else{'CHANGED'}
 $receivedCount=0
 foreach($slot in $slots){$proofPath=Join-Path $slot.session ($slot.request_id+'.origin_received.json');if(Test-Path -LiteralPath $proofPath){$proof=Get-Content $proofPath -Raw|ConvertFrom-Json;$key=$slot.owner+':'+$slot.sequence;if($results.ContainsKey($key)-and$proof.status-ceq'PASS'-and$proof.owner-ceq$slot.owner-and$proof.source_thread_id-ceq$slot.source_thread_id-and$proof.request_id-ceq$slot.request_id-and$proof.result_sha256-ceq$results[$key].result_sha256){$receivedCount++}}}
 $complete=($results.Count-eq2-and$receivedCount-eq2-and@($results.Values|Where-Object status -CNE 'COMPLETED').Count-eq0-and-not$errorDetail-and$sourceProtection-ceq'UNCHANGED_ON_DISK')
 $overlap=0;$writeSpanOverlap=0;$writeBatchOverlap=0
 $aRows=@($results.Values|Where-Object {$_.owner-ceq'A'-and$_.ContainsKey('native_result')-and$_.status-ceq'COMPLETED'})
 $bRows=@($results.Values|Where-Object {$_.owner-ceq'B'-and$_.ContainsKey('native_result')-and$_.status-ceq'COMPLETED'})
 foreach($a in $aRows){foreach($b in $bRows){$x=@([DateTimeOffset]::Parse($a.native_result.handler_started_utc),[DateTimeOffset]::Parse($b.native_result.handler_started_utc))|Sort-Object|Select-Object -Last 1;$y=@([DateTimeOffset]::Parse($a.native_result.utc),[DateTimeOffset]::Parse($b.native_result.utc))|Sort-Object|Select-Object -First 1;$overlap+=[Math]::Max(0,($y-$x).TotalMilliseconds)}}
 foreach($a in $aRows){foreach($b in $bRows){
  $begin=@([DateTimeOffset]::Parse($a.native_result.write_first_utc),[DateTimeOffset]::Parse($b.native_result.write_first_utc))|Sort-Object|Select-Object -Last 1
  $end=@([DateTimeOffset]::Parse($a.native_result.write_last_utc),[DateTimeOffset]::Parse($b.native_result.write_last_utc))|Sort-Object|Select-Object -First 1
  $writeSpanOverlap+=[Math]::Max(0,($end-$begin).TotalMilliseconds)
  foreach($wa in $a.native_result.write_batches){foreach($wb in $b.native_result.write_batches){$bs=@([DateTimeOffset]::Parse($wa.start_utc),[DateTimeOffset]::Parse($wb.start_utc))|Sort-Object|Select-Object -Last 1;$be=@([DateTimeOffset]::Parse($wa.end_utc),[DateTimeOffset]::Parse($wb.end_utc))|Sort-Object|Select-Object -First 1;$writeBatchOverlap+=[Math]::Max(0,($be-$bs).TotalMilliseconds)}}
 }}
 $environment=@(foreach($h in $hosts.Values){$alive=Get-Process -Id $h.receipt.pid -ErrorAction SilentlyContinue;if(-not$alive){& (Join-Path $root 'scripts/restore_cad_manual_dialogs_after_exit.ps1') -ClosedProcessId $h.receipt.pid -ExecutablePath $h.receipt.image}else{@{status='PENDING_EXECUTOR_PROTECTED_CLOSE';pid=$h.receipt.pid;created=$h.receipt.created}}})
 $report=@{schema_version=3;profile_id=$scope.profile_id;validation_mode='PARALLEL_NATIVE_WRITE_ONLY';run_id=$scope.run_id;status=$(if($complete-and$writeBatchOverlap-gt0){'PASS_REAL_TWO_ORIGIN_PARALLEL_NATIVE_WRITE'}else{'PARTIAL_OR_UNKNOWN_PARALLEL_NATIVE_WRITE'});results=@($results.Values);detail=$errorDetail;native_task_count=@($results.Values|Where-Object {$_.ContainsKey('native_result')}).Count;external_com_business_send_count=0;foreground_input_count=0;retry_count=0;source_protection=$sourceProtection;handler_UTC_overlap_ms=$overlap;write_span_UTC_overlap_ms=$writeSpanOverlap;write_batch_UTC_overlap_ms=$writeBatchOverlap;per_owner_request_limit=1;actual_origin_receipts_required=2;actual_origin_receipts_observed=$receivedCount;two_origin_request_actions_required=$true;resource_closeout_required=$true;environment_restoration=$environment;protected_existing_hosts=$preexisting;elapsed_ms=$clock.ElapsedMilliseconds;research_hosts=@(foreach($h in $hosts.Values){@{launch=$h.receipt;native_ready=$h.native}})}
 Write-FixedV3NewJson (Join-Path $v.run 'controller_receipt.json') $report
 foreach($h in $hosts.Values){[void][FixedV3PrivateLaunch]::CloseDesktop($h.desktop_handle)}
 if($guard){Exit-CadOperationGuard -Guard $guard}
}
[pscustomobject]$report


