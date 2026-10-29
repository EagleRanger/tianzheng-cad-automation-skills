#!/usr/bin/env python3
"""Plan one quantified native grip-0 band for mixed ARC/LINE source paths.

The planner is drawing-data driven.  It reads the live segment inventory,
native source mapping, actual text heights and per-source polyline widths.  A
closed source is placed on its topological exterior; an open source preserves
the currently generated side.  Only native grip 0 is moved.  Text-state and
along-path correction are separate, later stages.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

from annotation_layout_formula import load_vector_layout_formula, quantified_common_band_h


ROOT = Path(__file__).resolve().parents[1]


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict[str, object]], fields: tuple[str, ...]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def circle_through(start, mid, end):
    # Translate to a local origin before squaring coordinates. Project WCS
    # values can be tens of millions; the global determinant formula loses
    # centimetres there and can make an exactly closed path look open.
    ax, ay = start
    bx, by = mid[0] - ax, mid[1] - ay
    cx, cy = end[0] - ax, end[1] - ay
    determinant = 2.0 * (bx * cy - cx * by)
    if abs(determinant) <= 1.0e-10:
        raise ValueError("degenerate arc points")
    b2, c2 = bx * bx + by * by, cx * cx + cy * cy
    local_x = (b2 * cy - c2 * by) / determinant
    local_y = (c2 * bx - b2 * cx) / determinant
    center = ax + local_x, ay + local_y
    return center, math.hypot(local_x, local_y)


def signed_sweep_through(start_angle: float, mid_angle: float, end_angle: float) -> float:
    ccw_end = (end_angle - start_angle) % (2.0 * math.pi)
    ccw_mid = (mid_angle - start_angle) % (2.0 * math.pi)
    return ccw_end if ccw_mid <= ccw_end + 1.0e-10 else ccw_end - 2.0 * math.pi


def sample_segment(row: dict[str, str], maximum_step_degrees: float = 6.0):
    start = (float(row["START_X"]), float(row["START_Y"]))
    mid = (float(row["MID_X"]), float(row["MID_Y"]))
    end = (float(row["END_X"]), float(row["END_Y"]))
    if row["SEGMENT_TYPE"].upper() == "LINE":
        return [start, end]
    center, radius = circle_through(start, mid, end)
    angles = tuple(math.atan2(point[1] - center[1], point[0] - center[0]) for point in (start, mid, end))
    sweep = signed_sweep_through(*angles)
    count = max(2, int(math.ceil(abs(math.degrees(sweep)) / maximum_step_degrees)))
    return [
        (
            center[0] + radius * math.cos(angles[0] + sweep * index / count),
            center[1] + radius * math.sin(angles[0] + sweep * index / count),
        )
        for index in range(count + 1)
    ]


def source_polygon(rows: list[dict[str, str]]):
    ordered = sorted(rows, key=lambda row: int(row["SEGMENT_INDEX"]))
    if not ordered:
        return [], False
    points = []
    for row in ordered:
        sampled = sample_segment(row)
        points.extend(sampled if not points else sampled[1:])
    declared = {
        row.get("SOURCE_CLOSED", "").strip().upper()
        for row in ordered
        if row.get("SOURCE_CLOSED", "").strip()
    }
    if len(declared) > 1 or declared - {"TRUE", "FALSE"}:
        raise ValueError("inconsistent native source closed state")
    raw_start = float(ordered[0]["START_X"]), float(ordered[0]["START_Y"])
    raw_end = float(ordered[-1]["END_X"]), float(ordered[-1]["END_Y"])
    raw_closed = len(points) >= 4 and math.dist(raw_start, raw_end) <= 1.0e-5
    closed = (next(iter(declared)) == "TRUE") if declared else raw_closed
    return points, closed


def point_in_polygon(point, polygon) -> bool:
    x, y = point
    inside = False
    previous = polygon[-1]
    for current in polygon:
        x1, y1 = previous
        x2, y2 = current
        if (y1 > y) != (y2 > y):
            crossing = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < crossing:
                inside = not inside
        previous = current
    return inside


def orientation(dx: float, dy: float) -> str:
    if abs(dy) >= abs(dx):
        return "TOP" if dy >= 0.0 else "BOTTOM"
    return "RIGHT" if dx >= 0.0 else "LEFT"


def polygon_signed_area(polygon) -> float:
    return 0.5 * sum(
        x1 * y2 - x2 * y1
        for (x1, y1), (x2, y2) in zip(polygon, polygon[1:] + polygon[:1])
    )


def choose_signed_target(current_signed: float, band: float, base_point, normal, polygon, closed, tangent=None):
    signs = (1.0, -1.0) if closed else ((1.0,) if current_signed >= 0.0 else (-1.0,))
    if closed:
        # For a simple closed path, traversal orientation and the local source
        # tangent define the exterior exactly.  This avoids treating the true
        # arc boundary as outside a coarse chord-sampled polygon.
        if tangent is not None:
            area = polygon_signed_area(polygon)
            if abs(area) > 1.0e-8:
                interior_normal = (
                    (-tangent[1], tangent[0])
                    if area > 0.0
                    else (tangent[1], -tangent[0])
                )
                positive_points_inside = (
                    normal[0] * interior_normal[0] + normal[1] * interior_normal[1]
                ) > 0.0
                return (-band if positive_points_inside else band)

        # Determine topology side immediately beside the source boundary.  A
        # full annotation band can cross a narrow closed loop, making both
        # distant candidates appear outside even though only one direction is
        # the local exterior.
        probe = max(1.0e-4, min(abs(band) * 0.05, 0.05))
        outside_signs = []
        for sign in signs:
            point = (
                base_point[0] + normal[0] * sign * probe,
                base_point[1] + normal[1] * sign * probe,
            )
            if not point_in_polygon(point, polygon):
                outside_signs.append(sign)
        if len(outside_signs) == 1:
            return outside_signs[0] * band

        # Retain the distant candidate as a bounded fallback for coarse or
        # imperfect source polygons.  Ambiguity still stops planning instead
        # of silently choosing an inside direction.
        outside_targets = []
        for sign in signs:
            target_signed = sign * band
            point = (
                base_point[0] + normal[0] * target_signed,
                base_point[1] + normal[1] * target_signed,
            )
            if not point_in_polygon(point, polygon):
                outside_targets.append(target_signed)
        if len(outside_targets) != 1:
            raise ValueError("closed source has no unique exterior band candidate")
        return outside_targets[0]
    return signs[0] * band


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--source-styles", required=True, type=Path)
    parser.add_argument("--formula", type=Path, default=ROOT / "config" / "annotation_vector_layout_formula_v2.json")
    parser.add_argument("--output-plan", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--output-summary", required=True, type=Path)
    args = parser.parse_args()

    formula = load_vector_layout_formula(args.formula)
    geometry_rows = [row for row in read_tsv(args.geometry) if row["SEGMENT_TYPE"].upper() in {"ARC", "LINE"}]
    geometry = {(row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row for row in geometry_rows}
    mapping_rows = [row for row in read_tsv(args.mapping) if row.get("STATUS", "").upper() == "PASS"]
    mapping = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row["NATIVE_HANDLE"].upper()
        for row in mapping_rows
    }
    if set(geometry) != set(mapping):
        raise SystemExit(f"geometry/mapping mismatch: {sorted(set(geometry) ^ set(mapping))}")
    wanted_handles = set(mapping.values())
    grip0 = {}
    for row in read_tsv(args.grips):
        handle = row["HANDLE"].upper()
        if handle in wanted_handles and int(row["GRIP_INDEX"]) == 0:
            grip0[handle] = (float(row["GRIP_X"]), float(row["GRIP_Y"]))
    text_heights = {
        row["SOURCE_HANDLE"].upper(): float(row.get("HEIGHT", "") or row.get("TEXT_HEIGHT", "") or 0.0)
        for row in read_tsv(args.text_bboxes)
        if row.get("SOURCE_HANDLE", "").upper() in wanted_handles
    }
    widths = {}
    for row in read_tsv(args.source_styles):
        handle = (row.get("HANDLE") or row.get("SOURCE_HANDLE") or "").upper()
        if handle and row.get("CONSTANT_WIDTH", "") != "":
            widths[handle] = float(row["CONSTANT_WIDTH"])

    rows_by_source = {}
    for row in geometry_rows:
        rows_by_source.setdefault(row["SOURCE_HANDLE"].upper(), []).append(row)
    source_bands = {}
    source_polygons = {}
    for source, rows in rows_by_source.items():
        handles = [mapping[(source, int(row["SEGMENT_INDEX"]))] for row in rows]
        missing = [handle for handle in handles if handle not in grip0 or text_heights.get(handle, 0.0) <= 0.0]
        if missing:
            raise SystemExit(f"{source}: missing grip0 or measured text height: {missing}")
        if source not in widths:
            raise SystemExit(f"{source}: missing measured CONSTANT_WIDTH")
        reference_height = max(text_heights[handle] for handle in handles)
        raw_h, snapped_h = quantified_common_band_h(
            text_height=reference_height,
            source_width=widths[source],
            target_text_radial_thicknesses=tuple(text_heights[handle] for handle in handles),
            rule=formula.quantified_common_band,
            candidate_bands_h=formula.two_pass_batch_policy.candidate_bands_h,
        )
        polygon, closed = source_polygon(rows)
        source_polygons[source] = (polygon, closed)
        source_bands[source] = {
            "reference_height": reference_height,
            "source_width": widths[source],
            "raw_band_h": raw_h,
            "snapped_band_h": snapped_h,
            "absolute_band": snapped_h * reference_height,
            "closed": closed,
        }

    plan = []
    audit = []
    for key in sorted(geometry):
        source, segment = key
        row = geometry[key]
        handle = mapping[key]
        current = grip0[handle]
        start = (float(row["START_X"]), float(row["START_Y"]))
        mid = (float(row["MID_X"]), float(row["MID_Y"]))
        end = (float(row["END_X"]), float(row["END_Y"]))
        polygon, closed = source_polygons[source]
        band = source_bands[source]["absolute_band"]
        if row["SEGMENT_TYPE"].upper() == "ARC":
            center, radius = circle_through(start, mid, end)
            vector = (current[0] - center[0], current[1] - center[1])
            current_radius = math.hypot(*vector)
            if current_radius <= 1.0e-9:
                raise SystemExit(f"{handle}: degenerate arc grip0")
            normal = (vector[0] / current_radius, vector[1] / current_radius)
            current_signed = current_radius - radius
            source_point = (center[0] + normal[0] * radius, center[1] + normal[1] * radius)
            start_angle = math.atan2(start[1] - center[1], start[0] - center[0])
            mid_angle = math.atan2(mid[1] - center[1], mid[0] - center[0])
            end_angle = math.atan2(end[1] - center[1], end[0] - center[0])
            sweep = signed_sweep_through(start_angle, mid_angle, end_angle)
            tangent = (-normal[1], normal[0]) if sweep > 0.0 else (normal[1], -normal[0])
            target_signed = choose_signed_target(
                current_signed, band, source_point, normal, polygon, closed, tangent
            )
        else:
            tangent = (end[0] - start[0], end[1] - start[1])
            length = math.hypot(*tangent)
            if length <= 1.0e-9:
                raise SystemExit(f"{handle}: degenerate line segment")
            normal = (-tangent[1] / length, tangent[0] / length)
            current_signed = (current[0] - mid[0]) * normal[0] + (current[1] - mid[1]) * normal[1]
            unit_tangent = (tangent[0] / length, tangent[1] / length)
            target_signed = choose_signed_target(
                current_signed, band, mid, normal, polygon, closed, unit_tangent
            )
        delta = target_signed - current_signed
        dx, dy = normal[0] * delta, normal[1] * delta
        if math.hypot(dx, dy) > 1.0e-8:
            plan.append({"HANDLE": handle, "GRIP_INDEX": 0, "DX": dx, "DY": dy, "DZ": 0.0})
        audit.append({
            "SOURCE_HANDLE": source,
            "SEGMENT_INDEX": segment,
            "SEGMENT_TYPE": row["SEGMENT_TYPE"].upper(),
            "NATIVE_HANDLE": handle,
            "CURRENT_SIGNED_BAND": current_signed,
            "TARGET_SIGNED_BAND": target_signed,
            "TARGET_ORIENTATION": orientation(normal[0] * target_signed, normal[1] * target_signed),
            "DX": dx,
            "DY": dy,
            "SOURCE_PATH_CLOSED": str(closed).upper(),
        })

    write_tsv(args.output_plan, plan, ("HANDLE", "GRIP_INDEX", "DX", "DY", "DZ"))
    write_tsv(
        args.output_audit,
        audit,
        (
            "SOURCE_HANDLE", "SEGMENT_INDEX", "SEGMENT_TYPE", "NATIVE_HANDLE",
            "CURRENT_SIGNED_BAND", "TARGET_SIGNED_BAND", "TARGET_ORIENTATION",
            "DX", "DY", "SOURCE_PATH_CLOSED",
        ),
    )
    payload = {
        "status": "PASS",
        "formula_id": formula.formula_id,
        "planning_unit": "one_continuous_source_polyline",
        "source_bands": source_bands,
        "target_count": len(audit),
        "move_count": len(plan),
        "mutable_grip_indexes": [0],
        "next_stage": "NATIVE_TEXT_PRESERVATION_AUDIT",
    }
    args.output_summary.parent.mkdir(parents=True, exist_ok=True)
    args.output_summary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
