#!/usr/bin/env python3
"""Join source geometry and native grip evidence to classify grip0 response.

The report is read-only.  It measures the remaining absolute-target error in
the native grip0 radial frame so a CAD-internal controller can use the axis the
TDbDimension2 object actually accepts instead of treating grip0 as a free 2-D
point.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def arc_center(row: dict[str, str]) -> tuple[float, float]:
    x1, y1 = float(row["START_X"]), float(row["START_Y"])
    x2, y2 = float(row["END_X"]), float(row["END_Y"])
    bulge = float(row["BULGE"])
    dx, dy = x2 - x1, y2 - y1
    chord = math.hypot(dx, dy)
    if chord <= 1.0e-12 or abs(bulge) <= 1.0e-12:
        raise ValueError("degenerate arc")
    midpoint_x, midpoint_y = (x1 + x2) * 0.5, (y1 + y2) * 0.5
    # Signed distance from chord midpoint to centre.  Positive bulge puts the
    # arc on the chord's left, so the centre lies on the opposite side for a
    # sub-semicircle and the sign naturally flips for major arcs.
    offset = chord * (1.0 - bulge * bulge) / (4.0 * bulge)
    left_x, left_y = -dy / chord, dx / chord
    return midpoint_x + left_x * offset, midpoint_y + left_y * offset


def unit_axis(
    geometry: dict[str, str], grip_x: float, grip_y: float
) -> tuple[float, float, str]:
    if geometry["SEGMENT_TYPE"].upper() == "ARC":
        cx, cy = arc_center(geometry)
        ax, ay = grip_x - cx, grip_y - cy
        kind = "ARC_RADIAL"
    else:
        dx = float(geometry["END_X"]) - float(geometry["START_X"])
        dy = float(geometry["END_Y"]) - float(geometry["START_Y"])
        ax, ay = -dy, dx
        kind = "LINE_NORMAL"
    length = math.hypot(ax, ay)
    if length <= 1.0e-12:
        raise ValueError("zero control axis")
    return ax / length, ay / length, kind


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--mapping", type=Path, required=True)
    parser.add_argument("--grips", type=Path, required=True)
    parser.add_argument("--convergence", type=Path, required=True)
    parser.add_argument("--output-tsv", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    args = parser.parse_args()

    geometry = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in read_tsv(args.geometry)
    }
    mapping = {
        row["NATIVE_HANDLE"].upper(): row
        for row in read_tsv(args.mapping)
        if row.get("STATUS", "").upper() == "PASS" and row.get("NATIVE_HANDLE")
    }
    grips = {
        row["HANDLE"].upper(): row
        for row in read_tsv(args.grips)
        if int(row["GRIP_INDEX"]) == 0
    }
    convergence = [
        row
        for row in read_tsv(args.convergence)
        if row.get("HANDLE", "").upper() != "SUMMARY"
    ]

    output: list[dict[str, object]] = []
    by_status: Counter[str] = Counter()
    by_source: dict[str, Counter[str]] = defaultdict(Counter)
    tangential_dominant = 0
    radial_reachable = 0
    missing: list[str] = []

    for result in convergence:
        handle = result["HANDLE"].upper()
        if handle not in mapping or handle not in grips:
            missing.append(handle)
            continue
        mapped = mapping[handle]
        key = (mapped["SOURCE_HANDLE"].upper(), int(mapped["SEGMENT_INDEX"]))
        if key not in geometry:
            missing.append(handle)
            continue
        segment = geometry[key]
        grip = grips[handle]
        gx, gy = float(grip["GRIP_X"]), float(grip["GRIP_Y"])
        tx, ty = float(result["TARGET_X"]), float(result["TARGET_Y"])
        ex, ey = tx - gx, ty - gy
        ux, uy, axis_kind = unit_axis(segment, gx, gy)
        radial = ex * ux + ey * uy
        tangential = ex * (-uy) + ey * ux
        total = math.hypot(ex, ey)
        radial_abs, tangent_abs = abs(radial), abs(tangential)
        tangent_ratio = tangent_abs / total if total > 1.0e-12 else 0.0
        classification = (
            "AT_TARGET"
            if total <= 1.0e-6
            else "TANGENTIAL_DOMINANT"
            if tangent_abs > radial_abs
            else "RADIAL_DOMINANT"
        )
        if classification == "TANGENTIAL_DOMINANT":
            tangential_dominant += 1
        if radial_abs > 1.0e-6:
            radial_reachable += 1
        status = result["STATUS"]
        by_status[status] += 1
        by_source[key[0]][status] += 1
        output.append(
            {
                "HANDLE": handle,
                "SOURCE_HANDLE": key[0],
                "SEGMENT_INDEX": key[1],
                "SEGMENT_TYPE": segment["SEGMENT_TYPE"],
                "AXIS_KIND": axis_kind,
                "STATUS": status,
                "START_ERROR": float(result["START_ERROR"]),
                "FINAL_ERROR": float(result["FINAL_ERROR"]),
                "CURRENT_ERROR": total,
                "RADIAL_RESIDUAL": radial,
                "TANGENTIAL_RESIDUAL": tangential,
                "TANGENTIAL_RATIO": tangent_ratio,
                "CLASSIFICATION": classification,
                "ATTEMPTS": int(result["ATTEMPTS"]),
                "COMMITS": int(result["IMPROVEMENT_COMMITS"]),
            }
        )

    fields = list(output[0].keys()) if output else []
    args.output_tsv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_tsv.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t")
        writer.writeheader()
        writer.writerows(output)

    failed = [row for row in output if row["STATUS"] != "PASS"]
    summary = {
        "schema_version": 1,
        "row_count": len(output),
        "missing_handles": missing,
        "status_counts": dict(sorted(by_status.items())),
        "source_status_counts": {
            source: dict(sorted(counts.items()))
            for source, counts in sorted(by_source.items())
        },
        "failed_count": len(failed),
        "failed_tangential_dominant_count": sum(
            row["CLASSIFICATION"] == "TANGENTIAL_DOMINANT" for row in failed
        ),
        "failed_radial_dominant_count": sum(
            row["CLASSIFICATION"] == "RADIAL_DOMINANT" for row in failed
        ),
        "all_tangential_dominant_count": tangential_dominant,
        "radial_residual_above_tolerance_count": radial_reachable,
        "failed_max_tangential_ratio": max(
            (float(row["TANGENTIAL_RATIO"]) for row in failed), default=0.0
        ),
        "failed_median_tangential_ratio": (
            sorted(float(row["TANGENTIAL_RATIO"]) for row in failed)[len(failed) // 2]
            if failed
            else 0.0
        ),
        "interpretation": (
            "A free-XY absolute target is incompatible with a native grip0 that "
            "projects requests onto its current radial.  Use a scalar target "
            "radius and radial residual control; audit the remaining tangential "
            "component as planner error rather than retrying it in CAD."
        ),
    }
    args.output_json.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
