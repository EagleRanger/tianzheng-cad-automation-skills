"""Audit native grip-0 against scalar axis contracts; XY is legacy fallback only."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def scalar_at(row: dict[str, str], point: tuple[float, float, float]) -> float:
    anchor_x, anchor_y = float(row["ANCHOR_X"]), float(row["ANCHOR_Y"])
    axis_x, axis_y = float(row["AXIS_X"]), float(row["AXIS_Y"])
    axis_length = math.hypot(axis_x, axis_y)
    if axis_length <= 1.0e-12:
        raise ValueError(f"zero axis: {row['HANDLE']}")
    axis_x, axis_y = axis_x / axis_length, axis_y / axis_length
    kind = row["AXIS_KIND"].upper()
    if kind == "ARC_RADIUS":
        return math.hypot(point[0] - anchor_x, point[1] - anchor_y)
    if kind == "LINE_NORMAL_DISTANCE":
        return (point[0] - anchor_x) * axis_x + (point[1] - anchor_y) * axis_y
    raise ValueError(f"unsupported axis kind: {kind}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()
    current = {
        row["HANDLE"].upper(): (float(row["GRIP_X"]), float(row["GRIP_Y"]), float(row["GRIP_Z"]))
        for row in rows(args.grips)
        if int(row["GRIP_INDEX"]) == 0
    }
    audit: list[dict[str, str]] = []
    for row in rows(args.targets):
        handle = row["HANDLE"].upper()
        tolerance = float(row["TOLERANCE"])
        if handle not in current:
            audit.append({"HANDLE": handle, "METRIC": "", "ACTUAL_SCALAR": "", "TARGET_SCALAR": row.get("TARGET_SCALAR", ""), "ERROR": "", "TOLERANCE": repr(tolerance), "STATUS": "MISSING"})
            continue
        actual = current[handle]
        scalar_contract = all(row.get(key, "").strip() for key in ("AXIS_KIND", "ANCHOR_X", "ANCHOR_Y", "AXIS_X", "AXIS_Y", "TARGET_SCALAR"))
        if scalar_contract:
            actual_scalar = scalar_at(row, actual)
            target_scalar = float(row["TARGET_SCALAR"])
            error = abs(actual_scalar - target_scalar)
            metric = row["AXIS_KIND"].upper() + "_SCALAR"
        else:
            target = float(row["TARGET_X"]), float(row["TARGET_Y"]), float(row["TARGET_Z"])
            error = math.dist(actual, target)
            actual_scalar = math.nan
            target_scalar = math.nan
            metric = "LEGACY_XYZ_POINT"
        audit.append({
            "HANDLE": handle,
            "METRIC": metric,
            "ACTUAL_SCALAR": "" if math.isnan(actual_scalar) else repr(actual_scalar),
            "TARGET_SCALAR": "" if math.isnan(target_scalar) else repr(target_scalar),
            "ERROR": repr(error),
            "TOLERANCE": repr(tolerance),
            "STATUS": "PASS" if error <= tolerance else "FAIL",
        })
    args.output_audit.parent.mkdir(parents=True, exist_ok=True)
    fields = ["HANDLE", "METRIC", "ACTUAL_SCALAR", "TARGET_SCALAR", "ERROR", "TOLERANCE", "STATUS"]
    with args.output_audit.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", quoting=csv.QUOTE_NONE, lineterminator="\n", escapechar="\\")
        writer.writeheader()
        writer.writerows(audit)
    counts = {status: sum(1 for row in audit if row["STATUS"] == status) for status in ("PASS", "FAIL", "MISSING")}
    errors = [float(row["ERROR"]) for row in audit if row["ERROR"]]
    summary = {
        "status": "PASS" if counts["FAIL"] == 0 and counts["MISSING"] == 0 else "PARTIAL",
        "target_count": len(audit),
        "counts": counts,
        "max_error": max(errors, default=0.0),
        "authoritative_metric": "source_geometry_scalar_when_present__legacy_XYZ_only_for_old_six_column_plans",
    }
    args.output_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())