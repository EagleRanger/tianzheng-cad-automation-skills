# BINDING TEMPLATE ONLY: replace PID/created/HWND=0, DBMOD=-1, root/run/desktop/hash from current evidence; never infer or replay.
$ErrorActionPreference='Stop'
$root='C:\RECEIVER\CAD_ROOT'
$dir=Join-Path $root 'runs/RECEIVER_RUN_ID/resource_closeout/A'
$out=Join-Path $dir 'identity_read_v4_corrected.json'
if(Test-Path -LiteralPath $out){throw 'READ_EVIDENCE_ALREADY_EXISTS'}
Import-Module (Join-Path $root 'scripts/common/CadOperationGuard.psm1') -Force
$null=[Reflection.Assembly]::LoadFrom((Join-Path $root 'reports/cad_multi_window_interface_research/independent_project_jobs_v3/bin/OwnStartupJobV4.dll'))
$guard=$null;$job=$null;$report=[ordered]@{status='UNKNOWN';error=$null;worker=$null;helper=$null;cad_closed=$false}
try {
 $guard=Enter-CadOperationGuard -ProjectRoot $root -OperationId 'resource_closeout_RECEIVER_OWNER_identity_v4' -AllowExistingAcad -TimeoutMilliseconds 0
 $job=[CadResearchStartupJobV4.OwnHelperJob]::Start((Get-Command pwsh -ErrorAction Stop).Source,(Join-Path $dir 'startup_tip_worker_v4.ps1'),@(),$root,'RECEIVER_EXACT_PRIVATE_DESKTOP')
 $sw=[Diagnostics.Stopwatch]::StartNew()
 while($sw.Elapsed.TotalSeconds -lt 20){$job.Pump();if($job.OutputLimit){throw 'HELPER_OUTPUT_LIMIT'};if($job.RootExited -and $job.ActiveProcesses -eq 0 -and $job.StdoutEof -and $job.StderrEof){break};Start-Sleep -Milliseconds 30}
 if(-not $job.RootExited -or $job.ActiveProcesses -ne 0 -or -not $job.StdoutEof -or -not $job.StderrEof){$job.StopOwnJob();throw 'HELPER_TIMEOUT_ONLY_HELPER_STOPPED'}
 $report.helper=@{pid=$job.ProcessId;exit_code=$job.ExitCode;active=$job.ActiveProcesses;bound=$job.JobBoundBeforeResume;stderr=$job.Stderr;elapsed_ms=$sw.ElapsedMilliseconds}
 if($job.ExitCode -ne 0){throw 'HELPER_FAILED'}
 $report.worker=$job.Stdout|ConvertFrom-Json
 $report.status=[string]$report.worker.status
} catch {$report.error=$_.Exception.ToString()} finally {
 if($job){$job.Dispose()};if($guard){Exit-CadOperationGuard -Guard $guard}
 [IO.File]::WriteAllText($out,($report|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
}
$report|ConvertTo-Json -Depth 20 -Compress
