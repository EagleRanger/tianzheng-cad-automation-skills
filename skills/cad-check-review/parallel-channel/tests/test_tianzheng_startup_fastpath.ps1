$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$watcherPath = Join-Path $root 'scripts\watch_tianzheng_dialogs.ps1'
$starterPath = Join-Path $root 'scripts\start_owned_tianzheng_direct_dwg.ps1'
$supervisedStarterPath = Join-Path $root 'scripts\start_owned_tianzheng_supervised.ps1'
$platformModulePath = Join-Path $root 'scripts\common\TianzhengPlatformSelector.psm1'
$whitelistPath = Join-Path $root 'config\tianzheng_dialog_whitelist.json'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($path in @($watcherPath, $starterPath, $supervisedStarterPath, $platformModulePath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "PARSE_FAILED=$path"
}

$watcher = Get-Content -LiteralPath $watcherPath -Raw -Encoding UTF8
$starter = Get-Content -LiteralPath $starterPath -Raw -Encoding UTF8
$supervisedStarter = Get-Content -LiteralPath $supervisedStarterPath -Raw -Encoding UTF8
$platformModule = Get-Content -LiteralPath $platformModulePath -Raw -Encoding UTF8
$config = Get-Content -LiteralPath $whitelistPath -Raw -Encoding UTF8 | ConvertFrom-Json
$xref = @($config.rules | Where-Object { $_.id -eq 'xref_missing_ignore_unresolved' })
$repair = @($config.rules | Where-Object { $_.id -eq 'graphic_repair_close_notification' })
$expectedXrefButton = -join ([char[]]@(0x5FFD, 0x7565, 0x672A, 0x89E3, 0x51B3, 0x7684, 0x53C2, 0x7167, 0x6587, 0x4EF6))

Assert-True ($xref.Count -eq 1) 'XREF_RULE_NOT_UNIQUE'
Assert-True ($xref[0].required_button_text -eq $expectedXrefButton) 'XREF_BUTTON_CHANGED'
Assert-True ($xref[0].action -eq 'click_exact_button') 'XREF_ACTION_CHANGED'
Assert-True ($repair.Count -eq 1) 'REPAIR_RULE_NOT_UNIQUE'
Assert-True ($repair[0].action -eq 'post_standard_close_and_verify') 'REPAIR_CLOSE_ACTION_MISSING'
Assert-True ($watcher.Contains('TransientBlankDialogGraceMilliseconds')) 'BLANK_DIALOG_GRACE_MISSING'
Assert-True ($watcher.Contains('[int]$TransientBlankDialogGraceMilliseconds = 15000')) 'BLANK_DIALOG_GRACE_NOT_EXTENDED'
Assert-True ($watcher.Contains("matched_by='blank_title_exact_button'")) 'BLANK_XREF_FASTPATH_MISSING'
Assert-True ($watcher.Contains("matched_by='exact_signature_standard_close'")) 'REPAIR_STANDARD_CLOSE_FASTPATH_MISSING'
Assert-True ($watcher.Contains("[string]::IsNullOrWhiteSpace(`$RequiredTitle)-or`$candidateTitle.IndexOf")) 'VISIBLE_MAIN_WINDOW_GATE_MISSING'
Assert-True ($starter.Contains("-RequiredMainTitle '' -QuietSeconds `$StableSeconds")) 'COMBINED_READY_GATE_MISSING'
Assert-True ($starter.Contains('Get-ExactNativeDocumentIdentity')) 'NATIVE_DOCUMENT_IDENTITY_GATE_MISSING'
Assert-True ($starter.Contains('$combinedWatchSeconds = [Math]::Max($DialogWatchSeconds, $StableSeconds + 3)')) 'COMBINED_TIMEOUT_MISSING'
Assert-True (-not $starter.Contains('$stable = [Diagnostics.Stopwatch]::StartNew()')) 'DUPLICATE_STABLE_WAIT_REINTRODUCED'
Assert-True ($starter.Contains('$activeLaunchTransport = ''TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT''')) 'TIANZHENG_SHORTCUT_TRANSPORT_MISSING'
Assert-True ($starter.Contains('$launcherIdsBefore -notcontains $_.Id')) 'OWNED_HEADLESS_LAUNCHER_GATE_MISSING'
Assert-True ($starter.Contains('wait_tianzheng_resource_quiescence.ps1')) 'RESOURCE_QUIESCENCE_GATE_MISSING'
Assert-True ($starter.Contains('CAD_RESOURCE_NOT_QUIESCENT=')) 'RESOURCE_QUIESCENCE_FAIL_CLOSED_MISSING'
Assert-True ($starter.Contains('get_tianzheng_adaptive_startup_budget.ps1')) 'ADAPTIVE_STARTUP_BUDGET_MISSING'
Assert-True ($starter.Contains('$lastProgressSignature')) 'PROGRESS_LEASE_MISSING'
Assert-True (-not $starter.Contains('Start-Sleep -Seconds 15')) 'FIXED_POST_CLEANUP_SLEEP_REINTRODUCED'
Assert-True ($starter.Contains("`$desktopShell = New-Object -ComObject Shell.Application")) 'EXPLORER_SHELLEXECUTE_BINDING_MISSING'
Assert-True ($starter.Contains('$desktopShell.ShellExecute($shortcutCandidates[0].FullName')) 'TIANZHENG_SHORTCUT_DWG_ARGUMENT_MISSING'
Assert-True ($starter.Contains("Where-Object { `$_.Name -like '*T20*Arch*V10.0*' }")) 'TIANZHENG_SHORTCUT_IDENTITY_MISSING'
Assert-True (-not $starter.Contains('$document.SendCommand($command)')) 'FAILED_ROT_OPEN_COMMAND_REINTRODUCED'
Assert-True (-not $starter.Contains('GetRunningObjectTable(0,out table)')) 'FAILED_ROT_APPLICATION_BINDING_REINTRODUCED'
Assert-True ($starter.Contains('OPEN_ARGUMENT_PLUS_EXACT_NAME_WHEN_FULLNAME_EMPTY')) 'EARLY_EMPTY_FULLNAME_IDENTITY_MISSING'
Assert-True ($starter.Contains('$script:ownedProcessObserved')) 'OWNED_PROCESS_EXIT_SENTINEL_MISSING'
Assert-True ($starter.Contains('EXACT_SHORTCUT_ARGUMENT_PLUS_TARGET_WINDOW_TITLE')) 'HISTORICAL_TARGET_TITLE_IDENTITY_MISSING'
Assert-True ($starter.Contains('$identityTimeoutSeconds = [Math]::Min($hardCapSeconds,[Math]::Max(120,$NoProgressTimeoutSeconds))')) 'ADAPTIVE_IDENTITY_TIMEOUT_MISSING'
Assert-True (-not $starter.Contains('TARGET_WINDOW_IDENTITY_TIMEOUT_60S')) 'FIXED_60_SECOND_IDENTITY_TIMEOUT_REINTRODUCED'
Assert-True ($starter.Contains('AUTOCAD_EXITED_AFTER_OPEN_DISPATCH')) 'POST_OPEN_PROCESS_EXIT_FAST_GATE_MISSING'
Assert-True (-not $starter.Contains('TArch20V10.arg')) 'HEADLESS_TIANZHENG_ARG_ROUTE_REINTRODUCED'
Assert-True ($starter.Contains('EXPLORER_LAUNCH_ATTEMPTS_EXHAUSTED')) 'BOUNDED_RETRY_GATE_MISSING'
Assert-True ($platformModule.Contains('SelectAutoCad2021')) 'PLATFORM_SELECTION_HANDLER_MISSING'
Assert-True ($starter.Contains('PLATFORM_AUTOCAD_2021_CONFIRMED')) 'PLATFORM_SELECTION_EVIDENCE_MISSING'
Assert-True ($starter.Contains('TianzhengPlatformSelector.psm1')) 'DIRECT_SHARED_PLATFORM_GATE_MISSING'
Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'scripts\start_owned_tianzheng_human_flow.ps1'))) 'LEGACY_HUMAN_FLOW_REINTRODUCED'
Assert-True ($supervisedStarter.Contains("start_owned_tianzheng_direct_dwg.ps1")) 'SUPERVISOR_CANONICAL_DIRECT_OPEN_MISSING'
Assert-True ($supervisedStarter.Contains("route='TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'")) 'SUPERVISOR_SHORTCUT_ROUTE_EVIDENCE_MISSING'
Assert-True ($supervisedStarter.Contains("platform='AutoCAD 2021'")) 'SUPERVISOR_PLATFORM_EVIDENCE_MISSING'
Assert-True ($supervisedStarter.Contains('-NoProgressTimeoutSeconds $effectiveInitialFrameTimeout')) 'SUPERVISOR_ADAPTIVE_PROGRESS_TIMEOUT_NOT_FORWARDED'
Assert-True ($supervisedStarter.Contains('-MaxLaunchAttempts 1')) 'NESTED_STARTUP_RETRY_REINTRODUCED'
Assert-True (-not $supervisedStarter.Contains('start_owned_tianzheng_human_flow.ps1')) 'SUPERVISOR_LEGACY_ROUTE_REINTRODUCED'
Assert-True ($supervisedStarter.Contains("-RecentCadCleanup:`$recentCadCleanup")) 'SUPERVISOR_RECENT_CLEANUP_BUDGET_NOT_PRESERVED'
Assert-True ($supervisedStarter.Contains("Stage 'prelaunch_resource_quiescence'")) 'SUPERVISOR_PRELAUNCH_MEMORY_QUIESCENCE_MISSING'
Assert-True ($supervisedStarter.Contains("Status 'SKIPPED_FAST_OWNED_HANDOFF'")) 'FAST_OWNED_HANDOFF_SKIP_EVIDENCE_MISSING'
Assert-True ($supervisedStarter.Contains('$needsExtendedQuiescence = ($plan.target_count -gt 0 -and [bool]$preCleanupBudget.memory_pressure)')) 'EXTENDED_QUIESCENCE_NOT_PRESSURE_GATED'
Assert-True ($supervisedStarter.Contains('$PostReturnStableSeconds = 3')) 'SHORT_POST_RETURN_STABILITY_DEFAULT_MISSING'
Assert-True ($supervisedStarter.Contains('Test-TianzhengOwnerWindowLive -Path $ownerState')) 'OWNER_STATE_EXACT_HWND_POST_RETURN_GATE_MISSING'
Assert-True (-not $supervisedStarter.Contains('(Get-Date).AddSeconds(20)')) 'DUPLICATE_TWENTY_SECOND_POST_RETURN_WAIT_REINTRODUCED'
Assert-True ($supervisedStarter.Contains('-TransientBlankDialogGraceMilliseconds $TransientBlankDialogGraceMilliseconds')) 'SUPERVISOR_BLANK_DIALOG_GRACE_NOT_FORWARDED'
Assert-True ($platformModule.Contains('AutoCAD 2021')) 'PLATFORM_2021_TARGET_MISSING'
Assert-True ($platformModule.Contains('LB_GETCURSEL')) 'PLATFORM_SELECTION_VERIFICATION_MISSING'
Assert-True ($platformModule.Contains('screen_coordinates_used = $false')) 'PLATFORM_GATE_MUST_BE_RESOLUTION_INDEPENDENT'
Assert-True ($platformModule.Contains('AutoCAD 2021')) 'PLATFORM_VERSION_GATE_MISSING'
Assert-True ($starter.Contains('OWNED_STUCK_ACAD_CLEARED_PID=')) 'OWNED_STUCK_ACAD_RECOVERY_MISSING'
Assert-True ($starter.Contains('$ownedAcadIds.Contains([int]$_.Id)')) 'EXACT_OWNED_PID_KILL_GATE_MISSING'
Assert-True ($starter.Contains('Never claim or stop a')) 'UNOWNED_PROCESS_PROTECTION_MISSING'

[pscustomobject]@{
    status = 'PASS'
    assertions = 41
    xref_default = 'ignore_unresolved'
    graphic_repair_default = 'standard_close_without_persistent_preference_change'
    readiness = 'bounded_owned_process_recovery_plus_combined_dialog_and_title_quiet_gate'
} | ConvertTo-Json -Compress
