param([Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][ValidateSet('A','B')][string]$Owner,[Parameter(Mandatory)][string]$SourceThreadId,[Parameter(Mandatory)][ValidateRange(1,1)][int]$Sequence)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'channel_contract_v11.ps1');$root=Resolve-FixedV3Root (Join-Path $PSScriptRoot '../../..');$run=Resolve-FixedV3Path $root $RunDirectory
$ready=Get-Content -LiteralPath (Join-Path $run 'execution_handoff.json') -Raw|ConvertFrom-Json
$current=Get-Content -LiteralPath (Join-Path $root 'config/current_execution_handoff.json') -Raw|ConvertFrom-Json
$claim=Get-Content -LiteralPath (Join-Path $run 'execution_controller_claim.json') -Raw|ConvertFrom-Json
if($ready.status-cne'READY'-or$current.run_id-cne$ready.run_id-or$current.immutable_handoff_sha256-cne(Get-FileHash (Join-Path $run 'execution_handoff.json')).Hash-or-not$claim.controller_attempt_reserved-or$claim.run_id-cne$ready.run_id-or(Test-Path (Join-Path $run 'execution_return.json'))){throw 'CHANNEL_SUBMISSION_NO_ACTIVE_EXECUTOR_CLAIM'}
$routing=Get-Content -LiteralPath (Join-Path $run 'channel_ready.json') -Raw|ConvertFrom-Json -DateKind String
$slot=@($routing.slots|Where-Object {$_.owner-ceq$Owner-and$_.sequence-eq$Sequence})[0]
$expectedSource=if($Owner-ceq'A'){'RECEIVER_SOURCE_A'}else{'RECEIVER_SOURCE_B'}
if($SourceThreadId-cne$expectedSource-or$slot.source_thread_id-cne$SourceThreadId-or$routing.run_id-cne$ready.run_id){throw 'CHANNEL_SUBMISSION_WRONG_ORIGIN'}
$originUtc=[DateTimeOffset]::UtcNow.ToString('o')
if($Sequence-eq1){
 $intent=@{owner=$Owner;sequence=1;request_id=$slot.request_id;nonce=$slot.nonce;source_thread_id=$SourceThreadId;origin_action_utc=$originUtc}
 Write-FixedV3NewJson (Join-Path $slot.session 'origin_intent_1.json') $intent
 $release=Join-Path $run 'first_release.json';$clock=[Diagnostics.Stopwatch]::StartNew()
 while(-not(Test-Path $release)-and$clock.Elapsed.TotalSeconds-lt50){Start-Sleep -Milliseconds 30}
 if(-not(Test-Path $release)){throw 'CHANNEL_FIRST_RELEASE_TIMEOUT_NO_SEND'}
 $rel=Get-Content $release -Raw|ConvertFrom-Json
 if($rel.run_id-cne$ready.run_id-or$rel.status-cne'BOTH_REAL_ORIGIN_INTENTS_BOUND'){throw 'CHANNEL_FIRST_RELEASE_MISMATCH'}
}
$p=Get-Process -Id $slot.pid -ErrorAction Stop
if($p.StartTime.ToFileTimeUtc()-ne$slot.created-or$p.Path-ine[IO.Path]::GetFullPath('C:/Program Files/Autodesk/AutoCAD 2021/acad.exe')){throw 'CHANNEL_SUBMISSION_OWNER_CHANGED'}
$deadline=[DateTimeOffset]::UtcNow.AddSeconds(45);$bootDeadline=[DateTimeOffset]::Parse($slot.boot_expires_utc);if($deadline-gt$bootDeadline){$deadline=$bootDeadline}
$task=@{schema_version=10;request_id=$slot.request_id;nonce=$slot.nonce;source_thread_id=$SourceThreadId;run_id=$ready.run_id;owner=$Owner;sequence=$Sequence;operation=$slot.operation;pid=$slot.pid;created=$slot.created;hwnd=$slot.hwnd;document=$slot.document;expires_utc=$deadline.ToString('o')}
Write-FixedV3NewJson $slot.task_path $task
$hash=(Get-FileHash $slot.task_path).Hash;$submission=@{request_id=$slot.request_id;nonce=$slot.nonce;source_thread_id=$SourceThreadId;owner=$Owner;origin_action_utc=$originUtc;submitted_utc=[DateTimeOffset]::UtcNow.ToString('o');sequence=$Sequence;first_release_used=($Sequence-eq1);task_sha256=$hash}
Write-FixedV3NewJson (Join-Path $slot.session ($slot.request_id+'.origin_submission.json')) $submission
Write-FixedV3NewJson $slot.queue_path @{path=$slot.task_path;sha256=$hash}
[pscustomobject]$submission


