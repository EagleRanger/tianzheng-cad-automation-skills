#!/usr/bin/env python3
"""Choose baseline or TMirDim text state for each native angle dimension.

The selector implements the user-approved manual-reference contract.  It keeps
the dimension-line grip fixed and compares the two *observed* native text
states.  It never predicts or rebuilds Tianzheng text geometry.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path

from annotation_layout_formula import load_vector_layout_formula
from annotation_vector_geometry import VectorPoint, oriented_box, polygons_overlap
from audit_native_angle_source_text_clearance import (
    oriented_box_from_aabb,
    point_oriented_box_distance,
)


@dataclass(frozen=True)
class Box:
    handle: str
    min_x: float
    min_y: float
    max_x: float
    max_y: float
    rotation: float = 0.0
    local_width: float | None = None
    local_height: float | None = None

    @property
    def center(self) -> tuple[float, float]:
        return ((self.min_x + self.max_x) * 0.5, (self.min_y + self.max_y) * 0.5)

    @property
    def height(self) -> float:
        if self.local_height is not None:
            return max(0.01, self.local_height)
        return max(0.01, min(self.max_x - self.min_x, self.max_y - self.min_y))

    @property
    def width(self) -> float:
        if self.local_width is not None:
            return max(0.01, self.local_width)
        return max(0.01, self.max_x - self.min_x)

    def polygon(self, padding: float = 0.0):
        return oriented_box(
            VectorPoint(*self.center),
            VectorPoint(math.cos(self.rotation), math.sin(self.rotation)),
            self.width + 2.0 * max(0.0, padding),
            self.height + 2.0 * max(0.0, padding),
            "native_text",
        )


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def load_boxes(path: Path) -> dict[str, Box]:
    boxes: dict[str, Box] = {}
    for row in read_tsv(path):
        handle = row["SOURCE_HANDLE"].strip().upper()
        if handle in boxes:
            raise ValueError(f"multiple text bodies for {handle}")
        min_x, min_y = float(row["MIN_X"]), float(row["MIN_Y"])
        max_x, max_y = float(row["MAX_X"]), float(row["MAX_Y"])
        rotation = float(row.get("ROTATION", "0") or 0.0)
        native_height = float(row.get("HEIGHT", "0") or 0.0)
        recovered = oriented_box_from_aabb(
            (min_x, min_y, max_x, max_y), native_height, rotation
        )
        boxes[handle] = Box(
            handle,
            min_x,
            min_y,
            max_x,
            max_y,
            rotation,
            recovered[2] if recovered is not None else None,
            recovered[3] if recovered is not None else None,
        )
    if not boxes:
        raise ValueError(f"empty text bbox inventory: {path}")
    return boxes


def load_grip0(path: Path) -> dict[str, tuple[float, float]]:
    result: dict[str, tuple[float, float]] = {}
    for row in read_tsv(path):
        if int(row["GRIP_INDEX"]) == 0 and row.get("RXCLASS", "") == "TDbDimension2":
            result[row["HANDLE"].strip().upper()] = (float(row["GRIP_X"]), float(row["GRIP_Y"]))
    return result


def load_association(path: Path) -> tuple[list[str], dict[str, tuple[str, int]]]:
    ordered: list[str] = []
    association: dict[str, tuple[str, int]] = {}
    for row in read_tsv(path):
        if row.get("KIND", "").upper() not in {"ANGLE", "LENGTH"}:
            continue
        handle = row["NATIVE_HANDLE"].strip().upper()
        source, segment = row["SOURCE_SEGMENT"].strip().upper().split(":", 1)
        ordered.append(handle)
        association[handle] = (source, int(segment))
    return ordered, association


def load_geometry(path: Path) -> dict[tuple[str, int], tuple[tuple[float, float], tuple[float, float], tuple[float, float]]]:
    result = {}
    for row in read_tsv(path):
        key = (row["SOURCE_HANDLE"].strip().upper(), int(row["SEGMENT_INDEX"]))
        result[key] = (
            (float(row["START_X"]), float(row["START_Y"])),
            (float(row["MID_X"]), float(row["MID_Y"])),
            (float(row["END_X"]), float(row["END_Y"])),
        )
    return result


def load_source_half_widths(path: Path) -> dict[str, float]:
    result = {}
    for row in read_tsv(path):
        handle = (row.get("HANDLE") or row.get("SOURCE_HANDLE") or "").strip().upper()
        width = row.get("CONSTANT_WIDTH", "")
        if handle and width != "":
            result[handle] = max(0.0, float(width)) * 0.5
    if not result:
        raise ValueError(f"empty source width inventory: {path}")
    return result


def boxes_overlap(left: Box, right: Box, padding: float = 0.0) -> bool:
    # Native MText is often steeply rotated.  Its world AABB can overlap a
    # neighbour or the thick source while the visible glyph bands remain
    # separate.  The selector must therefore use the recovered native OBB;
    # otherwise a false failure needlessly triggers a second correction pass.
    half = max(0.0, padding) * 0.5
    return polygons_overlap(left.polygon(half), right.polygon(half))


def point_box_distance(point: tuple[float, float], box: Box) -> float:
    x, y = point
    dx = max(box.min_x - x, x - box.max_x, 0.0)
    dy = max(box.min_y - y, y - box.max_y, 0.0)
    return math.hypot(dx, dy)


def quadratic_bezier(points, steps: int = 32):
    start, mid, end = points
    # A quadratic through start/mid/end is sufficient for a conservative
    # text-corridor probe; live acceptance still uses a rendered screenshot.
    control = (2.0 * mid[0] - 0.5 * (start[0] + end[0]), 2.0 * mid[1] - 0.5 * (start[1] + end[1]))
    for index in range(steps + 1):
        t = index / steps
        u = 1.0 - t
        yield (
            u * u * start[0] + 2.0 * u * t * control[0] + t * t * end[0],
            u * u * start[1] + 2.0 * u * t * control[1] + t * t * end[1],
        )


def source_clearance(box: Box, points) -> float:
    recovered = (
        box.center[0],
        box.center[1],
        box.width,
        box.height,
        box.rotation,
    )
    return min(
        point_oriented_box_distance(point[0], point[1], recovered)
        for point in quadratic_bezier(points)
    )


def orientation_class(box: Box, points) -> str:
    """Classify text by the dominant source-midpoint-to-text-center component."""

    source_mid = points[1]
    center = box.center
    dx, dy = center[0] - source_mid[0], center[1] - source_mid[1]
    if abs(dy) >= abs(dx):
        return "TOP" if dy >= 0.0 else "BOTTOM"
    return "RIGHT" if dx >= 0.0 else "LEFT"


def choose_states(
    baseline: dict[str, Box],
    mirrored: dict[str, Box],
    grip0: dict[str, tuple[float, float]],
    ordered: list[str],
    association: dict[str, tuple[str, int]],
    geometry,
    beam_width: int = 512,
    target_clearance_h: float = 1.0 / 3.0,
    source_half_widths: dict[str, float] | None = None,
):
    expected = set(ordered)
    for name, values in (("baseline", baseline), ("mirrored", mirrored), ("grip0", grip0)):
        missing = expected - set(values)
        if missing:
            raise ValueError(f"{name} missing handles: {sorted(missing)}")
    if target_clearance_h <= 0.0:
        raise ValueError("target clearance must be positive")
    source_half_widths = source_half_widths or {}
    metrics = {}
    eligible_by_source: dict[str, list[float]] = {}
    for handle in ordered:
        source_key = association[handle]
        if source_key not in geometry:
            raise ValueError(f"missing source geometry: {source_key}")
        source = source_key[0]
        for state_name, box in (("BASELINE", baseline[handle]), ("MIRRORED", mirrored[handle])):
            height = box.height
            visible_clearance = source_clearance(box, geometry[source_key]) - source_half_widths.get(source, 0.0)
            clearance_h = visible_clearance / height
            metrics[(handle, state_name)] = (
                visible_clearance,
                clearance_h,
                orientation_class(box, geometry[source_key]),
            )
            if clearance_h + 1.0e-9 >= target_clearance_h:
                eligible_by_source.setdefault(source, []).append(clearance_h)
    reference_by_source = {
        source: min(values) if values else target_clearance_h
        for source, values in {
            key[0]: eligible_by_source.get(key[0], []) for key in association.values()
        }.items()
    }

    states = [(0.0, {}, None, None)]  # score, choices, previous source, previous state
    for handle in ordered:
        expanded = []
        source_key = association[handle]
        if source_key not in geometry:
            raise ValueError(f"missing source geometry: {source_key}")
        for score, chosen, previous_source, previous_state in states:
            for state_name, box in (("BASELINE", baseline[handle]), ("MIRRORED", mirrored[handle])):
                height = box.height
                visible_clearance, clearance_h, _orientation = metrics[(handle, state_name)]
                center = box.center
                line_distance = math.hypot(center[0] - grip0[handle][0], center[1] - grip0[handle][1])
                increment = 0.0
                # Text touching the thick blue source is a hard visual failure.
                if visible_clearance + 1.0e-9 < target_clearance_h * height:
                    increment += 1.0e9
                    increment += (target_clearance_h * height - visible_clearance) * 5.0e5
                else:
                    increment += abs(
                        clearance_h - reference_by_source[source_key[0]]
                    ) * 5.0e5
                # Keep native text close to its dimension arc.  TMirDim should
                # solve side placement, not manufacture a distant text band.
                target_distance = 0.65 * height
                increment += abs(line_distance - target_distance) * 120.0
                # Direct and padded text-body collisions dominate all soft
                # aesthetic preferences.
                for other in chosen.values():
                    padding = 0.08 * min(height, other.height)
                    if boxes_overlap(box, other, 0.0):
                        increment += 1.0e9
                    elif boxes_overlap(box, other, padding):
                        increment += 1.0e7
                # Preserve a locally consistent reading side along one source
                # polyline unless a collision forces a switch.
                if previous_source == source_key[0] and previous_state != state_name:
                    increment += 250.0
                next_chosen = dict(chosen)
                next_chosen[handle] = box
                expanded.append((score + increment, next_chosen, source_key[0], state_name))
        expanded.sort(key=lambda item: item[0])
        states = expanded[: max(1, beam_width)]
    score, selected_boxes, _, _ = states[0]
    choices = {
        handle: ("MIRRORED" if selected_boxes[handle] == mirrored[handle] else "BASELINE")
        for handle in ordered
    }
    direct = []
    for index, handle in enumerate(ordered):
        for other in ordered[index + 1 :]:
            if boxes_overlap(selected_boxes[handle], selected_boxes[other]):
                direct.append((handle, other))
    source_hits = [
        handle
        for handle in ordered
        if metrics[(handle, choices[handle])][0]
        + 1.0e-9
        < target_clearance_h * selected_boxes[handle].height
    ]
    failed_subset = sorted(
        set(source_hits)
        | {handle for pair in direct for handle in pair}
    )
    orientation_summary: dict[str, dict[str, list[float]]] = {}
    selected_reference_by_source: dict[str, float] = {}
    for handle in ordered:
        source = association[handle][0]
        _visible, clearance_h, orientation = metrics[(handle, choices[handle])]
        orientation_summary.setdefault(source, {}).setdefault(orientation, []).append(clearance_h)
    for source, groups in orientation_summary.items():
        values = [value for group in groups.values() for value in group]
        hard_pass_values = [
            value for value in values if value + 1.0e-9 >= target_clearance_h
        ]
        selected_reference_by_source[source] = (
            min(hard_pass_values) if hard_pass_values else target_clearance_h
        )
    maximum_alignment_delta_h = {
        source: max(
            abs(value - selected_reference_by_source[source])
            for group in groups.values()
            for value in group
        )
        for source, groups in orientation_summary.items()
    }
    return choices, {
        "status": "PASS_OFFLINE" if not direct and not source_hits else "FAIL_OFFLINE",
        "handle_count": len(ordered),
        "mirror_count": sum(value == "MIRRORED" for value in choices.values()),
        "baseline_count": sum(value == "BASELINE" for value in choices.values()),
        "direct_text_collisions": direct,
        "source_corridor_hits": source_hits,
        "failed_subset": failed_subset,
        "failed_subset_next_action": (
            "along_arc_shift_then_contiguous_cluster_band_promotion"
            if failed_subset
            else "none"
        ),
        "target_visible_clearance_h": target_clearance_h,
        "candidate_reference_clearance_h_by_source": reference_by_source,
        "selected_reference_clearance_h_by_source": selected_reference_by_source,
        "selected_orientation_clearances_h": orientation_summary,
        "maximum_alignment_delta_h_by_source": maximum_alignment_delta_h,
        "normal_correction_order": [
            "choose_baseline_or_mirrored",
            "along_arc_shift",
            "promote_contiguous_failed_cluster_one_band",
        ],
        "single_item_radial_exception": "last_resort_only_after_all_normal_candidates_fail",
        "score": score,
        "real_dwg_acceptance": "PENDING_E4_E5_VISUAL",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-bboxes", required=True, type=Path)
    parser.add_argument("--mirrored-bboxes", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--association-plan", required=True, type=Path)
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--source-styles", required=True, type=Path)
    parser.add_argument("--output-plan", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--beam-width", type=int, default=64)
    parser.add_argument(
        "--formula",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "config"
        / "annotation_vector_layout_formula_v2.json",
    )
    args = parser.parse_args()
    formula = load_vector_layout_formula(args.formula)
    alignment = formula.four_direction_text_alignment
    ordered, association = load_association(args.association_plan)
    choices, audit = choose_states(
        load_boxes(args.baseline_bboxes),
        load_boxes(args.mirrored_bboxes),
        load_grip0(args.grips),
        ordered,
        association,
        load_geometry(args.geometry),
        beam_width=max(1, args.beam_width),
        target_clearance_h=alignment.target_visible_clearance_h,
        source_half_widths=load_source_half_widths(args.source_styles),
    )
    args.output_plan.parent.mkdir(parents=True, exist_ok=True)
    with args.output_plan.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=("HANDLE", "STATE", "TOGGLE"), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for handle in ordered:
            writer.writerow({"HANDLE": handle, "STATE": choices[handle], "TOGGLE": "YES" if choices[handle] == "MIRRORED" else "NO"})
    args.output_audit.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=False))
    return 0 if audit["status"] == "PASS_OFFLINE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
