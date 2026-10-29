#!/usr/bin/env python3
"""Audit a complete native-dimension layout without board-specific identities.

The audit binds runtime source geometry and source-to-native mapping to native
grips before and after layout.  It accepts five- or six-grip native objects,
and distinguishes commanded grip0 targets from native dependent grip1/grip4 recomputation.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def read_tsv(path: Path, encoding: str) -> list[dict[str, str]]:
    with path.open("r", encoding=encoding, newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def key(row: dict[str, str]) -> tuple[str, int]:
    return row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])


def point(row: dict[str, str], prefix: str) -> tuple[float, float, float]:
    return (
        float(row[f"{prefix}_X"]),
        float(row[f"{prefix}_Y"]),
        float(row.get(f"{prefix}_Z", "0") or 0.0),
    )


def distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.dist(a, b)


def target_error(row: dict[str, str], actual: tuple[float, float, float]) -> tuple[str, float]:
    scalar_contract = all(row.get(name, "").strip() for name in (
        "AXIS_KIND", "ANCHOR_X", "ANCHOR_Y", "AXIS_X", "AXIS_Y", "TARGET_SCALAR",
    ))
    if not scalar_contract:
        return "LEGACY_XYZ_POINT", distance(actual, point(row, "TARGET"))
    anchor_x, anchor_y = float(row["ANCHOR_X"]), float(row["ANCHOR_Y"])
    axis_x, axis_y = float(row["AXIS_X"]), float(row["AXIS_Y"])
    axis_length = math.hypot(axis_x, axis_y)
    if axis_length <= 1.0e-12:
        raise ValueError(f"zero target axis: {row['HANDLE']}")
    axis_x, axis_y = axis_x / axis_length, axis_y / axis_length
    kind = row["AXIS_KIND"].upper()
    if kind == "ARC_RADIUS":
        actual_scalar = math.hypot(actual[0] - anchor_x, actual[1] - anchor_y)
    elif kind == "LINE_NORMAL_DISTANCE":
        actual_scalar = (actual[0] - anchor_x) * axis_x + (actual[1] - anchor_y) * axis_y
    else:
        raise ValueError(f"unsupported target axis kind: {kind}")
    return kind + "_SCALAR", abs(actual_scalar - float(row["TARGET_SCALAR"]))


def grip_map(rows: list[dict[str, str]]) -> dict[tuple[str, int], tuple[float, float, float]]:
    result: dict[tuple[str, int], tuple[float, float, float]] = {}
    for row in rows:
        grip_key = row["HANDLE"].upper(), int(row["GRIP_INDEX"])
        if grip_key in result:
            raise ValueError(f"duplicate grip key: {grip_key}")
        result[grip_key] = point(row, "GRIP")
    return result


def geometry_map(rows: list[dict[str, str]]) -> dict[tuple[str, int], dict[str, str]]:
    result: dict[tuple[str, int], dict[str, str]] = {}
    for row in rows:
        geometry_key = key(row)
        if geometry_key in result:
            raise ValueError(f"duplicate geometry key: {geometry_key}")
        result[geometry_key] = row
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry-before", required=True, type=Path)
    parser.add_argument("--geometry-after", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--seed-grips", required=True, type=Path)
    parser.add_argument("--after-grips", required=True, type=Path)
    parser.add_argument("--targets", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    parser.add_argument("--geometry-before-encoding", default="utf-8-sig")
    parser.add_argument("--geometry-after-encoding", required=True)
    parser.add_argument("--mapping-encoding", default="utf-8-sig")
    parser.add_argument("--seed-grips-encoding", default="utf-8-sig")
    parser.add_argument("--after-grips-encoding", default="utf-8-sig")
    parser.add_argument("--targets-encoding", default="utf-8-sig")
    parser.add_argument("--tolerance", type=float, default=1.0e-6)
    args = parser.parse_args()

    before_geometry = geometry_map(read_tsv(args.geometry_before, args.geometry_before_encoding))
    after_geometry = geometry_map(read_tsv(args.geometry_after, args.geometry_after_encoding))
    seed = grip_map(read_tsv(args.seed_grips, args.seed_grips_encoding))
    after = grip_map(read_tsv(args.after_grips, args.after_grips_encoding))

    mapping: dict[tuple[str, int], str] = {}
    for row in read_tsv(args.mapping, args.mapping_encoding):
        if row.get("STATUS", "").upper() != "PASS":
            raise SystemExit("NON_PASS_MAPPING_ROW")
        mapping_key = key(row)
        native = row["NATIVE_HANDLE"].upper()
        if mapping_key in mapping or native in mapping.values():
            raise SystemExit("DUPLICATE_MAPPING_KEY_OR_NATIVE_HANDLE")
        mapping[mapping_key] = native

    targets: dict[str, dict[str, str]] = {}
    for row in read_tsv(args.targets, args.targets_encoding):
        native = row["HANDLE"].upper()
        if native in targets or int(row["GRIP_INDEX"]) != 0:
            raise SystemExit("TARGET_HANDLE_DUPLICATE_OR_NON_GRIP0")
        targets[native] = row

    geometry_fields = (
        "START_X", "START_Y", "MID_X", "MID_Y", "END_X", "END_Y",
        "BULGE", "SEGMENT_LENGTH", "CONSTANT_WIDTH",
    )
    after_eligible_geometry = {
        item: row for item, row in after_geometry.items()
        if row["SEGMENT_TYPE"].upper() in {"ARC", "LINE"}
    }
    exact_geometry_keys = set(before_geometry) == set(after_eligible_geometry) == set(mapping)
    ignored_non_eligible_after_geometry_count = len(after_geometry) - len(after_eligible_geometry)
    source_geometry_drift_max = 0.0
    source_type_mismatch_count = 0
    for geometry_key in set(before_geometry) & set(after_geometry):
        before_row, after_row = before_geometry[geometry_key], after_geometry[geometry_key]
        if before_row["SEGMENT_TYPE"].upper() != after_row["SEGMENT_TYPE"].upper():
            source_type_mismatch_count += 1
        for field in geometry_fields:
            source_geometry_drift_max = max(
                source_geometry_drift_max,
                abs(float(before_row[field]) - float(after_row[field])),
            )

    mapping_handles = set(mapping.values())
    seed_handles = {handle for handle, _ in seed}
    after_handles = {handle for handle, _ in after}
    exact_native_handle_set = seed_handles == after_handles == mapping_handles
    exact_grip_key_set = set(seed) == set(after)

    audit_rows: list[dict[str, object]] = []
    seed_endpoint_error_max = 0.0
    after_endpoint_error_max = 0.0
    missing_endpoint_count = 0
    for geometry_key, native in sorted(mapping.items()):
        geometry = before_geometry.get(geometry_key)
        required = ((native, 2), (native, 3))
        if geometry is None or any(item not in seed or item not in after for item in required):
            missing_endpoint_count += 1
            audit_rows.append({
                "SOURCE_HANDLE": geometry_key[0], "SEGMENT_INDEX": geometry_key[1],
                "NATIVE_HANDLE": native, "STATUS": "MISSING_ENDPOINT",
                "SEED_ENDPOINT_ERROR": "", "AFTER_ENDPOINT_ERROR": "",
            })
            continue
        start, end = point(geometry, "START"), point(geometry, "END")

        def endpoint_error(grips: dict[tuple[str, int], tuple[float, float, float]]) -> float:
            g2, g3 = grips[(native, 2)], grips[(native, 3)]
            direct = max(distance(g2, start), distance(g3, end))
            reverse = max(distance(g2, end), distance(g3, start))
            return min(direct, reverse)

        seed_error = endpoint_error(seed)
        after_error = endpoint_error(after)
        seed_endpoint_error_max = max(seed_endpoint_error_max, seed_error)
        after_endpoint_error_max = max(after_endpoint_error_max, after_error)
        audit_rows.append({
            "SOURCE_HANDLE": geometry_key[0], "SEGMENT_INDEX": geometry_key[1],
            "NATIVE_HANDLE": native,
            "STATUS": "PASS" if max(seed_error, after_error) <= args.tolerance else "FAIL_ENDPOINT",
            "SEED_ENDPOINT_ERROR": seed_error, "AFTER_ENDPOINT_ERROR": after_error,
        })

    target_keys = {(handle, 0) for handle in targets}
    missing_target_count = 0
    target_fail_count = 0
    target_error_max = 0.0
    target_metric_counts: dict[str, int] = {}
    for native, target_row in targets.items():
        target_key = native, 0
        if target_key not in after:
            missing_target_count += 1
            continue
        metric, error = target_error(target_row, after[target_key])
        target_metric_counts[metric] = target_metric_counts.get(metric, 0) + 1
        target_error_max = max(target_error_max, error)
        tolerance = float(target_row.get("TOLERANCE", "") or args.tolerance)
        if error > tolerance:
            target_fail_count += 1

    changed_keys = {
        grip_key for grip_key in set(seed) & set(after)
        if distance(seed[grip_key], after[grip_key]) > args.tolerance
    }
    dependent_changed_keys = sorted(item for item in changed_keys if item[1] in {1, 4})
    protected_grip_indexes = {2, 3, 5}
    protected_grip_drift_max = max(
        (distance(seed[item], after[item]) for item in set(seed) & set(after)
         if item[1] in protected_grip_indexes),
        default=0.0,
    )
    non_target_grip0_drift_max = max(
        (distance(seed[item], after[item]) for item in set(seed) & set(after)
         if item[1] == 0 and item not in target_keys),
        default=0.0,
    )
    command_scope_grip0_only = mapping_handles.issuperset(targets)
    passed = all((
        exact_geometry_keys,
        source_type_mismatch_count == 0,
        source_geometry_drift_max <= args.tolerance,
        exact_native_handle_set,
        exact_grip_key_set,
        mapping_handles.issuperset(targets),
        missing_endpoint_count == 0,
        seed_endpoint_error_max <= args.tolerance,
        after_endpoint_error_max <= args.tolerance,
        missing_target_count == 0,
        target_fail_count == 0,
        command_scope_grip0_only,
        protected_grip_drift_max <= args.tolerance,
        non_target_grip0_drift_max <= args.tolerance,
    ))

    args.output_audit.parent.mkdir(parents=True, exist_ok=True)
    with args.output_audit.open("w", encoding="utf-8", newline="") as stream:
        fields = ("SOURCE_HANDLE", "SEGMENT_INDEX", "NATIVE_HANDLE", "STATUS", "SEED_ENDPOINT_ERROR", "AFTER_ENDPOINT_ERROR")
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(audit_rows)

    summary = {
        "schema_version": 4,
        "status": "PASS" if passed else "FAIL",
        "mapping_count": len(mapping),
        "native_handle_count": len(mapping_handles),
        "seed_grip_key_count": len(seed),
        "after_grip_key_count": len(after),
        "target_count": len(targets),
        "exact_geometry_key_set": exact_geometry_keys,
        "exact_native_handle_set": exact_native_handle_set,
        "exact_grip_key_set": exact_grip_key_set,
        "source_type_mismatch_count": source_type_mismatch_count,
        "source_geometry_drift_max": source_geometry_drift_max,
        "missing_endpoint_count": missing_endpoint_count,
        "seed_endpoint_association_max": seed_endpoint_error_max,
        "after_endpoint_association_max": after_endpoint_error_max,
        "missing_target_count": missing_target_count,
        "target_error_max": target_error_max,
        "target_fail_count": target_fail_count,
        "target_metric_counts": target_metric_counts,
        "target_acceptance_semantics": "AXIS_SCALAR_WHEN_PRESENT__LEGACY_XYZ_POINT_ONLY_WITHOUT_AXIS_CONTRACT",
        "changed_grip_key_count": len(changed_keys),
        "dependent_changed_grip_key_count": len(dependent_changed_keys),
        "command_scope_grip0_only": command_scope_grip0_only,
        "protected_grip_drift_max": protected_grip_drift_max,
        "non_target_grip0_drift_max": non_target_grip0_drift_max,
        "ignored_non_eligible_after_geometry_count": ignored_non_eligible_after_geometry_count,
        "tolerance": args.tolerance,
        "board_specific_algorithm_literals": 0,
        "input_encodings": {
            "geometry_before": args.geometry_before_encoding,
            "geometry_after": args.geometry_after_encoding,
            "mapping": args.mapping_encoding,
            "seed_grips": args.seed_grips_encoding,
            "after_grips": args.after_grips_encoding,
            "targets": args.targets_encoding,
        },
    }
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": summary["status"], "mapping_count": len(mapping), "target_count": len(targets)}))
    return 0 if passed else 2


if __name__ == "__main__":
    raise SystemExit(main())
