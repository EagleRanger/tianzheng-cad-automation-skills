Set-StrictMode -Version Latest

function Read-CadWorkerReceiptV1 {
  param([Parameter(Mandatory=$true)][string]$Path)
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){
    return [pscustomobject]@{state='MISSING';data=$null;detail=$null;path=$Path}
  }
  try{
    $raw=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    if([string]::IsNullOrWhiteSpace($raw)){return [pscustomobject]@{state='PARTIAL';data=$null;detail='EMPTY';path=$Path}}
    $data=$raw|ConvertFrom-Json -ErrorAction Stop
    if([string]$data.status-ceq'PASS'-and[int]$data.post_call_count-eq1){return [pscustomobject]@{state='VALID';data=$data;detail=$null;path=$Path}}
    if([string]$data.status-ceq'FAILED'){return [pscustomobject]@{state='TERMINAL_INVALID';data=$data;detail=[string]$data.detail;path=$Path}}
    return [pscustomobject]@{state='INVALID';data=$data;detail='STATUS_OR_CALL_COUNT';path=$Path}
  }catch{
    return [pscustomobject]@{state='PARTIAL';data=$null;detail=$_.Exception.Message;path=$Path}
  }
}

function Wait-CadWorkerReceiptV1 {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [ValidateRange(25,30000)][int]$TimeoutMilliseconds=5000,
    [ValidateRange(10,1000)][int]$PollMilliseconds=25
  )
  $clock=[Diagnostics.Stopwatch]::StartNew();$attempts=0;$last=$null
  do{
    $attempts++;$last=Read-CadWorkerReceiptV1 -Path $Path
    if([string]$last.state-ceq'VALID'){$clock.Stop();return [pscustomobject]@{status='PASS';state='VALID';data=$last.data;attempts=$attempts;elapsed_ms=[int]$clock.ElapsedMilliseconds;path=$Path}}
    if([string]$last.state-in@('TERMINAL_INVALID','INVALID')){$clock.Stop();return [pscustomobject]@{status='FAILED';state=[string]$last.state;data=$last.data;detail=[string]$last.detail;attempts=$attempts;elapsed_ms=[int]$clock.ElapsedMilliseconds;path=$Path}}
    Start-Sleep -Milliseconds $PollMilliseconds
  }while($clock.ElapsedMilliseconds-lt$TimeoutMilliseconds)
  $clock.Stop();[pscustomobject]@{status='TIMEOUT';state=if($last){[string]$last.state}else{'MISSING'};data=$null;detail=if($last){[string]$last.detail}else{$null};attempts=$attempts;elapsed_ms=[int]$clock.ElapsedMilliseconds;path=$Path}
}
