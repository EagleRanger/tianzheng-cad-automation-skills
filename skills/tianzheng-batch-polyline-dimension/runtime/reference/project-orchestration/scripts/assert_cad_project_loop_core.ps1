param([switch]$PassThru)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$loopPath = Join-Path $projectRoot 'config\cad_project_loop.json'
$indexPath = Join-Path $projectRoot 'config\project_execution_index.json'
$loop = Get-Content -LiteralPath $loopPath -Raw -Encoding UTF8 | ConvertFrom-Json
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
$contractPath = Join-Path $projectRoot '.project-reasoning\PROJECT_LOOP.md'
$contractText = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8
$architecturePath = Join-Path $projectRoot ([string]$loop.development_cycle.architecture_authority)
$architecture = Get-Content -LiteralPath $architecturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$errors = [Collections.Generic.List[string]]::new()
$contractBytes = (Get-Item -LiteralPath $contractPath).Length

if ($loop.loop_id -cne 'auto-CAD-project-loop') { $errors.Add('LOOP_ID_INVALID') }
if ($loop.status -cne 'active') { $errors.Add('LOOP_NOT_ACTIVE') }
if ($loop.global_methodology_loop -cne 'project-reasoning-loop') { $errors.Add('GLOBAL_METHODOLOGY_INVALID') }
if ($index.loop_id -cne [string]$loop.loop_id) { $errors.Add('INDEX_LOOP_ID_INVALID') }
if ($index.machine_loop -cne 'config/cad_project_loop.json') { $errors.Add('INDEX_LOOP_CONFIG_INVALID') }
if ($index.canonical_contract -cne [string]$loop.canonical_document) { $errors.Add('INDEX_LOOP_DOCUMENT_INVALID') }
if ($null -ne $index.PSObject.Properties['run_status']) { $errors.Add('OBSOLETE_RUN_STATUS_AUTHORITY_REINTRODUCED') }
if ($null -ne $loop.project_authorities.PSObject.Properties['current_status']) { $errors.Add('OBSOLETE_CURRENT_STATUS_AUTHORITY_REINTRODUCED') }
if (Test-Path -LiteralPath (Join-Path $projectRoot 'config\current_phase_status.json')) { $errors.Add('OBSOLETE_PHASE_STATUS_FILE_REINTRODUCED') }
if ('config/derived_project_state.json' -in @($index.model_bootstrap_order)) { $errors.Add('DERIVED_MACHINE_SNAPSHOT_REINTRODUCED_TO_MODEL_HOT_LAYER') }
if ('config/current_execution_return.json' -notin @($index.model_bootstrap_order)) { $errors.Add('CURRENT_EXECUTION_RETURN_MISSING_FROM_MODEL_HOT_LAYER') }
if ($null -ne $loop.project_authorities.PSObject.Properties['recent_context_handoff']) { $errors.Add('STALE_RECENT_CONTEXT_REINTRODUCED_AS_AUTHORITY') }
if ([string]$index.record_chain_reconciler -cne 'reference/project-orchestration/scripts/settle_cad_hot_state_v2.ps1') { $errors.Add('GENERIC_TERMINAL_SETTLER_POINTER_INVALID') }
if ([string]$index.return_delivery_policy -cne 'config/cad_task_return_delivery_policy.json') { $errors.Add('RETURN_DELIVERY_POLICY_POINTER_INVALID') }
if ([string]$index.return_delivery_assertion -cne 'reference/project-orchestration/scripts/assert_cad_return_delivery_contract.ps1') { $errors.Add('RETURN_DELIVERY_ASSERTION_POINTER_INVALID') }
if ([string]$index.command_research_routing -cne 'config/cad_command_research_routing_v1.json') { $errors.Add('COMMAND_RESEARCH_ROUTING_POINTER_INVALID') }
if ([string]$index.command_research_routing_assertion -cne 'reference/project-orchestration/scripts/assert_cad_command_research_routing_v1.ps1') { $errors.Add('COMMAND_RESEARCH_ROUTING_ASSERTION_POINTER_INVALID') }
try { & (Join-Path $projectRoot ([string]$index.command_research_routing_assertion)) | Out-Null } catch { $errors.Add('COMMAND_RESEARCH_ROUTING_INVALID:' + $_.Exception.Message) }
if ($contractText -match '短暂恢复并前置|前台\s*`?ScreenCopy`?\s*回退允许') { $errors.Add('PROJECT_LOOP_FOREGROUND_CAPTURE_FALLBACK_REINTRODUCED') }

