#!/usr/bin/env python3
"""Audit native Tianzheng angle text against its own thick source arc.

This complements text-vs-text collision checks.  Tianzheng can keep two text
boxes disjoint while pushing a short-arc label onto the source polyline.  The
audit therefore maps every generated native dimension back to its source arc
and measures the minimum distance from the text footprint to sampled source
points.  Rotated text must use an oriented box: its axis-aligned extents can
intersect the source even when the actual glyph band is visibly clear.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def angle_delta(start: float, end: float, sweep: float) -> float:
    if sweep >= 0.0:
        return (end - start) % (2.0 * math.pi)
    return -((start - end) % (2.0 * math.pi))


def point_box_distance(x: float, y: float, box: tuple[float, float, float, float]) -> float:
    min_x, min_y, max_x, max_y = box
    dx = max(min_x - x, x - max_x, 0.0)
    dy = max(min_y - y, y - max_y, 0.0)
    return math.hypot(dx, dy)


def oriented_box_from_aabb(
    box: tuple[float, float, float, float],
    height: float,
    rotation: float,
) -> tuple[float, float, float, float, float] | None:
    """Recover (cx, cy, local_width, local_height, rotation) from text extents.

    Tianzheng's child MText inventory exposes a tight world AABB, rotation and
    actual text height.  Those are sufficient to recover the local width except
    at a numerical singularity; both projected axes are used when available.
    """
    if height <= 0.0 or not math.isfinite(rotation):
        return None
    min_x, min_y, max_x, max_y = box
    world_width = max_x - min_x
    world_height = max_y - min_y
    if world_width <= 0.0 or world_height <= 0.0:
        return None
    cosine = abs(math.cos(rotation))
    sine = abs(math.sin(rotation))
    candidates: list[float] = []
    if cosine > 1.0e-6:
        candidates.append((world_width - sine * height) / cosine)
    if sine > 1.0e-6:
        candidates.append((world_height - cosine * height) / sine)
    candidates = [value for value in candidates if value > 1.0e-6 and math.isfinite(value)]
    if not candidates:
        return None
    local_width = sum(candidates) / len(candidates)
    return (
        (min_x + max_x) * 0.5,
        (min_y + max_y) * 0.5,
        local_width,
        height,
        rotation,
    )


def point_oriented_box_distance(
    x: float,
    y: float,
    box: tuple[float, float, float, float, float],
) -> float:
    cx, cy, width, height, rotation = box
    dx, dy = x - cx, y - cy
    cosine, sine = math.cos(rotation), math.sin(rotation)
    local_x = cosine * dx + sine * dy
    local_y = -sine * dx + cosine * dy
    outside_x = max(abs(local_x) - width * 0.5, 0.0)
    outside_y = max(abs(local_y) - height * 0.5, 0.0)
    return math.hypot(outside_x, outside_y)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--details", required=True, type=Path)
    parser.add_argument("--bboxes", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--source-half-width", type=float, default=0.25)
    parser.add_argument("--polyline-inventory", type=Path)
    parser.add_argument("--padding-height-ratio", type=float, default=1.0 / 3.0)
    parser.add_argument("--samples", type=int, default=160)
    parser.add_argument(
        "--text-box-mode",
        choices=("aabb", "oriented"),
        default="aabb",
        help="Use oriented for rotated native MText visual-clearance QA.",
    )
    args = parser.parse_args()

    geometry = {
        (row["SOURCE_HANDLE"].strip().upper(), int(row["SEGMENT_INDEX"])): row
        for row in rows(args.geometry)
    }
    detail_rows = [row for row in rows(args.details) if row.get("STATUS", "").strip().upper() == "PASS"]
    boxes = {
        row["SOURCE_HANDLE"].strip().upper(): row
        for row in rows(args.bboxes)
    }
    source_half_widths: dict[str, float] = {}
    if args.polyline_inventory:
        for row in rows(args.polyline_inventory):
            handle = (row.get("HANDLE", "") or row.get("SOURCE_HANDLE", "")).strip().upper()
            if handle:
                source_half_widths[handle] = (
                    max(0.0, float(row.get("CONSTANT_WIDTH", "0") or 0.0)) * 0.5
                )

    results: list[dict[str, object]] = []
    violations: list[dict[str, object]] = []
    missing: list[str] = []
    for detail in detail_rows:
        source = detail["SOURCE_HANDLE"].strip().upper()
        segment = int(detail["SEGMENT_INDEX"])
        handle = detail["ADDED_HANDLE"].strip().upper()
        arc = geometry.get((source, segment))
        text = boxes.get(handle)
        if arc is None or text is None:
            missing.append(f"{source}:{segment}:{handle}")
            continue

        center_x = float(arc["CENTER_X"])
        center_y = float(arc["CENTER_Y"])
        radius = float(arc["RADIUS"])
        start_x = float(arc["START_X"])
        start_y = float(arc["START_Y"])
        end_x = float(arc["END_X"])
        end_y = float(arc["END_Y"])
        sweep = float(arc["SWEEP_DEGREES"])
        start_angle = math.atan2(start_y - center_y, start_x - center_x)
        end_angle = math.atan2(end_y - center_y, end_x - center_x)
        delta = angle_delta(start_angle, end_angle, sweep)
        if abs(math.degrees(delta) - sweep) > 0.05:
            delta = math.radians(sweep)

        box = (float(text["MIN_X"]), float(text["MIN_Y"]), float(text["MAX_X"]), float(text["MAX_Y"]))
        count = max(16, args.samples)
        oriented_box = None
        if args.text_box_mode == "oriented":
            oriented_box = oriented_box_from_aabb(
                box,
                float(text.get("HEIGHT", "0") or 0.0),
                float(text.get("ROTATION", "0") or 0.0),
            )
        distances = []
        for index in range(count + 1):
            angle = start_angle + delta * (index / count)
            x = center_x + radius * math.cos(angle)
            y = center_y + radius * math.sin(angle)
            if oriented_box is not None:
                distances.append(point_oriented_box_distance(x, y, oriented_box))
            else:
                distances.append(point_box_distance(x, y, box))
        distance = min(distances)
        height = float(text.get("HEIGHT", "0") or 0.0)
        source_half_width = source_half_widths.get(source, args.source_half_width)
        required = source_half_width + args.padding_height_ratio * height
        item = {
            "source_handle": source,
            "segment_index": segment,
            "dimension_handle": handle,
            "text": text.get("TEXT", ""),
            "source_to_text_bbox": distance,
            "required_clearance": required,
            "source_half_width": source_half_width,
            "visible_edge_to_text_bbox": distance - source_half_width,
            "clearance_over_height": (distance - source_half_width) / height if height > 0 else None,
            "text_box_mode": "oriented" if oriented_box is not None else "aabb",
            "status": "PASS" if distance >= required else "FAIL",
        }
        results.append(item)
        if item["status"] == "FAIL":
            violations.append(item)

    payload = {
        "status": "PASS" if not violations and not missing else "FAIL",
        "checked": len(results),
        "violations": violations,
        "missing": missing,
        "source_half_width": args.source_half_width,
        "source_half_width_mode": (
            "per_source_constant_width" if args.polyline_inventory else "fixed_fallback"
        ),
        "padding_height_ratio": args.padding_height_ratio,
        "text_box_mode": args.text_box_mode,
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: payload[key] for key in ("status", "checked", "violations", "missing")}, ensure_ascii=False))
    return 0 if payload["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
