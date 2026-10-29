#!/usr/bin/env python3
"""Audit hard visual collisions of native Tianzheng arc-angle dimensions.

The audit is drawing-coordinate based and deliberately narrow:

* text bodies must not overlap one another;
* text proximity to the displayed thick-blue source corridor is reported as a
  soft condition because the approved manual reference permits partial
  text/line overlap where a short arc has no wider corridor;
* text bodies must not overlap native arrow footprints;
* non-adjacent dimension arcs must not cross.

Thin dimension-line/text crossings are intentionally not failures.  The user
has confirmed that this is an acceptable last-resort condition when a short
arc has no wider placement corridor.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path

from annotation_vector_geometry import (
    ConvexPolygon,
    Polyline,
    VectorPoint,
    conservative_arrow,
    oriented_box,
    polygons_overlap,
    polylines_intersect,
    segments_intersect,
)


@dataclass(frozen=True)
class ArcState:
    source: str
    segment: int
    handle: str
    center: VectorPoint
    source_radius: float
    dimension_radius: float
    start_angle: float
    sweep: float
    source_line: Polyline
    dimension_line: Polyline
    arrows: tuple[ConvexPolygon, ConvexPolygon]


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def point(x: float, y: float) -> VectorPoint:
    return VectorPoint(float(x), float(y))


def distance(first: VectorPoint, second: VectorPoint) -> float:
    return math.hypot(first.x - second.x, first.y - second.y)


def point_segment_distance(p: VectorPoint, a: VectorPoint, b: VectorPoint) -> float:
    dx, dy = b.x - a.x, b.y - a.y
    length2 = dx * dx + dy * dy
    if length2 <= 1.0e-18:
        return distance(p, a)
    scale = max(0.0, min(1.0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
    return distance(p, VectorPoint(a.x + scale * dx, a.y + scale * dy))


def segment_distance(a: VectorPoint, b: VectorPoint, c: VectorPoint, d: VectorPoint) -> float:
    if segments_intersect(a, b, c, d):
        return 0.0
    return min(
        point_segment_distance(a, c, d),
        point_segment_distance(b, c, d),
        point_segment_distance(c, a, b),
        point_segment_distance(d, a, b),
    )


def polyline_polygon_distance(line: Polyline, polygon: ConvexPolygon) -> float:
    edges = tuple(
        (polygon.points[index], polygon.points[(index + 1) % len(polygon.points)])
        for index in range(len(polygon.points))
    )
    return min(
        segment_distance(line.points[index], line.points[index + 1], left, right)
        for index in range(len(line.points) - 1)
        for left, right in edges
    )


def sample_arc(center: VectorPoint, radius: float, start_angle: float, sweep: float, max_step: float) -> Polyline:
    count = max(2, int(math.ceil(abs(sweep) / max_step)) + 1)
    points = tuple(
        VectorPoint(
            center.x + radius * math.cos(start_angle + sweep * index / (count - 1)),
            center.y + radius * math.sin(start_angle + sweep * index / (count - 1)),
        )
        for index in range(count)
    )
    return Polyline(points, "arc")


def text_obb(row: dict[str, str], height: float) -> ConvexPolygon:
    min_x, min_y = float(row["MIN_X"]), float(row["MIN_Y"])
    max_x, max_y = float(row["MAX_X"]), float(row["MAX_Y"])
    rotation = float(row.get("ROTATION", "0") or 0.0)
    cos_value, sin_value = abs(math.cos(rotation)), abs(math.sin(rotation))
    aabb_width, aabb_height = max_x - min_x, max_y - min_y
    estimates: list[float] = []
    if cos_value > 1.0e-6:
        estimates.append(max(0.0, (aabb_width - sin_value * height) / cos_value))
    if sin_value > 1.0e-6:
        estimates.append(max(0.0, (aabb_height - cos_value * height) / sin_value))
    width = max(height, sum(estimates) / len(estimates)) if estimates else max(aabb_width, height)
    return oriented_box(
        VectorPoint((min_x + max_x) * 0.5, (min_y + max_y) * 0.5),
        VectorPoint(math.cos(rotation), math.sin(rotation)),
        width,
        height,
        "text",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--mapping", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--text-height", required=True, type=float)
    parser.add_argument("--source", action="append", required=True)
    parser.add_argument("--blue-halfwidth-h", type=float, default=0.22)
    parser.add_argument("--arrow-size-h", type=float, default=0.50)
    parser.add_argument("--arc-step-degrees", type=float, default=2.0)
    parser.add_argument("--output-tsv", required=True, type=Path)
    parser.add_argument("--output-json", required=True, type=Path)
    args = parser.parse_args()
    if min(args.text_height, args.blue_halfwidth_h, args.arrow_size_h, args.arc_step_degrees) <= 0.0:
        raise SystemExit("all geometry controls must be positive")

    sources = {item.upper() for item in args.source}
    geometry = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row
        for row in read_tsv(args.geometry)
        if row["SOURCE_HANDLE"].upper() in sources
    }
    mapping = {
        (row["SOURCE_HANDLE"].upper(), int(row["SEGMENT_INDEX"])): row["NATIVE_HANDLE"].upper()
        for row in read_tsv(args.mapping)
        if row.get("STATUS") == "PASS" and row["SOURCE_HANDLE"].upper() in sources
    }
    if set(geometry) != set(mapping):
        raise SystemExit(f"geometry/mapping mismatch: {sorted(set(geometry) ^ set(mapping))}")

    wanted_handles = set(mapping.values())
    grips: dict[str, dict[int, VectorPoint]] = {}
    for row in read_tsv(args.grips):
        handle = row["HANDLE"].upper()
        if handle in wanted_handles:
            grips.setdefault(handle, {})[int(row["GRIP_INDEX"])] = point(row["GRIP_X"], row["GRIP_Y"])
    bbox_rows = {
        row["SOURCE_HANDLE"].upper(): row
        for row in read_tsv(args.text_bboxes)
        if row["SOURCE_HANDLE"].upper() in wanted_handles
    }
    if set(bbox_rows) != wanted_handles:
        raise SystemExit(f"missing text boxes: {sorted(wanted_handles - set(bbox_rows))}")

    boxes = {handle: text_obb(row, args.text_height) for handle, row in bbox_rows.items()}
    states: dict[tuple[str, int], ArcState] = {}
    step = math.radians(args.arc_step_degrees)
    arrow_size = args.arrow_size_h * args.text_height
    for key, row in geometry.items():
        handle = mapping[key]
        native = grips.get(handle, {})
        if not all(index in native for index in (0, 2, 3)):
            raise SystemExit(f"{handle}: missing grips 0/2/3")
        center = point(row["CENTER_X"], row["CENTER_Y"])
        start = point(row["START_X"], row["START_Y"])
        source_radius = float(row["RADIUS"])
        dimension_radius = distance(native[0], center)
        start_angle = math.atan2(start.y - center.y, start.x - center.x)
        sweep = math.radians(float(row["SWEEP_DEGREES"]))
        source_line = sample_arc(center, source_radius, start_angle, sweep, step)
        dimension_line = sample_arc(center, dimension_radius, start_angle, sweep, step)
        start_tip, end_tip = dimension_line.points[0], dimension_line.points[-1]
        start_tangent = VectorPoint(
            dimension_line.points[1].x - start_tip.x,
            dimension_line.points[1].y - start_tip.y,
        )
        end_tangent = VectorPoint(
            dimension_line.points[-2].x - end_tip.x,
            dimension_line.points[-2].y - end_tip.y,
        )
        arrows = (
            conservative_arrow(start_tip, start_tangent, arrow_size),
            conservative_arrow(end_tip, end_tangent, arrow_size),
        )
        states[key] = ArcState(
            key[0], key[1], handle, center, source_radius, dimension_radius,
            start_angle, sweep, source_line, dimension_line, arrows,
        )

    violations: list[dict[str, object]] = []
    soft_conditions: list[dict[str, object]] = []
    ordered = sorted(states)

    for index, key in enumerate(ordered):
        state, box = states[key], boxes[states[key].handle]
        clearance = polyline_polygon_distance(state.source_line, box)
        hard_blue_clearance = args.blue_halfwidth_h * args.text_height
        if clearance < hard_blue_clearance:
            soft_conditions.append({
                "TYPE": "SOFT_TEXT_BLUE_PROXIMITY", "FIRST": state.handle, "SECOND": state.source,
                "SOURCE": state.source, "SEGMENT": state.segment,
                "MEASURED": clearance, "REQUIRED": hard_blue_clearance,
            })
        for arrow_index, arrow in enumerate(state.arrows):
            if polygons_overlap(box, arrow):
                violations.append({
                    "TYPE": "TEXT_OWN_ARROW_OVERLAP", "FIRST": state.handle,
                    "SECOND": f"{state.handle}:ARROW:{arrow_index}", "SOURCE": state.source,
                    "SEGMENT": state.segment, "MEASURED": 0.0, "REQUIRED": arrow_size,
                })
        for second_key in ordered[index + 1:]:
            second = states[second_key]
            second_box = boxes[second.handle]
            if polygons_overlap(box, second_box):
                violations.append({
                    "TYPE": "TEXT_TEXT_OVERLAP", "FIRST": state.handle, "SECOND": second.handle,
                    "SOURCE": state.source, "SEGMENT": state.segment,
                    "MEASURED": 0.0, "REQUIRED": 0.0,
                })
            for arrow_index, arrow in enumerate(second.arrows):
                if polygons_overlap(box, arrow):
                    violations.append({
                        "TYPE": "TEXT_OTHER_ARROW_OVERLAP", "FIRST": state.handle,
                        "SECOND": f"{second.handle}:ARROW:{arrow_index}", "SOURCE": state.source,
                        "SEGMENT": state.segment, "MEASURED": 0.0, "REQUIRED": arrow_size,
                    })
            for arrow_index, arrow in enumerate(state.arrows):
                if polygons_overlap(second_box, arrow):
                    violations.append({
                        "TYPE": "TEXT_OTHER_ARROW_OVERLAP", "FIRST": second.handle,
                        "SECOND": f"{state.handle}:ARROW:{arrow_index}", "SOURCE": second.source,
                        "SEGMENT": second.segment, "MEASURED": 0.0, "REQUIRED": arrow_size,
                    })
            if state.source != second.source:
                continue
            count = len([candidate for candidate in ordered if candidate[0] == state.source])
            adjacent = abs(state.segment - second.segment) == 1 or {state.segment, second.segment} == {0, count - 1}
            if not adjacent and polylines_intersect(state.dimension_line, second.dimension_line):
                violations.append({
                    "TYPE": "NONADJACENT_DIMENSION_ARC_CROSS", "FIRST": state.handle,
                    "SECOND": second.handle, "SOURCE": state.source, "SEGMENT": state.segment,
                    "MEASURED": 0.0, "REQUIRED": 0.0,
                })

    fields = ["TYPE", "FIRST", "SECOND", "SOURCE", "SEGMENT", "MEASURED", "REQUIRED"]
    write_tsv(args.output_tsv, violations + soft_conditions, fields)
    counts: dict[str, int] = {}
    for violation in violations:
        counts[str(violation["TYPE"])] = counts.get(str(violation["TYPE"]), 0) + 1
    soft_counts: dict[str, int] = {}
    for condition in soft_conditions:
        soft_counts[str(condition["TYPE"])] = soft_counts.get(str(condition["TYPE"]), 0) + 1
    summary = {
        "status": "PASS" if not violations else "FAIL",
        "source_count": len(sources),
        "arc_count": len(states),
        "text_height": args.text_height,
        "blue_halfwidth_h": args.blue_halfwidth_h,
        "arrow_size_h": args.arrow_size_h,
        "violation_count": len(violations),
        "violation_counts": counts,
        "soft_condition_count": len(soft_conditions),
        "soft_condition_counts": soft_counts,
        "thin_dimension_line_text_overlap_policy": "ALLOWED_IF_NEEDED",
        "blue_line_text_proximity_policy": "SOFT_IF_NO_WIDER_CORRIDOR",
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False))
    return 0 if not violations else 2


if __name__ == "__main__":
    raise SystemExit(main())