$componentRegistryPath = Join-Path $projectRoot ([string]$index.component_registry)
$componentRegistry = Get-Content -LiteralPath $componentRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$activeComponentRows = @($componentRegistry.components | Where-Object { [string]$_.id -in @($componentRegistry.component_selection_policy.active_reusable_component_ids) })
if ($activeComponentRows.Count -ne @($componentRegistry.component_selection_policy.active_reusable_component_ids).Count) { $errors.Add('ACTIVE_REUSABLE_COMPONENT_ID_NOT_UNIQUE') }
foreach ($row in $activeComponentRows) {
    if ([string]$row.status -in @('planned','blocked','rejected','superseded')) { $errors.Add('NON_CALLABLE_COMPONENT_IN_ACTIVE_REUSABLE_SET:' + [string]$row.id) }
}
$expectedDevelopmentCycle = @('HYPOTHESIS_AND_PLAN','REAL_VALIDATION','EVIDENCE_DRIVEN_ADJUSTMENT','VERSIONED_RESULT','ATOMIC_KNOWLEDGE_SETTLEMENT','NEXT_HYPOTHESIS_AND_PLAN')
if ([string]$loop.development_cycle.id -cne 'CAD_DEVELOPMENT_EVIDENCE_CYCLE_V1') { $errors.Add('DEVELOPMENT_CYCLE_ID_INVALID') }
if ((@($loop.development_cycle.ordered_stages) -join '|') -cne ($expectedDevelopmentCycle -join '|')) { $errors.Add('DEVELOPMENT_CYCLE_ORDER_INVALID') }
if ((@($architecture.development_cycle.ordered_stages) -join '|') -cne ($expectedDevelopmentCycle -join '|')) { $errors.Add('ARCHITECTURE_DEVELOPMENT_CYCLE_ORDER_INVALID') }
if ([string]$architecture.development_cycle.id -cne [string]$loop.development_cycle.id) { $errors.Add('DEVELOPMENT_CYCLE_AUTHORITY_MISMATCH') }
if (-not [bool]$loop.development_cycle.no_direct_rerun_without_adjustment) { $errors.Add('DIRECT_RERUN_WITHOUT_ADJUSTMENT_NOT_FORBIDDEN') }
if (-not [bool]$loop.development_cycle.no_next_capability_before_result_settlement) { $errors.Add('UNSETTLED_RESULT_CAN_ADVANCE') }
if (-not [bool]$loop.development_cycle.reuse_unchanged_verified_capability) { $errors.Add('VERIFIED_CAPABILITY_REUSE_MISSING') }
if ([string]$index.ready_handoff_publisher -cne 'scripts/publish_cad_ready_handoff_v8.ps1') { $errors.Add('READY_V8_PUBLISHER_POINTER_INVALID') }
if ([string]$index.ready_verified_reuse_assertion -cne 'reference/project-orchestration/scripts/assert_cad_ready_verified_reuse_v1.ps1') { $errors.Add('READY_REUSE_ASSERTION_POINTER_INVALID') }
if ([string]$loop.one_shot_workflow.ready_handoff_publisher -cne [string]$index.ready_handoff_publisher) { $errors.Add('READY_PUBLISHER_AUTHORITY_MISMATCH') }
if ([string]$loop.one_shot_workflow.ready_verified_reuse_assertion -cne [string]$index.ready_verified_reuse_assertion) { $errors.Add('READY_REUSE_ASSERTION_AUTHORITY_MISMATCH') }
if (-not [bool]$loop.adapter_mutation_gate.ready_requires_machine_checked_reuse_admission) { $errors.Add('READY_REUSE_ADMISSION_NOT_ENFORCED') }
if (-not [bool]$loop.adapter_mutation_gate.pass_through_interface_forbids_controller_recalculation) { $errors.Add('READY_PASS_THROUGH_RECALCULATION_NOT_FORBIDDEN') }
if (-not [bool]$loop.adapter_mutation_gate.canonical_state_updates_must_precede_ready_publication) { $errors.Add('READY_STATE_UPDATE_ORDER_NOT_ENFORCED') }
if (-not [bool]$loop.development_cycle.safety_gates_are_stage_support_not_cycle_owner) { $errors.Add('SAFETY_GATE_OWNS_DEVELOPMENT_CYCLE') }
if (-not [bool]$loop.development_cycle.auxiliary_monitor_failure_cannot_override_settled_native_generation_and_mapping) { $errors.Add('AUXILIARY_FAILURE_CAN_OVERRIDE_NATIVE_MAPPING') }
if ([string]::IsNullOrWhiteSpace([string]$architecture.development_cycle.auxiliary_failure_settlement_rule)) { $errors.Add('AUXILIARY_FAILURE_SETTLEMENT_RULE_MISSING') }
if (-not [bool]$architecture.development_cycle.task_specific_runtime_data_forbidden) { $errors.Add('DEVELOPMENT_CYCLE_TASK_DATA_BOUNDARY_MISSING') }
if ([string]$loop.stage_execution.entrypoint -cne 'reference/project-orchestration/scripts/invoke_owned_stage_transition.ps1') { $errors.Add('STAGE_TRANSITION_ENTRYPOINT_INVALID') }
if ([string]$loop.stage_execution.assertion -cne 'reference/project-orchestration/scripts/assert_owned_stage_checkpoint.ps1') { $errors.Add('STAGE_CHECKPOINT_ASSERTION_INVALID') }
if ([int]$loop.stage_execution.retention -ne 10) { $errors.Add('STAGE_CHECKPOINT_RETENTION_INVALID') }
if (-not [bool]$loop.stage_execution.normal_save_close_auto_checkpoints) { $errors.Add('STAGE_CLOSE_GATE_NOT_ENFORCED') }
if (-not [bool]$loop.stage_execution.discard_requires_explicit_no_checkpoint_authority) { $errors.Add('STAGE_DISCARD_AUTHORITY_NOT_ENFORCED') }
if (-not [bool]$loop.stage_execution.emergency_process_cleanup_is_not_a_stage_transition) { $errors.Add('EMERGENCY_STAGE_BOUNDARY_INVALID') }
if (-not [bool]$loop.stage_execution.final_does_not_equal_accepted_pass) { $errors.Add('STAGE_FINAL_ACCEPTANCE_BOUNDARY_INVALID') }

