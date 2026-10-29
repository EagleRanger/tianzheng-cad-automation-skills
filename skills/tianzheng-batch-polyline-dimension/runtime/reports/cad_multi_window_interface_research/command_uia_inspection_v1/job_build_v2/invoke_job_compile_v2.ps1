param(
    [Parameter(Mandatory)][ValidateSet('compile')][string]$Mode,
    [Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$SourceSha256,
    [Parameter(Mandatory)][ValidatePattern('^[A-F0-9]{64}$')][string]$PythonSha256
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
function GetBoundarySubtreeEvidenceV3([string]$ExpectedMode,$Worker,[bool]$RootExited,[bool]$OutputComplete){
    $unknown=[pscustomobject]@{known=$false;state='UNKNOWN'}
    if($null-eq$Worker-or-not$RootExited-or-not$OutputComplete){return $unknown}
    $required=@('mode','status','cleanup_verified','root_handle_exited','job_active','stdout_eof','stderr_eof')
    if(@($required|Where-Object {$null-eq$Worker.PSObject.Properties[$_]}).Count-ne0){return $unknown}
    if($Worker.mode-ceq$ExpectedMode-and$Worker.status-cin@('PASS_COMPILED_NOT_LOADED','FAILED_OR_UNKNOWN')-and$Worker.cleanup_verified-eq$true-and$Worker.root_handle_exited-eq$true-and$Worker.job_active-eq0-and$Worker.stdout_eof-eq$true-and$Worker.stderr_eof-eq$true){return [pscustomobject]@{known=$true;state='WORKER_PROVED_ROOT_EXIT_JOB_EMPTY_AND_BOTH_EOF'}}
    $unknown
}
$pythonExe=$(if($env:CAD_PYTHON){[IO.Path]::GetFullPath($env:CAD_PYTHON)}else{(Get-Command python.exe -CommandType Application -ErrorAction Stop).Source})
$source=Join-Path $PSScriptRoot 'bounded_job_compile_v2.py'
foreach($pair in @(@($pythonExe,$PythonSha256),@($source,$SourceSha256))){
    if((Get-FileHash -LiteralPath $pair[0]).Hash-cne$pair[1]){throw 'BOUNDARY_INPUT_HASH_MISMATCH'}
    $item=Get-Item -LiteralPath $pair[0]
    if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'BOUNDARY_REPARSE_INPUT'}
}
if((Get-Item -LiteralPath $source).Length-gt65536){throw 'BOUNDARY_BOOTSTRAP_SOURCE_TOO_LARGE'}
$caseRoot=Join-Path (Split-Path -Parent $env:CAD_JOB_COMPILE_SPEC_PATH) 'cases'
if(-not(Test-Path -LiteralPath $caseRoot)){$null=New-Item -ItemType Directory -Path $caseRoot}
if((Get-Item -LiteralPath $caseRoot).Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'BOUNDARY_REPARSE_CASE_ROOT'}
$caseDirectory=Join-Path $caseRoot ([Guid]::NewGuid().ToString('N')+'_'+$Mode)
if(Test-Path -LiteralPath $caseDirectory){throw 'BOUNDARY_CASE_ALREADY_EXISTS'}
$null=New-Item -ItemType Directory -Path $caseDirectory
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$pythonExe
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
foreach($argument in @('-I','-S',$source,$Mode,$caseDirectory)){$info.ArgumentList.Add($argument)}
$child=$null;$startUtc=$null;$identity=$null;$bootstrapBound=$false;$watchReason=$null;$caughtError=$null
$outputComplete=$false;$cleanupKnown=$false;$childExited=$false;$processExitCode=$null
$parentKilledRoot=$false
$timer=[Diagnostics.Stopwatch]::StartNew();$stdout=[Text.StringBuilder]::new();$stderr=[Text.StringBuilder]::new()
$stdoutBuffer=[char[]]::new(2048);$stderrBuffer=[char[]]::new(2048);$stdoutTask=$null;$stderrTask=$null
$stdoutDone=$false;$stderrDone=$false;$peakPrivate=0L
try{
try{
    $child=[Diagnostics.Process]::Start($info)
    $null=$child.Handle # Retain the actual created-process handle, not a later PID lookup.
    $startUtc=$child.StartTime.ToUniversalTime()
    # Process.Path can be null immediately after creation; never substitute the
    # requested executable for an observed image. Only refresh this retained
    # created-process object, under the original prebind memory/outer budgets.
    $imageWait=[Diagnostics.Stopwatch]::StartNew();$observedImage=''
    while([string]::IsNullOrWhiteSpace($observedImage)-and$imageWait.ElapsedMilliseconds-lt500){
        $child.Refresh();$observedImage=[string]$child.Path
        if($child.HasExited-and[string]::IsNullOrWhiteSpace($observedImage)){throw 'BOUNDARY_CREATED_IMAGE_UNOBSERVED_EXIT'}
        if(-not$child.HasExited-and$child.PrivateMemorySize64-gt128MB){throw 'BOUNDARY_IMAGE_WAIT_PREBIND_MEMORY'}
        if($timer.Elapsed.TotalSeconds-ge4){throw 'BOUNDARY_IMAGE_WAIT_BOOTSTRAP_DEADLINE'}
        if([string]::IsNullOrWhiteSpace($observedImage)){Start-Sleep -Milliseconds 10}
    }
    if([string]::IsNullOrWhiteSpace($observedImage)){throw 'BOUNDARY_CREATED_IMAGE_UNOBSERVED_NO_FALLBACK'}
    $identity=[ordered]@{process_id=$child.Id;process_start_utc=$startUtc.ToString('o');image=$observedImage;image_wait_ms=$imageWait.ElapsedMilliseconds}
    if(-not[IO.Path]::GetFullPath($observedImage).Equals($pythonExe,[StringComparison]::OrdinalIgnoreCase)){throw 'BOUNDARY_CREATED_IMAGE_MISMATCH'}
    $stdoutTask=$child.StandardOutput.ReadAsync($stdoutBuffer,0,$stdoutBuffer.Length)
    $stderrTask=$child.StandardError.ReadAsync($stderrBuffer,0,$stderrBuffer.Length)
    while($timer.Elapsed.TotalSeconds-lt35){
        foreach($streamName in @('stdout','stderr')){
            $task=if($streamName-ceq'stdout'){$stdoutTask}else{$stderrTask}
            $done=if($streamName-ceq'stdout'){$stdoutDone}else{$stderrDone}
            if(-not$done-and$null-ne$task-and$task.IsCompleted){
                $count=$task.GetAwaiter().GetResult()
                if($count-eq0){if($streamName-ceq'stdout'){$stdoutDone=$true}else{$stderrDone=$true}}
                else{
                    $builder=if($streamName-ceq'stdout'){$stdout}else{$stderr}
                    $buffer=if($streamName-ceq'stdout'){$stdoutBuffer}else{$stderrBuffer}
                    if($builder.Length+$count-gt16384){$watchReason='PARENT_CAPTURE_LIMIT';break}
                    $null=$builder.Append($buffer,0,$count)
                    if($streamName-ceq'stdout'){$stdoutTask=$child.StandardOutput.ReadAsync($stdoutBuffer,0,$stdoutBuffer.Length)}
                    else{$stderrTask=$child.StandardError.ReadAsync($stderrBuffer,0,$stderrBuffer.Length)}
                }
            }
        }
        if($watchReason){break}
        $child.Refresh();$childExited=$child.HasExited
        $stagePath=Join-Path $caseDirectory 'stages.jsonl'
            if(-not$bootstrapBound-and(Test-Path -LiteralPath $stagePath)){
                $stageInfo=Get-Item -LiteralPath $stagePath
                if($stageInfo.Length-gt262144){$watchReason='PARENT_STAGE_SIZE_LIMIT';break}
                if($stageInfo.Length-gt0){
                    $stageStream=[IO.FileStream]::new($stagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                    $stageReader=[IO.StreamReader]::new($stageStream)
                    try{$firstLine=$stageReader.ReadLine()}finally{$stageReader.Dispose()}
                    if($null-ne$firstLine-and$firstLine.Length-le8192){$firstStage=$firstLine|ConvertFrom-Json;$bootstrapBound=$firstStage.stage-ceq'BOOTSTRAP_BOUND'-and$firstStage.pid-eq$child.Id}
                }
            }
        if(-not$childExited){
            $peakPrivate=[Math]::Max($peakPrivate,$child.PrivateMemorySize64)
            # Pre-bind is an observed watchdog, NOT a kernel-at-creation guarantee.
            $memoryLimit=if($bootstrapBound){256MB}else{128MB}
            if($child.PrivateMemorySize64-gt$memoryLimit){$watchReason='PARENT_MEMORY_WATCHDOG';break}
            if(-not$bootstrapBound-and$timer.Elapsed.TotalSeconds-gt4){$watchReason='BOOTSTRAP_DEADLINE';break}
        }
        if($childExited-and$stdoutDone-and$stderrDone){$outputComplete=$true;break}
        Start-Sleep -Milliseconds 50
    }
    if(-not$outputComplete-and-not$watchReason){$watchReason='PARENT_OUTER_DEADLINE'}
}catch{$caughtError=$_.Exception.ToString().Substring(0,[Math]::Min(1500,$_.Exception.ToString().Length))}
finally{
    if($null-ne$child){
        try{
            if(-not$child.HasExited){
                # Only this retained created Python handle. Its non-inherited Job
                # handles close on death; no generic process-tree/PID-name killing.
                $parentKilledRoot=$true
                $child.Kill()
            }
            $cleanupKnown=$child.WaitForExit(2000)
            $childExited=$cleanupKnown-and$child.HasExited
            if($childExited){$processExitCode=$child.ExitCode}
        }catch{$cleanupKnown=$false;if(-not$caughtError){$caughtError=$_.Exception.Message}}
    }
}
$workerResult=$null;$resultPath=Join-Path $caseDirectory 'result.json'
if(Test-Path -LiteralPath $resultPath){
    if((Get-Item -LiteralPath $resultPath).Length-le16384){try{$workerResult=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json}catch{$watchReason='PARENT_RESULT_INVALID_JSON'}}
    else{$watchReason='PARENT_RESULT_LIMIT'}
}
$subtree=GetBoundarySubtreeEvidenceV3 $Mode $workerResult $cleanupKnown $outputComplete
$subtreeKnown=$subtree.known;$subtreeState=$subtree.state
$result=[ordered]@{status='FAILED_OR_UNKNOWN';mode=$Mode;case_directory=$caseDirectory;identity=$identity;
    source_sha256=$SourceSha256;python_sha256=$PythonSha256;bootstrap_bound=$bootstrapBound;
    prebind_memory_guard='OBSERVED_128MIB_WATCHDOG_NOT_ATOMIC_KERNEL_LIMIT';parent_watch_reason=$watchReason;
    parent_error=$caughtError;parent_elapsed_ms=$timer.ElapsedMilliseconds;parent_observed_peak_private_bytes=$peakPrivate;
    retained_root_exited=$childExited;parent_root_cleanup_known=$cleanupKnown;parent_killed_root=$parentKilledRoot;subtree_cleanup_known=$subtreeKnown;subtree_cleanup_state=$subtreeState;output_complete=$outputComplete;
    exit_code=$processExitCode;stdout_chars=$stdout.Length;stderr_chars=$stderr.Length;
    stderr_excerpt=$stderr.ToString().Substring(0,[Math]::Min(1200,$stderr.Length));worker_result=$workerResult;
    cad_calls=0;compiler_calls=$(if($null-ne$workerResult-and$null-ne$workerResult.PSObject.Properties['compiler_calls']){$workerResult.compiler_calls}else{$null});compiler_call_evidence='WORKER_RESULT_OR_UNKNOWN';full_fixture_verified=$false;live_verified=$false}
if($bootstrapBound-and$cleanupKnown-and$subtreeKnown-and$outputComplete-and-not$watchReason-and-not$caughtError-and$processExitCode-eq0-and$null-ne$workerResult-and$workerResult.status-like'PASS_*'){$result.status='PASS_BOUNDARY_COMPILE_ONLY'}
$receiptPath=Join-Path $caseDirectory 'parent_receipt.json'
$receiptBytes=[Text.Encoding]::UTF8.GetBytes(($result|ConvertTo-Json -Depth 8))
$receiptStream=[IO.FileStream]::new($receiptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$receiptStream.Write($receiptBytes,0,$receiptBytes.Length);$receiptStream.Flush($true)}finally{$receiptStream.Dispose()}
[pscustomobject]$result
if($result.status-cne'PASS_BOUNDARY_COMPILE_ONLY'){throw 'BOUNDARY_COMPILATION_NOT_PASS_NO_RETRY'}
}finally{
    # Covers result-read/JSON/receipt-write exceptions as well as launch failures.
    if($null-ne$child){
        try{if(-not$child.HasExited){$child.Kill();$null=$child.WaitForExit(2000)}}catch{}
        finally{
            try{$child.StandardOutput.Dispose()}catch{}
            try{$child.StandardError.Dispose()}catch{}
            $child.Dispose()
        }
    }
}
