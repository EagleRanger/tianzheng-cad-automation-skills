"""Compose accepted compilers/auditors; no CAD access or new layout formula."""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path
import subprocess
import sys
from native_text_codes import display_text

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "scripts"))
from annotation_layout_formula import load_vector_layout_formula, quantified_common_band_h
from select_representative_segments import select, write_table, eligible
from audit_preexisting_typed_source_coverage import audit as audit_existing


def read(path, encoding="utf-8-sig"):
    with path.open(encoding=encoding, newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def dump(path, data):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)


def call(script, *args):
    subprocess.run([sys.executable, str(ROOT / script), *map(str, args)], check=True, stdout=subprocess.DEVNULL)


def metrics_adapter(source, target):
    rows = read(source)
    if len(rows) != 2 or any(row["STATUS"] != "PASS" or row["RXCLASS"] != "TDbText" for row in rows):
        raise ValueError("TWO_REAL_NATIVE_TEXT_METRICS_REQUIRED")
    out = []
    for row in rows:
        h = float(row["HEIGHT_MODEL"])
        if not math.isfinite(h) or h <= 0:
            raise ValueError("NATIVE_TEXT_HEIGHT_INVALID")
        # V2 measures a detached TDbText created from native GetText. Its
        # CREATED_COUNT=1 is an in-memory object, not a database insertion.
        if (row["DBMOD_BEFORE"] != row["DBMOD_AFTER"] or row["CREATED_COUNT"] != "1"
                or row["DETACHED"].lower() != "true" or row["DISPOSED"].lower() != "true"):
            raise ValueError("TEXT_READER_CHANGED_DATABASE")
        out.append({"SOURCE_HANDLE": row["HANDLE"], "HANDLE": row["HANDLE"], "HEIGHT": row["HEIGHT_MODEL"], "TEXT": display_text(row["TEXT"]), "RAW_TEXT": row["TEXT"], "TEXT_ADAPTER": "STANDARD_DISPLAY_CODES_ONLY_NO_CAD_EDIT",
                    "MIN_X": row["MIN_X"], "MIN_Y": row["MIN_Y"], "MAX_X": row["MAX_X"], "MAX_Y": row["MAX_Y"]})
    write_table(target, out, list(out[0]))


