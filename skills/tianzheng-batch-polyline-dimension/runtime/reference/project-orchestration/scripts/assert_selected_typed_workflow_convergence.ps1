$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$entry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_workflow.ps1'
$core = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_batch.ps1'
$developmentController = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_polyline_controller.ps1'
$layoutEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_layout_stage.ps1'
$loop = Join-Path $projectRoot '.project-reasoning\PROJECT_LOOP.md'
$phase = Join-Path $projectRoot 'knowledge\phase_plans\P3_NATIVE_DIMENSION_RELAYOUT.md'
$registryPath = Join-Path $projectRoot 'config\cad_automation_component_packages.json'
$indexPath = Join-Path $projectRoot 'config\project_execution_index.json'
$captureEntry = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1'
$captureBackend = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))) 'scripts/cad_capture_compat.ps1'
$recoveryPath = Join-Path $projectRoot 'config\current_recovery_contract.json'

foreach ($path in @($entry,$core,$developmentController,$layoutEntry,$loop,$phase,$registryPath,$indexPath,$captureEntry,$captureBackend,$recoveryPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "CONVERGENCE_FILE_MISSING:$path" }
}

$text = Get-Content -LiteralPath $entry -Raw -Encoding UTF8
$coreText = Get-Content -LiteralPath $core -Raw -Encoding UTF8
$developmentControllerText = Get-Content -LiteralPath $developmentController -Raw -Encoding UTF8
$layoutText = Get-Content -LiteralPath $layoutEntry -Raw -Encoding UTF8
$captureEntryText = Get-Content -LiteralPath $captureEntry -Raw -Encoding UTF8
$captureBackendText = Get-Content -LiteralPath $captureBackend -Raw -Encoding UTF8
if (([regex]::Matches($text, '& \$core')).Count -ne 2) { throw 'WORKFLOW_CORE_CALL_COUNT_CHANGED_EXPECT_PREPARE_AND_EXECUTE_ONLY' }
if ($text -notmatch 'GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED' -or $text -notmatch 'INVALID_UNSAVED_CANDIDATE_DO_NOT_SAVE') { throw 'WORKFLOW_MACHINE_GATE_MISSING' }
foreach ($layoutToken in @('quantified common distance band','preserving')) {
    if ($text -notmatch [regex]::Escape($layoutToken)) { throw "WORKFLOW_BOUND_LAYOUT_ADAPTER_GATE_MISSING:$layoutToken" }
}
foreach ($layoutToken in @('quantified_common_band_grip0_plan','PRESERVE_NATIVE_GENERATED_STATE__DISTANCE_ONLY','text_position_mutation_count','tmirdim_invocation_count','grip4_move_count')) {
    if ($layoutText -notmatch [regex]::Escape($layoutToken)) { throw "WORKFLOW_LAYOUT_STAGE_TOKEN_MISSING:$layoutToken" }
}
foreach ($forbiddenLayoutToken in @('-Action TMIRDIM_BATCH','failed_subset_along_arc_grip4_plan','residual_contiguous_cluster_grip0_plan','last_resort_failed_subset_grip4_plan','plan_native_angle_text_relief.py','plan_native_failed_cluster_band.py')) {
    if ($layoutText -match [regex]::Escape($forbiddenLayoutToken)) { throw "WORKFLOW_DISTANCE_ONLY_LAYOUT_FORBIDDEN_TOKEN:$forbiddenLayoutToken" }
}
foreach ($controllerText in @($coreText,$developmentControllerText)) {
    if ($controllerText -match 'FOUR_DIRECTION_NATIVE_TEXT_STATE_ALIGNMENT') { throw 'WORKFLOW_STALE_FOUR_DIRECTION_NEXT_GATE_REINTRODUCED' }
    if ($controllerText -notmatch 'PRESERVE_NATIVE_TEXT__DISTANCE_ONLY') { throw 'WORKFLOW_DISTANCE_ONLY_NEXT_GATE_MISSING' }
}
if ($text -notmatch 'invoke_selected_typed_dimension_layout_stage\.ps1' -or $text -notmatch 'final_layout_receipt') { throw 'WORKFLOW_LAYOUT_STAGE_NOT_COMPOSED' }
if ($text -notmatch 'invoke_owned_cad_visual_capture\.ps1' -or $text -notmatch 'foreground_or_input_used = \$false') { throw 'WORKFLOW_BACKGROUND_CAPTURE_POLICY_MISSING' }
if ($text -match 'computer-use|SetForegroundWindow|SendKeys') { throw 'WORKFLOW_FOREGROUND_OR_INPUT_ROUTE_FORBIDDEN' }
foreach ($forbiddenCaptureToken in @('SetForegroundWindow','SetWindowPos','Invoke-ScreenCopyCapture','CopyFromScreen')) {
    if ($captureEntryText -match [regex]::Escape($forbiddenCaptureToken) -or $captureBackendText -match [regex]::Escape($forbiddenCaptureToken)) {
        throw "WORKFLOW_CAPTURE_WINDOW_MUTATION_OR_FOREGROUND_FALLBACK:$forbiddenCaptureToken"
    }
}
foreach ($requiredCaptureToken in @('Backend PrintWindow','AllowNonActivatingRestore','PrepareOnly','-Action REGEN','full_frame_prepare_before_regen = $true','regen_before_capture = $true','window_nonactivating_restore_used','foreground_screen_copy_used = $false')) {
    if ($captureEntryText -notmatch [regex]::Escape($requiredCaptureToken)) { throw "WORKFLOW_IMMUTABLE_BACKGROUND_CAPTURE_TOKEN_MISSING:$requiredCaptureToken" }
}
$recovery = Get-Content -LiteralPath $recoveryPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([bool]$recovery.screenshot_contract.window_activation_for_capture -or
    [bool]$recovery.screenshot_contract.window_show_or_restore_for_capture -or
    [bool]$recovery.screenshot_contract.foreground_screen_copy_fallback_allowed) {
    throw 'WORKFLOW_RECOVERY_CONTRACT_ALLOWS_CAPTURE_WINDOW_MUTATION'
}
if ([string]$recovery.screenshot_contract.development_purpose -cne 'one_user_viewable_actual_CAD_frame_only__not_a_machine_acceptance_gate_for_generation_mapping_or_layout' -or
    [int]$recovery.screenshot_contract.development_capture_count -ne 1 -or
    [string]$recovery.screenshot_contract.development_framing_policy -cne 'use_the_existing_controller_view__no_extra_ZE_ZA_REGEN_ROI_OCR_semantic_pixel_gate_or_second_capture') {
    throw 'WORKFLOW_RECOVERY_DEVELOPMENT_SCREENSHOT_POLICY_MISSING'
}
if ([bool]$recovery.screenshot_contract.window_nonactivating_restore_for_minimized_owned_window -or
    [bool]$recovery.screenshot_contract.regen_after_full_frame_prepare_before_capture -or
    [bool]$recovery.screenshot_contract.quality_valid_required) {
    throw 'WORKFLOW_RECOVERY_DEVELOPMENT_SCREENSHOT_STILL_OVER_GOVERNED'
}
if ([string]$recovery.screenshot_contract.unavailable_terminal -cne 'REPORT_SCREENSHOT_UNAVAILABLE_WITHOUT_RETRY_OR_BUSINESS_ROLLBACK') {
    throw 'WORKFLOW_DEVELOPMENT_SCREENSHOT_FAILURE_TERMINAL_DRIFT'
}
foreach ($requiredToken in @(
    'extract_cad_canvas_roi.py',
    'audit_annotation_screenshot_layout.py',
    'SCREENSHOT_RASTER_QA_FAILED',
    'CODEX_VISUAL_REVIEW_REQUIRED',
    'ONLY_PASS_MAY_REQUEST_HUMAN_APPROVAL'
)) {
    if ($text -notmatch [regex]::Escape($requiredToken)) { throw "WORKFLOW_VISUAL_GATE_TOKEN_MISSING:$requiredToken" }
}
if ($text -match '\$state\.status\s*=\s*''HUMAN_REVIEW_REQUIRED''') { throw 'WORKFLOW_CAN_BYPASS_CODEX_VISUAL_REVIEW' }

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$component = @($registry.components | Where-Object { [string]$_.id -ceq 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' })
if ($component.Count -ne 1) { throw 'WORKFLOW_COMPONENT_NOT_UNIQUE' }
$captureComponent = @($registry.components | Where-Object { [string]$_.id -ceq 'CAD-UI-BACKGROUND-CAPTURE-V1' })
if ($captureComponent.Count -ne 1) { throw 'WORKFLOW_CAPTURE_COMPONENT_NOT_UNIQUE' }
if ([string]$captureComponent[0].entry -cne 'reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1') { throw 'WORKFLOW_CAPTURE_COMPONENT_ENTRY_INVALID' }
if ([string]$captureComponent[0].backend_entry -cne 'scripts/cad_capture_compat.ps1') { throw 'WORKFLOW_CAPTURE_COMPONENT_BACKEND_INVALID' }
if ([string]$captureComponent[0].regen_action_entry -cne 'reference/project-orchestration/scripts/invoke_owned_tianzheng_whitelist_action.ps1') { throw 'WORKFLOW_CAPTURE_COMPONENT_REGEN_ACTION_INVALID' }
if ([string]$captureComponent[0].entry_sha256 -cne (Get-FileHash -LiteralPath $captureEntry -Algorithm SHA256).Hash) { throw 'WORKFLOW_CAPTURE_COMPONENT_ENTRY_HASH_DRIFT' }
if ([string]$captureComponent[0].backend_entry_sha256 -cne (Get-FileHash -LiteralPath $captureBackend -Algorithm SHA256).Hash) { throw 'WORKFLOW_CAPTURE_COMPONENT_BACKEND_HASH_DRIFT' }
if ([string]$captureComponent[0].regen_action_entry_sha256 -cne (Get-FileHash -LiteralPath (Join-Path $projectRoot ([string]$captureComponent[0].regen_action_entry)) -Algorithm SHA256).Hash) { throw 'WORKFLOW_CAPTURE_COMPONENT_REGEN_ACTION_HASH_DRIFT' }
if ([string]$component[0].entry -cne 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_workflow.ps1') { throw 'WORKFLOW_COMPONENT_ENTRY_NOT_CONVERGED' }
if ([string]$component[0].core_entry -cne 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_batch.ps1') { throw 'WORKFLOW_COMPONENT_CORE_NOT_DECLARED' }
if ([string]$component[0].final_layout_entry -cne 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_layout_stage.ps1') { throw 'WORKFLOW_COMPONENT_LAYOUT_ENTRY_NOT_DECLARED' }
if ([string]$component[0].entry_sha256 -cne (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash) { throw 'WORKFLOW_COMPONENT_ENTRY_HASH_DRIFT' }
if ([string]$component[0].core_entry_sha256 -cne (Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash) { throw 'WORKFLOW_COMPONENT_CORE_HASH_DRIFT' }
if ([string]$component[0].final_layout_entry_sha256 -cne (Get-FileHash -LiteralPath $layoutEntry -Algorithm SHA256).Hash) { throw 'WORKFLOW_COMPONENT_LAYOUT_ENTRY_HASH_DRIFT' }
if ('TMIRDIM_BATCH' -in @($component[0].allowed_actions)) { throw 'WORKFLOW_COMPONENT_DEFAULT_TMIRDIM_STILL_ALLOWED' }
if ('CAD-UI-BACKGROUND-CAPTURE-V1' -notin @($component[0].dependencies)) { throw 'WORKFLOW_CAPTURE_DEPENDENCY_MISSING' }
if ('CAD-DIM-VISUAL-QA-V1' -notin @($component[0].dependencies)) { throw 'WORKFLOW_RASTER_QA_DEPENDENCY_MISSING' }
foreach ($gate in @('SCREENSHOT_RASTER_QA','CODEX_VISUAL_REVIEW','HUMAN_VISUAL_APPROVAL')) {
    if ($gate -notin @($component[0].required_acceptance_gate_ids)) { throw "WORKFLOW_VISUAL_ACCEPTANCE_GATE_MISSING:$gate" }
}

$loopText = Get-Content -LiteralPath $loop -Raw -Encoding UTF8
$phaseText = Get-Content -LiteralPath $phase -Raw -Encoding UTF8
if ($loopText -notmatch 'invoke_selected_typed_dimension_workflow\.ps1' -or $phaseText -notmatch 'invoke_selected_typed_dimension_workflow\.ps1') { throw 'WORKFLOW_NOT_IN_PROJECT_HOT_CONTRACTS' }
if ($loopText -match '当前唯一天正进程为\d+') { throw 'LOOP_CONTAINS_STALE_PROCESS_ID' }

$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ('reference/project-orchestration/scripts/invoke_selected_typed_dimension_workflow.ps1' -notin @($index.execution_authority_hash_order)) { throw 'WORKFLOW_NOT_IN_AUTHORITY_HASH_ORDER' }

[pscustomobject]@{
    status = 'PASS'
    entry_sha256 = (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash
    core_sha256 = (Get-FileHash -LiteralPath $core -Algorithm SHA256).Hash
    component_version = [string]$component[0].version
    background_capture_dependency = $true
    canvas_roi_and_raster_gate = $true
    codex_before_human_gate = $true
    stale_process_id_removed = $true
}
