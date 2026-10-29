param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$architecturePath = Join-Path $projectRoot 'config\cad_development_architecture.json'
$componentPath = Join-Path $projectRoot 'config\cad_automation_component_packages.json'
$loopPath = Join-Path $projectRoot 'config\cad_project_loop.json'
$controllerPath = Join-Path $projectRoot 'scripts\invoke_selected_typed_dimension_polyline_controller.ps1'
$layoutStagePath = Join-Path $projectRoot 'scripts\invoke_selected_typed_dimension_layout_stage.ps1'
$tipPlannerPath = Join-Path $projectRoot 'scripts\plan_native_angle_grip0_beauty.py'
$formulaPath = Join-Path $projectRoot 'config\annotation_vector_layout_formula_v2.json'
$recoveryPath = Join-Path $projectRoot 'config\current_recovery_contract.json'
$derivedPath = Join-Path $projectRoot 'config\derived_project_state.json'
$indexPath = Join-Path $projectRoot 'config\project_execution_index.json'
$contractPath = Join-Path $projectRoot '.project-reasoning\PROJECT_LOOP.md'
$phasePlanPath = Join-Path $projectRoot 'knowledge\phase_plans\P3_NATIVE_DIMENSION_RELAYOUT.md'
$errors = [Collections.Generic.List[string]]::new()

foreach ($path in @($architecturePath,$componentPath,$loopPath,$controllerPath,$layoutStagePath,$tipPlannerPath,$formulaPath,$recoveryPath,$derivedPath,$indexPath,$contractPath,$phasePlanPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("LAYOUT_COMPOSITION_AUTHORITY_MISSING:$path") }
}
if ($errors.Count -gt 0) { throw ('TYPED_LAYOUT_COMPOSITION_ASSERTION_FAILED:' + ($errors -join '|')) }

