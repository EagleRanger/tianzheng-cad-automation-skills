param(
  [Parameter(Mandatory=$true)][string]$DocumentName,[Parameter(Mandatory=$true)][string]$CommandPath,[Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][long]$WindowHandle,
  [Parameter(Mandatory=$true)][string]$OwnerStatePath,[Parameter(Mandatory=$true)][string]$ProgressPath,[Parameter(Mandatory=$true)][string]$ObservationDirectory,
  [int]$DocumentBindTimeoutSeconds=12,[int]$StartAckTimeoutSeconds=12,[int]$StallEvidenceSeconds=15,[int]$CommandCompletionTimeoutSeconds=120,[int]$SnapshotIntervalMilliseconds=2000,[int]$WorkerReceiptSettleTimeoutMilliseconds=5000,[int]$RpcSettlementTimeoutMilliseconds=5000
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'cad_command_signal_parser_v3.ps1')
. (Join-Path $PSScriptRoot 'cad_worker_receipt_settlement_v1.ps1')
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$ownerPath=[IO.Path]::GetFullPath($OwnerStatePath);$commandFile=[IO.Path]::GetFullPath($CommandPath);$progress=[IO.Path]::GetFullPath($ProgressPath);$observation=[IO.Path]::GetFullPath($ObservationDirectory)
foreach($path in @($ownerPath,$commandFile,$progress,$observation)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'POST_OBSERVED_V12_PATH_OUTSIDE_PROJECT'}}
if(-not(Test-Path -LiteralPath $commandFile -PathType Leaf)){throw 'POST_OBSERVED_V12_COMMAND_MISSING'}
if(Test-Path -LiteralPath $progress){throw 'POST_OBSERVED_V12_PROGRESS_PREEXISTS'}
[IO.Directory]::CreateDirectory($observation)|Out-Null
$timeline=Join-Path $observation 'timeline.jsonl';$receiptPath=Join-Path $observation 'observation_receipt.json';$workerReceipt=Join-Path $observation 'worker_receipt.json';$workerProgress=Join-Path $observation 'worker_progress.jsonl'
foreach($path in @($timeline,$receiptPath,$workerReceipt,$workerProgress)){if(Test-Path -LiteralPath $path){throw 'POST_OBSERVED_V12_EVIDENCE_PREEXISTS'}}
function Write-PostObservedV12Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
function Append-PostObservedV12($Value){[IO.File]::AppendAllText($timeline,($Value|ConvertTo-Json -Compress -Depth 20)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}
function Read-PostObservedV12SignalResult{Read-CadCommandSignalResultV3 -Path $progress}
function Capture-PostObservedV12([string]$Reason){try{& (Join-Path $PSScriptRoot 'capture_cad_commandline_passive_v1.ps1') -ProcessId $ProcessId -WindowHandle $WindowHandle -OutputDirectory (Join-Path $observation 'capture') -Label $Reason}catch{[pscustomobject]@{status='CAPTURE_FAILED';detail=$_.Exception.Message;passive=$true}}}
function Stop-PostObservedV12Worker([Diagnostics.Process]$Worker){if($null-ne$Worker-and-not$Worker.HasExited){Stop-Process -Id $Worker.Id -Force -ErrorAction Stop;$Worker.WaitForExit(5000)|Out-Null;return $true};$false}
function Read-PostObservedV12Worker{$read=Read-CadWorkerReceiptV1 -Path $workerReceipt;if([string]$read.state-in@('VALID','TERMINAL_INVALID','INVALID')){$read.data}else{$null}}
$owner=Get-Content -LiteralPath $ownerPath -Raw -Encoding UTF8|ConvertFrom-Json;$owned=Get-Process -Id $ProcessId -ErrorAction Stop
if([string]$owner.status-cne'ready'-or[int]$owner.process_id-ne$ProcessId-or[long]$owner.main_window_handle-ne$WindowHandle-or-not$owned.Responding-or[long]$owned.MainWindowHandle-ne$WindowHandle){throw 'POST_OBSERVED_V12_OWNER_MISMATCH'}
$workerScript=Join-Path $PSScriptRoot 'cad_rot_send_command_worker_v10.ps1';$pwsh=Join-Path $PSHOME 'pwsh.exe'
if(-not(Test-Path -LiteralPath $workerScript -PathType Leaf)-or-not(Test-Path -LiteralPath $pwsh -PathType Leaf)){throw 'POST_OBSERVED_V12_DEPENDENCY_MISSING'}
$start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$pwsh;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
foreach($argument in @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$workerScript,'-DocumentName',$DocumentName,'-CommandPath',$commandFile,'-ProcessId',[string]$ProcessId,'-WindowHandle',[string]$WindowHandle,'-WorkerReceiptPath',$workerReceipt,'-WorkerProgressPath',$workerProgress,'-DocumentBindTimeoutSeconds',[string]$DocumentBindTimeoutSeconds,'-CadSideProgressPath',$progress,'-CadAckTimeoutSeconds',[string]$StartAckTimeoutSeconds,'-RpcSettlementTimeoutMilliseconds',[string]$RpcSettlementTimeoutMilliseconds)){[void]$start.ArgumentList.Add($argument)}
$started=[DateTime]::UtcNow;$worker=[Diagnostics.Process]::Start($start);if($null-eq$worker){throw 'POST_OBSERVED_V12_WORKER_START_FAILED'};$lastSnapshot=$started.AddMilliseconds(-$SnapshotIntervalMilliseconds);$lastProgressWrite=$null;$ackAt=$null;$completeAt=$null;$stallCapture=$null;$noAckCapture=$null;$stallCaptured=$false;$workerTerminated=$false;$receiptSettlement=$null;$deadline=$started.AddSeconds($CommandCompletionTimeoutSeconds)
try{
  do{
    Start-Sleep -Milliseconds 250;$now=[DateTime]::UtcNow;$owned.Refresh();$worker.Refresh();$signalResult=Read-PostObservedV12SignalResult;$signals=[string[]]@($signalResult.lines)
    if(Test-CadCommandSignalSetV3 -Lines $signals -Token 'CAD_COMMAND_ACK'){if($null-eq$ackAt){$ackAt=$now}}
    if(Test-CadCommandSignalSetV3 -Lines $signals -Token 'CAD_COMMAND_COMPLETE'){if($null-eq$completeAt){$completeAt=$now}}
    if(Test-Path -LiteralPath $progress -PathType Leaf){$write=(Get-Item -LiteralPath $progress).LastWriteTimeUtc;if($null-eq$lastProgressWrite-or$write-gt$lastProgressWrite){$lastProgressWrite=$write}}
    if(($now-$lastSnapshot).TotalMilliseconds-ge$SnapshotIntervalMilliseconds){Append-PostObservedV12 ([ordered]@{at=$now.ToString('o');elapsed_ms=[int]($now-$started).TotalMilliseconds;cad_process_responding=[bool]$owned.Responding;worker_pid=$worker.Id;worker_exited=[bool]$worker.HasExited;ack_received=$null-ne$ackAt;complete_received=$null-ne$completeAt;signal_count=$signals.Count;progress_age_ms=if($null-ne$lastProgressWrite){[int]($now-$lastProgressWrite).TotalMilliseconds}else{$null}});$lastSnapshot=$now}
    if($worker.HasExited){$workerData=Read-PostObservedV12Worker;if($null-eq$workerData-or[string]$workerData.status-cne'PASS'){$noAckCapture=Capture-PostObservedV12 'POST_WORKER_FAILED';throw 'CAD_POST_OBSERVED_V12_WORKER_FAILED'}}
    if($null-eq$ackAt-and($now-$started).TotalSeconds-ge$StartAckTimeoutSeconds){$noAckCapture=Capture-PostObservedV12 'POSTED_NO_CAD_ACK';$workerTerminated=Stop-PostObservedV12Worker $worker;throw 'CAD_POST_OBSERVED_V12_COMMAND_NO_ACK'}
    if($null-ne$ackAt-and-not$stallCaptured-and$null-ne$lastProgressWrite-and($now-$lastProgressWrite).TotalSeconds-ge$StallEvidenceSeconds){$stallCapture=Capture-PostObservedV12 'CAD_PROGRESS_STALLED';$stallCaptured=$true}
    if($null-ne$ackAt-and$null-ne$completeAt){break}
  }while([DateTime]::UtcNow-lt$deadline)
  if($null-eq$ackAt-or$null-eq$completeAt){throw 'CAD_POST_OBSERVED_V12_COMMAND_COMPLETION_TIMEOUT'}
  $receiptSettlement=Wait-CadWorkerReceiptV1 -Path $workerReceipt -TimeoutMilliseconds $WorkerReceiptSettleTimeoutMilliseconds -PollMilliseconds 25
  if([string]$receiptSettlement.status-cne'PASS'){throw ('CAD_POST_OBSERVED_V12_WORKER_RECEIPT_SETTLEMENT_'+[string]$receiptSettlement.status+'_'+[string]$receiptSettlement.state)}
  $workerData=$receiptSettlement.data
  $result=[ordered]@{schema_version=1;status='PASS';transport='ACTIVEX_SENDCOMMAND_EXACT_DOCUMENT_NONFOCUS_ISOLATED';binding_method='ENUMERATE_ALL_THEN_EXACT_HWND_THEN_EXACT_DOCUMENT';foreground_required=$false;document=$DocumentName;worker_pid=$worker.Id;worker_status=[string]$workerData.status;worker_receipt_settlement_status=[string]$receiptSettlement.status;worker_receipt_settlement_state=[string]$receiptSettlement.state;worker_receipt_settlement_attempts=[int]$receiptSettlement.attempts;worker_receipt_settlement_elapsed_ms=[int]$receiptSettlement.elapsed_ms;post_call_count=1;send_call_accepted=[bool]$workerData.send_call_accepted;com_call_attempt_count=[int]$workerData.com_call_attempt_count;rpc_rejection_count=[int]$workerData.rpc_rejection_count;retry_count=0;ack_received=$true;complete_received=$true;ack_elapsed_ms=[int]($ackAt-$started).TotalMilliseconds;complete_elapsed_ms=[int]($completeAt-$started).TotalMilliseconds;stall_evidence_captured=$stallCaptured;stall_capture=$stallCapture;no_ack_capture=$noAckCapture;timeline=$timeline;worker_progress=$workerProgress;elapsed_ms=[int]([DateTime]::UtcNow-$started).TotalMilliseconds}
  Write-PostObservedV12Json $receiptPath $result;[pscustomobject]$result
}catch{
  if($null-ne$worker-and-not$worker.HasExited){$workerTerminated=Stop-PostObservedV12Worker $worker}
  $workerData=Read-PostObservedV12Worker
  $result=[ordered]@{schema_version=1;status='FAILED';detail=$_.Exception.Message;worker_detail=if($workerData){[string]$workerData.detail}else{$null};transport='ACTIVEX_SENDCOMMAND_EXACT_DOCUMENT_NONFOCUS_ISOLATED';foreground_required=$false;document=$DocumentName;worker_pid=$worker.Id;worker_terminated=$workerTerminated;post_call_count=if($workerData){[int]$workerData.post_call_count}else{0};send_call_accepted=if($workerData){[bool]$workerData.send_call_accepted}else{$false};com_call_attempt_count=if($workerData){[int]$workerData.com_call_attempt_count}else{0};rpc_rejection_count=if($workerData){[int]$workerData.rpc_rejection_count}else{0};retry_count=0;ack_received=$null-ne$ackAt;complete_received=$null-ne$completeAt;stall_evidence_captured=$stallCaptured;stall_capture=$stallCapture;no_ack_capture=$noAckCapture;timeline=$timeline;worker_progress=$workerProgress;elapsed_ms=[int]([DateTime]::UtcNow-$started).TotalMilliseconds}
  Write-PostObservedV12Json $receiptPath $result;throw
}