$humanPolicyRelative = [string]$loop.human_review.policy
$humanPolicyPath = Join-Path $projectRoot $humanPolicyRelative
if (-not (Test-Path -LiteralPath $humanPolicyPath -PathType Leaf)) {
    $errors.Add('HUMAN_REVIEW_POLICY_MISSING')
}
else {
    $humanPolicy = Get-Content -LiteralPath $humanPolicyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$humanPolicy.status -cne 'active') { $errors.Add('HUMAN_REVIEW_POLICY_NOT_ACTIVE') }
    if ([string]$humanPolicy.approval_authority -cne 'USER_ONLY') { $errors.Add('HUMAN_REVIEW_AUTHORITY_INVALID') }
    if (-not [bool]$humanPolicy.machine_audit_can_propose_but_cannot_approve) { $errors.Add('MACHINE_APPROVAL_NOT_FORBIDDEN') }
    if (-not [bool]$humanPolicy.codex_visual_review_can_propose_but_cannot_approve) { $errors.Add('CODEX_APPROVAL_NOT_FORBIDDEN') }
    if (-not [bool]$humanPolicy.silence_or_generic_continue_is_not_approval) { $errors.Add('GENERIC_CONTINUE_APPROVAL_NOT_FORBIDDEN') }
    if (-not [bool]$humanPolicy.candidate_change_invalidates_prior_approval) { $errors.Add('STALE_APPROVAL_NOT_INVALIDATED') }
    $requiredReviewStages = @('SHARP_DENSE_SAMPLE', 'PASS1_CANDIDATE', 'FINAL_CANDIDATE_BEFORE_E4_E5')
    if ((@($humanPolicy.required_review_stages | Sort-Object) -join '|') -cne (($requiredReviewStages | Sort-Object) -join '|')) {
        $errors.Add('HUMAN_REVIEW_STAGE_SET_INVALID')
    }
    $requiredEvidence = @('exact_state_sha256', 'stage_dwg_path_and_sha256', 'one_or_more_screenshot_paths_and_sha256', 'current_user_turn_confirmation_ref')
    if ((@($humanPolicy.required_evidence | Sort-Object) -join '|') -cne (($requiredEvidence | Sort-Object) -join '|')) {
        $errors.Add('HUMAN_REVIEW_EVIDENCE_SET_INVALID')
    }
}
if (-not [bool]$loop.human_review.machine_audit_only_proposes_next_state) { $errors.Add('LOOP_MACHINE_APPROVAL_BOUNDARY_INVALID') }
if (-not [bool]$loop.human_review.scope_expansion_requires_user_approval) { $errors.Add('LOOP_SCOPE_EXPANSION_APPROVAL_MISSING') }
if (-not [bool]$loop.human_review.pass_2_requires_user_approval) { $errors.Add('LOOP_PASS2_APPROVAL_MISSING') }
if (-not [bool]$loop.human_review.final_candidate_requires_user_approval) { $errors.Add('LOOP_FINAL_APPROVAL_MISSING') }
if (-not [bool]$loop.human_review.approval_must_bind_state_dwg_and_screenshot_hashes) { $errors.Add('LOOP_APPROVAL_BINDING_INVALID') }

