#!/usr/bin/env python3
"""Plan local text-grip moves for native Tianzheng angle dimensions.

This is the second layer of the verified layout workflow:

1. grip 0 establishes one close, continuous dimension-line band;
2. only when native text bodies collide, grip 4 slides the affected text;
3. source grips 2/3 and the dimension-line grip 0 are never moved here.

The planner is drawing-coordinate based.  It does not depend on screen pixels,
window size, zoom, or a physical mouse.  Output is accepted directly by
``CXGENERICGRIPBATCHMOVE``.
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
from audit_native_angle_source_text_clearance import oriented_box_from_aabb
from select_native_angle_text_state import (
    load_association,
    load_geometry,
    load_source_half_widths,
    source_clearance,
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
    def width(self) -> float:
        return self.max_x - self.min_x

    @property
    def height(self) -> float:
        return self.max_y - self.min_y

    @property
    def text_height(self) -> float:
        # Rotated text enlarges one world-axis extent.  The smaller extent is
        # the more stable proxy for plotted text height.
        if self.local_height is not None:
            return max(0.01, self.local_height)
        return max(0.01, min(self.width, self.height))

    @property
    def local_text_width(self) -> float:
        return max(0.01, self.local_width if self.local_width is not None else self.width)

    @property
    def center(self) -> tuple[float, float]:
        return ((self.min_x + self.max_x) * 0.5, (self.min_y + self.max_y) * 0.5)

    def polygon(self, padding: float = 0.0):
        return oriented_box(
            VectorPoint(*self.center),
            VectorPoint(math.cos(self.rotation), math.sin(self.rotation)),
            self.local_text_width + 2.0 * max(0.0, padding),
            self.text_height + 2.0 * max(0.0, padding),
            "native_text",
        )

    def shifted(self, dx: float, dy: float) -> "Box":
        return Box(
            self.handle,
            self.min_x + dx,
            self.min_y + dy,
            self.max_x + dx,
            self.max_y + dy,
            self.rotation,
            self.local_width,
            self.local_height,
        )


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def overlap(left: Box, right: Box, padding: float = 0.0) -> bool:
    half = max(0.0, padding) * 0.5
    return polygons_overlap(left.polygon(half), right.polygon(half))


def box_clearance(left: Box, right: Box) -> float:
    dx = max(right.min_x - left.max_x, left.min_x - right.max_x, 0.0)
    dy = max(right.min_y - left.max_y, left.min_y - right.max_y, 0.0)
    return math.hypot(dx, dy)


def collision_pairs(boxes: dict[str, Box], padding_ratio: float = 0.0) -> list[tuple[str, str]]:
    handles = sorted(boxes)
    pairs: list[tuple[str, str]] = []
    for index, first_handle in enumerate(handles):
        first = boxes[first_handle]
        for second_handle in handles[index + 1 :]:
            second = boxes[second_handle]
            padding = padding_ratio * min(first.text_height, second.text_height)
            if overlap(first, second, padding):
                pairs.append((first_handle, second_handle))
    return pairs


def parse_boxes(path: Path) -> dict[str, Box]:
    result: dict[str, Box] = {}
    for row in read_tsv(path):
        handle = row.get("SOURCE_HANDLE", "").strip().upper()
        if not handle:
            continue
        if handle in result:
            raise ValueError(f"multiple text bodies for native handle {handle}")
        min_x, min_y = float(row["MIN_X"]), float(row["MIN_Y"])
        max_x, max_y = float(row["MAX_X"]), float(row["MAX_Y"])
        rotation = float(row.get("ROTATION", "0") or 0.0)
        native_height = float(row.get("HEIGHT", "0") or 0.0)
        recovered = oriented_box_from_aabb(
            (min_x, min_y, max_x, max_y), native_height, rotation
        )
        result[handle] = Box(
            handle,
            min_x,
            min_y,
            max_x,
            max_y,
            rotation,
            recovered[2] if recovered is not None else None,
            recovered[3] if recovered is not None else None,
        )
    if not result:
        raise ValueError("text bbox inventory is empty")
    return result


def parse_grips(path: Path) -> tuple[dict[str, dict[int, tuple[float, float]]], dict[str, str]]:
    grips: dict[str, dict[int, tuple[float, float]]] = {}
    classes: dict[str, str] = {}
    for row in read_tsv(path):
        handle = row["HANDLE"].strip().upper()
        grips.setdefault(handle, {})[int(row["GRIP_INDEX"])] = (
            float(row["GRIP_X"]),
            float(row["GRIP_Y"]),
        )
        classes[handle] = row.get("RXCLASS", "")
    return grips, classes


def unit_vector(dx: float, dy: float) -> tuple[float, float]:
    length = math.hypot(dx, dy)
    if length <= 1.0e-9:
        raise ValueError("zero-length source grip direction")
    return dx / length, dy / length


def candidates(
    box: Box,
    entity_grips: dict[int, tuple[float, float]],
    max_along_heights: float,
    max_normal_heights: float,
) -> list[tuple[float, float, float, float]]:
    if not all(index in entity_grips for index in (0, 2, 3, 4)):
        raise ValueError(f"{box.handle}: native grips 0/2/3/4 are required")
    tangent = unit_vector(
        entity_grips[3][0] - entity_grips[2][0],
        entity_grips[3][1] - entity_grips[2][1],
    )
    normal = (-tangent[1], tangent[0])
    height = box.text_height
    along_levels = (
        0.0,
        -0.25, 0.25,
        -0.5, 0.5,
        -0.75, 0.75,
        -1.0, 1.0,
        -1.5, 1.5,
        -2.0, 2.0,
        -2.5, 2.5,
        -3.0, 3.0,
        -4.0, 4.0,
    )
    normal_levels = (0.0, -0.35, 0.35, -0.5, 0.5)
    result: list[tuple[float, float, float, float]] = []
    seen: set[tuple[int, int]] = set()
    for along_level in along_levels:
        if abs(along_level) > max_along_heights + 1.0e-9:
            continue
        for normal_level in normal_levels:
            if abs(normal_level) > max_normal_heights + 1.0e-9:
                continue
            along = along_level * height
            normal_distance = normal_level * height
            dx = tangent[0] * along + normal[0] * normal_distance
            dy = tangent[1] * along + normal[1] * normal_distance
            key = (round(dx * 1_000_000), round(dy * 1_000_000))
            if key in seen:
                continue
            seen.add(key)
            result.append((dx, dy, abs(along), abs(normal_distance)))
    return result


def plan_relief(
    boxes: dict[str, Box],
    grips: dict[str, dict[int, tuple[float, float]]],
    classes: dict[str, str],
    padding_ratio: float = 0.10,
    max_along_heights: float = 2.0,
    max_normal_heights: float = 0.5,
    beam_width: int = 256,
    required_handles: set[str] | None = None,
    source_context: dict[str, tuple[object, float, float]] | None = None,
    allow_unresolved: bool = False,
) -> tuple[dict[str, tuple[float, float]], dict[str, object]]:
    initial_direct = collision_pairs(boxes, 0.0)
    initial_padded = collision_pairs(boxes, padding_ratio)
    movable = sorted(required_handles or {handle for pair in initial_padded for handle in pair})
    if not movable:
        return {}, {
            "status": "PASS",
            "initial_direct_collisions": len(initial_direct),
            "initial_padded_collisions": 0,
            "remaining_direct_collisions": 0,
            "remaining_padded_collisions": 0,
            "moved": 0,
            "remaining_source_corridor_hits": [],
        }
    for handle in movable:
        if classes.get(handle) != "TDbDimension2":
            raise ValueError(f"{handle}: expected TDbDimension2, got {classes.get(handle)!r}")

    fixed = {handle: box for handle, box in boxes.items() if handle not in movable}
    # state = score, placed boxes, movement vectors
    beam: list[tuple[float, dict[str, Box], dict[str, tuple[float, float]]]] = [(0.0, {}, {})]
    for handle in movable:
        expanded: list[tuple[float, dict[str, Box], dict[str, tuple[float, float]]]] = []
        source = boxes[handle]
        for score, placed, moves in beam:
            obstacles = tuple(fixed.values()) + tuple(placed.values())
            for dx, dy, along, normal_distance in candidates(
                source, grips.get(handle, {}), max_along_heights, max_normal_heights
            ):
                shifted = source.shifted(dx, dy)
                collisions = 0
                clearances: list[float] = []
                for obstacle in obstacles:
                    padding = padding_ratio * min(shifted.text_height, obstacle.text_height)
                    if overlap(shifted, obstacle, padding):
                        collisions += 1
                    clearances.append(box_clearance(shifted, obstacle))
                source_failure = False
                source_deficit = 0.0
                if source_context and handle in source_context:
                    points, source_half_width, target_clearance_h = source_context[handle]
                    required = source_half_width + target_clearance_h * shifted.text_height
                    measured = source_clearance(shifted, points)
                    source_failure = measured + 1.0e-9 < required
                    source_deficit = max(0.0, required - measured)
                displacement = math.hypot(dx, dy)
                clearance = min(clearances) if clearances else 10.0 * shifted.text_height
                # Moving normal to the dimension line is allowed only as a
                # small local escape.  It costs more than sliding along it.
                increment = (
                    (collisions + int(source_failure)) * 1.0e9
                    + source_deficit * 5.0e5
                    + displacement * 100.0
                    + normal_distance * 160.0
                    + along * 20.0
                    - min(clearance, 2.0 * shifted.text_height)
                )
                next_placed = dict(placed)
                next_placed[handle] = shifted
                next_moves = dict(moves)
                next_moves[handle] = (dx, dy)
                expanded.append((score + increment, next_placed, next_moves))
        expanded.sort(
            key=lambda item: (
                item[0],
                tuple((key, round(value[0], 9), round(value[1], 9)) for key, value in sorted(item[2].items())),
            )
        )
        beam = expanded[: max(1, beam_width)]

    _score, placed, moves = beam[0]
    final_boxes = dict(fixed)
    final_boxes.update(placed)
    remaining_direct = collision_pairs(final_boxes, 0.0)
    remaining_padded = collision_pairs(final_boxes, padding_ratio)
    remaining_source = []
    if source_context:
        for handle in movable:
            points, source_half_width, target_clearance_h = source_context[handle]
            box = final_boxes[handle]
            if source_clearance(box, points) + 1.0e-9 < (
                source_half_width + target_clearance_h * box.text_height
            ):
                remaining_source.append(handle)
    if (remaining_direct or remaining_padded or remaining_source) and not allow_unresolved:
        raise ValueError(
            "no collision-free local text-grip solution within configured bounds: "
            f"direct={remaining_direct} padded={remaining_padded} source={remaining_source}"
        )
    nonzero = {
        handle: vector
        for handle, vector in moves.items()
        if math.hypot(vector[0], vector[1]) > 1.0e-9
    }
    remaining_failed = sorted(
        set(remaining_source)
        | {handle for pair in remaining_direct for handle in pair}
        | {handle for pair in remaining_padded for handle in pair}
    )
    return nonzero, {
        "status": "PASS" if not remaining_direct and not remaining_padded and not remaining_source else "PARTIAL",
        "initial_direct_collisions": len(initial_direct),
        "initial_padded_collisions": len(initial_padded),
        "remaining_direct_collisions": len(remaining_direct),
        "remaining_padded_collisions": len(remaining_padded),
        "remaining_direct_collision_pairs": remaining_direct,
        "remaining_padded_collision_pairs": remaining_padded,
        "remaining_source_corridor_hits": remaining_source,
        "failed_subset": remaining_failed,
        "moved": len(nonzero),
        "movable_handles": movable,
        "max_move": max((math.hypot(*vector) for vector in nonzero.values()), default=0.0),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--output-plan", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    parser.add_argument("--padding-ratio", type=float, default=0.10)
    parser.add_argument("--max-along-heights", type=float, default=2.0)
    parser.add_argument("--max-normal-heights", type=float, default=0.5)
    parser.add_argument("--beam-width", type=int, default=256)
    parser.add_argument("--failed-audit", type=Path)
    parser.add_argument("--association-plan", type=Path)
    parser.add_argument("--geometry", type=Path)
    parser.add_argument("--source-styles", type=Path)
    parser.add_argument("--formula", type=Path)
    parser.add_argument("--allow-unresolved", action="store_true")
    args = parser.parse_args()
    if args.padding_ratio < 0 or args.max_along_heights < 0 or args.max_normal_heights < 0:
        raise SystemExit("padding and movement bounds must be non-negative")

    boxes = parse_boxes(args.text_bboxes)
    grips, classes = parse_grips(args.grips)
    required_handles = None
    source_context = None
    context_paths = (
        args.failed_audit,
        args.association_plan,
        args.geometry,
        args.source_styles,
        args.formula,
    )
    if any(context_paths) and not all(context_paths):
        raise SystemExit("failed-subset source context requires all five context paths")
    if all(context_paths):
        failed = json.loads(args.failed_audit.read_text(encoding="utf-8"))
        required_handles = {
            str(handle).strip().upper() for handle in failed.get("failed_subset", [])
        }
        _ordered, association = load_association(args.association_plan)
        geometry = load_geometry(args.geometry)
        half_widths = load_source_half_widths(args.source_styles)
        formula = load_vector_layout_formula(args.formula)
        target_h = formula.four_direction_text_alignment.target_visible_clearance_h
        source_context = {
            handle: (
                geometry[association[handle]],
                half_widths.get(association[handle][0], 0.0),
                target_h,
            )
            for handle in required_handles
        }
    moves, audit = plan_relief(
        boxes,
        grips,
        classes,
        padding_ratio=args.padding_ratio,
        max_along_heights=args.max_along_heights,
        max_normal_heights=args.max_normal_heights,
        beam_width=args.beam_width,
        required_handles=required_handles,
        source_context=source_context,
        allow_unresolved=args.allow_unresolved,
    )
    args.output_plan.parent.mkdir(parents=True, exist_ok=True)
    with args.output_plan.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(
            stream,
            fieldnames=("HANDLE", "GRIP_INDEX", "DX", "DY", "DZ"),
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        for handle in sorted(moves):
            dx, dy = moves[handle]
            writer.writerow(
                {"HANDLE": handle, "GRIP_INDEX": 4, "DX": dx, "DY": dy, "DZ": 0.0}
            )
    args.output_audit.parent.mkdir(parents=True, exist_ok=True)
    args.output_audit.write_text(
        json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(audit, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
