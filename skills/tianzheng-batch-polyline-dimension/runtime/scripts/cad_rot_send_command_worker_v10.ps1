param(
  [Parameter(Mandatory=$true)][string]$DocumentName,[Parameter(Mandatory=$true)][string]$CommandPath,
  [Parameter(Mandatory=$true)][int]$ProcessId,[Parameter(Mandatory=$true)][long]$WindowHandle,
  [Parameter(Mandatory=$true)][string]$WorkerReceiptPath,[Parameter(Mandatory=$true)][string]$WorkerProgressPath,
  [Parameter(Mandatory=$true)][string]$CadSideProgressPath,[int]$DocumentBindTimeoutSeconds=12,[int]$CadAckTimeoutSeconds=20,[int]$RpcSettlementTimeoutMilliseconds=5000
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'cad_command_signal_parser_v3.ps1')
. (Join-Path $PSScriptRoot 'cad_com_rejected_call_settlement_v1.ps1')
$root=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$commandFile=[IO.Path]::GetFullPath($CommandPath);$receipt=[IO.Path]::GetFullPath($WorkerReceiptPath);$progress=[IO.Path]::GetFullPath($WorkerProgressPath);$cadProgress=[IO.Path]::GetFullPath($CadSideProgressPath)
foreach($path in @($commandFile,$receipt,$progress,$cadProgress)){if(-not$path.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'SEND_WORKER_V10_PATH_OUTSIDE_PROJECT'}}
if(-not(Test-Path -LiteralPath $commandFile -PathType Leaf)){throw 'SEND_WORKER_V10_COMMAND_MISSING'}
function Write-SendWorkerV10Json([string]$Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))}
function Write-SendWorkerV10Stage([string]$Stage,$Data=$null){$row=[ordered]@{at=(Get-Date).ToString('o');stage=$Stage;worker_pid=$PID};if($null-ne$Data){$row.data=$Data};[IO.File]::AppendAllText($progress,($row|ConvertTo-Json -Compress -Depth 20)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))}
$started=Get-Date;$postEntered=$false;$postAccepted=$false;$comCallAttempts=0;$rpcRejectedCount=0;$sample=0;$lastBinding=$null;$ackReceived=$false
Write-SendWorkerV10Stage 'WORKER_STARTED'
function Invoke-SendWorkerV10ComValue([string]$Label,[scriptblock]$Operation){$settled=Invoke-CadRejectedCallSettlementV1 -Operation $Operation -Label $Label -TimeoutMilliseconds $RpcSettlementTimeoutMilliseconds -PollMilliseconds 100;$script:comCallAttempts+=[int]$settled.attempts;$script:rpcRejectedCount+=[int]$settled.rejected_count;$settled.value}
try{
  $owned=Get-Process -Id $ProcessId -ErrorAction Stop
  if(-not$owned.Responding-or[long]$owned.MainWindowHandle-ne$WindowHandle){throw 'SEND_WORKER_V10_OWNER_MISMATCH'}
  . (Join-Path $PSScriptRoot 'cad_rot_exact_document_binding_v2.ps1')
  Add-Type -TypeDefinition @'
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Runtime.InteropServices.ComTypes;
public static class CadRotNonFocusWorkerBridgeV1 { [DllImport("ole32.dll")] static extern int GetRunningObjectTable(int r,out IRunningObjectTable t);[DllImport("ole32.dll")] static extern int CreateBindCtx(int r,out IBindCtx c);public sealed class Entry{public string Name;public dynamic Instance;}public static IEnumerable<Entry> Enumerate(){IRunningObjectTable t;IBindCtx c;Marshal.ThrowExceptionForHR(GetRunningObjectTable(0,out t));Marshal.ThrowExceptionForHR(CreateBindCtx(0,out c));IEnumMoniker e;t.EnumRunning(out e);var m=new IMoniker[1];while(e.Next(1,m,IntPtr.Zero)==0){string n="";object o=null;try{m[0].GetDisplayName(c,null,out n);}catch{}try{t.GetObject(m[0],out o);}catch{}if(o!=null)yield return new Entry{Name=n,Instance=o};}} }
'@
  $document=$null;$application=$null;$deadline=(Get-Date).AddSeconds($DocumentBindTimeoutSeconds)
  do{$sample++;$entries=@([CadRotNonFocusWorkerBridgeV1]::Enumerate());$lastBinding=Select-CadRotExactDocumentV2 -Entries $entries -WindowHandle $WindowHandle -DocumentName $DocumentName -OwnerMainWindowTitle ([string]$owned.MainWindowTitle);if([string]$lastBinding.status-ceq'PASS'){$document=$lastBinding.document;$application=$lastBinding.application;break};Start-Sleep -Milliseconds 250}while((Get-Date)-lt$deadline)
  if($null-eq$document-or$null-eq$application){throw 'SEND_WORKER_V10_EXACT_DOCUMENT_BIND_TIMEOUT'}
  Write-SendWorkerV10Stage 'EXACT_DOCUMENT_BOUND' ([ordered]@{sample=$sample;enumerated_count=[int]$lastBinding.enumerated_count;exact_hwnd_count=[int]$lastBinding.exact_hwnd_count;observed=@($lastBinding.observed)})
  $isQuiescent=[bool](Invoke-SendWorkerV10ComValue 'GET_QUIESCENT' {$application.GetAcadState().IsQuiescent});$cmdNames=[string](Invoke-SendWorkerV10ComValue 'GET_CMDNAMES' {$document.GetVariable('CMDNAMES')});$cmdActive=[int](Invoke-SendWorkerV10ComValue 'GET_CMDACTIVE' {$document.GetVariable('CMDACTIVE')})
  Write-SendWorkerV10Stage 'PRE_SEND_IDLE_STATE' ([ordered]@{is_quiescent=$isQuiescent;cmdnames=$cmdNames;cmdactive=$cmdActive;foreground_required=$false})
  if(-not$isQuiescent-or-not[string]::IsNullOrWhiteSpace($cmdNames)-or$cmdActive-ne0){throw 'SEND_WORKER_V10_DOCUMENT_NOT_IDLE'}
  $source=[IO.File]::ReadAllText($commandFile,[Text.Encoding]::UTF8);if([string]::IsNullOrWhiteSpace($source)){throw 'SEND_WORKER_V10_COMMAND_EMPTY'};$command=$source.Replace("`r`n","`n").Replace("`r","`n").Replace("`n","`r");if($command.Contains("`n")){throw 'SEND_WORKER_V10_LINE_NORMALIZATION_FAILED'}
  Write-SendWorkerV10Stage 'SEND_CALL_ENTER';$postEntered=$true;Invoke-SendWorkerV10ComValue 'SEND_COMMAND' {$document.SendCommand($command+"`n");$null}|Out-Null;$postAccepted=$true;Write-SendWorkerV10Stage 'SEND_CALL_RETURN'
  $ackDeadline=(Get-Date).AddSeconds($CadAckTimeoutSeconds);do{if(Test-Path -LiteralPath $cadProgress -PathType Leaf){$signalResult=Read-CadCommandSignalResultV3 -Path $cadProgress;$signals=[string[]]@($signalResult.lines);if(Test-CadCommandSignalSetV3 -Lines $signals -Token 'CAD_COMMAND_ACK'){$ackReceived=$true;break}};Start-Sleep -Milliseconds 100}while((Get-Date)-lt$ackDeadline)
  if(-not$ackReceived){throw 'SEND_WORKER_V10_CAD_ACK_TIMEOUT'}
  Write-SendWorkerV10Stage 'CAD_ACK_OBSERVED_BY_WORKER'
  Write-SendWorkerV10Json $receipt ([ordered]@{schema_version=2;status='PASS';worker_pid=$PID;document_bind_samples=$sample;binding_method='EXACT_HWND_THEN_NAME_FULLNAME_COLLECTION_OR_EMPTY_PROXY_OWNER_TITLE';transport='ACTIVEX_SENDCOMMAND_EXACT_DOCUMENT_NONFOCUS_ISOLATED';terminator='CR_ONLY';pre_send_is_quiescent=$isQuiescent;pre_send_cmdnames=$cmdNames;pre_send_cmdactive=$cmdActive;foreground_required=$false;focus_acquired=$false;input_injection_count=0;cad_ack_observed=$ackReceived;post_call_count=1;send_call_attempted=$postEntered;send_call_accepted=$postAccepted;com_call_attempt_count=$comCallAttempts;rpc_rejection_count=$rpcRejectedCount;retry_count=0;command_sha256=(Get-FileHash -LiteralPath $commandFile -Algorithm SHA256).Hash;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds})
}catch{
  Write-SendWorkerV10Stage 'WORKER_FAILED' ([ordered]@{detail=$_.Exception.Message;sample=$sample;post_call_entered=$postEntered;foreground_required=$false;cad_ack_observed=$ackReceived})
  Write-SendWorkerV10Json $receipt ([ordered]@{schema_version=2;status='FAILED';worker_pid=$PID;transport='ACTIVEX_SENDCOMMAND_EXACT_DOCUMENT_NONFOCUS_ISOLATED';post_call_entered=$postEntered;send_call_accepted=$postAccepted;post_call_count=if($postAccepted){1}else{0};com_call_attempt_count=$comCallAttempts;rpc_rejection_count=$rpcRejectedCount;foreground_required=$false;focus_acquired=$false;input_injection_count=0;cad_ack_observed=$ackReceived;retry_count=0;detail=$_.Exception.Message;elapsed_ms=[int]((Get-Date)-$started).TotalMilliseconds})
  exit 1
}