$canonicalOpen = $loop.canonical_open
if ([string]$canonicalOpen.entrypoint -cne 'reference/project-orchestration/scripts/start_owned_tianzheng_supervised.ps1') { $errors.Add('CANONICAL_OPEN_ENTRYPOINT_INVALID') }
if ([string]$canonicalOpen.inner_entrypoint -cne 'reference/project-orchestration/scripts/start_owned_tianzheng_direct_dwg.ps1') { $errors.Add('CANONICAL_OPEN_INNER_ENTRYPOINT_INVALID') }
if ([string]$canonicalOpen.transport -cne 'TIANZHENG_SHORTCUT_SHELLEXECUTE_WITH_DWG_ARGUMENT') { $errors.Add('CANONICAL_OPEN_TRANSPORT_INVALID') }
if ([string]$canonicalOpen.platform -cne 'AutoCAD 2021') { $errors.Add('CANONICAL_OPEN_PLATFORM_INVALID') }
if ([string]$canonicalOpen.target -cne 'isolated_dwg_only') { $errors.Add('CANONICAL_OPEN_TARGET_INVALID') }
if (-not [bool]$canonicalOpen.supervisor_owns_retry) { $errors.Add('CANONICAL_OPEN_RETRY_OWNER_INVALID') }
if ([int]$canonicalOpen.inner_max_launch_attempts -ne 1) { $errors.Add('CANONICAL_OPEN_INNER_ATTEMPTS_INVALID') }
if (-not [bool]$canonicalOpen.legacy_alternative_routes_forbidden) { $errors.Add('CANONICAL_OPEN_LEGACY_ROUTE_NOT_FORBIDDEN') }
if ([string]$canonicalOpen.component_id -cne 'CAD-LC-OPEN-V1') { $errors.Add('CANONICAL_OPEN_COMPONENT_ID_INVALID') }
if ([string]$canonicalOpen.component_version -cne '1.2.8') { $errors.Add('CANONICAL_OPEN_COMPONENT_VERSION_INVALID') }
if (-not [bool]$canonicalOpen.ready_handoff_binding_required) { $errors.Add('CANONICAL_OPEN_HANDOFF_BINDING_NOT_REQUIRED') }
if ([string]$canonicalOpen.invocation_policy -cne 'canonical_entrypoint_only') { $errors.Add('CANONICAL_OPEN_INVOCATION_POLICY_INVALID') }
if ([string]$canonicalOpen.open_result_semantics -cne 'target_DWG_open_chain_observed_or_fail') { $errors.Add('CANONICAL_OPEN_RESULT_SEMANTICS_INVALID') }
if ([bool]$canonicalOpen.inline_startup_wrapper_allowed) { $errors.Add('CANONICAL_OPEN_INLINE_WRAPPER_ALLOWED') }
if ([bool]$canonicalOpen.alternate_transport_allowed) { $errors.Add('CANONICAL_OPEN_ALTERNATE_TRANSPORT_ALLOWED') }
if ([bool]$canonicalOpen.timeout_may_reclassify_failed_open) { $errors.Add('CANONICAL_OPEN_TIMEOUT_RECLASSIFICATION_ALLOWED') }