def prepare(run):
    r = run / "reports"
    summary = read(r / "source_geometry_before_summary.tsv", "gbk")
    if len(summary) != 1 or summary[0]["STATUS"] != "PASS" or summary[0]["DBMOD_BEFORE"] != summary[0]["DBMOD_AFTER"]:
        raise ValueError("FRESH_GEOMETRY_INVENTORY_NOT_PASS")
    geometry = read(r / "source_geometry_before.tsv", "gbk")
    grips = read(r / "grips_before.tsv")
    model = read(r / "model_before.tsv", "gbk")
    dimensions = {row["HANDLE"] for row in model if row["CLASS"] == "TDbDimension2"}
    endpoint_keys = {(row["HANDLE"], row["GRIP_INDEX"]) for row in grips
                     if all(math.isfinite(float(row[name])) for name in ("GRIP_X", "GRIP_Y", "GRIP_Z"))}
    if not dimensions or any((handle, index) not in endpoint_keys for handle in dimensions for index in ("2", "3")):
        raise ValueError("PREEXISTING_NATIVE_DIMENSION_ENDPOINT_COVERAGE_UNVERIFIED")
    candidates = [row for row in geometry if eligible(row)]
    coverage, coverage_summary = audit_existing(candidates, grips, 1e-6)
    write_table(r / "preexisting_coverage.tsv", coverage, list(coverage[0]))
    dump(r / "preexisting_coverage.json", coverage_summary)
    clear = {(row["SOURCE_HANDLE"], int(row["SEGMENT_INDEX"])) for row in coverage if row["STATUS"] == "CLEAR"}
    selected, _ = select([row for row in candidates if (row["SOURCE_HANDLE"], int(row["SEGMENT_INDEX"])) in clear])
    selected_sources = {row["SOURCE_HANDLE"] for row in selected}
    full = [row for row in geometry if row["SOURCE_HANDLE"] in selected_sources]
    write_table(r / "selection_ledger.tsv", selected, list(selected[0]))
    write_table(r / "selected_source_full_geometry.tsv", full, list(full[0]))
    selected_geometry = [{k: v for k, v in row.items() if k != "DISPOSITION"} for row in selected]
    write_table(r / "selected_geometry.tsv", selected_geometry, list(selected_geometry[0]))
    reference = read(r / "reference_metrics.tsv")
    if len(reference) != 1 or reference[0]["STATUS"] != "PASS":
        raise ValueError("REAL_REFERENCE_TEXT_HEIGHT_REQUIRED")
    h = float(reference[0]["HEIGHT_MODEL"])
    if not math.isfinite(h) or h <= 0:
        raise ValueError("REAL_REFERENCE_TEXT_HEIGHT_INVALID")
    formula = load_vector_layout_formula(ROOT / "config/annotation_vector_layout_formula_v2.json")
    offsets = []
    for source in sorted({row["SOURCE_HANDLE"] for row in selected}):
        widths = {float(row["CONSTANT_WIDTH"]) for row in full if row["SOURCE_HANDLE"] == source}
        if len(widths) != 1:
            raise ValueError("SOURCE_WIDTH_AMBIGUOUS")
        _, band_h = quantified_common_band_h(text_height=h, source_width=next(iter(widths)), target_text_radial_thicknesses=(h,),
                                             rule=formula.quantified_common_band, candidate_bands_h=formula.two_pass_batch_policy.candidate_bands_h)
        offsets.append(f"{source}={band_h * h:.12g}")
    scope = json.loads((run / "scope.json").read_text(encoding="utf-8-sig"))
    call("scripts/compile_selected_typed_segment_batch.py", "--ledger", r / "selection_ledger.tsv", "--output", r / "typed_segment_task_spec.lsp",
         "--report", r / "typed_compile_report.json", "--expected-drawing", scope["owners"][1]["document_full_path"], "--drawing-binding", "owner-state",
         "--offset", h, "--source-offsets", ",".join(offsets), "--group", "ROAD",
         # The ASCII task-spec is parsed for its task list only, never loaded.
         # The admitted native stage sets the actual Unicode absolute output
         # paths independently before invoking the mature engine.
         "--summary-path", "generation_summary.tsv", "--details-path", "generation_details.tsv")
    text = (r / "typed_segment_task_spec.lsp").read_text(encoding="ascii")
    match = re.search(r"\(setq cx:\*full-batch-tasks\* '(\([\s\S]*?\n\))\)", text)
    if match is None:
        raise ValueError("ACCEPTED_COMPILER_TASK_DATA_FORM_MISSING")
    with (r / "native_tasks.txt").open("x", encoding="ascii") as stream:
        stream.write(" ".join(match.group(1).split()) + "\n")
    dump(r / "selection_receipt.json", {"status": "PASS_REUSED_NATIVE_DISCOVERY_SELECTION_AND_ACCEPTED_COMPILER" if scope.get("resumed_discovery_native_only") else "PASS_FRESH_SELECTION_AND_ACCEPTED_COMPILER", "source_discovery_run": scope.get("source_discovery_run"), "arc": 1, "line": 1,
         "measured_reference_H": h, "initial_source_offsets": offsets, "second_pass_uses_actual_new_annotation_H": True,
         "sources": sorted({row["SOURCE_HANDLE"] for row in selected}), "full_topology_rows": len(full)})


def after_generation(run):
    r = run / "reports"
    summary = read(r / "generation_summary.tsv", "gbk")
    if len(summary) != 1 or summary[0]["STATUS"] != "PASS" or int(summary[0]["SUCCESS_COUNT"]) != 2:
        raise ValueError("TWO_REAL_NATIVE_GENERATIONS_NOT_PROVEN")
    rows = read(r / "generation_details.tsv", "gbk")
    handles = []
    for row in rows:
        handles.append(row["ADDED_HANDLE"])
    if len(rows) != 2 or len(handles) != 2 or len(set(handles)) != 2:
        raise ValueError("TWO_UNIQUE_NEW_NATIVE_HANDLES_REQUIRED")
    with (r / "new_native_handles.txt").open("x", encoding="ascii") as stream:
        stream.write("\n".join(handles) + "\n")
    write_table(r / "generation_details_utf8.tsv", rows, list(rows[0]))
    call("scripts/audit_native_typed_source_mapping.py", "--geometry", r / "selected_geometry.tsv", "--generation-details", r / "generation_details_utf8.tsv",
         "--grips", r / "grips_generated.tsv", "--tolerance", "0.000001", "--output-mapping", r / "typed_source_mapping.tsv", "--output-summary", r / "mapping_audit.json")


