"""Replay historical CAD project-loop failures against the current contracts.

The audit is read-only.  It checks project semantics and recovery routes, not
drawing-specific object counts or handles.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]


def load_json(relative: str) -> dict[str, Any]:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def read_text(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8-sig")


def command_rows() -> list[dict[str, str]]:
    with (ROOT / "knowledge/t20v10_command_registry.tsv").open(
        "r", encoding="utf-8-sig", newline=""
    ) as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def get_path(value: Any, dotted: str) -> Any:
    current = value
    for part in dotted.split("."):
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            raise KeyError(dotted)
    return current


def run_audit() -> dict[str, Any]:
    loop = load_json("config/cad_project_loop.json")
    architecture = load_json("config/cad_development_architecture.json")
    recovery = load_json("config/current_recovery_contract.json")
    dialog_rules = load_json("config/tianzheng_dialog_whitelist.json")
    formula = load_json("config/annotation_vector_layout_formula_v2.json")
    index = load_json("config/project_execution_index.json")
    rejected = load_json("config/rejected_legacy_entrypoints.json")
    project_loop_text = read_text(".project-reasoning/PROJECT_LOOP.md")
    capture_entry_text = read_text("reference/project-orchestration/scripts/invoke_owned_cad_visual_capture.ps1")
    capture_backend_text = read_text("scripts/cad_capture_compat.ps1")
    one_shot_validation_text = read_text(
        "reference/project-orchestration/scripts/invoke_owned_tianzheng_one_shot_validation.ps1"
    )
    controller_text = read_text("reference/project-orchestration/scripts/invoke_selected_typed_dimension_polyline_controller.ps1")
    layout_stage_text = read_text("reference/project-orchestration/scripts/invoke_selected_typed_dimension_layout_stage.ps1")
    dialog_watcher_text = read_text("reference/project-orchestration/scripts/watch_tianzheng_dialogs.ps1")
    tip_planner_text = read_text("scripts/plan_native_angle_grip0_beauty.py")
    rows = command_rows()

    active_hash_paths = set(index["execution_authority_hash_order"])
    deleted_paths = {row["path"] for row in rejected["deleted_entrypoints"]}
    command_by_name = {
        row["full_command"].upper(): row
        for row in rows
        if row.get("full_command")
    }
    dialog_rule_by_id = {row["id"]: row for row in dialog_rules["rules"]}

    cases: list[tuple[str, str, str, Callable[[], bool]]] = [
        (
            "OPTIONAL_TDIMMP_PALETTE_OVERRULED_NATIVE_SUCCESS",
            "The exact trusted TDimMP palette is observed without mutation; native objects and source mapping decide success.",
            "LES-20260823-CAD-DIALOG-017",
            lambda: (
                loop["development_cycle"]["auxiliary_monitor_failure_cannot_override_settled_native_generation_and_mapping"]
                and "recover_deterministic_engine_outputs_and_native_grips" in architecture["safety_modes"]["development_experiment"]["post_failure_evidence_recovery"]
                and dialog_rule_by_id["tdimmp_first_session_total_dimension_mode"]["action"] == "observe_trusted_nonblocking_command_palette"
                and "KNOWN_NONBLOCKING_DIALOG_OBSERVED" in dialog_watcher_text
                and "bmSetCheck=0x00F1" not in dialog_watcher_text
                and "let_optional_tdimmp_total_dimension_checkbox_override" in "|".join(recovery["rejected_development_control_patterns"])
            ),
        ),
        (
            "KNOWN_COMMAND_CANDIDATE_WAS_IGNORED",
            "Native command interface failure recalls verified, unpromoted, and rejected routes before adapter mutation.",
            "DEC-20260822-CAPABILITY-RECALL-AND-ATOMIC-PROMOTION",
            lambda: (
                command_by_name["TDIMMP"]["chinese_name"] == "逐点标注"
                and command_by_name["TDIMTP"]["chinese_name"] == "两点标注"
                and len(index["conditional_capability_recall_order"]) >= 3
                and "native_command_or_adapter_failure" in recovery["history_policy"]
                and loop["adapter_mutation_gate"]["unpromoted_same_semantic_candidate_must_remain_retrievable"]
            ),
        ),
        (
            "PROMOTION_UPDATED_ONLY_ONE_REGISTRY",
            "A verified capability cannot become active until all promotion domains and the consistency assertion agree.",
            "LES-20260822-CAD-LOOP-013",
            lambda: (
                architecture["knowledge_promotion_transaction"]["incomplete_terminal"] == "PROMOTION_INCOMPLETE"
                and loop["knowledge_promotion_transaction"]["incomplete_promotion_cannot_be_active_mainline"]
                and loop["knowledge_promotion_transaction"]["consistency_assertion"]
                in active_hash_paths
                and len(architecture["knowledge_promotion_transaction"]["atomic_update_domains"]) >= 6
            ),
        ),
        (
            "LOCAL_FAILURE_ROLLED_BACK_ALL_SUCCESSES",
            "Development failure decomposes to the smallest failed segment or endpoint cluster and already successful objects remain frozen.",
            "LES-20260821-CAD-SAFETY-GATE-007",
            lambda: (
                architecture["safety_modes"]["development_experiment"]["execution_unit"] == "one_source_polyline"
                and "retain_and_freeze_successful_segments" in architecture["safety_modes"]["development_experiment"]["local_failure"]
                and "preserve_unsaved" in architecture["safety_modes"]["development_experiment"]["successful_units"]
                and "SOURCE_BATCH_ROLLED_BACK__DECOMPOSED_TO_SEGMENTS" in controller_text
                and "GENERATION_PARTIAL_SUCCESS_FINAL_LAYOUT_REQUIRED" in controller_text
            ),
        ),
        (
            "DEVELOPMENT_CHECKPOINT_BLOCKED_BY_PRODUCTION_GATE",
            "A labeled partial checkpoint is allowed while formal delivery remains separately gated.",
            "DEC-20260821-DEVELOPMENT-SAFETY-GATE-SPLIT",
            lambda: (
                loop["stage_execution"]["development_partial_checkpoint_allowed"]
                and loop["stage_execution"]["development_checkpoint_is_recovery_not_acceptance"]
                and loop["stage_execution"]["development_checkpoint_must_not_overwrite_baseline_or_formal_delivery"]
            ),
        ),
        (
            "GENERATION_BYPASSED_VERIFIED_LAYOUT_FORMULA",
            "Generation uses the versioned final offset and cannot reach visual review before quantified layout and audit.",
            "DEC-20260821-GENERATION-MUST-COMPOSE-FINAL-LAYOUT",
            lambda: (
                architecture["typed_dimension_composition_contract"]["generation_offset_semantics"]
                == "per_source_formula_band__per_segment_native_endpoint_state_selects_signed_side__post_generation_grip0_residual_only"
                and architecture["typed_dimension_composition_contract"]["required_stage_order"].index("FINAL_QUANTIFIED_LAYOUT")
                < architecture["typed_dimension_composition_contract"]["required_stage_order"].index("CODEX_VISUAL_REVIEW")
                and "plan_typed_dimension_quantified_common_band.py" in layout_stage_text
                and "COMMON_BAND_ONLY__NO_PROMOTED_SPECIAL_TIP_PROFILE" in layout_stage_text
            ),
        ),
        (
            "UNCONFIRMED_TIP_CALIBRATION_ENTERED_ACTIVE_ONE_CLICK_CHAIN",
            "The active one-click layout excludes the unpromoted sharp-tip calibration planner and exposes only promoted-profile dispatch.",
            "DEC-20260822-TIP-CALIBRATION-BEFORE-RUNTIME-DISPATCH",
            lambda: (
                "plan_native_angle_grip0_beauty.py" not in layout_stage_text
                and "pass2_failed_cluster_plan.tsv" not in layout_stage_text
                and "VERIFIED_LAYOUT_PROFILE_DISPATCH"
                in architecture["typed_dimension_composition_contract"]["required_stage_order"]
                and architecture["typed_dimension_composition_contract"]["special_layout_profile_policy"]["mandatory_runtime_second_pass"] is False
                and formula["sharp_corner_correction"]["activation"]
                == "calibration_candidate_only__runtime_dispatch_disabled_until_promotion"
            ),
        ),
        (
            "ONE_PASS1_FAILURE_CLEARED_ALL_SUCCESS_MOVES",
            "Pass 1 emits its successful subset and retains only the exact failed handles for pass 2.",
            "USER-CORRECTION-MONOTONIC-PARTIAL-CONVERGENCE",
            lambda: (
                "PARTIAL_PASS1_SUCCESS_SUBSET_PREPARED" in tip_planner_text
                and "successful_subset_handles" in tip_planner_text
                and "failed_subset_handles" in tip_planner_text
                and "BLOCKED_PASS1_TARGET_FORECAST" not in tip_planner_text
                and "return 2 if target_forecast_failed else 0" not in tip_planner_text
            ),
        ),
        (
            "PARTIAL_GENERATION_SUCCESS_NEVER_REACHED_LAYOUT",
            "A mapped successful subset reaches quantified layout even when another segment remains failed.",
            "USER-CORRECTION-KEEP-SUCCESSFUL-PARTS",
            lambda: (
                "$created.Count -gt 0 -and $mappingPassed" in controller_text
                and "GENERATION_PARTIAL_SUCCESS_FINAL_LAYOUT_REQUIRED" in controller_text
                and "successfulSegmentKeys" in controller_text
            ),
        ),
        (
            "DISTANCE_TASK_EXPANDED_INTO_TEXT_RELAYOUT",
            "Default distance work preserves native text and forbids mirror, grip4, and image-derived positioning.",
            "LES-20260822-CAD-BATCH-LAYOUT-011",
            lambda: (
                "preserve_generated_state" in loop["one_shot_workflow"]["native_text_policy"]
                and "tmirdim_forbidden" in loop["one_shot_workflow"]["native_text_policy"]
                and "grip4_move" in recovery["workflow_contract"]["forbidden_default_text_mutations"]
                and "screenshot_derived_positioning" in recovery["workflow_contract"]["forbidden_default_text_mutations"]
            ),
        ),
        (
            "SCREENSHOT_OR_OCR_DROVE_MUTATION_COORDINATES",
            "Visual evidence is read-only acceptance and never a positioning input.",
            "LES-20260822-CAD-BATCH-LAYOUT-011",
            lambda: (
                "never_drives_coordinates_or_mutation" in loop["one_shot_workflow"]["visual_positioning_policy"]
                and recovery["screenshot_contract"]["foreground_or_input_for_capture"] is False
                and recovery["screenshot_contract"]["visual_evidence_can_drive_mutation_coordinates"] is False
            ),
        ),
        (
            "BACKGROUND_SCREENSHOT_ACTIVATED_OR_RESTORED_CAD_WINDOW",
            "Visual capture uses exact-owned-HWND PrintWindow only and cannot activate, show, restore, move, foreground-copy, or send input to CAD.",
            "USER-CORRECTION-20260822-BACKGROUND-CAPTURE-IMMUTABLE-WINDOW",
            lambda: (
                loop["one_shot_workflow"]["background_visual_capture_policy"].startswith(
                    "exact_owned_HWND_PrintWindow_only"
                )
                and (
                    "no_activation_show_restore_move_input_or_foreground_copy"
                    in loop["one_shot_workflow"]["background_visual_capture_policy"]
                    or "no_activation_focus_move_input_or_foreground_copy"
                    in loop["one_shot_workflow"]["background_visual_capture_policy"]
                )
                and recovery["screenshot_contract"]["foreground_or_input_for_capture"] is False
                and recovery["screenshot_contract"]["window_activation_for_capture"] is False
                and recovery["screenshot_contract"]["window_show_or_restore_for_capture"] is False
                and recovery["screenshot_contract"]["foreground_screen_copy_fallback_allowed"]
                in (
                    False,
                    "only_when_exact_owned_window_is_already_visible_and_foreground__PER_MONITOR_AWARE_V2_required__no_activation_or_input",
                )
                and recovery["screenshot_contract"]["unavailable_terminal"]
                in (
                    "BACKGROUND_PRINTWINDOW_CAPTURE_UNAVAILABLE_NO_WINDOW_MUTATION",
                    "after_one_bounded_backend_fallback_report_SCREENSHOT_UNAVAILABLE__never_business_rollback",
                )
                and "-Backend PrintWindow" in capture_entry_text
            ),
        ),
        (
            "OLD_AND_NEW_CAD_OPEN_RETRIED_IN_A_LOOP",
            "One supervisor owns one cleanup plan and one successor launch; legacy routes remain forbidden.",
            "LES-20260821-CAD-WINDOW-LIVENESS-005",
            lambda: (
                loop["canonical_open"]["supervisor_owns_retry"]
                and loop["canonical_open"]["inner_max_launch_attempts"] == 1
                and loop["canonical_open"]["legacy_alternative_routes_forbidden"]
                and recovery["lifecycle_contract"]["legacy_keepalive_or_multiple_CAD_is_not_a_valid_steady_state"]
            ),
        ),
        (
            "LAUNCH_CONTROLLER_RETURNED_BEFORE_MUTATION_AUDIT_AND_CAPTURE",
            "Validation keeps launch, governed mutation, machine audit, and immutable-window PrintWindow capture in one controller before returning.",
            "LES-20260821-CAD-WINDOW-LIVENESS-005",
            lambda: (
                recovery["lifecycle_contract"]["validation_entry"]
                == "reference/project-orchestration/scripts/invoke_owned_tianzheng_one_shot_validation.ps1"
                and recovery["lifecycle_contract"]["single_controller_sequence"]
                == "launch_then_mutate_then_machine_audit_then_background_capture_before_return"
                and recovery["lifecycle_contract"]["sleep_only_keepalive_is_not_session_ownership"]
                and "return_from_the_launch_controller_before_mutation_machine_audit_and_background_capture"
                in recovery["rejected_recovery_routes"]
                and one_shot_validation_text.index("start_owned_tianzheng_supervised.ps1")
                < one_shot_validation_text.index("TDIM_TYPED_SEGMENT_BATCH")
                < one_shot_validation_text.index("AUDIT_NATIVE_DIM_BBOXES")
                < one_shot_validation_text.index("-Label $afterCaptureLabel")
                and not any(
                    token in one_shot_validation_text
                    for token in (
                        "SetForegroundWindow",
                        "ShowWindow",
                        "SetWindowPos",
                        "CopyFromScreen",
                        "ScreenCopy",
                        "computer-use",
                    )
                )
            ),
        ),
        (
            "DRAWING_COUNTS_OR_HANDLES_WERE_WRITTEN_INTO_LOOP",
            "The loop remains task-agnostic and runtime object data stays in the task binding and run evidence.",
            "DEC-20260821-CAD-DEVELOPMENT-ARCHITECTURE-REBUILD",
            lambda: (
                architecture["task_data_boundary"].startswith("all_drawing_specific_counts_handles")
                and loop["knowledge_promotion_transaction"]["runtime_object_counts_handles_offsets_and_hashes_remain_task_evidence_only"]
                and re.search(r"\b[0-9A-F]{5,}:[0-9]+\b", project_loop_text) is None
            ),
        ),
        (
            "UNCHANGED_VERIFIED_CAPABILITY_WAS_REPLAYED_WHOLE",
            "An unchanged terminal state is not rerun; a fresh full-coverage stage starts clean, while a partial-success stage freezes successes and analyzes only its bound failed subset.",
            "LES-20260821-CAD-TIME-006",
            lambda: (
                loop["one_shot_workflow"]["repeat_unchanged_terminal_state"] is False
                and loop["development_cycle"]["no_direct_rerun_without_adjustment"]
                and loop["development_cycle"]["reuse_unchanged_verified_capability"]
                and "never_repeat" in recovery["workflow_contract"]["successful_unit_policy"]
                and load_json("config/cad_task_history_policy.json")["execution_return_delivery"]["callback_failure_authorizes_cad_rerun"] is False
            ),
        ),
        (
            "SUPERSEDED_ENTRYPOINT_REMAINED_CALLABLE",
            "Every tombstoned entry is absent and excluded from active authority paths.",
            "config/retrospective_20260807_11_component_reframe.json",
            lambda: all(
                not (ROOT / relative).exists() and relative not in active_hash_paths
                for relative in deleted_paths
            ),
        ),
        (
            "HUMAN_READABLE_AUTHORITY_WAS_MACHINE_UNREADABLE",
            "The command capability TSV has real columns and is parsed by the promotion consistency harness.",
            "LES-20260822-CAD-LOOP-013",
            lambda: (
                set(rows[0]) == {"chinese_name", "full_command", "aliases", "menu_macro", "protocol_status", "evidence"}
                and "TDIMMP" in command_by_name
                and "TDIMTP" in command_by_name
                and "reference/project-orchestration/scripts/assert_cad_knowledge_promotion_consistency.ps1" in active_hash_paths
            ),
        ),
        (
            "FAILED_VALIDATION_WENT_DIRECTLY_TO_UNCHANGED_RERUN",
            "Every failed validation is followed by evidence-bound adjustment before another run.",
            "CAD_DEVELOPMENT_EVIDENCE_CYCLE_V1",
            lambda: (
                loop["development_cycle"]["no_direct_rerun_without_adjustment"]
                and architecture["development_cycle"]["adjustment_rule"].startswith("bind_change_to_verified_cause")
                and architecture["development_cycle"]["ordered_stages"].index("REAL_VALIDATION")
                < architecture["development_cycle"]["ordered_stages"].index("EVIDENCE_DRIVEN_ADJUSTMENT")
            ),
        ),
        (
            "RESULT_WAS_NOT_SETTLED_BEFORE_NEXT_CAPABILITY_PLAN",
            "A versioned result is atomically settled before it can seed the next hypothesis.",
            "CAD_DEVELOPMENT_EVIDENCE_CYCLE_V1",
            lambda: (
                loop["development_cycle"]["no_next_capability_before_result_settlement"]
                and loop["development_cycle"]["reuse_unchanged_verified_capability"]
                and architecture["development_cycle"]["ordered_stages"].index("VERSIONED_RESULT")
                < architecture["development_cycle"]["ordered_stages"].index("ATOMIC_KNOWLEDGE_SETTLEMENT")
                < architecture["development_cycle"]["ordered_stages"].index("NEXT_HYPOTHESIS_AND_PLAN")
            ),
        ),
        (
            "UNRESOLVED_VISUAL_PROBLEM_WAS_REPLACED_BY_ASSISTANT_SIDE_WORK",
            "The current user-selected development stage remains exclusive until its own acceptance or an explicit redirect.",
            "USER-CORRECTION-NO-ASSISTANT-SCOPE-EXPANSION",
            lambda: (
                recovery["focus_lock"]["status"]
                in {
                    "LOCKED_UNTIL_NORMAL_TYPED_BATCH_COVERAGE_OR_EXPLICIT_REDIRECT",
                    "LOCKED_TO_FRESH_BASEBOARD_GENERATION_AND_QUANTIZED_LAYOUT_V3_VALIDATION",
                    "LOCKED_TO_FRESH_BASEBOARD_GENERATION_AND_QUANTIZED_LAYOUT_V4_VALIDATION",
                    "LOCKED_TO_FRESH_BASEBOARD_PLACEMENT_GATED_GENERATION_VALIDATION",
                    "LOCKED_TO_RUN176_D3_QUANTIZED_COMMON_BAND_VISUAL_VALIDATION",
                }
                and recovery["focus_lock"]["assistant_initiated_scope_expansion"] is False
                and loop["development_cycle"]["unresolved_focus_is_exclusive_until_current_stage_acceptance_or_explicit_redirect"]
                and loop["development_cycle"]["assistant_initiated_side_optimization_forbidden_during_focus_lock"]
            ),
        ),
        (
            "TIP_DEVELOPMENT_TWO_STEP_WAS_MISTAKEN_FOR_PRODUCTION_TWO_PASS",
            "Tip adjustment is a calibration cycle ending in quantified profile promotion; production dispatch has no mandatory second pass.",
            "DEC-20260822-TIP-CALIBRATION-BEFORE-RUNTIME-DISPATCH",
            lambda: (
                "mandatory_second_pass_false"
                in loop["one_shot_workflow"]["special_layout_runtime_policy"]
                and formula["two_pass_batch_policy"]["role"]
                == "development_bounded_convergence_only__not_a_mandatory_production_layout_sequence"
                and "USER_VISUAL_TARGET_CONFIRMATION"
                in architecture["typed_dimension_composition_contract"]["special_layout_profile_policy"]["calibration_sequence"]
            ),
        ),
    ]

    results = []
    for case_id, expected, evidence, check in cases:
        detail = ""
        try:
            passed = bool(check())
        except Exception as exc:  # report the exact missing contract instead of hiding it
            passed = False
            detail = f"{type(exc).__name__}: {exc}"
        results.append(
            {
                "case_id": case_id,
                "status": "PASS" if passed else "FAIL",
                "expected_guardrail": expected,
                "historical_evidence": evidence,
                "detail": detail,
            }
        )

    failed = [row["case_id"] for row in results if row["status"] != "PASS"]
    return {
        "schema_version": 1,
        "status": "PASS" if not failed else "FAIL",
        "mode": "READ_ONLY_HISTORICAL_FAILURE_REPLAY",
        "case_count": len(results),
        "pass_count": len(results) - len(failed),
        "fail_count": len(failed),
        "failed_cases": failed,
        "cad_mutation_performed": False,
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = run_audit()
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