$retirement = $loop.failure_retirement
if ([string]$retirement.policy -cne 'exact_disproof_immediate_executable_retirement') { $errors.Add('FAILURE_RETIREMENT_POLICY_INVALID') }
if ([string]$retirement.trigger -cne 'real_run_uniquely_binds_object_scope_input_sequence_and_failure_result') { $errors.Add('FAILURE_RETIREMENT_TRIGGER_INVALID') }
if ([string]$retirement.tombstone_registry -cne 'config/rejected_legacy_entrypoints.json') { $errors.Add('FAILURE_RETIREMENT_TOMBSTONE_INVALID') }
$requiredRetiredLayers = @('entrypoint_file','whitelist_action','workflow_registration','component_registration','dedicated_scope','dedicated_test','project_owned_cache')
if ((@($retirement.required_removed_layers | Sort-Object) -join '|') -cne (($requiredRetiredLayers | Sort-Object) -join '|')) { $errors.Add('FAILURE_RETIREMENT_LAYER_SET_INVALID') }
$requiredPostDeleteGates = @('config_and_registry_parse','tombstoned_path_absent','removed_workflow_component_and_action_absent','active_reference_scan','current_verified_mainline_regression')
if ((@($retirement.post_delete_gates | Sort-Object) -join '|') -cne (($requiredPostDeleteGates | Sort-Object) -join '|')) { $errors.Add('FAILURE_RETIREMENT_POST_DELETE_GATES_INVALID') }
if ([string]$retirement.pre_delete_gate -cne 'reverse_reference_inventory') { $errors.Add('FAILURE_RETIREMENT_PRE_DELETE_GATE_INVALID') }
if (-not [bool]$retirement.rejected_but_callable_forbidden) { $errors.Add('REJECTED_BUT_CALLABLE_NOT_FORBIDDEN') }
if ([string]$retirement.unverified_route_policy -cne 'non_callable_quarantine_with_one_bounded_validation_gate') { $errors.Add('UNVERIFIED_ROUTE_POLICY_INVALID') }
foreach ($relative in @([string]$canonicalOpen.entrypoint, [string]$canonicalOpen.inner_entrypoint)) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
        $errors.Add("CANONICAL_OPEN_ENTRYPOINT_MISSING:$relative")
    }
}

$tombstoneRelative = [string]$loop.project_authorities.rejected_legacy_entrypoints
$tombstonePath = Join-Path $projectRoot $tombstoneRelative
if (-not (Test-Path -LiteralPath $tombstonePath -PathType Leaf)) {
    $errors.Add('REJECTED_LEGACY_ENTRYPOINTS_REGISTRY_MISSING')
}
else {
    $tombstone = Get-Content -LiteralPath $tombstonePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$tombstone.status -cne 'active_tombstone') { $errors.Add('REJECTED_LEGACY_ENTRYPOINTS_REGISTRY_INACTIVE') }
    foreach ($entry in @($tombstone.deleted_entrypoints)) {
        $relative = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($relative)) {
            $errors.Add('REJECTED_LEGACY_ENTRYPOINT_PATH_EMPTY')
        }
        elseif (Test-Path -LiteralPath (Join-Path $projectRoot $relative)) {
            $errors.Add("REJECTED_LEGACY_ENTRYPOINT_REINTRODUCED:$relative")
        }
    }
}

$protectedEntrypoints = @($loop.stage_execution.protected_entrypoints)
if ($protectedEntrypoints.Count -ne 4) { $errors.Add('STAGE_PROTECTED_ENTRYPOINT_SET_INVALID') }
foreach ($relative in $protectedEntrypoints) {
    $path = Join-Path $projectRoot ([string]$relative)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("STAGE_PROTECTED_ENTRYPOINT_MISSING:$relative")
        continue
    }
    $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($content -match '(?i)\bStop-Process\b|\btaskkill\b|\bTerminateProcess\b') {
        $errors.Add("STAGE_PROTECTED_ENTRYPOINT_TERMINATES_PROCESS:$relative")
    }
}

$roadmapPath = Join-Path $projectRoot ([string]$loop.project_authorities.roadmap)
$roadmap = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentPhase = [string]$roadmap.current_phase
$phaseRows = @($roadmap.phases | Where-Object { [string]$_.id -ceq $currentPhase })
if ($phaseRows.Count -ne 1) { $errors.Add('ROADMAP_CURRENT_PHASE_NOT_UNIQUE') }
elseif ([string]::IsNullOrWhiteSpace([string]$phaseRows[0].detail)) { $errors.Add('ROADMAP_CURRENT_PHASE_DETAIL_MISSING') }

