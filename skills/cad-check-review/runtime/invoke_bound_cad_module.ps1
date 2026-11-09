param([Parameter(Mandatory=$true)][string]$Manifest,[switch]$ProbeOnly,[string]$ProbeReceipt)
$ErrorActionPreference='Stop'
$env:PSModulePath=$env:WINDIR+'\System32\WindowsPowerShell\v1.0\Modules'
$m=ConvertFrom-Json ([IO.File]::ReadAllText($Manifest))
$destination=if($ProbeOnly){$ProbeReceipt}else{$m.dispatch_receipt}
if(-not $destination -or (Test-Path -LiteralPath $destination)){throw 'OUTPUT_EXISTS_OR_UNSPECIFIED'}
$app=$null;$doc=$null;$proc=$null;$oldFileDia=$null;$oldCmdDia=$null;$stage='start';$sendAttempted=$false;$idleChecks=0
function Read-Rpc([scriptblock]$Action) {
 for($attempt=0;$attempt -lt 5;$attempt++){
  try{return (& $Action)}catch{
   if($_.Exception.ToString() -notmatch '80010001|8001010A' -or $attempt -eq 4){throw}
   Start-Sleep -Milliseconds 700
  }
 }
}
try {
 Add-Type @'
using System;using System.Runtime.InteropServices;
public static class BoundCadDispatchIdentity {
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);
}
'@
 $proc=[Diagnostics.Process]::GetProcessById([int]$m.host.pid)
 if($proc.StartTime.ToUniversalTime().ToFileTimeUtc() -ne [int64]$m.host.created){throw 'HOST_REUSED'}
 if(-not [String]::Equals($proc.MainModule.FileName,$m.host.image,[StringComparison]::OrdinalIgnoreCase)){throw 'HOST_IMAGE_CHANGED'}
 if((Get-FileHash -LiteralPath $m.dll -Algorithm SHA256).Hash.ToLowerInvariant() -ne $m.dll_sha256){throw 'MODULE_HASH_CHANGED'}
 $entry=if($m.entry){[string]$m.entry}else{'HLCADBOUNDAPPLYV1'}
 if($entry -notmatch '^HLCAD[A-Z0-9]+$'){throw 'INVALID_FIXED_ENTRY'}
 $moduleMetadata=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($m.dll))
 if(-not [Regex]::IsMatch($moduleMetadata,'(?<![A-Z0-9])'+[Regex]::Escape($entry)+'(?![A-Z0-9])')){throw ('MODULE_ENTRY_NOT_FOUND:'+ $entry)}
 $stage='bind_com';$app=Read-Rpc {[Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application.24')}
 $stage='host_window';$hwnd=Read-Rpc {$app.HWND}
 [uint32]$windowPid=0
 [void][BoundCadDispatchIdentity]::GetWindowThreadProcessId([IntPtr][int64]$hwnd,[ref]$windowPid)
 if($windowPid -ne [uint32]$m.host.pid){throw 'COM_HOST_MISMATCH'}
 $stage='active_document';$doc=Read-Rpc {$app.ActiveDocument};$fullName=Read-Rpc {$doc.FullName}
 if(-not [String]::Equals([IO.Path]::GetFullPath($fullName),[IO.Path]::GetFullPath($m.document),[StringComparison]::OrdinalIgnoreCase)){throw 'DOCUMENT_CHANGED'}
 $stage='command_idle';$active=Read-Rpc {$doc.GetVariable('CMDACTIVE')};$names=Read-Rpc {$doc.GetVariable('CMDNAMES')}
 if([int]$active -ne 0){throw ('COMMAND_ACTIVE:'+ $names)}
 $s=ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $m.session_dir 'session_status.json')))
 if($s.status -ne 'READY_SAME_DOCUMENT' -or $s.last_sha256 -ne $m.source_sha256 -or $s.last_saved -ne $m.saved_path){throw 'CHECKPOINT_CHANGED'}
 if($ProbeOnly){
  $r=@{status='BOUND_HOST_READ_ONLY';pid=$m.host.pid;created=$m.host.created;document=$fullName;cmdactive=[int]$active;cmdnames=[string]$names;dbmod=(Read-Rpc {$doc.GetVariable('DBMOD')});layout=(Read-Rpc {$doc.GetVariable('CTAB')});source_sha256=$m.source_sha256;request=$m.request;at=[DateTime]::UtcNow.ToString('o')}
 }else{
 foreach($path in @($m.dll,$Manifest)){if($path -match '[\r\n"]'){throw 'UNSAFE_COMMAND_PATH'}}
 $stage='read_dialog_flags';$oldFileDia=Read-Rpc {$doc.GetVariable('FILEDIA')};$oldCmdDia=Read-Rpc {$doc.GetVariable('CMDDIA')}
 $stage='set_dialog_flags';if([int]$oldFileDia -ne 0){Read-Rpc {$doc.SetVariable('FILEDIA',0)}};if([int]$oldCmdDia -ne 0){Read-Rpc {$doc.SetVariable('CMDDIA',0)}}
 $commandInput=if($m.command_config){[string]$m.command_config}else{$Manifest}
 if($commandInput -match '[\r\n"]'){throw 'UNSAFE_CONFIG_PATH'}
 $command='_NETLOAD'+"`n"+'"'+$m.dll+'"'+"`n"+$entry+"`n"+'"'+$commandInput+'"'+"`n"
 if($entry -eq 'HLCADNATIVEVIEWTESTCLOSEV1'){$command=$entry+"`n"}
 # CMDACTIVE=0 alone does not establish that the COM server is ready.
 # Wait only before the first send; never retry an uncertain SendCommand.
 $stage='application_idle';$ready=$false
 for($idleChecks=1;$idleChecks -le 20;$idleChecks++){
  $cadState=Read-Rpc {$app.GetAcadState()}
  try{$ready=[bool](Read-Rpc {$cadState.IsQuiescent})}finally{if([Runtime.InteropServices.Marshal]::IsComObject($cadState)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($cadState)}}
  if($ready){break};Start-Sleep -Milliseconds 150
 }
 if(-not $ready){throw 'APPLICATION_BUSY_BEFORE_SEND'}
 $stage='send_command';$sendAttempted=$true
 # Native SendCommand may already have taken effect: never retry it on an RPC error.
 $doc.SendCommand($command)
 $r=@{status='COMMAND_DISPATCHED_NOT_ACCEPTANCE';pid=$m.host.pid;request=$m.request;idle_checks=$idleChecks;dispatched_at=[DateTime]::UtcNow.ToString('o')}
 }
}catch{$r=@{status='BOUND_DISPATCH_FAILED';error=$_.Exception.Message;stage=$stage;send_attempted=$sendAttempted;idle_checks=$idleChecks;line=$_.InvocationInfo.ScriptLineNumber;request=$m.request}}
finally{
 if($null -ne $doc){
  if($null -ne $oldFileDia -and [int]$oldFileDia -ne 0){try{Read-Rpc {$doc.SetVariable('FILEDIA',$oldFileDia)}}catch{}}
  if($null -ne $oldCmdDia -and [int]$oldCmdDia -ne 0){try{Read-Rpc {$doc.SetVariable('CMDDIA',$oldCmdDia)}}catch{}}
 }
 foreach($obj in @($doc,$app)){if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($obj)}}
 if($null -ne $proc){$proc.Dispose()}
}
[IO.File]::WriteAllText($destination,(ConvertTo-Json -InputObject $r -Depth 5),(New-Object Text.UTF8Encoding($false)))
if($r.status -eq 'BOUND_DISPATCH_FAILED'){exit 2}
