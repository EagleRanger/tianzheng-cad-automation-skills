param(
    [string]$HandoffPath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))

function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON_MISSING=$Path" }
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-ProjectPath([string]$Relative, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Relative)) { throw "${Label}_EMPTY" }
    $full = [IO.Path]::GetFullPath((Join-Path $projectRoot $Relative.Replace('/','\')))
    if (-not $full.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Label}_OUTSIDE_PROJECT=$Relative"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "${Label}_MISSING=$Relative" }
    return $full
}

function Assert-Equal([string]$Actual, [string]$Expected, [string]$Code) {
    if ($Actual -cne $Expected) { throw "${Code}=expected:$Expected;actual:$Actual" }
}

$loop = Read-Json (Join-Path $projectRoot 'config\cad_project_loop.json')
$components = Read-Json (Join-Path $projectRoot 'config\cad_automation_component_packages.json')
$canonical = $loop.canonical_open
$openRows = @($components.components | Where-Object { [string]$_.id -ceq 'CAD-LC-OPEN-V1' })
if ($openRows.Count -ne 1) { throw "CANONICAL_OPEN_COMPONENT_NOT_UNIQUE=$($openRows.Count)" }
$component = $openRows[0]
if ([string]$component.status -cne 'active_with_regression') { throw "CANONICAL_OPEN_COMPONENT_NOT_ACTIVE=$($component.status)" }

Assert-Equal ([string]$canonical.component_id) ([string]$component.id) 'CANONICAL_OPEN_LOOP_COMPONENT_MISMATCH'
Assert-Equal ([string]$canonical.component_version) ([string]$component.version) 'CANONICAL_OPEN_LOOP_COMPONENT_VERSION_MISMATCH'
Assert-Equal ([string]$component.entry) ([string]$canonical.entrypoint) 'CANONICAL_OPEN_COMPONENT_ENTRY_MISMATCH'
Assert-Equal ([string]$component.inner_entry) ([string]$canonical.inner_entrypoint) 'CANONICAL_OPEN_COMPONENT_INNER_ENTRY_MISMATCH'
Assert-Equal ([string]$component.launch_transport) ([string]$canonical.transport) 'CANONICAL_OPEN_COMPONENT_TRANSPORT_MISMATCH'
Assert-Equal ([string]$component.platform) ([string]$canonical.platform) 'CANONICAL_OPEN_COMPONENT_PLATFORM_MISMATCH'
if ([int]$component.inner_max_launch_attempts -ne [int]$canonical.inner_max_launch_attempts) {
    throw 'CANONICAL_OPEN_COMPONENT_ATTEMPT_POLICY_MISMATCH'
}

$entryPath = Resolve-ProjectPath ([string]$component.entry) 'CANONICAL_OPEN_ENTRY'
$innerPath = Resolve-ProjectPath ([string]$component.inner_entry) 'CANONICAL_OPEN_INNER_ENTRY'
Assert-Equal ((Get-FileHash -LiteralPath $entryPath -Algorithm SHA256).Hash) ([string]$component.entry_sha256) 'CANONICAL_OPEN_ENTRY_HASH_MISMATCH'
Assert-Equal ((Get-FileHash -LiteralPath $innerPath -Algorithm SHA256).Hash) ([string]$component.inner_entry_sha256) 'CANONICAL_OPEN_INNER_HASH_MISMATCH'

foreach ($path in @($entryPath, $innerPath)) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw "CANONICAL_OPEN_PARSE_FAILED=$path" }
}

