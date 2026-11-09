# The single-drawing receiver test lane. Check does not start CAD.
[CmdletBinding()]
param(
    [ValidateSet('Check','Prepare','Open','Run','Review')][string]$Stage = 'Check',
    [string]$SourceDrawing,
    [string]$RunDirectory,
    [string]$TianzhengShortcutPath,
    [string[]]$SourceHandles,
    [ValidateSet('ROAD','SHORE')][string]$Group = 'ROAD',
    [double]$Offset,
    [switch]$ConfirmIsolatedDesktop,
    [switch]$ConfirmWriteToTestCopy,
    [ValidateRange(20,900)][int]$WaitSeconds = 180
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$runs = Join-Path $root 'runs'
$orchestration = Join-Path $root 'reference/project-orchestration/scripts'
$lifecycle = Join-Path $orchestration 'common/TianzhengLifecycle.psm1'
$utf8 = [Text.UTF8Encoding]::new($false)
function FileHash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function ReadJson($p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json -DateKind String }
function NewFile([string]$p,[string]$content) {
    $stream = [IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes = $utf8.GetBytes($content); $stream.Write($bytes,0,$bytes.Length) }
    finally { $stream.Dispose() }
}
function JsonFile($p,$value) { NewFile $p ($value | ConvertTo-Json -Depth 12) }
function LispString([string]$p) {
    if ($p -match '["\x00-\x1f]') { throw 'UNSUPPORTED_LISP_PATH' }
    '"' + $p.Replace('\','/') + '"'
}
function AssertPackage {
    if ($PSVersionTable.PSVersion -lt [version]'7.5') { throw 'POWERSHELL_7_5_OR_NEWER_REQUIRED' }
    & (Join-Path (Split-Path -Parent $root) 'scripts/inspect_capability.ps1') -ProjectRoot $root | Out-Null
    foreach ($p in @($lifecycle,(Join-Path $orchestration 'common/TianzhengPlatformSelector.psm1'),
        (Join-Path $orchestration 'common/TestDrawingHistory.psm1'))) {
        Import-Module -Name $p -ErrorAction Stop
    }
}
function AssertOrdinaryItem($p) {
    $i = Get-Item -LiteralPath $p
    if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "LINK_NOT_ALLOWED:$p" }
    $i
}

if ($Stage -eq 'Check') {
    AssertPackage
    [pscustomobject]@{ status='PASS'; stage='offline_package_and_import'; cad_started=$false; runtime_validated=$false }
    return
}
if ($Stage -eq 'Prepare') {
    AssertPackage
    if (-not $SourceDrawing -or -not $SourceHandles -or $Offset -eq 0 -or -not [double]::IsFinite($Offset)) {
        throw 'SUPPLY_SOURCE_DWG_EXACT_HANDLES_AND_NONZERO_OFFSET'
    }
    $inputDwg = AssertOrdinaryItem $SourceDrawing
    if ($inputDwg.PSIsContainer -or $inputDwg.Extension -ine '.dwg') { throw 'DWG_REQUIRED' }
    $handles = @($SourceHandles | ForEach-Object { $_.Split(',') } | ForEach-Object { $_.Trim().ToUpperInvariant() } | Select-Object -Unique)
    if ($handles.Count -lt 1 -or $handles.Count -gt 5 -or @($handles | Where-Object { $_ -notmatch '^[0-9A-F]{1,16}$' }).Count) {
        throw 'SUPPLY_ONE_TO_FIVE_HEX_POLYLINE_HANDLES'
    }
    if (Test-Path -LiteralPath $runs) { [void](AssertOrdinaryItem $runs) }
    else { [void](New-Item -ItemType Directory -Path $runs) }
    $id = [guid]::NewGuid().ToString('N')
    $run = (New-Item -ItemType Directory -Path (Join-Path $runs "portable-$id")).FullName
    $copy = Join-Path $run "cadtest-$id.dwg"
    $before = FileHash $inputDwg.FullName
    [IO.File]::Copy($inputDwg.FullName,$copy,$false)
    if ((FileHash $copy) -cne $before -or (FileHash $inputDwg.FullName) -cne $before) { throw 'SOURCE_COPY_HASH_MISMATCH' }
    $bundle = Join-Path $run 'native-bundle.lsp'
    $built = & (Join-Path $PSScriptRoot 'build_continuous_selection_bundle_v12.ps1') -OutputPath $bundle -Group $Group -Offset $Offset
    if ($built.status -cne 'PASS') { throw 'NATIVE_BUNDLE_BUILD_FAILED' }
    $entry = Join-Path $run 'start-native-test.lsp'
    $handleForm = ($handles | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $dwgForm = LispString $copy
    $readyForm = LispString (Join-Path $run 'ready.flag')
    $claimedForm = LispString (Join-Path $run 'started.flag')
    $bundleForm = LispString $bundle
    $detailsForm = LispString (Join-Path $run 'details.tsv')
    $summaryForm = LispString (Join-Path $run 'summary.tsv')
    $offsetForm = $Offset.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    # Loads business code only after the exact document, clean baseline, and
    # one-use local READY marker match. The user runs this load in CAD.
    $lisp = @"
(defun cx:portable-test (/ ss h e valid drawing tasks)
  (setq drawing (strcase (vl-string-translate "\\" "/" (strcat (getvar "DWGPREFIX") (getvar "DWGNAME"))))
        ss (ssadd) valid T)
  (foreach h '($handleForm)
    (setq e (handent h))
    (if (and e (= (cdr (assoc 0 (entget e))) "LWPOLYLINE") (= (cdr (assoc 410 (entget e))) "Model"))
      (ssadd e ss)
      (setq valid nil)))
  (cond
    ((/= drawing (strcase $dwgForm)) (prompt "\nPORTABLE_TEST_WRONG_DOCUMENT"))
    ((/= (getvar "DBMOD") 0) (prompt "\nPORTABLE_TEST_DIRTY_BASELINE"))
    ((or (not valid) (/= (sslength ss) $($handles.Count))) (prompt "\nPORTABLE_TEST_SCOPE_MISMATCH"))
    ((not (vl-file-rename $readyForm $claimedForm)) (prompt "\nPORTABLE_TEST_NOT_ARMED_OR_ALREADY_STARTED"))
    (T
      (load $bundleForm)
      (setq tasks (cx:cs-selection-tasks ss))
      (if (/= (length tasks) $($handles.Count))
        (prompt "\nPORTABLE_TEST_SCOPE_HAS_NONDIMENSIONABLE_SOURCE")
        (progn
          (setq cx:*full-batch-tasks* tasks
                cx:*full-batch-cleanup-handles* '()
                cx:*full-batch-clean-slate-object-names* '()
                cx:*full-batch-expected-drawing* $dwgForm
                cx:*full-batch-summary-path* $summaryForm
                cx:*full-batch-details-path* $detailsForm
                cx:*full-batch-save-on-success* nil)
          (c:CXTDIMARCFULLBATCH)))))
  (princ))
(vl-load-com)
(cx:portable-test)
"@
    NewFile $entry $lisp
    $scope = [ordered]@{ id=$id; mode='single_native_test_no_save'; source=$inputDwg.FullName; source_sha256=$before;
        copy=$copy; source_handles=$handles; group=$Group; offset=$offsetForm; entry_sha256=(FileHash $entry);
        bundle_sha256=(FileHash $bundle); runtime_manifest_sha256=(FileHash (Join-Path $root 'public-runtime-manifest.json')) }
    JsonFile (Join-Path $run 'scope.json') $scope
    [pscustomobject]@{ status='PREPARED_NOT_READY'; run=$run; drawing=$copy; scope_sha256=(FileHash (Join-Path $run 'scope.json')); next='Open' }
    return
}

if (-not $RunDirectory) { throw 'RUN_DIRECTORY_REQUIRED' }
$run = (AssertOrdinaryItem $RunDirectory).FullName
if (-not $run.StartsWith($runs.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Parent $run) -ine $runs -or (Split-Path -Leaf $run) -notmatch '^portable-[0-9a-f]{32}$') {
    throw 'RUN_OUTSIDE_RECEIVER_TEST_AREA'
}
$scopePath = Join-Path $run 'scope.json'
$scopeHash = FileHash $scopePath
$scope = ReadJson $scopePath
$copy = Join-Path $run "cadtest-$($scope.id).dwg"
$entry = Join-Path $run 'start-native-test.lsp'
$bundle = Join-Path $run 'native-bundle.lsp'
$summary = Join-Path $run 'summary.tsv'
$details = Join-Path $run 'details.tsv'
$started = Join-Path $run 'started.flag'
$ready = Join-Path $run 'ready.flag'
$claim = Join-Path $run 'claim.json'
$settlement = Join-Path $run 'test-receipt.json'
$ownerPath = Join-Path $run 'owner_state.json'
if ($Stage -eq 'Review') {
    [pscustomobject]@{
        status=if (Test-Path -LiteralPath $settlement) {(ReadJson $settlement).status} elseif(Test-Path -LiteralPath $started){'STARTED_OUTCOME_UNVERIFIED'}else{'NOT_OBSERVED'}
        native_summary=if(Test-Path -LiteralPath $summary){Get-Content -LiteralPath $summary}
        native_details=if(Test-Path -LiteralPath $details){$details}
        original_unchanged=((FileHash $scope.source) -ceq $scope.source_sha256)
        saved_copy_unchanged=((FileHash $copy) -ceq $scope.source_sha256)
        visual_acceptance='REVIEW_CAD_AND_CAPTURE_THE_TEST_VIEW'
    }
    return
}
AssertPackage
foreach($p in @($copy,$entry,$bundle,$scopePath)){[void](AssertOrdinaryItem $p)}
if ($copy -cne [string]$scope.copy -or (FileHash $scope.source) -cne $scope.source_sha256 -or
    (FileHash $copy) -cne $scope.source_sha256 -or (FileHash $entry) -cne $scope.entry_sha256 -or
    (FileHash $bundle) -cne $scope.bundle_sha256 -or
    (FileHash (Join-Path $root 'public-runtime-manifest.json')) -cne $scope.runtime_manifest_sha256) {
    throw 'RECEIVER_SCOPE_OR_INPUT_HASH_MISMATCH'
}
if ($Stage -eq 'Open') {
    if (-not $ConfirmIsolatedDesktop -or -not $TianzhengShortcutPath) { throw 'EXPLICIT_ISOLATED_DESKTOP_AND_INSTALLED_SHORTCUT_REQUIRED' }
    if (Get-Process -Name acad,TGStart -ErrorAction SilentlyContinue) { throw 'CLOSE_OTHER_CAD_SESSIONS_YOURSELF_BEFORE_TEST' }
    if (Test-Path -LiteralPath $ownerPath) { throw 'OPEN_ATTEMPT_EXISTS_PREPARE_NEW_RUN' }
    & (Join-Path $orchestration 'start_owned_tianzheng_supervised.ps1') -DrawingPath $copy `
        -ExpectedSha256 $scope.source_sha256 -OwnerStatePath $ownerPath -DialogLogPath (Join-Path $run 'dialogs.jsonl') `
        -LifecycleReportPath (Join-Path $run 'lifecycle.json') -TianzhengShortcutPath $TianzhengShortcutPath `
        -ManualPlatformSelection -PreserveOnFailure -RetryCount 0
    $owner = ReadJson $ownerPath
    $process = Get-Process -Id ([int]$owner.process_id) -ErrorAction Stop
    if ($owner.status -cne 'ready' -or $owner.target_dwg -cne $copy -or $process.ProcessName -cne 'acad') { throw 'INVALID_OWNER_RETURN' }
    JsonFile (Join-Path $run 'owner-binding.json') @{
        scope_sha256=$scopeHash; owner_sha256=(FileHash $ownerPath); pid=$process.Id
        started_utc=$process.StartTime.ToUniversalTime().ToString('o'); image=$process.Path; hwnd=$owner.main_window_handle
    }
    return
}

if (-not $ConfirmWriteToTestCopy) { throw 'EXPLICIT_TEST_COPY_WRITE_CONFIRMATION_REQUIRED' }
$bound = ReadJson (Join-Path $run 'owner-binding.json')
$owner = ReadJson $ownerPath
Import-Module (Join-Path $PSScriptRoot 'common/CadOperationGuard.psm1')
$lease = Enter-CadOperationGuard -ProjectRoot $root -OperationId $scope.id -AllowExistingAcad
try {
    if ($bound.scope_sha256 -cne $scopeHash -or $bound.owner_sha256 -cne (FileHash $ownerPath)) { throw 'OWNER_OR_SCOPE_CHANGED' }
    $p = Get-Process -Id ([int]$bound.pid) -ErrorAction Stop
    $all = @(Get-Process -Name acad -ErrorAction SilentlyContinue)
    if ($all.Count -ne 1 -or $all[0].Id -ne $p.Id -or $p.Path -cne $bound.image -or
        $p.StartTime.ToUniversalTime().ToString('o') -cne $bound.started_utc -or
        -not (Test-TianzhengOwnerWindowLive -Path $ownerPath)) { throw 'OWNER_PID_IMAGE_START_OR_WINDOW_CHANGED' }
    foreach($p0 in @($summary,$details,$ready,$started,$claim,$settlement)){if(Test-Path -LiteralPath $p0){throw 'RUN_ALREADY_USED_PREPARE_NEW_COPY'}}
    JsonFile $claim @{ scope_sha256=$scopeHash; owner_sha256=$bound.owner_sha256; cad_pid=$bound.pid; controller_pid=$PID;
        claim_utc=[DateTime]::UtcNow.ToString('o'); save=$false }
    NewFile $ready $scopeHash
    Write-Host ('仅在测试副本的 CAD 命令行运行一次: (load ' + (LispString $entry) + ')')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $WaitSeconds) {
        if ((Test-Path -LiteralPath $started) -and (Test-Path -LiteralPath $summary) -and (Test-Path -LiteralPath $details)) { break }
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 300
    }
    # Atomically retire any unconsumed marker. A CAD-side claim and expiry
    # race cannot both rename the same input. Never replay either outcome.
    if (Test-Path -LiteralPath $ready) {
        try { [IO.File]::Move($ready,(Join-Path $run 'expired.flag')) }
        catch [IO.IOException] { if (-not (Test-Path -LiteralPath $started)) { throw } }
    }
    $observed = (Test-Path -LiteralPath $started) -and (Test-Path -LiteralPath $summary) -and (Test-Path -LiteralPath $details)
    $status = if($observed){'NATIVE_REPORT_AVAILABLE_REVIEW_REQUIRED'}elseif(Test-Path -LiteralPath $started){'STARTED_OUTCOME_UNVERIFIED_DO_NOT_RETRY'}else{'NOT_STARTED'}
    $result = @{ status=$status; drawing=$copy; original_unchanged=((FileHash $scope.source) -ceq $scope.source_sha256);
        saved_copy_unchanged=((FileHash $copy) -ceq $scope.source_sha256); auto_save=$false; visual_acceptance=$false }
    JsonFile $settlement $result
    [pscustomobject]$result
}
finally {
    try {
        if (Test-Path -LiteralPath $ready) {
            try { [IO.File]::Move($ready,(Join-Path $run 'expired.flag')) }
            catch [IO.IOException] { if (-not (Test-Path -LiteralPath $started)) { throw } }
        }
    } finally { Exit-CadOperationGuard -Guard $lease }
}