$requiredPaths = @([string]$loop.canonical_document, [string]$loop.outbound.candidate_queue, [string]$loop.stage_execution.entrypoint, [string]$loop.stage_execution.assertion, [string]$canonicalOpen.entrypoint, [string]$canonicalOpen.inner_entrypoint) + $protectedEntrypoints
foreach ($property in $loop.project_authorities.PSObject.Properties) { $requiredPaths += [string]$property.Value }
if ($phaseRows.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$phaseRows[0].detail)) {
    $requiredPaths += [string]$phaseRows[0].detail
}
foreach ($relative in $requiredPaths | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
        $errors.Add("PROJECT_LOOP_AUTHORITY_MISSING:$relative")
    }
}

$recoveryAssertion = Join-Path $projectRoot 'scripts\assert_cad_recovery_context.ps1'
if (-not (Test-Path -LiteralPath $recoveryAssertion -PathType Leaf)) {
    $errors.Add('CAD_RECOVERY_CONTEXT_ASSERTION_MISSING')
}
else {
    try { & $recoveryAssertion | Out-Null }
    catch { $errors.Add('CAD_RECOVERY_CONTEXT_INVALID:' + $_.Exception.Message) }
}

$taskChannelAssertion = Join-Path $projectRoot 'scripts\assert_cad_task_channel_architecture.ps1'
if (-not (Test-Path -LiteralPath $taskChannelAssertion -PathType Leaf)) {
    $errors.Add('CAD_TASK_CHANNEL_ARCHITECTURE_ASSERTION_MISSING')
}
else {
    try { & $taskChannelAssertion | Out-Null }
    catch { $errors.Add('CAD_TASK_CHANNEL_ARCHITECTURE_INVALID:' + $_.Exception.Message) }
}

$layoutCompositionAssertion = Join-Path $projectRoot 'scripts\assert_typed_dimension_layout_composition.ps1'
if (-not (Test-Path -LiteralPath $layoutCompositionAssertion -PathType Leaf)) {
    $errors.Add('TYPED_LAYOUT_COMPOSITION_ASSERTION_MISSING')
}
else {
    try { & $layoutCompositionAssertion | Out-Null }
    catch { $errors.Add('TYPED_LAYOUT_COMPOSITION_INVALID:' + $_.Exception.Message) }
}

$promotionConsistencyAssertion = Join-Path $projectRoot 'scripts\assert_cad_knowledge_promotion_consistency.ps1'
if (-not (Test-Path -LiteralPath $promotionConsistencyAssertion -PathType Leaf)) {
    $errors.Add('CAD_KNOWLEDGE_PROMOTION_CONSISTENCY_ASSERTION_MISSING')
}
else {
    try { & $promotionConsistencyAssertion | Out-Null }
    catch { $errors.Add('CAD_KNOWLEDGE_PROMOTION_CONSISTENCY_INVALID:' + $_.Exception.Message) }
}

$canonicalOpenConsistencyAssertion = Join-Path $projectRoot 'scripts\assert_cad_canonical_open_consistency.ps1'
if (-not (Test-Path -LiteralPath $canonicalOpenConsistencyAssertion -PathType Leaf)) {
    $errors.Add('CAD_CANONICAL_OPEN_CONSISTENCY_ASSERTION_MISSING')
}
else {
    try { & $canonicalOpenConsistencyAssertion | Out-Null }
    catch { $errors.Add('CAD_CANONICAL_OPEN_CONSISTENCY_INVALID:' + $_.Exception.Message) }
}

if ([string]$loop.outbound.promotion -cne 'review_only_in_global_project_reasoning_loop_maintenance_task') {
    $errors.Add('GLOBAL_PROMOTION_BOUNDARY_INVALID')
}
if ($errors.Count -gt 0) { throw ('CAD_PROJECT_LOOP_ASSERTION_FAILED:' + ($errors -join '|')) }

$result = [pscustomobject]@{
    status = 'PASS'
    loop_id = [string]$loop.loop_id
    current_phase = $currentPhase
    authorities_checked = ($requiredPaths | Select-Object -Unique).Count
    project_loop_context_bytes = $contractBytes
    context_budget_is_advisory = $true
}
if ($PassThru) { $result } else { $result | ConvertTo-Json -Compress }