$entryText = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
$innerText = Get-Content -LiteralPath $innerPath -Raw -Encoding UTF8
foreach ($required in @(
    "`$activeLaunchTransport = 'TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'",
    '$desktopShell.ShellExecute($shortcutCandidates[0].FullName',
    'EXPLORER_LAUNCH_ATTEMPTS_EXHAUSTED'
)) {
    if ($innerText.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "CANONICAL_OPEN_INNER_SEMANTIC_MISSING=$required" }
}
foreach ($forbidden in @('T20_V10_SHORTCUT_WITH_DWG_ARGUMENT','$tianzhengShortcut')) {
    if ($innerText.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "CANONICAL_OPEN_FORBIDDEN_ROUTE_PRESENT=$forbidden" }
}
if ($innerText.IndexOf('TArch20V10.arg', [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
    $innerText.IndexOf("Where-Object { `$_.Name -like '*T20*Arch*V10.0*' }", [StringComparison]::Ordinal) -lt 0 -or
    $innerText.IndexOf("`$desktopShell = New-Object -ComObject Shell.Application", [StringComparison]::Ordinal) -lt 0 -or
    $innerText.IndexOf('$desktopShell.ShellExecute($shortcutCandidates[0].FullName', [StringComparison]::Ordinal) -lt 0 -or
    $innerText.IndexOf('$document.SendCommand($command)', [StringComparison]::Ordinal) -ge 0 -or
    $innerText.IndexOf('GetRunningObjectTable(0,out table)', [StringComparison]::Ordinal) -ge 0 -or
    $innerText.IndexOf('OPEN_ARGUMENT_PLUS_EXACT_NAME_WHEN_FULLNAME_EMPTY', [StringComparison]::Ordinal) -lt 0 -or
    $innerText.IndexOf('$script:ownedProcessObserved', [StringComparison]::Ordinal) -lt 0 -or
    $innerText.IndexOf('AUTOCAD_EXITED_AFTER_OPEN_DISPATCH', [StringComparison]::Ordinal) -lt 0) {
    throw 'CANONICAL_OPEN_HEADLESS_PROFILE_ROUTE_OR_DIRECT_DWG_ARGUMENT_INVALID'
}
if ($entryText.IndexOf("route='TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT'", [StringComparison]::Ordinal) -lt 0) {
    throw 'CANONICAL_OPEN_SUPERVISOR_ROUTE_EVIDENCE_MISSING'
}

$startupRegression = Join-Path $projectRoot 'tests\test_tianzheng_startup_fastpath.ps1'
try { & $startupRegression | Out-Null }
catch { throw 'CANONICAL_OPEN_STATIC_REGRESSION_FAILED:' + $_.Exception.Message }

if ([string]::IsNullOrWhiteSpace($HandoffPath)) {
    $HandoffPath = Join-Path $projectRoot 'config\current_execution_handoff.json'
}
$handoff = Read-Json ([IO.Path]::GetFullPath($HandoffPath))
$canonicalBindingProperty = $handoff.PSObject.Properties['canonical_open']
$launchPolicyProperty = $handoff.PSObject.Properties['launch_policy']
if ($null -ne $handoff.PSObject.Properties['existing_b_document_arm_background_read'] -and [string]$handoff.status -cin @('READY','DRAFT')) {
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_command_research_routing_v1.ps1') -DraftPath $HandoffPath -PassThru | Out-Null
    $routing = Read-Json (Join-Path $projectRoot 'config/cad_command_research_routing_v1.json')
    $arm = $routing.routes.shared_annotation_interface_read.optional_lifecycle_profiles.'CAD-EXISTING-B-DOCUMENT-ARM-BACKGROUND-READ-V1'
    Assert-Equal ([string]$handoff.canonical_open.component_id) ([string]$component.id) 'EXISTING_B_ARM_COMPONENT'
    Assert-Equal ([string]$handoff.canonical_open.component_version) ([string]$component.version) 'EXISTING_B_ARM_VERSION'
    Assert-Equal ([string]$handoff.canonical_open.platform) ([string]$canonical.platform) 'EXISTING_B_ARM_PLATFORM'
    Assert-Equal ([string]$handoff.canonical_open.entrypoint) ([string]$arm.controller) 'EXISTING_B_ARM_CONTROLLER'
    Assert-Equal ([string]$handoff.canonical_open.transport) ([string]$arm.canonical_open_transport) 'EXISTING_B_ARM_TRANSPORT'
    [ordered]@{status='PASS';component='CAD-LC-OPEN-V1';transport=$handoff.canonical_open.transport;profile_id=$arm.profile_id;handoff_status=$handoff.status;launch_permitted=$false}|ConvertTo-Json -Compress
    return
}
if ($null -ne $handoff.PSObject.Properties['b_document_bridge_background_read'] -and [string]$handoff.status -cin @('READY','DRAFT')) {
    # Additive scoped experiment; the old V6 identity-only contract stays frozen.
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_command_research_routing_v1.ps1') -DraftPath $HandoffPath -PassThru | Out-Null
    $routing = Read-Json (Join-Path $projectRoot 'config/cad_command_research_routing_v1.json')
    $docBridge = $routing.routes.shared_annotation_interface_read.optional_lifecycle_profiles.'CAD-B-DOCUMENT-BRIDGE-BACKGROUND-READ-V1'
    Assert-Equal ([string]$handoff.canonical_open.entrypoint) ([string]$docBridge.controller) 'BDOC_CANONICAL_CONTROLLER'
    Assert-Equal ([string]$handoff.canonical_open.transport) 'TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_AND_BOUND_B_SCRIPT' 'BDOC_CANONICAL_TRANSPORT'
    [ordered]@{status='PASS';component='CAD-LC-OPEN-V1';transport=$handoff.canonical_open.transport;profile_id=$docBridge.profile_id;handoff_status=$handoff.status}|ConvertTo-Json -Compress
    return
}
if (($null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge_fresh_a'] -or $null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge'] -or $null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge_resume'] -or $null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge_replacement']) -and [string]$handoff.status -cin @('READY','DRAFT')) {
    # A sealed B-only experiment, never a change to the ordinary canonical opener.
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_command_research_routing_v1.ps1') -DraftPath $HandoffPath -PassThru | Out-Null
    $routing = Read-Json (Join-Path $projectRoot 'config/cad_command_research_routing_v1.json')
    $bridgeId = if ($null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge_fresh_a']) { 'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-FRESH-A-V6' } elseif ($null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge_replacement']) { 'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-REPLACEMENT-V3' } elseif ($null -ne $handoff.PSObject.Properties['multi_owner_b_startup_bridge_resume']) { 'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-RESUME-V2' } else { 'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-V1' }
    $bridge = $routing.routes.shared_annotation_interface_read.optional_lifecycle_profiles.$bridgeId
    $existingSettlement = $bridgeId -ceq 'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-FRESH-A-V6' -and [string]$handoff.multi_owner_b_startup_bridge_fresh_a.intent -cin @('ReadExistingOwnersAndRawDialogsOnly','ReadAndRejectExpiredFixedBLoad')
    if ($existingSettlement) {
        # Route validation above already admitted this no-launch recovery intent.
        $bridge = $bridge | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        foreach ($p in $bridge.recovery_intents.ReadExistingOwnersAndRawDialogsOnly.PSObject.Properties) { $bridge | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        if ([string]$handoff.multi_owner_b_startup_bridge_fresh_a.intent -ceq 'ReadAndRejectExpiredFixedBLoad') {
            foreach ($p in $bridge.recovery_intents.ReadAndRejectExpiredFixedBLoad.PSObject.Properties) { $bridge | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        }
    }
    # The preceding full route check resolved and hash-validated any source-sealed
    # fresh-A candidate. Consume that admitted controller, not the historical one.
    $bridgeController = if ($bridgeId -ceq 'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-FRESH-A-V6') { [string]$handoff.program.controller } else { [string]$bridge.controller }
    if ($null -eq $canonicalBindingProperty -or $null -eq $launchPolicyProperty) { throw 'B_BRIDGE_CANONICAL_POLICY_MISSING' }
    Assert-Equal ([string]$handoff.canonical_open.profile_id) ([string]$bridge.profile_id) 'B_BRIDGE_CANONICAL_PROFILE_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.component_id) ([string]$component.id) 'B_BRIDGE_CANONICAL_COMPONENT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.component_version) ([string]$component.version) 'B_BRIDGE_CANONICAL_VERSION_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.entrypoint) $bridgeController 'B_BRIDGE_CANONICAL_ENTRYPOINT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.inner_entrypoint) ([string]$canonical.inner_entrypoint) 'B_BRIDGE_CANONICAL_INNER_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.transport) ([string]$bridge.canonical_open_transport) 'B_BRIDGE_CANONICAL_TRANSPORT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.platform) ([string]$canonical.platform) 'B_BRIDGE_CANONICAL_PLATFORM_MISMATCH'
    foreach ($policy in @($handoff.canonical_open,$handoff.launch_policy)) {
        if ($policy.launch_permitted_for_this_handoff -isnot [bool] -or $policy.launch_permitted_for_this_handoff -ne (-not $existingSettlement)) { throw 'B_BRIDGE_LAUNCH_PERMISSION_REQUIRED' }
        Assert-Equal ([string]$policy.open_result_semantics) ([string]$bridge.open_result_semantics) 'B_BRIDGE_OPEN_RESULT_SEMANTICS_MISMATCH'
    }
    Assert-Equal ([string]$handoff.launch_policy.invocation) ([string]$bridge.invocation) 'B_BRIDGE_INVOCATION_POLICY_MISMATCH'
    if (-not $existingSettlement -and ($handoff.launch_policy.bound_startup_script_only -isnot [bool] -or $handoff.launch_policy.bound_startup_script_only -ne $true)) { throw 'B_BRIDGE_FIXED_STARTUP_SCOPE_REQUIRED' }
    foreach ($field in @('inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open','standalone_close_allowed')) {
        $property = $handoff.launch_policy.PSObject.Properties[$field]
        if ($null -eq $property -or $property.Value -isnot [bool] -or $property.Value -ne $false) { throw "B_BRIDGE_FORBIDDEN_LAUNCH_POLICY=$field" }
    }
    [pscustomobject]@{status='PASS';component=[string]$component.id;component_version=[string]$component.version;transport=[string]$bridge.canonical_open_transport;handoff_status=[string]$handoff.status;profile_id=[string]$bridge.profile_id;live_verified=$false} | ConvertTo-Json -Compress
    return
}
if (($null -ne $handoff.PSObject.Properties['multi_owner_test_preparation'] -or $null -ne $handoff.PSObject.Properties['multi_owner_a_only_preparation']) -and [string]$handoff.status -cin @('READY','DRAFT')) {
    # This is an admitted preparation-only profile, not the ordinary single-owner
    # supervisor contract. Reuse the public route's exact issuer/scope/hash gate;
    # never infer lifecycle permission from a profile-shaped metadata field alone.
    & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_command_research_routing_v1.ps1') -DraftPath $HandoffPath -PassThru | Out-Null
    $routing = Read-Json (Join-Path $projectRoot 'config/cad_command_research_routing_v1.json')
    $aOnlyPreparation = $null -ne $handoff.PSObject.Properties['multi_owner_a_only_preparation']
    $existingASettlement = $aOnlyPreparation -and $null -ne $handoff.multi_owner_a_only_preparation.PSObject.Properties['mode'] -and [string]$handoff.multi_owner_a_only_preparation.mode -ceq 'RESUME_EXISTING_A'
    $preparation = if ($aOnlyPreparation) { $routing.routes.shared_annotation_interface_read.optional_lifecycle_profiles.'CAD-MULTI-OWNER-A-ONLY-PREPARATION-V2' } else { $routing.routes.shared_annotation_interface_read.optional_lifecycle_profiles.'CAD-MULTI-OWNER-TEST-PREPARATION-V1' }
    if ($existingASettlement) { $preparation = $preparation.resume_existing_a }
    if (-not $aOnlyPreparation -and $null -ne $handoff.multi_owner_test_preparation.PSObject.Properties['mode'] -and [string]$handoff.multi_owner_test_preparation.mode -ceq 'RESUME_PREPARED_A') {
        $preparation = $preparation.resume_prepared_a
    }
    if ($null -eq $canonicalBindingProperty -or $null -eq $canonicalBindingProperty.Value) { throw 'PREPARATION_CANONICAL_OPEN_BINDING_MISSING' }
    if ($null -eq $launchPolicyProperty -or $null -eq $launchPolicyProperty.Value) { throw 'PREPARATION_LAUNCH_POLICY_MISSING' }
    Assert-Equal ([string]$handoff.canonical_open.profile_id) ([string]$preparation.profile_id) 'PREPARATION_CANONICAL_PROFILE_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.component_id) ([string]$component.id) 'PREPARATION_CANONICAL_COMPONENT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.component_version) ([string]$component.version) 'PREPARATION_CANONICAL_VERSION_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.entrypoint) ([string]$preparation.controller) 'PREPARATION_CANONICAL_ENTRYPOINT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.inner_entrypoint) ([string]$canonical.inner_entrypoint) 'PREPARATION_CANONICAL_INNER_ENTRYPOINT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.transport) ([string]$canonical.transport) 'PREPARATION_CANONICAL_TRANSPORT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.platform) ([string]$canonical.platform) 'PREPARATION_CANONICAL_PLATFORM_MISMATCH'
    foreach ($policy in @($handoff.canonical_open,$handoff.launch_policy)) {
        if ($policy.launch_permitted_for_this_handoff -isnot [bool] -or $policy.launch_permitted_for_this_handoff -ne (-not $existingASettlement)) { throw 'PREPARATION_LAUNCH_PERMISSION_REQUIRED' }
        $preparationSemantics = if ($aOnlyPreparation) { [string]$preparation.open_result_semantics } else { 'preparation_OS_owner_tuples_only__strict_COM_read_unverified' }
        Assert-Equal ([string]$policy.open_result_semantics) $preparationSemantics 'PREPARATION_OPEN_RESULT_SEMANTICS_MISMATCH'
    }
    $preparationInvocation = if ($aOnlyPreparation) { [string]$preparation.invocation } else { 'admitted_multi_owner_test_preparation_profile_only' }
    Assert-Equal ([string]$handoff.launch_policy.invocation) $preparationInvocation 'PREPARATION_INVOCATION_POLICY_MISMATCH'
    foreach ($field in @('inline_startup_wrapper_allowed','alternate_transport_allowed','timeout_may_reclassify_failed_open','standalone_close_allowed')) {
        $property = $handoff.launch_policy.PSObject.Properties[$field]
        if ($null -eq $property -or $property.Value -isnot [bool] -or $property.Value -ne $false) { throw "PREPARATION_FORBIDDEN_LAUNCH_POLICY=$field" }
    }
    [pscustomobject]@{status='PASS';component=[string]$component.id;component_version=[string]$component.version;transport=[string]$canonical.transport;handoff_status=[string]$handoff.status;profile_id=[string]$preparation.profile_id;live_verified=$false} | ConvertTo-Json -Compress
    return
}
if ([string]$handoff.status -ceq 'READY' -and ($null -eq $canonicalBindingProperty -or $null -eq $canonicalBindingProperty.Value)) { throw 'READY_HANDOFF_CANONICAL_OPEN_BINDING_MISSING' }
if ($null -ne $canonicalBindingProperty -and $null -ne $canonicalBindingProperty.Value -and $null -ne $canonicalBindingProperty.Value.PSObject.Properties['scoped_candidate']) {
    # An explicit LIMITED_EXPERIMENT may bind a mechanically equivalent copy
    # and its versioned regression. Do not pin future source-owned recovery to
    # the first SSAAA-only fixture; the accepted normal entry stays frozen.
    $scopedRegression = Resolve-ProjectPath ([string]$handoff.program.scoped_regression) 'SCOPED_OPEN_REGRESSION'
    Assert-Equal ((Get-FileHash -LiteralPath $scopedRegression -Algorithm SHA256).Hash) ([string]$handoff.program.scoped_regression_sha256) 'SCOPED_OPEN_REGRESSION_HASH_MISMATCH'
    & $scopedRegression -HandoffPath $HandoffPath | Out-Null
}
if ([string]$handoff.status -ceq 'READY') {
    if ($null -eq $handoff.canonical_open) { throw 'READY_HANDOFF_CANONICAL_OPEN_BINDING_MISSING' }
    if ($null -eq $handoff.launch_policy) { throw 'READY_HANDOFF_LAUNCH_POLICY_MISSING' }
    Assert-Equal ([string]$handoff.canonical_open.component_id) ([string]$component.id) 'READY_HANDOFF_COMPONENT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.component_version) ([string]$component.version) 'READY_HANDOFF_COMPONENT_VERSION_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.entrypoint) ([string]$canonical.entrypoint) 'READY_HANDOFF_ENTRYPOINT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.inner_entrypoint) ([string]$canonical.inner_entrypoint) 'READY_HANDOFF_INNER_ENTRYPOINT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.transport) ([string]$canonical.transport) 'READY_HANDOFF_TRANSPORT_MISMATCH'
    Assert-Equal ([string]$handoff.canonical_open.platform) ([string]$canonical.platform) 'READY_HANDOFF_PLATFORM_MISMATCH'
    $launchPermitted = [bool]$handoff.launch_policy.launch_permitted_for_this_handoff
    if ([bool]$handoff.canonical_open.launch_permitted_for_this_handoff -ne $launchPermitted) {
        throw 'READY_HANDOFF_LAUNCH_PERMISSION_BINDING_MISMATCH'
    }
    if ($launchPermitted) {
        Assert-Equal ([string]$handoff.launch_policy.invocation) ([string]$canonical.invocation_policy) 'READY_HANDOFF_INVOCATION_POLICY_MISMATCH'
        Assert-Equal ([string]$handoff.canonical_open.open_result_semantics) ([string]$canonical.open_result_semantics) 'READY_HANDOFF_CANONICAL_OPEN_RESULT_SEMANTICS_MISMATCH'
        Assert-Equal ([string]$handoff.launch_policy.open_result_semantics) ([string]$canonical.open_result_semantics) 'READY_HANDOFF_OPEN_RESULT_SEMANTICS_MISMATCH'
    } else {
        $reuseResultSemantics = 'exact_owned_PID_HWND_document_revalidated_or_fail'
        Assert-Equal ([string]$handoff.launch_policy.invocation) 'reuse_exact_owned_PID_HWND_only' 'READY_HANDOFF_REUSE_POLICY_MISMATCH'
        Assert-Equal ([string]$handoff.canonical_open.open_result_semantics) $reuseResultSemantics 'READY_HANDOFF_REUSE_CANONICAL_RESULT_SEMANTICS_MISMATCH'
        Assert-Equal ([string]$handoff.launch_policy.open_result_semantics) $reuseResultSemantics 'READY_HANDOFF_REUSE_RESULT_SEMANTICS_MISMATCH'
        $immutablePath = Resolve-ProjectPath ([string]$handoff.immutable_handoff_path) 'READY_HANDOFF_IMMUTABLE'
        Assert-Equal ((Get-FileHash -LiteralPath $immutablePath -Algorithm SHA256).Hash) ([string]$handoff.immutable_handoff_sha256) 'READY_HANDOFF_IMMUTABLE_HASH_MISMATCH'
        $immutable = Read-Json $immutablePath
        if ($null -eq $immutable.owner) { throw 'READY_HANDOFF_REUSE_OWNER_MISSING' }
        if ([int64]$immutable.owner.process_id -le 0) { throw 'READY_HANDOFF_REUSE_PID_INVALID' }
        $standaloneClose = [bool]$handoff.launch_policy.standalone_close_allowed
        $pidOnlyClose = $standaloneClose -and [string]$immutable.close_policy.identity_mode -ceq 'EXACT_PID_START_TIME_UNIQUE_ACAD_NO_HWND'
        if (-not $pidOnlyClose -and [int64]$immutable.owner.window_handle -le 0) { throw 'READY_HANDOFF_REUSE_HWND_INVALID' }
        if ([bool]$immutable.owner.launch_permitted) { throw 'READY_HANDOFF_REUSE_OWNER_LAUNCH_ALLOWED' }
        if (-not $pidOnlyClose -and [string]::IsNullOrWhiteSpace([string]$immutable.owner.drawing)) { throw 'READY_HANDOFF_REUSE_DRAWING_MISSING' }
        # No launch is not a prohibition on explicitly authorized close-only recovery.
        if ([bool]$handoff.launch_policy.standalone_close_allowed) {
            if ($immutable.launch_policy.standalone_close_allowed -ne $true -or $immutable.launch_policy.launch_permitted_for_this_handoff -ne $false) { throw 'READY_HANDOFF_CLOSE_ONLY_IMMUTABLE_PERMISSION' }
            $close = $immutable.close_policy
            if ($null -eq $close) { throw 'READY_HANDOFF_CLOSE_ONLY_POLICY_MISSING' }
            $closeRows = @($components.components | Where-Object { $_.id -ceq 'CAD-LC-CLOSE-V1' })
            if ($closeRows.Count -ne 1 -or $closeRows[0].status -cne 'active_with_regression') { throw 'READY_HANDOFF_CLOSE_ONLY_COMPONENT' }
            Assert-Equal ([string]$close.component_id) 'CAD-LC-CLOSE-V1' 'READY_HANDOFF_CLOSE_ONLY_COMPONENT'
            Assert-Equal ([string]$close.entrypoint) ([string]$closeRows[0].entry) 'READY_HANDOFF_CLOSE_ONLY_ENTRY'
            $closeEntry = Resolve-ProjectPath ([string]$close.entrypoint) 'READY_HANDOFF_CLOSE_ONLY_ENTRY'
            Assert-Equal ((Get-FileHash -LiteralPath $closeEntry).Hash) ([string]$closeRows[0].entry_sha256) 'READY_HANDOFF_CLOSE_ONLY_ENTRY_HASH'
            Assert-Equal ([string]$close.disposition) 'Discard' 'READY_HANDOFF_CLOSE_ONLY_DISPOSITION'
            $authority = $immutable.reasoning.user_authority
            if ([string]::IsNullOrWhiteSpace([string]$authority.quote) -or [string]::IsNullOrWhiteSpace([string]$authority.scope) -or [string]$authority.thread_id -cne [string]$immutable.issuer.thread_id) { throw 'READY_HANDOFF_CLOSE_ONLY_AUTHORITY' }
            if ($immutable.action.close_count -ne 1) { throw 'READY_HANDOFF_CLOSE_ONLY_ACTION' }
            foreach ($key in @('open_count','save_count_max','generation_send_count','layout_send_count','retry_count')) {
                if ($null -eq $immutable.action.PSObject.Properties[$key] -or $immutable.action.$key -ne 0) { throw "READY_HANDOFF_CLOSE_ONLY_ACTION=$key" }
            }
            if ($immutable.owner.save -ne $false -or $immutable.target_dwg.save -ne $false -or $immutable.target_dwg.leave_open -ne $false -or $immutable.target_dwg.open_once -ne $false -or $immutable.target_dwg.copy_once -ne $false) { throw 'READY_HANDOFF_CLOSE_ONLY_TARGET_CONFLICT' }
            $specPath = Resolve-ProjectPath ([string]$immutable.program.execution_spec) 'READY_HANDOFF_CLOSE_ONLY_SPEC'
            Assert-Equal ((Get-FileHash -LiteralPath $specPath).Hash) ([string]$immutable.program.execution_spec_sha256) 'READY_HANDOFF_CLOSE_ONLY_SPEC_HASH'
            $spec = Read-Json $specPath
            $started = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse([string]$close.process_started_utc, [ref]$started) -or [string]$spec.process_started_utc -cne [string]$close.process_started_utc -or $spec.process_id -ne $immutable.owner.process_id -or [string]$spec.run_id -cne [string]$immutable.run_id) { throw 'READY_HANDOFF_CLOSE_ONLY_PROCESS_BINDING' }
            if ($pidOnlyClose) {
                if ([int64]$immutable.owner.window_handle -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$immutable.owner.owner_state)) { throw 'READY_HANDOFF_PID_ONLY_CLOSE_WINDOW_IDENTITY_CONFLICT' }
            } else {
                $ownerPath = Resolve-ProjectPath ([string]$immutable.owner.owner_state) 'READY_HANDOFF_CLOSE_ONLY_OWNER'
                $ownerState = Read-Json $ownerPath
                if ($ownerState.process_id -ne $immutable.owner.process_id -or $ownerState.main_window_handle -ne $immutable.owner.window_handle -or [string]$spec.owner_state -cne [string]$immutable.owner.owner_state) { throw 'READY_HANDOFF_CLOSE_ONLY_OWNER_IDENTITY' }
            }
            $runRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot ('runs/' + $immutable.run_id))) + [IO.Path]::DirectorySeparatorChar
            $reportPath = [IO.Path]::GetFullPath((Join-Path $projectRoot ([string]$immutable.reporting.controller_receipt)))
            if (-not $reportPath.StartsWith($runRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($reportPath) -ine '.json') { throw 'READY_HANDOFF_CLOSE_ONLY_RECEIPT' }
        }
    }
    if ([bool]$handoff.launch_policy.inline_startup_wrapper_allowed) { throw 'READY_HANDOFF_INLINE_STARTUP_WRAPPER_ALLOWED' }
    if ([bool]$handoff.launch_policy.alternate_transport_allowed) { throw 'READY_HANDOFF_ALTERNATE_TRANSPORT_ALLOWED' }
    if ([bool]$handoff.launch_policy.timeout_may_reclassify_failed_open) { throw 'READY_HANDOFF_TIMEOUT_RECLASSIFICATION_ALLOWED' }
}

[pscustomobject]@{
    status = 'PASS'
    component = [string]$component.id
    component_version = [string]$component.version
    transport = [string]$canonical.transport
    handoff_status = [string]$handoff.status
} | ConvertTo-Json -Compress