def plan(run):
    r = run / "reports"
    metrics_adapter(r / "text_metrics_generated.tsv", r / "native_text_for_planner.tsv")
    geometry = read(r / "selected_source_full_geometry.tsv")
    styles = [{"HANDLE": source, "CONSTANT_WIDTH": next(row["CONSTANT_WIDTH"] for row in geometry if row["SOURCE_HANDLE"] == source)}
              for source in sorted({row["SOURCE_HANDLE"] for row in geometry})]
    write_table(r / "source_styles.tsv", styles, ["HANDLE", "CONSTANT_WIDTH"])
    call("reference/project-orchestration/reports/dimension_background_reproduction_v8/plan_with_full_topology.py", "--full-source-geometry", r / "selected_source_full_geometry.tsv",
         "--geometry", r / "selected_geometry.tsv", "--mapping", r / "typed_source_mapping.tsv", "--grips", r / "grips_generated.tsv",
         "--text-bboxes", r / "native_text_for_planner.tsv", "--source-styles", r / "source_styles.tsv", "--formula", ROOT / "config/annotation_vector_layout_formula_v2.json",
         "--output-plan", r / "band_delta_plan.tsv", "--output-audit", r / "band_plan_audit.tsv", "--output-summary", r / "band_plan_summary.json")
    call("scripts/build_axis_constrained_grip0_targets_v3.py", "--seed-grips", r / "grips_generated.tsv", "--current-grips", r / "grips_generated.tsv",
         "--delta-plan", r / "band_delta_plan.tsv", "--geometry", r / "selected_geometry.tsv", "--mapping", r / "typed_source_mapping.tsv",
         "--output", r / "scalar_targets.tsv", "--audit", r / "axis_contract_audit.tsv")


def final(run):
    r = run / "reports"
    metrics_adapter(r / "text_metrics_after.tsv", r / "native_text_after.tsv")
    call("scripts/audit_native_dimension_semantics_v1.py", "--geometry", r / "selected_geometry.tsv", "--mapping", r / "typed_source_mapping.tsv",
         "--text-inventory", r / "native_text_after.tsv", "--output-audit", r / "semantics_audit.tsv", "--output-summary", r / "semantics_summary.json")
    before = read(r / "source_geometry_before.tsv", "gbk")
    after = read(r / "source_geometry_after.tsv", "gbk")
    if before != after:
        raise ValueError("ORIGINAL_SOURCE_GEOMETRY_CHANGED")
    raw_before = {row["HANDLE"]: row["RAW_ENTGET"] for row in read(r / "model_before.tsv", "gbk")}
    raw_after = {row["HANDLE"]: row["RAW_ENTGET"] for row in read(r / "model_after.tsv", "gbk")}
    changed = [h for h, value in raw_before.items() if raw_after.get(h) != value]
    if changed or len(raw_after) != len(raw_before) + 2:
        raise ValueError("PREEXISTING_MODEL_DRIFT:" + ",".join(changed))
    def grip_index(rows):
        return {(row["HANDLE"], int(row["GRIP_INDEX"])): tuple(float(row[n]) for n in ("GRIP_X", "GRIP_Y", "GRIP_Z")) for row in rows}
    old = grip_index(read(r / "grips_before.tsv"))
    new = grip_index(read(r / "grips_after.tsv"))
    if not old or any(not all(math.isfinite(v) for v in point) for point in [*old.values(), *new.values()]):
        raise ValueError("PROTECTED_NATIVE_GRIP_INVENTORY_EMPTY_OR_NONFINITE")
    drift = max(math.dist(value, new.get(key, (math.inf,) * 3)) for key, value in old.items())
    if not math.isfinite(drift) or drift > 1e-6:
        raise ValueError("PROTECTED_NATIVE_GRIP_DRIFT")
    selected_keys = {(row["SOURCE_HANDLE"], row["SEGMENT_INDEX"]) for row in read(r / "selected_geometry.tsv")}
    selected_after = [row for row in after if (row["SOURCE_HANDLE"], row["SEGMENT_INDEX"]) in selected_keys]
    write_table(r / "selected_geometry_after.tsv", selected_after, list(selected_after[0]))
    handles = {row["NATIVE_HANDLE"] for row in read(r / "typed_source_mapping.tsv")}
    for source, target in (("grips_generated.tsv", "target_grips_generated.tsv"), ("grips_after.tsv", "target_grips_after.tsv")):
        rows = [row for row in read(r / source) if row["HANDLE"] in handles]
        write_table(r / target, rows, list(rows[0]))
    call("scripts/audit_full_native_layout_effect_v4.py", "--geometry-before", r / "selected_geometry.tsv", "--geometry-after", r / "selected_geometry_after.tsv", "--geometry-after-encoding", "utf-8-sig",
         "--mapping", r / "typed_source_mapping.tsv", "--seed-grips", r / "target_grips_generated.tsv", "--after-grips", r / "target_grips_after.tsv", "--targets", r / "scalar_targets.tsv",
         "--output-audit", r / "layout_effect_audit.tsv", "--output-summary", r / "layout_effect_summary.json")
    dump(r / "protection_audit.json", {"status": "PASS", "preexisting_model_count": len(raw_before), "post_model_count": len(raw_after),
          "preexisting_raw_dxf_changed": changed, "all_source_segment_rows_unchanged": True, "protected_native_grip_max_drift": drift})


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=["prepare", "after_generation", "plan", "final"])
    parser.add_argument("--run", type=Path, required=True)
    args = parser.parse_args()
    globals()[args.stage](args.run)