function Read-PartitionedGovernanceText([string]$PrimaryRelative, $Index, [string]$Code) {
    $parts = [Collections.Generic.List[string]]::new()
    $primaryPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $PrimaryRelative))
    $parts.Add((Get-Content -LiteralPath $primaryPath -Raw -Encoding UTF8))
    $partitionProperty = $Index.PSObject.Properties['context_read_partition']
    if ($null -eq $partitionProperty) { return [string]::Join([Environment]::NewLine, $parts) }
    $warmDocuments = @($partitionProperty.Value.warm_documents)
    if ($warmDocuments.Count -eq 0) { $errors.Add("${Code}_WARM_DOCUMENTS_EMPTY"); return [string]::Join([Environment]::NewLine, $parts) }
    $fingerprinted = @($Index.execution_authority_hash_order | ForEach-Object { ([string]$_).Replace('\','/') })
    foreach ($raw in $warmDocuments) {
        $relative = ([string]$raw).Replace('\','/')
        if ([string]::IsNullOrWhiteSpace($relative)) { $errors.Add("${Code}_WARM_PATH_EMPTY"); continue }
        if ($relative -notin $fingerprinted) { $errors.Add("${Code}_WARM_NOT_FINGERPRINTED:$relative") }
        $path = [IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
        if (-not $path.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { $errors.Add("${Code}_WARM_OUTSIDE_PROJECT:$relative"); continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $errors.Add("${Code}_WARM_MISSING:$relative"); continue }
        $parts.Add((Get-Content -LiteralPath $path -Raw -Encoding UTF8))
    }
    return [string]::Join([Environment]::NewLine, $parts)
}

$architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$registry = Get-Content -LiteralPath $componentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$loop = Get-Content -LiteralPath $loopPath -Raw -Encoding UTF8 | ConvertFrom-Json
$formula = Get-Content -LiteralPath $formulaPath -Raw -Encoding UTF8 | ConvertFrom-Json
$controller = Get-Content -LiteralPath $controllerPath -Raw -Encoding UTF8
$layoutStage = Get-Content -LiteralPath $layoutStagePath -Raw -Encoding UTF8
$tipPlanner = Get-Content -LiteralPath $tipPlannerPath -Raw -Encoding UTF8
$recovery = Get-Content -LiteralPath $recoveryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$derived = Get-Content -LiteralPath $derivedPath -Raw -Encoding UTF8 | ConvertFrom-Json
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$contract = Read-PartitionedGovernanceText '.project-reasoning/PROJECT_LOOP.md' $index 'CANONICAL_LOOP_LAYOUT_GUARD'
$phasePlan = Get-Content -LiteralPath $phasePlanPath -Raw -Encoding UTF8
$typed = @($registry.components | Where-Object { [string]$_.id -ceq 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1' })

if ($typed.Count -ne 1) { $errors.Add('ACTIVE_TYPED_COMPONENT_NOT_UNIQUE') }
else {
    $component = $typed[0]
    if ('CAD-DIM-LAYOUT-V1' -notin @($component.dependencies)) { $errors.Add('ACTIVE_TYPED_COMPONENT_LAYOUT_DEPENDENCY_MISSING') }
    if ('CAD-DIM-ANGLE-FULL-BLUE-LAYOUT-V2' -in @($component.dependencies)) { $errors.Add('ACTIVE_TYPED_COMPONENT_UNPROMOTED_TIP_LAYOUT_DEPENDENCY_PRESENT') }
    if ([string]$component.layout_formula -cne 'config/annotation_vector_layout_formula_v2.json') { $errors.Add('ACTIVE_TYPED_COMPONENT_FORMULA_MISSING') }
    if ([string]$component.final_layout_entry -cne 'reference/project-orchestration/scripts/invoke_selected_typed_dimension_layout_stage.ps1') { $errors.Add('ACTIVE_TYPED_COMPONENT_LAYOUT_ENTRY_MISSING') }
    $tipPlannerProperty = $component.PSObject.Properties['tip_cluster_planner']
    if ($null -ne $tipPlannerProperty -and $null -ne $tipPlannerProperty.Value) { $errors.Add('ACTIVE_TYPED_COMPONENT_UNPROMOTED_TIP_PLANNER_PRESENT') }
    if ([string]$component.development_entry_sha256 -cne (Get-FileHash -LiteralPath $controllerPath -Algorithm SHA256).Hash) { $errors.Add('ACTIVE_TYPED_COMPONENT_CONTROLLER_HASH_STALE') }
    if ([string]$component.final_layout_entry_sha256 -cne (Get-FileHash -LiteralPath $layoutStagePath -Algorithm SHA256).Hash) { $errors.Add('ACTIVE_TYPED_COMPONENT_LAYOUT_HASH_STALE') }
    if ('FINAL_QUANTIFIED_LAYOUT_AUDIT' -notin @($component.required_acceptance_gate_ids)) { $errors.Add('ACTIVE_TYPED_COMPONENT_LAYOUT_ACCEPTANCE_GATE_MISSING') }
    $required = @('PRECHECK_ONCE','EXECUTE_BY_POLYLINE','MONOTONIC_PARTIAL_CONVERGENCE','FINAL_GENERATION_AUDIT_ONCE','FINAL_QUANTIFIED_LAYOUT','VERIFIED_LAYOUT_PROFILE_DISPATCH','NATIVE_TEXT_PRESERVATION_AUDIT','FINAL_LAYOUT_AUDIT_ONCE','VISUAL_EVIDENCE_ONCE','SCREENSHOT_RASTER_QA','CODEX_VISUAL_REVIEW','HUMAN_REVIEW_REQUIRED','E4_E5')
    $actual = @($component.state_machine)
    if (($actual -join '|') -cne ($required -join '|')) { $errors.Add('ACTIVE_TYPED_COMPONENT_STAGE_ORDER_INVALID') }
    if ([string]$component.regression_assertion -cne 'reference/project-orchestration/scripts/assert_typed_dimension_layout_composition.ps1') { $errors.Add('ACTIVE_TYPED_COMPONENT_LAYOUT_ASSERTION_MISSING') }
    foreach ($requiredInput in @('verified_layout_profile_dispatch_receipt','unmatched_special_topology_failed_subset')) {
        if ($requiredInput -notin @($component.final_layout_required_inputs)) { $errors.Add("ACTIVE_TYPED_COMPONENT_INPUT_MISSING:$requiredInput") }
    }
    foreach ($policyToken in @('source_batch_failure_decomposes_to_segments','freeze_successful_segments','retry_failed_segments_only','layout_successful_partial_subset')) {
        if ([string]$component.generation_policy -notmatch [regex]::Escape($policyToken)) { $errors.Add("ACTIVE_TYPED_COMPONENT_MONOTONIC_POLICY_MISSING:$policyToken") }
    }
}

$composition = $architecture.typed_dimension_composition_contract
if ($null -eq $composition) { $errors.Add('ARCHITECTURE_LAYOUT_COMPOSITION_CONTRACT_MISSING') }
else {
    if ([string]$composition.generation_offset_semantics -cne 'per_source_formula_band__per_segment_native_endpoint_state_selects_signed_side__post_generation_grip0_residual_only') { $errors.Add('ARCHITECTURE_GENERATION_OFFSET_BOUNDARY_INVALID') }
    if ([string]$composition.formal_visual_evidence_requires_final_layout_status -cne 'PASS') { $errors.Add('ARCHITECTURE_FORMAL_VISUAL_LAYOUT_GATE_MISSING') }
    if ([string]$composition.human_review_requires_final_layout_status -cne 'PASS') { $errors.Add('ARCHITECTURE_HUMAN_LAYOUT_GATE_MISSING') }
    if ([string]$composition.e4_e5_requires_final_layout_status -cne 'PASS') { $errors.Add('ARCHITECTURE_E4_E5_LAYOUT_GATE_MISSING') }
    if (-not [bool]$composition.task_override_forbidden) { $errors.Add('ARCHITECTURE_LAYOUT_GATE_TASK_OVERRIDE_ALLOWED') }
    if ([bool]$composition.special_layout_profile_policy.mandatory_runtime_second_pass) { $errors.Add('ARCHITECTURE_MANDATORY_TIP_SECOND_PASS_STILL_ACTIVE') }
    if ([string]$composition.special_layout_profile_policy.runtime_rule -notmatch 'dispatch_only_atomically_promoted_geometry_profiles') { $errors.Add('ARCHITECTURE_PROMOTED_PROFILE_DISPATCH_RULE_MISSING') }
}

$loopStages = @($loop.one_shot_workflow.stages)
foreach ($stage in @('FINAL_QUANTIFIED_LAYOUT','FINAL_LAYOUT_AUDIT','SCREENSHOT_RASTER_QA','CODEX_VISUAL_REVIEW','HUMAN_REVIEW_REQUIRED')) {
    if ($stage -notin $loopStages) { $errors.Add("MACHINE_LOOP_STAGE_MISSING:$stage") }
}
foreach ($stage in @('MONOTONIC_PARTIAL_CONVERGENCE','VERIFIED_LAYOUT_PROFILE_DISPATCH')) {
    if ($stage -notin $loopStages) { $errors.Add("MACHINE_LOOP_MONOTONIC_STAGE_MISSING:$stage") }
}
if ([Array]::IndexOf($loopStages, 'FINAL_QUANTIFIED_LAYOUT') -gt [Array]::IndexOf($loopStages, 'VISUAL_EVIDENCE')) { $errors.Add('MACHINE_LOOP_VISUAL_BEFORE_LAYOUT') }
if ([Array]::IndexOf($loopStages, 'SCREENSHOT_RASTER_QA') -gt [Array]::IndexOf($loopStages, 'CODEX_VISUAL_REVIEW')) { $errors.Add('MACHINE_LOOP_CODEX_BEFORE_RASTER_QA') }
if ([Array]::IndexOf($loopStages, 'CODEX_VISUAL_REVIEW') -gt [Array]::IndexOf($loopStages, 'HUMAN_REVIEW_REQUIRED')) { $errors.Add('MACHINE_LOOP_HUMAN_BEFORE_CODEX') }
if ([string]$loop.one_shot_workflow.generation_offset_semantics -cne 'per_source_formula_band__per_segment_native_endpoint_state_selects_signed_side__post_generation_grip0_residual_only') { $errors.Add('MACHINE_LOOP_GENERATION_OFFSET_BOUNDARY_INVALID') }
if ([string]$loop.one_shot_workflow.formal_visual_and_human_gate_requires_final_layout_status -cne 'PASS') { $errors.Add('MACHINE_LOOP_FINAL_LAYOUT_PASS_GATE_MISSING') }
if ([string]$loop.one_shot_workflow.special_layout_runtime_policy -notmatch 'mandatory_second_pass_false') { $errors.Add('MACHINE_LOOP_SPECIAL_PROFILE_RUNTIME_POLICY_MISSING') }

$continuity = $formula.source_path_continuity
if ($null -eq $continuity) { $errors.Add('FORMULA_SOURCE_PATH_CONTINUITY_MISSING') }
else {
    if ([string]$continuity.planning_unit -cne 'one_continuous_source_polyline') { $errors.Add('FORMULA_LAYOUT_UNIT_NOT_SOURCE_PATH') }
    if (-not [bool]$continuity.common_base_band_required) { $errors.Add('FORMULA_COMMON_BASE_BAND_NOT_REQUIRED') }
    if (-not [bool]$continuity.isolated_band_promotion_forbidden) { $errors.Add('FORMULA_ISOLATED_BAND_PROMOTION_ALLOWED') }
    if ([bool]$continuity.automatic_radial_grip4_feedback) { $errors.Add('FORMULA_AUTOMATIC_RADIAL_GRIP4_ALLOWED') }
}

$commonBand = $formula.quantified_common_band
if ($null -eq $commonBand) { $errors.Add('FORMULA_QUANTIFIED_COMMON_BAND_MISSING') }
else {
    if ([string]$commonBand.text_thickness_input -cne 'measured_native_text_height_on_target_tangent') { $errors.Add('FORMULA_COMMON_BAND_USES_CURRENT_ERROR_OBB') }
    if ([string]$commonBand.observed_obb_role -cne 'post_layout_local_failure_detection_only') { $errors.Add('FORMULA_OBB_ROLE_CAN_INFLATE_GLOBAL_BAND') }
    if ([string]$commonBand.observed_obb_failure_action -cne 'report_only__never_mutate_text_or_inflate_global_band') { $errors.Add('FORMULA_OBB_LOCAL_FAILURE_ACTION_INVALID') }
}

$nativeText = $formula.active_native_text_policy
if ($null -eq $nativeText) { $errors.Add('FORMULA_ACTIVE_NATIVE_TEXT_POLICY_MISSING') }
else {
    if ([string]$nativeText.scope -cne 'distance_only') { $errors.Add('FORMULA_ACTIVE_SCOPE_NOT_DISTANCE_ONLY') }
    if ((@($nativeText.allowed_automatic_mutable_grip_indexes) -join ',') -cne '0') { $errors.Add('FORMULA_ACTIVE_MUTABLE_GRIPS_NOT_ZERO_ONLY') }
    if ((@($nativeText.frozen_grip_indexes) -join ',') -cne '2,3,4') { $errors.Add('FORMULA_ACTIVE_FROZEN_GRIPS_INVALID') }
    if ([string]$nativeText.tmirdim -cne 'forbidden_in_default_workflow') { $errors.Add('FORMULA_ACTIVE_TMIRDIM_NOT_FORBIDDEN') }
    if ([string]$nativeText.along_arc_text_move -cne 'forbidden_in_default_workflow') { $errors.Add('FORMULA_ACTIVE_ALONG_ARC_TEXT_MOVE_NOT_FORBIDDEN') }
}

$layoutComponent = @($registry.components | Where-Object { [string]$_.id -ceq 'CAD-DIM-ANGLE-FULL-BLUE-LAYOUT-V2' })
if ($layoutComponent.Count -ne 1) { $errors.Add('ANGLE_LAYOUT_COMPONENT_IDENTITY_INVALID') }
else {
    if ((@($layoutComponent[0].two_pass_policy.mutable_grip_indexes) -join ',') -cne '0') { $errors.Add('ANGLE_LAYOUT_MUTABLE_GRIPS_NOT_GRIP0_ONLY') }
    if (4 -notin @($layoutComponent[0].two_pass_policy.frozen_grip_indexes)) { $errors.Add('ANGLE_LAYOUT_GRIP4_NOT_FROZEN') }
    if ([string]$layoutComponent[0].two_pass_policy.role -cne 'development_calibration_convergence_only__not_mandatory_production_runtime') { $errors.Add('ANGLE_LAYOUT_CALIBRATION_ROLE_MISSING') }
}

foreach ($token in @('FORMULA_DIRECT_NATIVE_GENERATION__ENDPOINT_STATE_CLASSIFICATION__OPPOSITE_SIDE_RETRY_IF_REQUIRED','per_source_formula_band__per_segment_native_endpoint_state_selects_signed_side__post_generation_grip0_residual_only','RETRY_OPPOSITE_SIDE_WRONG_NATIVE_STATE','REQUIRED_NOT_RUN','GENERATION_COMPLETE_FINAL_LAYOUT_REQUIRED','invoke_selected_typed_dimension_layout_stage.ps1','FINAL_LAYOUT_COMPLETE_VISUAL_QA_REQUIRED','DIAGNOSTIC_FAILED_SUBSET_PREVIEW__NOT_FORMAL_REVIEW')) {
    if ($controller -notmatch [regex]::Escape($token)) { $errors.Add("CONTROLLER_LAYOUT_BOUNDARY_TOKEN_MISSING:$token") }
}
foreach ($token in @('SOURCE_BATCH_ROLLED_BACK__DECOMPOSED_TO_SEGMENTS','GENERATION_PARTIAL_SUCCESS_FINAL_LAYOUT_REQUIRED','$created.Count -gt 0 -and $mappingPassed','ANALYZE_ONLY_FAILED_SEGMENTS_OR_LOCAL_CLUSTERS')) {
    if ($controller -notmatch [regex]::Escape($token)) { $errors.Add("CONTROLLER_MONOTONIC_CONVERGENCE_MISSING:$token") }
}
foreach ($token in @('COMMON_BAND_ONLY__NO_PROMOTED_SPECIAL_TIP_PROFILE','mandatory_special_tip_second_pass = $false','unpromoted_special_tip_auto_apply_count = 0','FREEZE_AND_CARRY_FORWARD_UNSAVED')) {
    if ($layoutStage -notmatch [regex]::Escape($token)) { $errors.Add("LAYOUT_PROMOTED_PROFILE_BOUNDARY_MISSING:$token") }
}
foreach ($forbidden in @('plan_native_angle_grip0_beauty.py','pass1_success_subset_plan.tsv','pass2_failed_cluster_plan.tsv','post_pass2_plan_not_applied.tsv')) {
    if ($layoutStage -match [regex]::Escape($forbidden)) { $errors.Add("LAYOUT_UNPROMOTED_TIP_CALIBRATION_COMPOSED:$forbidden") }
}
foreach ($token in @('PARTIAL_PASS1_SUCCESS_SUBSET_PREPARED','PASS1_FAILED_SUBSET_RETAINED_FOR_PASS2','successful_subset_handles','failed_subset_handles','return 0')) {
    if ($tipPlanner -notmatch [regex]::Escape($token)) { $errors.Add("TIP_PLANNER_PARTIAL_CONVERGENCE_MISSING:$token") }
}
foreach ($forbidden in @('BLOCKED_PASS1_TARGET_FORECAST','return 2 if target_forecast_failed else 0')) {
    if ($tipPlanner -match [regex]::Escape($forbidden)) { $errors.Add("TIP_PLANNER_GLOBAL_BLOCK_STILL_ACTIVE:$forbidden") }
}
if ([string]$formula.sharp_corner_correction.activation -cne 'calibration_candidate_only__runtime_dispatch_disabled_until_promotion') { $errors.Add('FORMULA_SHARP_CORNER_PREMATURE_RUNTIME_ACTIVATION') }
if ([string]$formula.sharp_corner_correction.status -notmatch 'pending_user_true_offset_confirmation') { $errors.Add('FORMULA_SHARP_CORNER_CALIBRATION_STATUS_MISSING') }
if ([string]$formula.two_pass_batch_policy.role -cne 'development_bounded_convergence_only__not_a_mandatory_production_layout_sequence') { $errors.Add('FORMULA_TWO_PASS_ROLE_NOT_DEVELOPMENT_ONLY') }
if ([string]$recovery.focus_lock.status -notin @('LOCKED_UNTIL_NORMAL_TYPED_BATCH_COVERAGE_OR_EXPLICIT_REDIRECT','LOCKED_TO_FRESH_BASEBOARD_GENERATION_AND_QUANTIZED_LAYOUT_V3_VALIDATION','LOCKED_TO_FRESH_BASEBOARD_GENERATION_AND_QUANTIZED_LAYOUT_V4_VALIDATION','LOCKED_TO_FRESH_BASEBOARD_PLACEMENT_GATED_GENERATION_VALIDATION','LOCKED_TO_RUN176_D3_QUANTIZED_COMMON_BAND_VISUAL_VALIDATION','LOCKED_TO_USER_ZOOM_REJECTION__D2_87_ARC_2_THEN_D3_OPEN_83_8B','LOCKED_TO_COMPOSED_LAYOUT_GOVERNANCE_REPAIR_AND_FULL_VALIDATION','LOCKED_TO_DIMENSION_FIRST_CROSS_COMMAND_LAYOUT_SEQUENCE')) { $errors.Add('RECOVERY_EXCLUSIVE_FOCUS_LOCK_MISSING') }
if ([string]$recovery.focus_lock.status -ceq 'LOCKED_TO_DIMENSION_FIRST_CROSS_COMMAND_LAYOUT_SEQUENCE') {
    if ([string]$recovery.workflow_contract.cross_command_layout_sequence -cne 'DIMENSION_GENERATION_AND_TWO_PASS_AESTHETIC_ACCEPTANCE_BEFORE_RADIUS_LAYOUT') { $errors.Add('RECOVERY_CROSS_COMMAND_SEQUENCE_INVALID') }
    if ([string]$recovery.workflow_contract.run373_disposition -cne 'DISCARD_UNSAVED_TEST_OWNER_AND_OPEN_FRESH_DIMENSION_ONLY_ZERO_RADIUS_COPY__NO_IN_PLACE_RADIUS_RESTORE_RUN') { $errors.Add('RECOVERY_RUN373_DISPOSITION_INVALID') }
    if ([string]$recovery.workflow_contract.radius_reentry_rule -notmatch 'old_run373_grip2_grip3_plans_forbidden') { $errors.Add('RECOVERY_RADIUS_REENTRY_INVALID') }
    if ([bool]$recovery.screenshot_contract.printwindow_formal_acceptance_allowed) { $errors.Add('RECOVERY_PRINTWINDOW_FORMAL_ACCEPTANCE_ALLOWED') }
    foreach ($field in @('review_canvas_absolute_path','review_canvas_sha256','nonblack_pass','full_canvas_pass','roi_or_view_location_audit','codex_visual_verdict')) {
        if (@($recovery.screenshot_contract.formal_receipt_required_fields) -cnotcontains $field) { $errors.Add("RECOVERY_FORMAL_VISUAL_RECEIPT_FIELD_MISSING:$field") }
    }
}
if ([bool]$recovery.focus_lock.assistant_initiated_scope_expansion) { $errors.Add('RECOVERY_ASSISTANT_SCOPE_EXPANSION_ALLOWED') }
if ([string]$derived.current_objective -cne [string]$recovery.current_objective) { $errors.Add('DERIVED_STATE_CURRENT_OBJECTIVE_STALE') }
if ($controller -match '\$state\.status\s*=.*''HUMAN_REVIEW_REQUIRED''') { $errors.Add('GENERATION_CONTROLLER_CAN_STILL_EMIT_HUMAN_REVIEW_REQUIRED') }
foreach ($phrase in @('生成—排版不可绕过门','偏距必须直接来自 D3','实测残差','final_layout_status != PASS','B_raw = max','特殊尖端排版标定闭环','用户给出真正需要的最终偏移','截图、OCR和任何图像识别只用于最终显示验收')) {
    if ($contract -notmatch [regex]::Escape($phrase)) { $errors.Add("CANONICAL_LOOP_LAYOUT_GUARD_MISSING:$phrase") }
}
foreach ($token in @('extract_cad_canvas_roi.py','audit_annotation_screenshot_layout.py','CODEX_VISUAL_REVIEW_REQUIRED','LAYOUT_FAILED_TEXT_SOURCE_COLLISION')) {
    $workflow = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\invoke_selected_typed_dimension_workflow.ps1') -Raw -Encoding UTF8
    if ($workflow -notmatch [regex]::Escape($token)) { $errors.Add("FORMAL_WORKFLOW_VISUAL_GATE_MISSING:$token") }
}
foreach ($phrase in @('FINAL_GENERATION_AUDIT_ONCE','FINAL_QUANTIFIED_LAYOUT','FINAL_LAYOUT_AUDIT_ONCE','final_layout_status != PASS')) {
    if ($phasePlan -notmatch [regex]::Escape($phrase)) { $errors.Add("P3_PHASE_PLAN_LAYOUT_GUARD_MISSING:$phrase") }
}

if ($errors.Count -gt 0) { throw ('TYPED_LAYOUT_COMPOSITION_ASSERTION_FAILED:' + ($errors -join '|')) }
$result = [pscustomobject]@{
    status = 'PASS'
    component_id = 'CAD-DIM-TYPED-SELECTED-AUTO-BATCH-V1'
    formula_sha256 = (Get-FileHash -LiteralPath $formulaPath -Algorithm SHA256).Hash
    stage_order = @($typed[0].state_machine)
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
