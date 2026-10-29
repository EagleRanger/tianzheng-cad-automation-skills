param(
    [string]$DraftPath = '',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$index = Get-Content -LiteralPath (Join-Path $root 'config\project_execution_index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath (Join-Path $root ([string]$index.native_task_registry)) -Raw -Encoding UTF8 | ConvertFrom-Json
$routing = Get-Content -LiteralPath (Join-Path $root ([string]$index.command_research_routing)) -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = [Collections.Generic.List[string]]::new()

if ([string]$routing.loop_id -cne [string]$index.loop_id) { $errors.Add('COMMAND_ROUTE_LOOP_ID_MISMATCH') }
if ([string]$routing.project_control.thread_id -cne [string]$registry.tasks.project_strategy.thread_id) { $errors.Add('COMMAND_ROUTE_PROJECT_CONTROL_MISMATCH') }
if ([string]$routing.execution.thread_id -cne [string]$registry.tasks.execution_run.thread_id) { $errors.Add('COMMAND_ROUTE_EXECUTION_MISMATCH') }

foreach ($routeProperty in @($routing.routes.PSObject.Properties)) {
    $routeId = [string]$routeProperty.Name
    $route = $routeProperty.Value
    $lane = [string]$route.owner_lane
    $task = $registry.tasks.PSObject.Properties[$lane]
    if ($null -eq $task) { $errors.Add("COMMAND_ROUTE_OWNER_LANE_MISSING:$routeId"); continue }
    if ([string]$task.Value.thread_id -cne [string]$route.research_thread_id) { $errors.Add("COMMAND_ROUTE_RESEARCH_THREAD_MISMATCH:$routeId") }
    if ([string]$route.detail_return_thread_id -cne [string]$route.research_thread_id) { $errors.Add("COMMAND_ROUTE_DETAIL_TARGET_MISMATCH:$routeId") }
    if ([string]$route.milestone_thread_id -cne [string]$registry.tasks.project_strategy.thread_id) { $errors.Add("COMMAND_ROUTE_MILESTONE_TARGET_MISMATCH:$routeId") }
    $issuerLane = [string]$route.ready_issuer_lane
    $issuerTask = $registry.tasks.PSObject.Properties[$issuerLane]
    if ($null -eq $issuerTask) { $errors.Add("COMMAND_ROUTE_READY_ISSUER_LANE_MISSING:$routeId"); continue }
    if ([string]$route.ready_issuer_thread_id -cne [string]$issuerTask.Value.thread_id) { $errors.Add("COMMAND_ROUTE_READY_ISSUER_THREAD_MISMATCH:$routeId") }
    if ([string]$route.ready_publisher -cne [string]$index.ready_handoff_publisher) { $errors.Add("COMMAND_ROUTE_READY_PUBLISHER_MISMATCH:$routeId") }
    if ($issuerLane -ne 'project_strategy') {
        if (-not [bool]$issuerTask.Value.may_publish_ready) { $errors.Add("COMMAND_ROUTE_READY_ISSUER_NOT_AUTHORIZED:$routeId") }
        if ([bool]$issuerTask.Value.may_control_cad -or [bool]$issuerTask.Value.may_write_project_authority) { $errors.Add("COMMAND_ROUTE_READY_ISSUER_EXCESS_AUTHORITY:$routeId") }
        $allowedRouteIds = @([string]$issuerTask.Value.publish_scope.route_id)
        $additionalRoutesProperty = $issuerTask.Value.publish_scope.PSObject.Properties['additional_route_ids']
        if ($null -ne $additionalRoutesProperty) { $allowedRouteIds += @($additionalRoutesProperty.Value) }
        if ($routeId -cnotin $allowedRouteIds) { $errors.Add("COMMAND_ROUTE_READY_SCOPE_ROUTE_MISMATCH:$routeId") }
        if ([string]$issuerTask.Value.publish_scope.publisher -cne [string]$index.ready_handoff_publisher) { $errors.Add("COMMAND_ROUTE_READY_SCOPE_PUBLISHER_MISMATCH:$routeId") }
        if ([string]$issuerTask.Value.publish_scope.target_lane -cne 'execution_run' -or [string]$issuerTask.Value.publish_scope.target_thread_id -cne [string]$registry.tasks.execution_run.thread_id) { $errors.Add("COMMAND_ROUTE_READY_SCOPE_TARGET_MISMATCH:$routeId") }
        if ([bool]$issuerTask.Value.publish_scope.may_publish_other_routes -or [bool]$issuerTask.Value.publish_scope.may_bypass_publisher) { $errors.Add("COMMAND_ROUTE_READY_SCOPE_TOO_BROAD:$routeId") }
    }
}

$validatedRouteId = ''
$validatedIssuerLane = ''
$validatedIssuerThreadId = ''
if (-not [string]::IsNullOrWhiteSpace($DraftPath)) {
    $draftFull = [IO.Path]::GetFullPath($DraftPath)
    if (-not $draftFull.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'COMMAND_ROUTE_DRAFT_OUTSIDE_PROJECT' }
    $draft = Get-Content -LiteralPath $draftFull -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $draft.PSObject.Properties['command_routing']) { $errors.Add('READY_COMMAND_ROUTING_MISSING') }
    else {
        $validatedRouteId = [string]$draft.command_routing.route_id
        $routeProperty = $routing.routes.PSObject.Properties[$validatedRouteId]
        if ($null -eq $routeProperty) { $errors.Add('READY_COMMAND_ROUTE_ID_UNKNOWN') }
        else {
            $route = $routeProperty.Value
            if ([string]$draft.command_routing.originating_research_thread_id -cne [string]$route.research_thread_id) { $errors.Add('READY_COMMAND_ROUTE_ORIGIN_MISMATCH') }
            if ([string]$draft.command_routing.detail_return_thread_id -cne [string]$route.detail_return_thread_id) { $errors.Add('READY_COMMAND_ROUTE_DETAIL_TARGET_MISMATCH') }
            if ([string]$draft.command_routing.milestone_thread_id -cne [string]$route.milestone_thread_id) { $errors.Add('READY_COMMAND_ROUTE_MILESTONE_TARGET_MISMATCH') }
            $validatedIssuerLane = [string]$route.ready_issuer_lane
            $validatedIssuerThreadId = [string]$route.ready_issuer_thread_id
            if ([string]$draft.issuer.lane -cne $validatedIssuerLane -or [string]$draft.issuer.thread_id -cne $validatedIssuerThreadId) { $errors.Add('READY_COMMAND_ROUTE_ISSUER_MISMATCH') }
            if ([string]$draft.target.lane -cne 'execution_run' -or [string]$draft.target.thread_id -cne [string]$registry.tasks.execution_run.thread_id) { $errors.Add('READY_COMMAND_ROUTE_EXECUTION_TARGET_MISMATCH') }
            $profileControllerDeclared = ''
            if ($null -ne $draft.PSObject.Properties['program'] -and $null -ne $draft.program.PSObject.Properties['controller']) {
                $profileControllerValue = [string]$draft.program.controller
                $profileControllerDeclared = if ([IO.Path]::IsPathRooted($profileControllerValue)) { [IO.Path]::GetFullPath($profileControllerValue) } else { [IO.Path]::GetFullPath((Join-Path $root $profileControllerValue)) }
            }
            $multiOwnerScopes = @('existing_b_document_arm_background_read','b_document_bridge_background_read','existing_a_fixture_open','single_a_passive_input_settlement','background_native_read','single_background_input','existing_b_fixed_read_command','existing_b_command_marker_clear','existing_b_window_prepare','existing_b_command_buffer_probe','existing_b_command_uia_read','existing_b_command_bootstrap','multi_owner_pinned_pipe_a_bootstrap','multi_owner_binding_comparison','multi_owner_b_startup_bridge_fresh_a','multi_owner_a_only_preparation','multi_owner_test_preparation','multi_owner_read_preflight','multi_owner_non_db_probe','multi_owner_binding_diagnostic','multi_owner_focus_registration','multi_owner_nativeom_diagnostic','multi_owner_a_expression_validation','multi_owner_b_startup_bridge','multi_owner_b_startup_bridge_resume','multi_owner_b_startup_bridge_replacement' | Where-Object { $null -ne $draft.PSObject.Properties[$_] })
            if ($null -ne $draft.PSObject.Properties['representative_command_batch']) { $multiOwnerScopes += 'representative_command_batch' }
            if ($null -ne $draft.PSObject.Properties['serial_business_registration']) { $multiOwnerScopes += 'serial_business_registration' }
            if ($null -ne $draft.PSObject.Properties['dual_business_concurrency']) { $multiOwnerScopes += 'dual_business_concurrency' }
            if ($multiOwnerScopes.Count -gt 1) { $errors.Add('MULTI_OWNER_PROFILE_SCOPES_MIXED') }
            if ($null -ne $draft.PSObject.Properties['dual_business_concurrency']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('DUAL_BUSINESS_WRONG_ROUTE') }
                elseif ($null -eq $route.optional_command_profiles.PSObject.Properties['CAD-AB-DUAL-BUSINESS-CONCURRENCY-V1']) { $errors.Add('DUAL_BUSINESS_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_dual_business_concurrency_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-AB-DUAL-BUSINESS-CONCURRENCY-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['serial_business_registration']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('SERIAL_REGISTRATION_WRONG_ROUTE') }
                elseif ($null -eq $route.optional_command_profiles.PSObject.Properties['CAD-AB-SERIAL-BUSINESS-REGISTRATION-V1']) { $errors.Add('SERIAL_REGISTRATION_NOT_ADMITTED') }
                else {
                    try { & (Join-Path $PSScriptRoot 'assert_cad_business_registration_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-AB-SERIAL-BUSINESS-REGISTRATION-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['representative_command_batch']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('REPRESENTATIVE_BATCH_WRONG_ROUTE') }
                elseif ($null -eq $route.optional_command_profiles.PSObject.Properties['CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1']) { $errors.Add('REPRESENTATIVE_BATCH_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_representative_command_batch_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-AB-REPRESENTATIVE-COMMAND-BATCH-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_document_arm_background_read']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('EXISTING_B_ARM_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-EXISTING-B-DOCUMENT-ARM-BACKGROUND-READ-V1']) { $errors.Add('EXISTING_B_ARM_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_existing_b_arm_background_read_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-EXISTING-B-DOCUMENT-ARM-BACKGROUND-READ-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['b_document_bridge_background_read']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('BDOC_BACKGROUND_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-B-DOCUMENT-BRIDGE-BACKGROUND-READ-V1']) { $errors.Add('BDOC_BACKGROUND_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_b_document_background_read_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-B-DOCUMENT-BRIDGE-BACKGROUND-READ-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_a_fixture_open']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('EXISTING_A_FIXTURE_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-EXISTING-A-READONLY-FIXTURE-OPEN-V1']) { $errors.Add('EXISTING_A_FIXTURE_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_existing_a_fixture_open_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-EXISTING-A-READONLY-FIXTURE-OPEN-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['single_a_passive_input_settlement']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('PASSIVE_A_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties['CAD-SINGLE-A-PASSIVE-INPUT-SETTLEMENT-V1']) { $errors.Add('PASSIVE_A_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_single_a_passive_input_settlement_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-SINGLE-A-PASSIVE-INPUT-SETTLEMENT-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['background_native_read']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('BACKGROUND_NATIVE_READ_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-SINGLE-BACKGROUND-NATIVE-READ-V1']) { $errors.Add('BACKGROUND_NATIVE_READ_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_background_native_read_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-SINGLE-BACKGROUND-NATIVE-READ-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['single_background_input']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('SINGLE_BACKGROUND_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-SINGLE-BACKGROUND-INPUT-V1']) { $errors.Add('SINGLE_BACKGROUND_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_single_background_input_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-SINGLE-BACKGROUND-INPUT-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_fixed_read_command']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_FIXED_COMMAND_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-EXACT-B-FIXED-READ-COMMAND-V1']) { $errors.Add('B_FIXED_COMMAND_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-EXACT-B-FIXED-READ-COMMAND-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_command_marker_clear']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_MARKER_CLEAR_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-EXACT-B-COMMAND-BUFFER-OWN-MARKER-CLEAR-V1']) { $errors.Add('B_MARKER_CLEAR_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-EXACT-B-COMMAND-BUFFER-OWN-MARKER-CLEAR-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_window_prepare']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_WINDOW_PREPARE_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-EXACT-B-WINDOW-PREPARE-V1']) { $errors.Add('B_WINDOW_PREPARE_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-EXACT-B-WINDOW-PREPARE-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_command_buffer_probe']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_COMMAND_BUFFER_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-EXACT-B-COMMAND-BUFFER-PROBE-V1']) { $errors.Add('B_COMMAND_BUFFER_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-EXACT-B-COMMAND-BUFFER-PROBE-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_command_uia_read']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_COMMAND_UIA_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties['CAD-EXACT-B-COMMAND-UIA-READ-V1']) { $errors.Add('B_COMMAND_UIA_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-EXACT-B-COMMAND-UIA-READ-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['existing_b_command_bootstrap']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_INPUT_INSPECTION_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties['CAD-EXISTING-B-PINNED-PIPE-BOOTSTRAP-V1']) { $errors.Add('B_INPUT_INSPECTION_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-EXISTING-B-PINNED-PIPE-BOOTSTRAP-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_a_only_preparation']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('A_ONLY_PREPARATION_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-MULTI-OWNER-A-ONLY-PREPARATION-V2']) { $errors.Add('A_ONLY_PREPARATION_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_test_preparation_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-MULTI-OWNER-A-ONLY-PREPARATION-V2' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_b_startup_bridge_fresh_a']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_FRESH_A_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-MULTI-OWNER-B-STARTUP-BRIDGE-FRESH-A-V6']) { $errors.Add('B_FRESH_A_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-FRESH-A-V6' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_b_startup_bridge_replacement']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_STARTUP_BRIDGE_REPLACEMENT_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-MULTI-OWNER-B-STARTUP-BRIDGE-REPLACEMENT-V3']) { $errors.Add('B_STARTUP_BRIDGE_REPLACEMENT_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-REPLACEMENT-V3' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_b_startup_bridge_resume']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_STARTUP_BRIDGE_RESUME_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-MULTI-OWNER-B-STARTUP-BRIDGE-RESUME-V2']) { $errors.Add('B_STARTUP_BRIDGE_RESUME_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-RESUME-V2' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_b_startup_bridge']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('B_STARTUP_BRIDGE_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-MULTI-OWNER-B-STARTUP-BRIDGE-V1']) { $errors.Add('B_STARTUP_BRIDGE_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-MULTI-OWNER-B-STARTUP-BRIDGE-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_a_expression_validation']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('A_EXPRESSION_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-MULTI-OWNER-A-EXPRESSION-VALIDATION-V2']) { $errors.Add('A_EXPRESSION_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_non_db_probe_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-MULTI-OWNER-A-EXPRESSION-VALIDATION-V2' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_nativeom_diagnostic']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('NATIVEOM_DIAGNOSTIC_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties['CAD-MULTI-OWNER-NATIVEOM-DIAGNOSTIC-V1']) { $errors.Add('NATIVEOM_DIAGNOSTIC_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-MULTI-OWNER-NATIVEOM-DIAGNOSTIC-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_focus_registration']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('FOCUS_REGISTRATION_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties['CAD-MULTI-OWNER-FOCUS-REGISTRATION-DIAGNOSTIC-V1']) { $errors.Add('FOCUS_REGISTRATION_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-MULTI-OWNER-FOCUS-REGISTRATION-DIAGNOSTIC-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_pinned_pipe_a_bootstrap']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('BINDING_DIAG_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-PINNED-PIPE-A-BOOTSTRAP-V1']) { $errors.Add('PINNED_BOOTSTRAP_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-PINNED-PIPE-A-BOOTSTRAP-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_binding_comparison']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('BINDING_DIAG_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties['CAD-MULTI-OWNER-BINDING-COMPARISON-V1']) { $errors.Add('BINDING_COMPARISON_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-MULTI-OWNER-BINDING-COMPARISON-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_binding_diagnostic']) {
                $diagnosticProfileId = if ([string]$draft.multi_owner_binding_diagnostic.profile_id -cin @('CAD-MULTI-OWNER-FRESH-BINDING-DIAGNOSTIC-V3','CAD-MULTI-OWNER-FRESH-BINDING-DIAGNOSTIC-V4')) { [string]$draft.multi_owner_binding_diagnostic.profile_id } else { 'CAD-MULTI-OWNER-BINDING-DIAGNOSTIC-V1' }
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('BINDING_DIAG_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_read_profiles'] -or $null -eq $route.optional_read_profiles.PSObject.Properties[$diagnosticProfileId]) { $errors.Add('BINDING_DIAG_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_binding_diagnostic_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.$diagnosticProfileId -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_non_db_probe']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('NONDB_PROBE_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_command_profiles'] -or $null -eq $route.optional_command_profiles.PSObject.Properties['CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1']) { $errors.Add('NONDB_PROBE_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_non_db_probe_v1.ps1') -Draft $draft -Contract $route.optional_command_profiles.'CAD-MULTI-OWNER-NONDB-COMMAND-PROBE-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_test_preparation']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('MULTI_OWNER_PREPARATION_WRONG_ROUTE') }
                elseif ($null -eq $route.PSObject.Properties['optional_lifecycle_profiles'] -or $null -eq $route.optional_lifecycle_profiles.PSObject.Properties['CAD-MULTI-OWNER-TEST-PREPARATION-V1']) { $errors.Add('MULTI_OWNER_PREPARATION_NOT_ADMITTED') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_test_preparation_v1.ps1') -Draft $draft -Contract $route.optional_lifecycle_profiles.'CAD-MULTI-OWNER-TEST-PREPARATION-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($null -ne $draft.PSObject.Properties['multi_owner_read_preflight']) {
                if ($validatedRouteId -cne 'shared_annotation_interface_read') { $errors.Add('MULTI_OWNER_PROFILE_WRONG_ROUTE') }
                else {
                    try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_cad_multi_owner_read_profile_v1.ps1') -Draft $draft -Contract $route.optional_read_profiles.'CAD-MULTI-OWNER-PURE-GET-PREFLIGHT-V1' -Root $root | Out-Null }
                    catch { $errors.Add($_.Exception.Message) }
                }
            } elseif ($profileControllerDeclared.StartsWith((Join-Path $root 'reports/cad_multi_window_interface_research')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
                $errors.Add('MULTI_OWNER_PROFILE_SCOPE_REQUIRED')
            }
            if ($validatedRouteId -ceq 'sheet_layout_baseboard_extract') {
                try { & (Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/assert_sheet_layout_baseboard_extract_scope_v1.ps1') -Draft $draft -Contract $route.baseboard_extract_contract | Out-Null }
                catch { $errors.Add($_.Exception.Message) }
            }
            if ($validatedRouteId -ceq 'sheet_layout_candidate_write') {
                $contract = $route.candidate_write_contract
                $writeScopeProperty = $draft.PSObject.Properties['layout_write_scope']
                if ($null -eq $writeScopeProperty) { $errors.Add('READY_LAYOUT_WRITE_SCOPE_MISSING') }
                else {
                    $writeScope = $writeScopeProperty.Value
                    # Plan-specific additive admission; retain the legacy contract unchanged.
                    $additionalContracts = $route.PSObject.Properties['additional_candidate_write_contracts']
                    if ($null -ne $additionalContracts) {
                        $matchedContracts = @($additionalContracts.Value | Where-Object { [string]$_.id -ceq [string]$writeScope.contract_id })
                        if ($matchedContracts.Count -gt 1) { throw 'READY_LAYOUT_WRITE_CONTRACT_NOT_UNIQUE' }
                        if ($matchedContracts.Count -eq 1) { $contract = $matchedContracts[0] }
                    }
                    if ([string]$writeScope.contract_id -cne [string]$contract.id) { $errors.Add('READY_LAYOUT_WRITE_CONTRACT_MISMATCH') }
                    $labelRestore = $null -ne $writeScope.PSObject.Properties['north_label_default_restore']
                    if ($labelRestore -and $null -eq $contract.PSObject.Properties['north_label_default_restore_extension']) { throw 'READY_LAYOUT_LABEL_RESTORE_NOT_ADMITTED' }
                    $protectionContract = if ($labelRestore) { $contract.north_label_default_restore_extension } else { $contract }
                    if ($labelRestore -and $null -ne $writeScope.north_label_default_restore.PSObject.Properties['stage'] -and [string]$writeScope.north_label_default_restore.stage -ceq 'CURRENT_RAM_CHECKPOINT_ONLY') { $protectionContract = $contract.north_label_default_restore_extension.checkpoint_only }
                    foreach ($field in @($protectionContract.required_true)) {
                        $property = $writeScope.PSObject.Properties[[string]$field]
                        if ($null -eq $property -or $property.Value -isnot [bool] -or $property.Value -ne $true) { $errors.Add("READY_LAYOUT_WRITE_PROTECTION_MISSING:$field") }
                    }
                    foreach ($field in @($protectionContract.required_false)) {
                        $property = $writeScope.PSObject.Properties[[string]$field]
                        if ($null -eq $property -or $property.Value -isnot [bool] -or $property.Value -ne $false) { $errors.Add("READY_LAYOUT_WRITE_FORBIDDEN:$field") }
                    }
                    if ([string]$writeScope.source_document -cnotin @($contract.allowed_source_documents)) { $errors.Add('READY_LAYOUT_WRITE_SOURCE_NOT_ADMITTED') }
                    $actions = @($writeScope.allowed_actions)
                    if ($actions.Count -eq 0 -or @($actions | Select-Object -Unique).Count -ne $actions.Count) { $errors.Add('READY_LAYOUT_WRITE_ACTION_SET_INVALID') }
                    foreach ($action in $actions) {
                        if ([string]$action -cnotin @($contract.allowed_actions)) { $errors.Add("READY_LAYOUT_WRITE_ACTION_NOT_ADMITTED:$action") }
                    }
                    try {
                        if ($labelRestore) {
                            & (Join-Path $root $contract.north_label_default_restore_extension.validator) -Scope $writeScope -Contract $contract.north_label_default_restore_extension -Root $root -Draft $draft | Out-Null
                        } elseif ('restore_bound_existing_native_north_label_default_grip2' -cin $actions) {
                            throw 'READY_LAYOUT_LABEL_RESTORE_SCOPE_REQUIRED'
                        } elseif ($null -ne $contract.PSObject.Properties['reviewed_candidate_repair']) {
                            & (Join-Path $root $contract.reviewed_candidate_repair.validator) -Scope $writeScope -Contract $contract -Root $root | Out-Null
                        } else {
                        $planPath = [IO.Path]::GetFullPath((Join-Path $root ([string]$writeScope.layout_plan_path)))
                        $admittedPlanPath = [IO.Path]::GetFullPath((Join-Path $root ([string]$contract.admitted_plan_path)))
                        $scaleVariant = $null
                        $admittedPlanHash = [string]$contract.admitted_plan_sha256
                        if ($null -ne $writeScope.PSObject.Properties['requested_scale_validation']) {
                            if ($null -eq $contract.PSObject.Properties['requested_scale_extension']) { throw 'READY_LAYOUT_SCALE_NOT_ADMITTED' }
                            $variants = @($contract.requested_scale_extension.admitted_plan_variants | Where-Object { [IO.Path]::GetFullPath((Join-Path $root ([string]$_.path))) -ieq $planPath })
                            if ($variants.Count -ne 1) { throw 'READY_LAYOUT_SCALE_PLAN_NOT_ADMITTED' }
                            $scaleVariant = $variants[0]; $admittedPlanPath = $planPath; $admittedPlanHash = [string]$scaleVariant.sha256
                        } elseif ('set_new_native_title_ScaleText' -cin $actions -or $null -ne $writeScope.PSObject.Properties['requested_scale_native_north'] -or @($actions|Where-Object{$_ -cin @('clone_bound_same_project_native_paper_north','set_new_native_north_rotation_and_label_grip2','create_new_native_paper_deviation_angle','create_new_paper_north_reference_rays')}).Count) { throw 'READY_LAYOUT_SCALE_SCOPE_REQUIRED' }
                        if (-not [string]::Equals($planPath, $admittedPlanPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'READY_LAYOUT_WRITE_PLAN_PATH_NOT_ADMITTED' }
                        if ([string]$writeScope.layout_plan_sha256 -cne $admittedPlanHash -or (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -cne $admittedPlanHash) { throw 'READY_LAYOUT_WRITE_PLAN_HASH_MISMATCH' }
                        $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        $documents = @($plan.output_documents | Where-Object { [string]$_.source -ceq [string]$writeScope.source_document })
                        if ($documents.Count -ne 1) { throw 'READY_LAYOUT_WRITE_PLAN_SOURCE_NOT_UNIQUE' }
                        $sourcePath = [IO.Path]::GetFullPath([string]$documents[0].base_dwg_path)
                        if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne [string]$documents[0].base_dwg_sha256) { throw 'READY_LAYOUT_WRITE_SOURCE_HASH_MISMATCH' }
                        $copyPaths = @()
                        foreach ($field in @('working_copy_path', 'save_copy_path')) {
                            if ([string]::IsNullOrWhiteSpace([string]$writeScope.$field)) { throw "READY_LAYOUT_WRITE_COPY_PATH_MISSING:$field" }
                            $copyPathValue = [string]$writeScope.$field
                            $copyPath = if ([IO.Path]::IsPathRooted($copyPathValue)) { [IO.Path]::GetFullPath($copyPathValue) } else { [IO.Path]::GetFullPath((Join-Path $root $copyPathValue)) }
                            if (-not $copyPath.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($copyPath) -ine '.dwg' -or [string]::Equals($copyPath, $sourcePath, [StringComparison]::OrdinalIgnoreCase)) { throw "READY_LAYOUT_WRITE_COPY_PATH_UNSAFE:$field" }
                            if ($null -ne $contract.PSObject.Properties['model_helper_extension']) {
                                foreach ($protectedDoc in @($plan.output_documents)) {
                                    if ([string]::Equals($copyPath, [IO.Path]::GetFullPath([string]$protectedDoc.base_dwg_path), [StringComparison]::OrdinalIgnoreCase)) { throw "READY_LAYOUT_WRITE_COPY_PATH_UNSAFE:$field" }
                                }
                            }
                            $copyPaths += $copyPath
                        }
                        if ([string]::Equals($copyPaths[0], $copyPaths[1], [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $copyPaths[1])) { throw 'READY_LAYOUT_WRITE_SAVE_COPY_NOT_UNIQUE' }
                        if (@($documents[0].planned_layouts).Count -eq 0 -or @($documents[0].planned_layouts | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) -or [string]$_ -ieq 'Model' }).Count -ne 0) { throw 'READY_LAYOUT_WRITE_NEW_LAYOUT_NAME_INVALID' }
                        $extension = $contract.standard_frame_title_extension
                        $titleSourceRole = [string]$writeScope.source_document
                        if ($null -ne $extension.PSObject.Properties['native_titles_source_document']) { $titleSourceRole = [string]$extension.native_titles_source_document }
                        $helperExtensionProperty = $contract.PSObject.Properties['model_helper_extension']
                        if ($null -ne $helperExtensionProperty) {
                            $helper = $helperExtensionProperty.Value
                            $helperScopeProperty = $writeScope.PSObject.Properties['model_subdivision_helpers']
                            if ($null -eq $helperScopeProperty -or [string]$helper.action -cnotin $actions) { throw 'READY_LAYOUT_HELPER_SCOPE_MISSING' }
                            $helperScope = $helperScopeProperty.Value
                            $expectedHelperLayer = if ($null -ne $scaleVariant) { [string]$scaleVariant.helper_layer } else { [string]$helper.layer }
                            if ([string]$helperScope.contract_id -cne [string]$helper.id -or [string]$helperScope.layer -cne $expectedHelperLayer) { throw 'READY_LAYOUT_HELPER_IDENTITY_MISMATCH' }
                            foreach ($field in @($helper.required_true)) {
                                $p = $helperScope.PSObject.Properties[[string]$field]
                                if ($null -eq $p -or $p.Value -isnot [bool] -or $p.Value -ne $true) { throw "READY_LAYOUT_HELPER_PROTECTION_MISSING:$field" }
                            }
                            foreach ($field in @($helper.required_false)) {
                                $p = $helperScope.PSObject.Properties[[string]$field]
                                if ($null -eq $p -or $p.Value -isnot [bool] -or $p.Value -ne $false) { throw "READY_LAYOUT_HELPER_FORBIDDEN:$field" }
                            }
                            $pageKeys = @($documents[0].page_ids)
                            $selectedPages = @($plan.selected.pages)
                            if ($pageKeys.Count -eq 0 -or $selectedPages.Count -ne $pageKeys.Count -or @($selectedPages | Where-Object { [string]$_.source -cne [string]$writeScope.source_document -or [string]$_.code -cnotin $pageKeys }).Count -ne 0 -or @($selectedPages.code | Select-Object -Unique).Count -ne $pageKeys.Count) { throw 'READY_LAYOUT_HELPER_PLAN_PAGES_INVALID' }
                            foreach ($field in @('rectangle_count','development_index_count')) {
                                $p = $helperScope.PSObject.Properties[$field]
                                if ($null -eq $p -or $p.Value -isnot [long] -and $p.Value -isnot [int] -or $p.Value -ne $pageKeys.Count) { throw "READY_LAYOUT_HELPER_COUNT_MISMATCH:$field" }
                            }
                        } elseif ($null -ne $writeScope.PSObject.Properties['model_subdivision_helpers']) { throw 'READY_LAYOUT_HELPER_NOT_ADMITTED' }
                        $cloneScopeProperty = $writeScope.PSObject.Properties['standard_frame_title_clone']
                        if ($null -ne $helperExtensionProperty -and (@($extension.actions | Where-Object { $_ -cnotin $actions }).Count -ne 0)) { throw 'READY_LAYOUT_CLONE_REQUIRED_ACTION_MISSING' }
                        if (@($actions | Where-Object { $_ -cin @($extension.actions) }).Count -gt 0 -or $null -ne $cloneScopeProperty) {
                            if ($null -eq $cloneScopeProperty) { throw 'READY_LAYOUT_CLONE_SCOPE_MISSING' }
                            $cloneScope = $cloneScopeProperty.Value
                            if ([string]$cloneScope.contract_id -cne [string]$extension.id) { throw 'READY_LAYOUT_CLONE_CONTRACT_MISMATCH' }
                            foreach ($field in @($extension.required_true)) {
                                $property = $cloneScope.PSObject.Properties[[string]$field]
                                if ($null -eq $property -or $property.Value -isnot [bool] -or $property.Value -ne $true) { throw "READY_LAYOUT_CLONE_PROTECTION_MISSING:$field" }
                            }
                            if ([string]$cloneScope.target_layout -cnotin @($documents[0].planned_layouts)) { throw 'READY_LAYOUT_CLONE_TARGET_LAYOUT_NOT_ADMITTED' }
                            if ([string]$cloneScope.frame_source_document -cne [string]$extension.frame_source_document -or [string]$cloneScope.frame_block_name -cne [string]$extension.frame_block_name -or [string]$cloneScope.native_titles_source_document -cne $titleSourceRole) { throw 'READY_LAYOUT_CLONE_SOURCE_ROLE_INVALID' }
                            $frameDocuments = @($plan.output_documents | Where-Object { [string]$_.source -ceq [string]$extension.frame_source_document })
                            if ($frameDocuments.Count -ne 1) { throw 'READY_LAYOUT_CLONE_FRAME_SOURCE_NOT_UNIQUE' }
                            $frameSourcePath = [IO.Path]::GetFullPath([string]$frameDocuments[0].base_dwg_path)
                            if (-not [string]::Equals([IO.Path]::GetFullPath([string]$cloneScope.frame_source_path), $frameSourcePath, [StringComparison]::OrdinalIgnoreCase) -or [string]$cloneScope.frame_source_sha256 -cne [string]$frameDocuments[0].base_dwg_sha256 -or (Get-FileHash -LiteralPath $frameSourcePath -Algorithm SHA256).Hash -cne [string]$frameDocuments[0].base_dwg_sha256) { throw 'READY_LAYOUT_CLONE_FRAME_SOURCE_HASH_OR_PATH_MISMATCH' }
                            if ($null -ne $extension.PSObject.Properties['native_title_change_fields']) {
                                $fields = @($cloneScope.native_title_change_fields)
                                $expectedTitleFields = @(if ($null -ne $scaleVariant) { $contract.requested_scale_extension.native_title_change_fields } else { $extension.native_title_change_fields })
                                if ($fields.Count -ne $expectedTitleFields.Count -or @($fields | Select-Object -Unique).Count -ne $fields.Count -or @($fields | Where-Object { $_ -cnotin $expectedTitleFields }).Count -ne 0) { throw 'READY_LAYOUT_CLONE_TITLE_CHANGE_FIELDS_INVALID' }
                            }
                            foreach ($prefix in @('frame_evidence', 'native_titles_evidence', 'construction_fields_evidence', 'clone_manifest')) {
                                $pathField = $prefix + '_path'; $hashField = $prefix + '_sha256'
                                if ($null -eq $cloneScope.PSObject.Properties[$pathField] -or $null -eq $cloneScope.PSObject.Properties[$hashField]) { throw "READY_LAYOUT_CLONE_EVIDENCE_BINDING_MISSING:$prefix" }
                                if ([string]::IsNullOrWhiteSpace([string]$cloneScope.$pathField) -or [string]$cloneScope.$hashField -cnotmatch '^[A-F0-9]{64}$') { throw "READY_LAYOUT_CLONE_EVIDENCE_BINDING_MISSING:$prefix" }
                                $boundPath = [IO.Path]::GetFullPath((Join-Path $root ([string]$cloneScope.$pathField)))
                                if (-not $boundPath.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "READY_LAYOUT_CLONE_EVIDENCE_OUTSIDE_PROJECT:$prefix" }
                                if ((Get-FileHash -LiteralPath $boundPath -Algorithm SHA256).Hash -cne [string]$cloneScope.$hashField) { throw "READY_LAYOUT_CLONE_EVIDENCE_HASH_MISMATCH:$prefix" }
                                if ($prefix -ceq 'frame_evidence' -and (-not [string]::Equals($boundPath, [IO.Path]::GetFullPath((Join-Path $root ([string]$extension.frame_evidence_path))), [StringComparison]::OrdinalIgnoreCase) -or [string]$cloneScope.$hashField -cne [string]$extension.frame_evidence_sha256)) { throw 'READY_LAYOUT_CLONE_FRAME_EVIDENCE_NOT_ADMITTED' }
                            }
                            $manifest = Get-Content -LiteralPath (Join-Path $root ([string]$cloneScope.clone_manifest_path)) -Raw -Encoding UTF8 | ConvertFrom-Json
                            if ($null -ne $scaleVariant) { & (Join-Path $root $contract.requested_scale_extension.validator) -Scope $writeScope -Plan $plan -Variant $scaleVariant -CloneManifest $manifest -Root $root | Out-Null }
                            if ([string]$manifest.target_layout -cne [string]$cloneScope.target_layout) { throw 'READY_LAYOUT_CLONE_MANIFEST_TARGET_MISMATCH' }
                            $cloneRoots = @($manifest.clone_roots)
                            if ($cloneRoots.Count -eq 0) { throw 'READY_LAYOUT_CLONE_ROOTS_EMPTY' }
                            $rootKeys = @($cloneRoots | ForEach-Object { [string]$_.source_document + ':' + [string]$_.source_handle })
                            if (@($rootKeys | Select-Object -Unique).Count -ne $rootKeys.Count) { throw 'READY_LAYOUT_CLONE_ROOTS_DUPLICATED' }
                            foreach ($cloneRoot in $cloneRoots) {
                                if ([string]$cloneRoot.kind -cnotin @($extension.allowed_clone_kinds)) { throw 'READY_LAYOUT_CLONE_ROOT_KIND_FORBIDDEN' }
                                if ([string]::IsNullOrWhiteSpace([string]$cloneRoot.source_layout) -or [string]$cloneRoot.source_handle -cnotmatch '^[A-Fa-f0-9]+$' -or [string]$cloneRoot.source_layout -ieq 'Model') { throw 'READY_LAYOUT_CLONE_ROOT_IDENTITY_INVALID' }
                                if ($cloneRoot.kind -ceq 'standard_frame') {
                                    if ('clone_standard_frame_block' -cnotin $actions) { throw 'READY_LAYOUT_CLONE_ROOT_ACTION_MISSING' }
                                    if ([string]$cloneRoot.source_document -cne [string]$extension.frame_source_document -or [string]$cloneRoot.native_type -cne 'AcDbBlockReference' -or [string]$cloneRoot.definition_name -cne [string]$extension.frame_block_name) { throw 'READY_LAYOUT_CLONE_FRAME_ROOT_INVALID' }
                                    if ($null -ne $extension.PSObject.Properties['frame_source_handle'] -and ([string]$cloneRoot.source_handle -ine [string]$extension.frame_source_handle -or [string]$cloneRoot.source_layout -cne [string]$extension.frame_source_layout)) { throw 'READY_LAYOUT_CLONE_FRAME_ROOT_NOT_BOUND_TEMPLATE' }
                                } else {
                                    if ('clone_construction_native_drawing_names' -cnotin $actions) { throw 'READY_LAYOUT_CLONE_ROOT_ACTION_MISSING' }
                                    if ([string]$cloneRoot.source_document -cne $titleSourceRole -or [string]$cloneRoot.native_type -cne 'TDbDrawingName' -or [string]$cloneRoot.target_sheet_key -cnotin @($documents[0].page_ids)) { throw 'READY_LAYOUT_CLONE_TITLE_ROOT_INVALID' }
                                    if ($null -ne $extension.PSObject.Properties['native_title_source_handle'] -and ([string]$cloneRoot.source_handle -ine [string]$extension.native_title_source_handle -or [string]$cloneRoot.source_layout -cne [string]$extension.frame_source_layout)) { throw 'READY_LAYOUT_CLONE_TITLE_ROOT_NOT_BOUND_TEMPLATE' }
                                }
                            }
                            if (@($actions | Where-Object { $_ -cin @('clone_standard_frame_block','clone_required_frame_dependencies') }).Count -gt 0 -and @($cloneRoots | Where-Object { $_.kind -ceq 'standard_frame' }).Count -eq 0) { throw 'READY_LAYOUT_CLONE_FRAME_ROOT_MISSING' }
                            if (@($actions | Where-Object { $_ -ceq 'clone_construction_native_drawing_names' }).Count -gt 0 -and @($cloneRoots | Where-Object { $_.kind -ceq 'native_drawing_name' }).Count -eq 0) { throw 'READY_LAYOUT_CLONE_TITLE_ROOT_MISSING' }
                        }
                        }
                    } catch { $errors.Add($_.Exception.Message) }
                }
            }
        }
    }
}

if ($errors.Count) { throw ('CAD_COMMAND_RESEARCH_ROUTING_FAILED:' + ($errors -join '|')) }
$result = [pscustomobject]@{
    status = 'PASS'
    route_count = @($routing.routes.PSObject.Properties).Count
    validated_route_id = $validatedRouteId
    validated_issuer_lane = $validatedIssuerLane
    validated_issuer_thread_id = $validatedIssuerThreadId
    project_control_thread_id = [string]$routing.project_control.thread_id
    execution_thread_id = [string]$routing.execution.thread_id
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
