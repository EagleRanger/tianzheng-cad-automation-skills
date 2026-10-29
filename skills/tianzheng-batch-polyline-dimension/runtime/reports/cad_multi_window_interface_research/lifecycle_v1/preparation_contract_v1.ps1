function Read-CadPreparationScopeV1([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String
}
function Assert-CadPreparationPathV1([string]$Path,[string]$Root) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'PREPARATION_PATH_NOT_ABSOLUTE' }
    $full=[IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'PREPARATION_PATH_OUTSIDE_PROJECT' }
    $cursor=$full
    while ($cursor -and $cursor.Length -ge $Root.Length) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'PREPARATION_REPARSE_PATH' }
        if ($cursor -ieq $Root) { break }; $cursor=Split-Path -Parent $cursor
    }
    $full
}
function Assert-CadPreparationScopeV1($Scope,[string]$Root,[string]$RunDirectory) {
    if ($Scope.schema_version -ne 1 -or $Scope.profile_id -cne 'CAD-MULTI-OWNER-TEST-PREPARATION-V1') { throw 'PREPARATION_SCOPE_IDENTITY' }
    if ($Scope.run_id -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$') { throw 'PREPARATION_RUN_ID' }
    $run=Assert-CadPreparationPathV1 $RunDirectory $Root
    if ($run -ine (Join-Path (Join-Path $Root 'runs') $Scope.run_id)) { throw 'PREPARATION_RUN_MISMATCH' }
    $admission=Get-CadPublicSourceAdmission -Root $Root;$fixed=Join-Path $Root ([string]$admission.path)
    $source=Assert-CadPreparationPathV1 ([string]$Scope.source_path) $Root
    if ($source -ine [IO.Path]::GetFullPath($fixed) -or $Scope.source_sha256 -cne [string]$admission.sha256) { throw 'PREPARATION_SOURCE_NOT_ADMITTED' }
    if ($Scope.request_second_instance -isnot [bool] -or -not $Scope.request_second_instance) { throw 'PREPARATION_SECOND_REQUEST_REQUIRED' }
    if ($Scope.allow_canonical_a_owned_failure_cleanup -isnot [bool] -or -not $Scope.allow_canonical_a_owned_failure_cleanup) { throw 'PREPARATION_CANONICAL_A_RECOVERY_SCOPE_REQUIRED' }
    foreach($pair in @(@('startup_timeout_seconds',180),@('second_instance_timeout_seconds',90))) {
        $v=$Scope.($pair[0]);$minimum=if($pair[0]-ceq'startup_timeout_seconds'){30}else{5}; if (($v -isnot [int] -and $v -isnot [long]) -or $v -lt $minimum -or $v -gt $pair[1]) { throw 'PREPARATION_TIMEOUT_INVALID' }
    }
    $copies=@()
    foreach($field in @('working_copy_a','working_copy_b')) {
        $copy=Assert-CadPreparationPathV1 ([string]$Scope.$field) $Root
        if ((Split-Path -Parent $copy) -ine (Join-Path $run 'drawings') -or [IO.Path]::GetExtension($copy) -ine '.dwg' -or (Test-Path -LiteralPath $copy)) { throw 'PREPARATION_COPY_UNSAFE_OR_EXISTS' }
        $copies+=$copy
    }
    if ($copies[0] -ieq $copies[1]) { throw 'PREPARATION_COPY_ALIAS' }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $Scope.source_sha256) { throw 'PREPARATION_SOURCE_HASH' }
    [pscustomobject]@{run_id=$Scope.run_id;run=$run;source=$source;source_sha256=$Scope.source_sha256;copies=$copies;startup_timeout_seconds=$Scope.startup_timeout_seconds;second_instance_timeout_seconds=$Scope.second_instance_timeout_seconds}
}
function Assert-CadPreparationDependenciesV1([string]$Directory,[string]$Root) {
    $manifest=Get-Content -LiteralPath (Join-Path $Directory 'candidate_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
    if ($manifest.id -cne 'CAD-MULTI-OWNER-TEST-PREPARATION-V1') { throw 'PREPARATION_MANIFEST_IDENTITY' }
    foreach($file in $manifest.files) {
        $path=Assert-CadPreparationPathV1 (Join-Path $Root $file.path) $Root
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256) { throw ('PREPARATION_DEPENDENCY_CHANGED:'+ $file.path) }
    }
}
function Get-CadPreparationTransitionV1($Owners,$FirstOwner,[string]$SecondLeaf) {
    $rows=@($Owners);$ids=@($rows.process_id)
    if (@($ids|Select-Object -Unique).Count -ne $ids.Count) { return 'AMBIGUOUS_DUPLICATE_PID' }
    $first=@($rows|Where-Object { $_.process_id -eq $FirstOwner.process_id })
    if ($first.Count -ne 1) { return 'FIRST_OWNER_GONE' }
    if ($first[0].process_start_time_utc -cne $FirstOwner.process_start_time_utc -or $first[0].process_image_path -ine $FirstOwner.process_image_path -or $first[0].window_handle -ne $FirstOwner.window_handle) { return 'FIRST_OWNER_CHANGED' }
    if ([string]$first[0].window_title -like ('*'+$SecondLeaf+'*')) { return 'SECOND_OPEN_REUSED_FIRST_PROCESS' }
    $new=@($rows|Where-Object { $_.process_id -ne $FirstOwner.process_id })
    if ($new.Count -gt 1) { return 'AMBIGUOUS_NEW_PROCESSES' }
    if ($new.Count -eq 0) { return 'WAIT_SECOND' }
    if ($new[0].process_image_path -ine $FirstOwner.process_image_path) { return 'UNEXPECTED_PROCESS_IMAGE' }
    if ($new[0].window_handle -gt 0 -and $new[0].responding -and [string]$new[0].window_title -like ('*'+$SecondLeaf+'*')) { return 'SECOND_WINDOW_PREPARED_IDENTITY_UNVERIFIED' }
    'WAIT_SECOND'
}
function Write-CadPreparationJsonV1([string]$Path,$Value) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 30))
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try {$stream.Write($bytes,0,$bytes.Length)} finally {$stream.Dispose()}
}
function Assert-CadPreparationLeaseV1([string]$Root,[string]$RunId,[int]$ControllerProcessId,[string]$ControllerStartUtc) {
    $controller=Get-Process -Id $ControllerProcessId
    if($controller.StartTime.ToUniversalTime().ToString('o') -cne $ControllerStartUtc){throw 'PREPARATION_CONTROLLER_IDENTITY'}
    $lease=Get-Content -LiteralPath (Join-Path $Root '.cad-operation-owner.json') -Raw|ConvertFrom-Json
    if($lease.process_id-ne$ControllerProcessId-or$lease.operation_id-cne$RunId){throw 'PREPARATION_WORKER_LEASE'}
    $mutex=[Threading.Mutex]::OpenExisting('Local\Codex.TianzhengCad.Exclusive.v1');$acquired=$false
    try {try{$acquired=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException] {$acquired=$true};if($acquired){throw 'PREPARATION_LEASE_NOT_HELD'}} finally {if($acquired){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
