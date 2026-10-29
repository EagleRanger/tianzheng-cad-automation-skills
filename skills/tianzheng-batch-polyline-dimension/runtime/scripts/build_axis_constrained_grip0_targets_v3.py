#!/usr/bin/env python3
"""Build scalar native grip0 contracts from a quantified layout plan.

TDbDimension2 grip0 is not a free WCS point.  The authoritative target is the
signed radial/normal scalar band, not the preview XY point.  Text boxes are not
an axis source: they remain planner-only collision evidence.
"""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path

from analyze_quantized_grip_response_v1 import arc_center, read_tsv


def grip0_rows(path: Path) -> dict[str, tuple[float, float, float]]:
    result: dict[str, tuple[float, float, float]] = {}
    for row in read_tsv(path):
        if int(row["GRIP_INDEX"]) != 0:
            continue
        handle = row["HANDLE"].upper()
        if handle in result:
            raise SystemExit(f"duplicate grip0: {handle}")
        result[handle] = (
            float(row["GRIP_X"]),
            float(row["GRIP_Y"]),
            float(row["GRIP_Z"]),
        )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed-grips", type=Path, required=True)
    parser.add_argument("--current-grips", type=Path, required=True)
    parser.add_argument("--delta-plan", type=Path, required=True)
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--mapping", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--tolerance", type=float, default=1.0e-6)
    args = parser.parse_args()
    if args.tolerance <= 0.0:
        raise SystemExit("tolerance must be positive")

    seed = grip0_rows(args.seed_grips)
    current = grip0_rows(args.current_grips)
    geometry = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in read_tsv(args.geometry)
    }
    mapping = {
        row["NATIVE_HANDLE"].upper(): (
            row["SOURCE_HANDLE"].upper(),
            int(row["SEGMENT_INDEX"]),
        )
        for row in read_tsv(args.mapping)
        if row.get("STATUS", "").upper() == "PASS" and row.get("NATIVE_HANDLE")
    }

    targets: list[dict[str, str]] = []
    audit: list[dict[str, str]] = []
    seen: set[str] = set()
    for row in read_tsv(args.delta_plan):
        handle = row["HANDLE"].upper()
        if handle in seen:
            raise SystemExit(f"duplicate plan handle: {handle}")
        seen.add(handle)
        if int(row["GRIP_INDEX"]) != 0:
            raise SystemExit(f"non-grip0 plan row: {handle}")
        if handle not in seed or handle not in current or handle not in mapping:
            raise SystemExit(f"missing seed/current/mapping: {handle}")
        key = mapping[handle]
        if key not in geometry:
            raise SystemExit(f"missing geometry: {handle}:{key[0]}:{key[1]}")

        sx, sy, sz = seed[handle]
        cx0, cy0, cz0 = current[handle]
        intended_x = sx + float(row["DX"])
        intended_y = sy + float(row["DY"])
        intended_z = sz + float(row["DZ"])
        segment = geometry[key]

        explicit_band = row.get("TARGET_SIGNED_BAND", "").strip()
        if segment["SEGMENT_TYPE"].upper() == "ARC":
            center_x, center_y = arc_center(segment)
            anchor_x, anchor_y = center_x, center_y
            source_radius = math.hypot(
                float(segment["START_X"]) - center_x,
                float(segment["START_Y"]) - center_y,
            )
            target_scalar = (
                source_radius + float(explicit_band)
                if explicit_band
                else math.hypot(intended_x - center_x, intended_y - center_y)
            )
            if target_scalar <= 1.0e-12:
                raise SystemExit(f"nonpositive arc target radius: {handle}")
            current_radius = math.hypot(cx0 - center_x, cy0 - center_y)
            if current_radius <= 1.0e-12:
                raise SystemExit(f"grip0 at arc centre: {handle}")
            ux, uy = (cx0 - center_x) / current_radius, (cy0 - center_y) / current_radius
            axis_x, axis_y = ux, uy
            target_x = center_x + ux * target_scalar
            target_y = center_y + uy * target_scalar
            current_scalar = current_radius
            axis_kind = "ARC_RADIUS"
            target_band_source = "EXPLICIT_SIGNED_BAND" if explicit_band else "LEGACY_VECTOR_MAGNITUDE"
        elif segment["SEGMENT_TYPE"].upper() == "LINE":
            dx = float(segment["END_X"]) - float(segment["START_X"])
            dy = float(segment["END_Y"]) - float(segment["START_Y"])
            length = math.hypot(dx, dy)
            if length <= 1.0e-12:
                raise SystemExit(f"degenerate line: {handle}")
            nx, ny = -dy / length, dx / length
            source_mid_x = 0.5 * (float(segment["START_X"]) + float(segment["END_X"]))
            source_mid_y = 0.5 * (float(segment["START_Y"]) + float(segment["END_Y"]))
            anchor_x, anchor_y = source_mid_x, source_mid_y
            axis_x, axis_y = nx, ny
            target_scalar = (
                float(explicit_band)
                if explicit_band
                else (intended_x - source_mid_x) * nx + (intended_y - source_mid_y) * ny
            )
            current_scalar = (cx0 - source_mid_x) * nx + (cy0 - source_mid_y) * ny
            scalar_delta = target_scalar - current_scalar
            target_x = cx0 + nx * scalar_delta
            target_y = cy0 + ny * scalar_delta
            axis_kind = "LINE_NORMAL_DISTANCE"
            target_band_source = "EXPLICIT_SIGNED_BAND" if explicit_band else "LEGACY_VECTOR_PROJECTION"
        else:
            raise SystemExit(f"unsupported segment type: {handle}:{segment['SEGMENT_TYPE']}")

        target = {
            "HANDLE": handle,
            "GRIP_INDEX": "0",
            "TARGET_X": repr(target_x),
            "TARGET_Y": repr(target_y),
            "TARGET_Z": repr(intended_z if abs(intended_z - cz0) > args.tolerance else cz0),
            "TOLERANCE": repr(args.tolerance),
            "AXIS_KIND": axis_kind,
            "ANCHOR_X": repr(anchor_x),
            "ANCHOR_Y": repr(anchor_y),
            "AXIS_X": repr(axis_x),
            "AXIS_Y": repr(axis_y),
            "TARGET_SCALAR": repr(target_scalar),
        }
        targets.append(target)
        audit.append(
            {
                "HANDLE": handle,
                "SOURCE_HANDLE": key[0],
                "SEGMENT_INDEX": str(key[1]),
                "SEGMENT_TYPE": segment["SEGMENT_TYPE"],
                "AXIS_KIND": axis_kind,
                "TARGET_BAND_SOURCE": target_band_source,
                "CURRENT_SCALAR": repr(current_scalar),
                "TARGET_SCALAR": repr(target_scalar),
                "SCALAR_RESIDUAL": repr(target_scalar - current_scalar),
                "AXIS_X": repr(axis_x),
                "AXIS_Y": repr(axis_y),
                "ANCHOR_X": repr(anchor_x),
                "ANCHOR_Y": repr(anchor_y),
                "TARGET_POINT_ROLE": "PREVIEW_ONLY__SCALAR_CONTRACT_AUTHORITATIVE",
                "DISCARDED_TANGENTIAL_DISTANCE": repr(
                    math.hypot(intended_x - target_x, intended_y - target_y)
                ),
            }
        )

    if not targets:
        raise SystemExit("axis-constrained target plan is empty")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=[
                "HANDLE", "GRIP_INDEX", "TARGET_X", "TARGET_Y", "TARGET_Z", "TOLERANCE",
                "AXIS_KIND", "ANCHOR_X", "ANCHOR_Y", "AXIS_X", "AXIS_Y", "TARGET_SCALAR",
            ],
            delimiter="\t",
            quoting=csv.QUOTE_NONE,
            lineterminator="\n",
            escapechar="\\",
        )
        writer.writeheader()
        writer.writerows(targets)
    with args.audit.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(audit[0]), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(audit)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
