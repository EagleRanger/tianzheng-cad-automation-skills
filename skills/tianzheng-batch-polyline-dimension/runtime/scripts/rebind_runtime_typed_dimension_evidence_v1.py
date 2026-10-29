#!/usr/bin/env python3
"""Rebind typed-dimension evidence to the current DWG by geometry and grips.

Reference source/native handles are never reused. Reference rows contribute
only source-segment semantics and layout metadata after a proven one-to-one
geometry match. Current native handles come only from the live grip inventory.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


DIMENSIONABLE = {"ARC", "LINE"}


def read_tsv(path: Path) -> list[dict[str, str]]:
    data = path.read_bytes()
    last_error: UnicodeDecodeError | None = None
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            text = data.decode(encoding)
            reader = csv.DictReader(text.splitlines(), delimiter="\t")
            rows = []
            for row in reader:
                # Six legacy generation-detail rows contain unquoted tabs in
                # ATTEMPTS, the final column. Preserve those tokens instead of
                # silently dropping DictReader's overflow bucket.
                overflow = row.pop(None, None)
                if overflow:
                    if not reader.fieldnames:
                        raise ValueError("TSV_HEADER_MISSING")
                    final_field = reader.fieldnames[-1]
                    row[final_field] = "\t".join(
                        [row.get(final_field, ""), *overflow]
                    )
                rows.append(row)
            return rows
        except UnicodeDecodeError as error:
            last_error = error
    assert last_error is not None
    raise last_error


def write_tsv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream, fieldnames=fieldnames, delimiter="\t", lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(rows)


def point(row: dict[str, str], x: str, y: str) -> tuple[float, float]:
    return float(row[x]), float(row[y])


def distance(left: tuple[float, float], right: tuple[float, float]) -> float:
    return math.hypot(left[0] - right[0], left[1] - right[1])


def endpoint_error(a0, a1, b0, b1) -> float:
    return min(
        distance(a0, b0) + distance(a1, b1),
        distance(a0, b1) + distance(a1, b0),
    )


def geometry_error(current: dict[str, str], reference: dict[str, str]) -> float:
    error = endpoint_error(
        point(current, "START_X", "START_Y"),
        point(current, "END_X", "END_Y"),
        point(reference, "START_X", "START_Y"),
        point(reference, "END_X", "END_Y"),
    )
    if current["SEGMENT_TYPE"].upper() == "ARC":
        error += distance(
            point(current, "MID_X", "MID_Y"),
            point(reference, "MID_X", "MID_Y"),
        )
    return error


def key(row: dict[str, object]) -> tuple[str, int]:
    return str(row["SOURCE_HANDLE"]).upper(), int(row["SEGMENT_INDEX"])


def clone_with_identity(
    row: dict[str, str], current: dict[str, str]
) -> dict[str, str]:
    result = dict(row)
    result["SOURCE_HANDLE"] = current["SOURCE_HANDLE"].upper()
    result["SEGMENT_INDEX"] = str(int(current["SEGMENT_INDEX"]))
    result["SEGMENT_TYPE"] = current["SEGMENT_TYPE"].upper()
    return result


def rebind(
    current_geometry_rows: list[dict[str, str]],
    current_grip_rows: list[dict[str, str]],
    reference_geometry_rows: list[dict[str, str]],
    reference_detail_rows: list[dict[str, str]],
    reference_mapping_rows: list[dict[str, str]],
    reference_tasks: list[dict[str, object]],
    geometry_tolerance: float,
    grip_tolerance: float,
    current_details_rows: list[dict[str, str]] | None = None,
) -> tuple[
    list[dict[str, str]],
    list[dict[str, str]],
    list[dict[str, object]],
    list[dict[str, object]],
    dict[str, object],
]:
    current_geometry = [
        row
        for row in current_geometry_rows
        if row["SEGMENT_TYPE"].upper() in DIMENSIONABLE
    ]
    reference_geometry = [
        row
        for row in reference_geometry_rows
        if row["SEGMENT_TYPE"].upper() in DIMENSIONABLE
    ]
    reference_details = {key(row): row for row in reference_detail_rows}
    reference_mapping = {key(row): row for row in reference_mapping_rows}
    reference_task_map = {
        (str(row["source_handle"]).upper(), int(row["segment_index"])): row
        for row in reference_tasks
    }
    current_details = {key(row): row for row in (current_details_rows or [])}

    geometry_matches: dict[tuple[str, int], dict[str, str]] = {}
    used_reference_keys: set[tuple[str, int]] = set()
    geometry_failures: list[str] = []
    max_geometry_error = 0.0
    for current in sorted(current_geometry, key=key):
        ranked = sorted(
            (
                geometry_error(current, reference),
                key(reference),
                reference,
            )
            for reference in reference_geometry
            if reference["SEGMENT_TYPE"].upper()
            == current["SEGMENT_TYPE"].upper()
        )
        exact = [
            (error, row)
            for error, _reference_key, row in ranked
            if error <= geometry_tolerance
        ]
        if len(exact) != 1 or key(exact[0][1]) in used_reference_keys:
            geometry_failures.append(
                f"{key(current)[0]}:{key(current)[1]}:"
                f"exact_reference_matches={len(exact)}"
            )
            continue
        error, reference = exact[0]
        max_geometry_error = max(max_geometry_error, error)
        geometry_matches[key(current)] = reference
        used_reference_keys.add(key(reference))

    grips: dict[str, dict[int, tuple[float, float]]] = {}
    grip_types: dict[str, str] = {}
    grip_layers: dict[str, str] = {}
    for row in current_grip_rows:
        handle = row["HANDLE"].upper()
        grips.setdefault(handle, {})[int(row["GRIP_INDEX"])] = point(
            row, "GRIP_X", "GRIP_Y"
        )
        grip_types[handle] = row["RXCLASS"]
        grip_layers[handle] = row["LAYER"]
    native_candidates = {
        handle: values
        for handle, values in grips.items()
        if grip_types.get(handle) == "TDbDimension2"
        and grip_layers.get(handle) == "PUB_DIM"
        and 2 in values
        and 3 in values
    }

    native_matches: dict[tuple[str, int], str] = {}
    used_native_handles: set[str] = set()
    ambiguous_native: list[str] = []
    max_native_error = 0.0
    for current in sorted(current_geometry, key=key):
        ranked = sorted(
            (
                endpoint_error(
                    values[2],
                    values[3],
                    point(current, "START_X", "START_Y"),
                    point(current, "END_X", "END_Y"),
                ),
                handle,
            )
            for handle, values in native_candidates.items()
        )
        exact = [
            (error, handle)
            for error, handle in ranked
            if error <= grip_tolerance
        ]
        if len(exact) > 1:
            ambiguous_native.append(
                f"{key(current)[0]}:{key(current)[1]}:"
                f"exact_native_matches={len(exact)}"
            )
        elif len(exact) == 1:
            error, handle = exact[0]
            if handle in used_native_handles:
                ambiguous_native.append(
                    f"{key(current)[0]}:{key(current)[1]}:"
                    f"duplicate_native_handle={handle}"
                )
            else:
                native_matches[key(current)] = handle
                used_native_handles.add(handle)
                max_native_error = max(max_native_error, error)

    rebound_details: list[dict[str, str]] = []
    rebound_mapping: list[dict[str, str]] = []
    missing_tasks: list[dict[str, object]] = []
    current_tasks: list[dict[str, object]] = []
    metadata_failures: list[str] = []
    missing_segments: list[str] = []
    for current in sorted(current_geometry, key=key):
        current_key = key(current)
        reference = geometry_matches.get(current_key)
        if reference is None:
            continue
        reference_key = key(reference)
        if (
            reference_key not in reference_details
            or reference_key not in reference_mapping
            or reference_key not in reference_task_map
        ):
            metadata_failures.append(
                f"{current_key[0]}:{current_key[1]}:reference_metadata_missing"
            )
            continue
        handle = native_matches.get(current_key, "")
        current_task = dict(reference_task_map[reference_key])
        current_task["source_handle"] = current_key[0]
        current_task["segment_index"] = current_key[1]
        current_task["segment_type"] = current["SEGMENT_TYPE"].upper()
        current_tasks.append(current_task)
        source_detail = current_details.get(
            current_key, reference_details[reference_key]
        )
        detail = clone_with_identity(source_detail, current)
        detail["ADDED_HANDLE"] = handle
        detail["STATUS"] = "PASS" if handle else "FAIL"
        if not handle:
            detail["ATTEMPTS"] = "RUNTIME_REBIND_MISSING_NATIVE"
        rebound_details.append(detail)

        mapping = clone_with_identity(reference_mapping[reference_key], current)
        mapping["NATIVE_HANDLE"] = handle
        mapping["STATUS"] = "PASS" if handle else "FAIL"
        rebound_mapping.append(mapping)

        if not handle:
            missing_segments.append(
                f"{current_key[0]}:{current_key[1]}:"
                f"{current['SEGMENT_TYPE'].upper()}"
            )
            missing_tasks.append(dict(current_task))

    unused_native = sorted(set(native_candidates) - used_native_handles)
    complete_geometry_bijection = (
        len(geometry_matches)
        == len(current_geometry)
        == len(reference_geometry)
        and len(used_reference_keys) == len(reference_geometry)
    )
    status = (
        "PASS"
        if complete_geometry_bijection
        and not geometry_failures
        and not ambiguous_native
        and not metadata_failures
        else "FAIL"
    )
    summary: dict[str, object] = {
        "status": status,
        "current_dimensionable_segment_count": len(current_geometry),
        "reference_dimensionable_segment_count": len(reference_geometry),
        "geometry_bijection_count": len(geometry_matches),
        "candidate_native_count": len(native_candidates),
        "mapped_native_count": len(native_matches),
        "missing_native_count": len(missing_segments),
        "missing_segments": missing_segments,
        "unused_native_handles": unused_native,
        "unrelated_native_count": len(unused_native),
        "geometry_failures": geometry_failures,
        "ambiguous_native": ambiguous_native,
        "metadata_failures": metadata_failures,
        "maximum_geometry_error": max_geometry_error,
        "maximum_native_endpoint_error": max_native_error,
        "geometry_tolerance": geometry_tolerance,
        "grip_tolerance": grip_tolerance,
        "reference_handles_reused": False,
    }
    return rebound_details, rebound_mapping, missing_tasks, current_tasks, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current-geometry", required=True, type=Path)
    parser.add_argument("--current-grips", required=True, type=Path)
    parser.add_argument("--reference-geometry", required=True, type=Path)
    parser.add_argument("--reference-details", required=True, type=Path)
    parser.add_argument("--reference-mapping", required=True, type=Path)
    parser.add_argument("--reference-task-spec", required=True, type=Path)
    parser.add_argument("--current-details", type=Path)
    parser.add_argument("--expected-drawing", required=True)
    parser.add_argument("--summary-path", required=True)
    parser.add_argument("--details-path", required=True)
    parser.add_argument("--stage-trace-path", required=True)
    parser.add_argument("--geometry-tolerance", type=float, default=0.08)
    parser.add_argument("--grip-tolerance", type=float, default=0.08)
    completeness = parser.add_mutually_exclusive_group()
    completeness.add_argument("--require-incomplete", action="store_true")
    completeness.add_argument("--require-complete", action="store_true")
    parser.add_argument("--output-details", required=True, type=Path)
    parser.add_argument("--output-mapping", required=True, type=Path)
    parser.add_argument("--output-missing-task-spec", required=True, type=Path)
    parser.add_argument("--output-current-task-spec", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()

    reference_details = read_tsv(args.reference_details)
    reference_mapping = read_tsv(args.reference_mapping)
    reference_task_spec = json.loads(
        args.reference_task_spec.read_text(encoding="utf-8-sig")
    )
    details, mapping, tasks, current_tasks, summary = rebind(
        read_tsv(args.current_geometry),
        read_tsv(args.current_grips),
        read_tsv(args.reference_geometry),
        reference_details,
        reference_mapping,
        list(reference_task_spec["tasks"]),
        args.geometry_tolerance,
        args.grip_tolerance,
        read_tsv(args.current_details) if args.current_details else None,
    )
    derived_total = int(summary["reference_dimensionable_segment_count"])
    derived_missing = int(summary["missing_native_count"])
    valid = (
        summary["status"] == "PASS"
        and summary["current_dimensionable_segment_count"] == derived_total
        and len(details) == derived_total
        and len(mapping) == derived_total
        and len(current_tasks) == derived_total
        and len(tasks) == derived_missing
        and (not args.require_incomplete or derived_missing > 0)
        and (not args.require_complete or derived_missing == 0)
    )
    summary["status"] = "PASS" if valid else "FAIL"
    summary["derived_total_count"] = derived_total
    summary["derived_missing_count"] = derived_missing
    summary["completeness_requirement"] = (
        "COMPLETE" if args.require_complete else "INCOMPLETE" if args.require_incomplete else "ANY"
    )

    detail_fields = list(reference_details[0]) if reference_details else []
    mapping_fields = list(reference_mapping[0]) if reference_mapping else []
    write_tsv(args.output_details, details, detail_fields)
    write_tsv(args.output_mapping, mapping, mapping_fields)
    task_spec = {
        "schema_version": reference_task_spec.get("schema_version", 1),
        "scope_id": "RUNTIME_REBOUND_MISSING_NATIVE_SUBSET_V1",
        "expected_drawing": args.expected_drawing,
        "summary_path": args.summary_path,
        "details_path": args.details_path,
        "stage_trace_path": args.stage_trace_path,
        "tasks": tasks,
    }
    args.output_missing_task_spec.parent.mkdir(parents=True, exist_ok=True)
    args.output_missing_task_spec.write_text(
        json.dumps(task_spec, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    current_task_spec = dict(task_spec)
    current_task_spec["scope_id"] = "RUNTIME_REBOUND_CURRENT_FULL_SCOPE_V1"
    current_task_spec["tasks"] = current_tasks
    args.output_current_task_spec.parent.mkdir(parents=True, exist_ok=True)
    args.output_current_task_spec.write_text(
        json.dumps(current_task_spec, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if valid else 2


if __name__ == "__main__":
    raise SystemExit(main())
