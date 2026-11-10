param([Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][ValidateSet('A','B')][string]$Owner,[Parameter(Mandatory)][string]$SourceThreadId,[Parameter(Mandatory)][ValidateRange(1,1)][int]$Sequence)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'channel_contract_v11.ps1');$root=Resolve-FixedV3Root (Join-Path $PSScriptRoot '../../..');$run=Resolve-FixedV3Path $root $RunDirectory
$routing=Get-Content (Join-Path $run 'channel_ready.json') -Raw|ConvertFrom-Json -DateKind String
$slot=@($routing.slots|Where-Object {$_.owner-ceq$Owner-and$_.sequence-eq$Sequence})[0]
if($null-eq$slot-or$slot.source_thread_id-cne$SourceThreadId){throw 'CHANNEL_RECEIVE_WRONG_SOURCE'}
$path=Join-Path $run ('returns/'+$SourceThreadId+'/'+$slot.request_id+'.json');$watch=[Diagnostics.Stopwatch]::StartNew()
while(-not(Test-Path $path)-and$watch.Elapsed.TotalSeconds-lt55){Start-Sleep -Milliseconds 50}
if(-not(Test-Path $path)){throw 'CHANNEL_RECEIVE_RESULT_TIMEOUT'}
$r=Get-Content $path -Raw|ConvertFrom-Json -DateKind String;$hash=(Get-FileHash $path).Hash
$task=Get-Content $slot.task_path -Raw|ConvertFrom-Json -DateKind String
if($r.run_id-cne$routing.run_id-or$r.owner-cne$Owner-or$r.source_thread_id-cne$SourceThreadId-or$r.request_id-cne$slot.request_id-or$r.nonce-cne$slot.nonce-or$r.sequence-ne$Sequence-or$r.task_sha256-cne(Get-FileHash $slot.task_path).Hash-or$r.pid-ne$slot.pid-or$r.created-ne$slot.created-or$r.hwnd-ne$slot.hwnd-or$r.document-ine$slot.document-or$task.source_thread_id-cne$SourceThreadId){throw 'CHANNEL_RECEIVE_EXACT_ROUTE'}
$checkpoint=$r.checkpoint
$checkpointPath=if($checkpoint){[string]$checkpoint.path}else{''};$checkpointHash=if($checkpoint){[string]$checkpoint.sha256}else{''}
$checkpointPass=($checkpoint-and$checkpoint.readback-ceq'INDEPENDENT_DATABASE_EXACT_1024_NATIVE_LINES_AND_HANDLES'-and$checkpoint.entity_count-eq1024-and(Test-Path -LiteralPath $checkpointPath)-and(Get-FileHash -LiteralPath $checkpointPath).Hash-ceq$checkpointHash)
$receipt=@{status=$(if($r.status-ceq'COMPLETED'-and$r.write_entity_count-eq1024-and$r.after-$r.before-eq1024-and@($r.write_batches).Count-eq64-and$checkpointPass){'PASS'}else{'HANDLER_FAILED'});owner=$Owner;source_thread_id=$SourceThreadId;sequence=$Sequence;request_id=$r.request_id;nonce=$r.nonce;result_sha256=$hash;result_path=$path;checkpoint_path=$checkpointPath;checkpoint_sha256=$checkpointHash;handler_status=$r.status;handler_elapsed_ms=$r.elapsed_handler_ms;received_utc=[DateTimeOffset]::UtcNow.ToString('o')}
Write-FixedV3NewJson (Join-Path $slot.session ($slot.request_id+'.origin_received.json')) $receipt
[pscustomobject]$receipt
if($receipt.status-cne'PASS'){throw 'CHANNEL_HANDLER_FAILED_STOP_THIS_SOURCE'}

