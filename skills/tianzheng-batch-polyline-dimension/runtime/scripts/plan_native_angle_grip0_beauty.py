#!/usr/bin/env python3
"""Plan small, feedback-driven grip-0 corrections for native angle dimensions.

This planner intentionally models only the control that is reliable in
Tianzheng T20 V10: grip 0 ("move dimension line").  It never moves the text
grip.  The result is a bounded first-pass correction; after it is applied the
caller must re-inventory native grips and text boxes before planning again.

The aesthetic contract is expressed in text-height units:

* keep already clean dimensions where they are;
* prefer one coherent band on the currently wider side;
* adjacent dimensions may meet at their construction seam, but text bodies
  may not overlap;
* short arcs move one band at a time and may cross to the opposite side only
  when the current side cannot contain their measured text box;
* the requested radial change is capped so a single pass cannot make a native
  dimension jump across several visual bands.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from dataclasses import dataclass
from pathlib import Path

from annotation_layout_formula import (
    audit_text_between_source_and_dimension,
    load_vector_layout_formula,
)
from annotation_vector_geometry import ConvexPolygon, VectorPoint


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class Box:
    min_x: float
    min_y: float
    max_x: float
    max_y: float

    def expanded(self, value: float) -> "Box":
        return Box(self.min_x - value, self.min_y - value, self.max_x + value, self.max_y + value)

    def overlaps(self, other: "Box") -> bool:
        return not (
            self.max_x <= other.min_x
            or other.max_x <= self.min_x
            or self.max_y <= other.min_y
            or other.max_y <= self.min_y
        )


@dataclass(frozen=True)
class OrientedBox:
    center: Point
    axis_x: Point
    axis_y: Point
    half_width: float
    half_height: float

    def expanded(self, value: float) -> "OrientedBox":
        return OrientedBox(
            self.center,
            self.axis_x,
            self.axis_y,
            self.half_width + value,
            self.half_height + value,
        )

    def corners(self) -> tuple[Point, Point, Point, Point]:
        wx = self.axis_x.x * self.half_width
        wy = self.axis_x.y * self.half_width
        hx = self.axis_y.x * self.half_height
        hy = self.axis_y.y * self.half_height
        return (
            Point(self.center.x + wx + hx, self.center.y + wy + hy),
            Point(self.center.x + wx - hx, self.center.y + wy - hy),
            Point(self.center.x - wx - hx, self.center.y - wy - hy),
            Point(self.center.x - wx + hx, self.center.y - wy + hy),
        )


def project(points: tuple[Point, ...], axis: Point) -> tuple[float, float]:
    values = [point.x * axis.x + point.y * axis.y for point in points]
    return min(values), max(values)


def obb_overlaps(first: OrientedBox, second: OrientedBox) -> bool:
    first_points = first.corners()
    second_points = second.corners()
    for axis in (first.axis_x, first.axis_y, second.axis_x, second.axis_y):
        first_min, first_max = project(first_points, axis)
        second_min, second_max = project(second_points, axis)
        if first_max <= second_min or second_max <= first_min:
            return False
    return True


def translate_obb(box: OrientedBox, dx: float, dy: float) -> OrientedBox:
    return OrientedBox(
        Point(box.center.x + dx, box.center.y + dy),
        box.axis_x,
        box.axis_y,
        box.half_width,
        box.half_height,
    )


def square_obb(center: Point, half_extent: float) -> OrientedBox:
    """Conservative heavy-body footprint for a native arrow marker."""

    return OrientedBox(
        center,
        Point(1.0, 0.0),
        Point(0.0, 1.0),
        half_extent,
        half_extent,
    )


def vector_polygon(box: OrientedBox) -> ConvexPolygon:
    return ConvexPolygon(
        tuple(VectorPoint(point.x, point.y) for point in box.corners()),
        "text",
    )


def nearest_allowed_band_h(target_h: float, bands_h: tuple[float, ...]) -> float:
    eligible = tuple(value for value in bands_h if value + 1.0e-9 >= target_h)
    return min(eligible) if eligible else max(bands_h)


def obb_from_native_bbox(row: dict[str, str], height: float) -> OrientedBox:
    min_x = float(row["MIN_X"])
    min_y = float(row["MIN_Y"])
    max_x = float(row["MAX_X"])
    max_y = float(row["MAX_Y"])
    rotation = float(row.get("ROTATION", "0") or 0.0)
    cos_value = abs(math.cos(rotation))
    sin_value = abs(math.sin(rotation))
    aabb_width = max_x - min_x
    aabb_height = max_y - min_y
    width_estimates: list[float] = []
    if cos_value > 1e-6:
        width_estimates.append(max(0.0, (aabb_width - sin_value * height) / cos_value))
    if sin_value > 1e-6:
        width_estimates.append(max(0.0, (aabb_height - cos_value * height) / sin_value))
    width = max(height, sum(width_estimates) / len(width_estimates)) if width_estimates else max(aabb_width, height)
    return OrientedBox(
        Point((min_x + max_x) / 2.0, (min_y + max_y) / 2.0),
        Point(math.cos(rotation), math.sin(rotation)),
        Point(-math.sin(rotation), math.cos(rotation)),
        width / 2.0,
        height / 2.0,
    )


def read_tsv(path: Path) -> list[dict[str, str]]:
    raw = path.read_bytes()
    decode_errors: list[str] = []
    encodings = ["utf-8-sig"]
    if raw.startswith((b"\xff\xfe", b"\xfe\xff")):
        encodings.append("utf-16")
    encodings.append("gb18030")
    for encoding in encodings:
        try:
            decoded = raw.decode(encoding)
        except UnicodeDecodeError as exc:
            decode_errors.append(f"{encoding}: {exc}")
            continue
        return list(csv.DictReader(io.StringIO(decoded, newline=""), delimiter="\t"))
    raise UnicodeError(f"cannot decode TSV {path}: {'; '.join(decode_errors)}")


def write_tsv(path: Path, rows: list[dict[str, object]], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def distance(first: Point, second: Point) -> float:
    return math.hypot(first.x - second.x, first.y - second.y)


def arc_center_radius(row: dict[str, str]) -> tuple[Point, float]:
    if row.get("CENTER_X") and row.get("CENTER_Y") and row.get("RADIUS"):
        return Point(float(row["CENTER_X"]), float(row["CENTER_Y"])), float(row["RADIUS"])

    start = Point(float(row["START_X"]), float(row["START_Y"]))
    end = Point(float(row["END_X"]), float(row["END_Y"]))
    bulge = float(row.get("BULGE", "0") or 0.0)
    chord = distance(start, end)
    if chord <= 1.0e-12 or abs(bulge) <= 1.0e-12:
        raise ValueError("arc geometry requires a non-zero chord and bulge")
    midpoint = Point((start.x + end.x) / 2.0, (start.y + end.y) / 2.0)
    left_normal = Point(-(end.y - start.y) / chord, (end.x - start.x) / chord)
    center_offset = chord * (1.0 - bulge * bulge) / (4.0 * bulge)
    center = Point(
        midpoint.x + left_normal.x * center_offset,
        midpoint.y + left_normal.y * center_offset,
    )
    radius = chord * (1.0 + bulge * bulge) / (4.0 * abs(bulge))
    return center, radius


def endpoint_error(first: Point, second: Point, start: Point, end: Point) -> float:
    return min(
        distance(first, start) + distance(second, end),
        distance(first, end) + distance(second, start),
    )


def source_orientation(rows: list[dict[str, str]]) -> float:
    """Return the closed-loop orientation, or zero for an open/degenerate path.

    Open blue shore lines are valid annotation targets.  They have no polygon
    interior, so forcing a clockwise/counter-clockwise answer used to make the
    long open line disappear from the batch.  Callers must fall back to the
    measured dominant native side when this function returns zero.
    """

    twice_area = 0.0
    for row in sorted(rows, key=lambda item: int(item["SEGMENT_INDEX"])):
        start_x = float(row["START_X"])
        start_y = float(row["START_Y"])
        end_x = float(row["END_X"])
        end_y = float(row["END_Y"])
        twice_area += start_x * end_y - end_x * start_y
    if abs(twice_area) < 1e-9:
        return 0.0
    return 1.0 if twice_area > 0.0 else -1.0


def load_source_half_widths(path: Path | None) -> dict[str, float]:
    """Load each source polyline's real visible half width.

    The source inventory uses AutoCAD's CONSTANT_WIDTH in drawing units.  A
    missing or zero value is deliberately *not* converted here; the caller
    records that the formula fallback was used instead.
    """

    if path is None:
        return {}
    result: dict[str, float] = {}
    for row in read_tsv(path):
        handle = row.get("HANDLE", "").strip().upper()
        if not handle:
            continue
        width = max(0.0, float(row.get("CONSTANT_WIDTH", "0") or 0.0))
        if width > 0.0:
            result[handle] = width * 0.5
    return result


def endpoint_clusters(
    keys: set[tuple[str, int]],
    geometry: dict[tuple[str, int], dict[str, str]],
    short_keys: set[tuple[str, int]],
    tolerance: float,
) -> list[list[tuple[str, int]]]:
    """Return true shared-endpoint components for failed sharp-turn arcs.

    Consecutive segment numbers are not a geometric relationship (and fail for
    closed-path wrap-around).  Two failed arcs belong to one correction cluster
    only when their real WCS endpoints meet within tolerance and at least one is
    a short/tight arc.  Non-clustered failures remain one-item components.
    """

    if tolerance <= 0.0:
        raise ValueError("endpoint tolerance must be positive")
    ordered = sorted(keys, key=lambda item: (item[0], item[1]))
    neighbours: dict[tuple[str, int], set[tuple[str, int]]] = {
        key: set() for key in ordered
    }

    def endpoints(key: tuple[str, int]) -> tuple[Point, Point]:
        row = geometry[key]
        return (
            Point(float(row["START_X"]), float(row["START_Y"])),
            Point(float(row["END_X"]), float(row["END_Y"])),
        )

    for index, first in enumerate(ordered):
        for second in ordered[index + 1 :]:
            if first[0] != second[0]:
                continue
            if first not in short_keys and second not in short_keys:
                continue
            if min(
                distance(left, right)
                for left in endpoints(first)
                for right in endpoints(second)
            ) <= tolerance:
                neighbours[first].add(second)
                neighbours[second].add(first)

    result: list[list[tuple[str, int]]] = []
    remaining = set(ordered)
    while remaining:
        seed = min(remaining)
        component: set[tuple[str, int]] = set()
        stack = [seed]
        while stack:
            current = stack.pop()
            if current in component:
                continue
            component.add(current)
            stack.extend(neighbours[current] - component)
        remaining -= component
        result.append(sorted(component, key=lambda item: (item[0], item[1])))
    return result


def promote_endpoint_cluster_failures(
    keys: set[tuple[str, int]],
    individual_failed_keys: set[tuple[str, int]],
    geometry: dict[tuple[str, int], dict[str, str]],
    short_keys: set[tuple[str, int]],
    state: dict[tuple[str, int], dict[str, object]],
    text_height: float,
    endpoint_tolerance: float,
    common_band_tolerance_h: float,
    *,
    promote_on_member_failure: bool,
    require_common_side: bool,
    require_common_band: bool,
) -> tuple[set[tuple[str, int]], dict[tuple[str, int], dict[str, object]]]:
    """Promote one local sharp endpoint cluster before pass-1 items freeze."""

    if text_height <= 0.0 or common_band_tolerance_h < 0.0:
        raise ValueError("invalid endpoint-cluster consistency input")
    promoted = set(individual_failed_keys)
    metadata: dict[tuple[str, int], dict[str, object]] = {}
    clusters = endpoint_clusters(keys, geometry, short_keys, endpoint_tolerance)
    cluster_number = 0
    for cluster in clusters:
        if len(cluster) < 2:
            continue
        reasons: list[str] = []
        if promote_on_member_failure and any(
            key in individual_failed_keys for key in cluster
        ):
            reasons.append("MEMBER_SANDWICH_FAILURE")
        signs = {
            1 if float(state[key]["signed_band"]) >= 0.0 else -1
            for key in cluster
        }
        if require_common_side and len(signs) > 1:
            reasons.append("MIXED_OFFSET_SIDE")
        bands_h = [
            abs(float(state[key]["signed_band"])) / text_height for key in cluster
        ]
        if (
            require_common_band
            and max(bands_h) - min(bands_h) > common_band_tolerance_h
        ):
            reasons.append("MIXED_OFFSET_BAND")
        if not reasons:
            continue
        cluster_number += 1
        cluster_id = f"PRECHECK_ENDPOINT_CLUSTER_{cluster_number:03d}"
        promoted.update(cluster)
        for key in cluster:
            metadata[key] = {
                "precheck_cluster_id": cluster_id,
                "precheck_cluster_size": len(cluster),
                "promotion_reasons": tuple(reasons),
            }
    return promoted, metadata


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def canonical_base_band_h(
    source_half_width: float,
    text_height: float,
    source_to_text_gap_h: float,
    text_to_dimension_gap_h: float,
    candidate_bands_h: tuple[float, ...],
) -> float:
    """Choose the first approved H-band that can contain the real sandwich.

    The native dimension curve offset is measured from the source centreline,
    while the user's visual rule starts at the *visible* blue edge.  Therefore
    the source half width must be part of the formula instead of a single
    drawing-wide constant.
    """

    if text_height <= 0.0 or source_half_width < 0.0:
        raise ValueError("invalid source/text dimensions")
    required_h = (
        source_half_width / text_height
        + source_to_text_gap_h
        + 1.0
        + text_to_dimension_gap_h
    )
    return nearest_allowed_band_h(required_h, candidate_bands_h)


def read_pass1_receipt(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or payload.get("pass_index") != 1:
        raise SystemExit("invalid pass-1 receipt")
    return payload


def parse_handles(details_paths: list[Path]) -> dict[tuple[str, int], str]:
    result: dict[tuple[str, int], str] = {}
    for path in details_paths:
        for row in read_tsv(path):
            if row.get("STATUS") != "PASS" or row.get("SEGMENT_TYPE") != "ARC":
                continue
            source = row.get("SOURCE_HANDLE", "").upper()
            handle = row.get("ADDED_HANDLE", "").upper()
            if not source or not handle:
                continue
            key = (source, int(row["SEGMENT_INDEX"]))
            if key in result and result[key] != handle:
                raise SystemExit(f"duplicate accepted mapping for {key}: {result[key]} / {handle}")
            result[key] = handle
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True, type=Path)
    parser.add_argument("--accepted-details", required=True, type=Path, action="append")
    parser.add_argument("--grips", required=True, type=Path)
    parser.add_argument("--text-bboxes", required=True, type=Path)
    parser.add_argument(
        "--source-styles",
        type=Path,
        help="Optional TSV containing HANDLE and CONSTANT_WIDTH.",
    )
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--text-height", type=float, default=0.0)
    parser.add_argument("--preferred-band-h", type=float, default=1.00)
    parser.add_argument("--collision-gap-h", type=float, default=0.18)
    parser.add_argument("--band-step-h", type=float, default=0.70)
    parser.add_argument("--max-step-h", type=float, default=1.20)
    parser.add_argument("--short-length-h", type=float, default=2.85)
    parser.add_argument(
        "--formula",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "config"
        / "annotation_vector_layout_formula_v2.json",
    )
    parser.add_argument(
        "--two-pass-sandwich",
        action="store_true",
        help="Use the measured blue-source -> text -> green-dimension two-pass rule.",
    )
    parser.add_argument(
        "--pass-index",
        type=int,
        choices=(1, 2),
        default=2,
        help="Pass 1 normalises the full batch; pass 2 freezes passes and repairs only failures.",
    )
    parser.add_argument(
        "--normalize-layout",
        action="store_true",
        help="First converge normal arcs to one outer H-band; keep only viable tight corners on nested inner bands.",
    )
    parser.add_argument("--endpoint-tolerance", type=float, default=0.00001)
    parser.add_argument(
        "--output-receipt",
        type=Path,
        help="Required for two-pass pass 1; binds the exact pre-pass snapshot.",
    )
    parser.add_argument(
        "--pass1-receipt",
        type=Path,
        help="Required for pass 2; proves pass 1 was applied and re-inventoried.",
    )
    parser.add_argument("--output-plan", required=True, type=Path)
    parser.add_argument("--output-audit", required=True, type=Path)
    args = parser.parse_args()

    vector_formula = load_vector_layout_formula(args.formula)
    sandwich_rule = vector_formula.sandwich_layout

    if args.two_pass_sandwich and args.pass_index == 1 and args.output_receipt is None:
        raise SystemExit("two-pass pass 1 requires --output-receipt")
    if args.two_pass_sandwich and args.pass_index == 2 and args.pass1_receipt is None:
        raise SystemExit("two-pass pass 2 requires --pass1-receipt")

    if min(args.preferred_band_h, args.collision_gap_h, args.band_step_h, args.max_step_h) <= 0:
        raise SystemExit("all H-normalised distances must be positive")

    wanted_sources = {item.upper() for item in args.source}
    accepted = parse_handles(args.accepted_details)

    geometry: dict[tuple[str, int], dict[str, str]] = {}
    for raw in read_tsv(args.geometry):
        row = {key.upper(): value for key, value in raw.items()}
        source = row["SOURCE_HANDLE"].upper()
        if wanted_sources and source not in wanted_sources:
            continue
        geometry[(source, int(row["SEGMENT_INDEX"]))] = row

    grips: dict[str, dict[int, Point]] = {}
    classes: dict[str, str] = {}
    for row in read_tsv(args.grips):
        handle = row["HANDLE"].upper()
        grips.setdefault(handle, {})[int(row["GRIP_INDEX"])] = Point(float(row["GRIP_X"]), float(row["GRIP_Y"]))
        classes[handle] = row["RXCLASS"]

    text_rows: dict[str, dict[str, str]] = {}
    measured_heights: list[float] = []
    for row in read_tsv(args.text_bboxes):
        handle = row.get("SOURCE_HANDLE", row.get("HANDLE", "")).upper()
        if not handle or not row.get("MIN_X"):
            continue
        text_rows[handle] = row
        if row.get("HEIGHT"):
            measured_heights.append(float(row["HEIGHT"]))
    height = args.text_height or (sum(measured_heights) / len(measured_heights) if measured_heights else 0.0)
    if height <= 0:
        raise SystemExit("no positive native text height")

    source_half_widths = load_source_half_widths(args.source_styles)

    selected_keys = sorted(
        (key for key in geometry if key in accepted),
        key=lambda key: (key[0], key[1]),
    )
    if not selected_keys:
        raise SystemExit("no accepted source segments")

    target_handles = sorted(accepted[key] for key in selected_keys)
    snapshot_hashes = {
        "grips_sha256": file_sha256(args.grips),
        "text_bboxes_sha256": file_sha256(args.text_bboxes),
    }
    if args.two_pass_sandwich and args.pass_index == 2:
        receipt = read_pass1_receipt(args.pass1_receipt)
        if receipt.get("formula_id") != vector_formula.formula_id:
            raise SystemExit("pass-1 receipt formula mismatch")
        if receipt.get("target_handles") != target_handles:
            raise SystemExit("pass-1 receipt target set mismatch")
        pre_snapshot = receipt.get("pre_snapshot", {})
        if (
            pre_snapshot.get("grips_sha256") == snapshot_hashes["grips_sha256"]
            and pre_snapshot.get("text_bboxes_sha256")
            == snapshot_hashes["text_bboxes_sha256"]
            and int(receipt.get("planned_move_count", 0)) > 0
        ):
            raise SystemExit(
                "pass 2 received the unchanged pre-pass snapshot; apply pass 1 and re-inventory first"
            )

    # Text collisions are measured from the real native child MText boxes.
    text_boxes = {handle: obb_from_native_bbox(row, height) for handle, row in text_rows.items()}
    collision_handles: set[str] = set()
    collision_pairs: list[tuple[str, str]] = []
    gap = args.collision_gap_h * height
    for index, first_key in enumerate(selected_keys):
        first_handle = accepted[first_key]
        first_box = text_boxes.get(first_handle)
        if not first_box:
            raise SystemExit(f"{first_handle}: missing native text bbox")
        for second_key in selected_keys[index + 1 :]:
            second_handle = accepted[second_key]
            second_box = text_boxes.get(second_handle)
            if not second_box:
                raise SystemExit(f"{second_handle}: missing native text bbox")
            if obb_overlaps(first_box.expanded(gap), second_box.expanded(gap)):
                collision_handles.update((first_handle, second_handle))
                collision_pairs.append((first_handle, second_handle))

    # Read the current signed band before choosing any correction.  Long,
    # non-colliding dimensions define the source's established visual side.
    state: dict[tuple[str, int], dict[str, object]] = {}
    dominant_samples: dict[str, list[float]] = {}
    for key in selected_keys:
        source, _segment = key
        row = geometry[key]
        handle = accepted[key]
        native = grips.get(handle, {})
        if classes.get(handle) != "TDbDimension2" or not all(index in native for index in (0, 2, 3)):
            raise SystemExit(f"{handle}: incomplete native grips")
        start = Point(float(row["START_X"]), float(row["START_Y"]))
        end = Point(float(row["END_X"]), float(row["END_Y"]))
        center, source_radius = arc_center_radius(row)
        arc_length = float(
            row.get("ARC_LENGTH", row.get("SEGMENT_LENGTH", row.get("LENGTH", "0"))) or 0.0
        )
        if arc_length <= 0.0 and row.get("SWEEP_DEGREES"):
            arc_length = source_radius * math.radians(abs(float(row["SWEEP_DEGREES"])))
        association_error = endpoint_error(native[2], native[3], start, end)
        if association_error > args.endpoint_tolerance:
            raise SystemExit(f"{handle}: source association error {association_error:.9f}")
        current_radius = distance(native[0], center)
        signed_band = current_radius - source_radius
        if source in source_half_widths:
            source_half_width = source_half_widths[source]
            source_width_mode = "ACTUAL_CONSTANT_WIDTH"
        else:
            source_half_width = sandwich_rule.source_half_width_fallback_h * height
            source_width_mode = "FORMULA_FALLBACK"
        base_band_h = canonical_base_band_h(
            source_half_width,
            height,
            sandwich_rule.source_to_text_gap_h,
            sandwich_rule.text_to_dimension_gap_h,
            vector_formula.two_pass_batch_policy.candidate_bands_h,
        )
        state[key] = {
            "center": center,
            "source_radius": source_radius,
            "arc_length": arc_length,
            "association_error": association_error,
            "grip0": native[0],
            "current_radius": current_radius,
            "signed_band": signed_band,
            "source_half_width": source_half_width,
            "source_width_mode": source_width_mode,
            "base_band_h": base_band_h,
            "sweep_sign": 1.0 if float(row.get("SWEEP_DEGREES", "0") or 0.0) >= 0.0 else -1.0,
        }
        if handle not in collision_handles and abs(signed_band) >= 0.05 * height:
            dominant_samples.setdefault(source, []).append(signed_band)

    dominant_side: dict[str, float] = {}
    source_orientations = {
        source: source_orientation([geometry[key] for key in selected_keys if key[0] == source])
        for source in {key[0] for key in selected_keys}
    }
    for source in {key[0] for key in selected_keys}:
        samples = dominant_samples.get(source, [])
        if not samples:
            samples = [float(state[key]["signed_band"]) for key in selected_keys if key[0] == source]
        dominant_side[source] = 1.0 if sum(1 if value > 0 else -1 for value in samples) >= 0 else -1.0

    # Consecutive tight-corner arcs receive deterministic local ranks.  Arc
    # length alone is insufficient: a large-sweep, small-radius return curve
    # is still a pointed-corner condition.  Ranks reset when a normal arc is
    # encountered so separate corners do not push one another into deep bands.
    short_rank: dict[tuple[str, int], int] = {}
    for source in {key[0] for key in selected_keys}:
        source_keys = [key for key in selected_keys if key[0] == source]
        local_rank = 0
        previous_was_short = False
        for key in source_keys:
            is_short = (
                float(state[key]["arc_length"]) < args.short_length_h * height
                or float(state[key]["source_radius"]) < args.short_length_h * height
            )
            if not is_short:
                previous_was_short = False
                local_rank = 0
                continue
            if previous_was_short:
                local_rank += 1
            else:
                local_rank = 0
            short_rank[key] = local_rank
            previous_was_short = True

    sandwich_audits: dict[tuple[str, int], object] = {}
    sandwich_target: dict[tuple[str, int], tuple[float, float, str]] = {}
    cluster_metadata: dict[tuple[str, int], dict[str, object]] = {}
    effective_failed_keys: set[tuple[str, int]] = set()
    if args.two_pass_sandwich:
        passed_keys: set[tuple[str, int]] = set()
        failed_keys: set[tuple[str, int]] = set()
        for key in selected_keys:
            handle = accepted[key]
            item = state[key]
            current_band = float(item["signed_band"])
            side_sign = 1 if current_band >= 0.0 else -1
            audit = audit_text_between_source_and_dimension(
                center=VectorPoint(item["center"].x, item["center"].y),
                grip0=VectorPoint(item["grip0"].x, item["grip0"].y),
                text_polygon=vector_polygon(text_boxes[handle]),
                source_radius=float(item["source_radius"]),
                source_half_width=float(item["source_half_width"]),
                text_height=height,
                source_to_text_gap_h=sandwich_rule.source_to_text_gap_h,
                text_to_dimension_gap_h=sandwich_rule.text_to_dimension_gap_h,
                side_sign=side_sign,
            )
            sandwich_audits[key] = audit
            (passed_keys if audit.passed else failed_keys).add(key)

        if args.pass_index == 1:
            # Freeze every object that already satisfies the final sandwich
            # contract.  Pass 1 normalises only the failed subset; otherwise a
            # later audit would manufacture regressions by pulling accepted
            # dimensions back to the coarse seed band.
            for key in selected_keys:
                if key in passed_keys:
                    current = float(state[key]["signed_band"])
                    sandwich_target[key] = (
                        1.0 if current >= 0.0 else -1.0,
                        abs(current) / height,
                        "PASS1_FREEZE_CURRENT_SANDWICH_PASS",
                    )
                    continue
                source = key[0]
                item = state[key]
                orientation = source_orientations[source]
                exterior_side = (
                    orientation * float(item["sweep_sign"])
                    if orientation != 0.0
                    else dominant_side[source]
                )
                sandwich_target[key] = (
                    exterior_side,
                    float(item["base_band_h"]),
                    "PASS1_UNIFORM_EXTERIOR_BALANCED_BAND",
                )
        else:
            effective_failed_keys, precheck_metadata = (
                promote_endpoint_cluster_failures(
                    selected_keys,
                    failed_keys,
                    geometry,
                    set(short_rank),
                    state,
                    height,
                    args.endpoint_tolerance,
                    vector_formula.endpoint_cluster.common_band_tolerance_h,
                    promote_on_member_failure=(
                        vector_formula.endpoint_cluster
                        .promote_full_cluster_on_member_failure
                    ),
                    require_common_side=(
                        vector_formula.endpoint_cluster.common_side_required
                    ),
                    require_common_band=(
                        vector_formula.endpoint_cluster.common_band_required
                    ),
                )
            )
            passed_keys = selected_keys - effective_failed_keys
            for key, metadata in precheck_metadata.items():
                cluster_metadata.setdefault(key, {}).update(metadata)

            # Freeze only effective pass-1 successes.  A local defect cannot
            # restart the batch, but it also cannot strand its neighbour on a
            # conflicting side or band.
            for key in passed_keys:
                current = float(state[key]["signed_band"])
                sandwich_target[key] = (
                    1.0 if current >= 0.0 else -1.0,
                    abs(current) / height,
                    "PASS2_FREEZE_SANDWICH_PASS",
                )

            # The user's seven red circles are geometric endpoint clusters,
            # not runs of consecutive segment numbers.  This also handles a
            # closed polyline's last/first segment seam correctly.
            failed_groups = endpoint_clusters(
                effective_failed_keys,
                geometry,
                set(short_rank),
                args.endpoint_tolerance,
            )

            frozen_boxes = {
                accepted[key]: text_boxes[accepted[key]].expanded(gap)
                for key in passed_keys
            }
            for cluster_index, group in enumerate(failed_groups, start=1):
                current_signs = [
                    1.0 if float(state[key]["signed_band"]) >= 0.0 else -1.0
                    for key in group
                ]
                shared_side = 1.0 if sum(current_signs) >= 0.0 else -1.0
                base_target_h = max(float(state[key]["base_band_h"]) for key in group)
                next_bands = tuple(
                    value
                    for value in vector_formula.two_pass_batch_policy.candidate_bands_h
                    if value > base_target_h + 1.0e-9
                )
                options = [
                    (shared_side, base_target_h, "PASS2_SAME_SIDE_BALANCED_BAND"),
                    (-shared_side, base_target_h, "PASS2_CLUSTER_SHARED_OPPOSITE_BALANCED_BAND"),
                ]
                options.extend(
                    (shared_side, value, "PASS2_CLUSTER_SHARED_SIDE_NEXT_BAND")
                    for value in next_bands
                )
                ranked_options: list[tuple[tuple[int, float, int], tuple[float, float, str]]] = []
                for option_index, (candidate_side, candidate_band_h, candidate_reason) in enumerate(options):
                    forecast: dict[str, OrientedBox] = {}
                    arrow_bodies: list[OrientedBox] = []
                    sandwich_failure_count = 0
                    total_offset_delta_h = 0.0
                    for key in group:
                        item = state[key]
                        handle = accepted[key]
                        current_radius = float(item["current_radius"])
                        target_radius = float(item["source_radius"]) + candidate_side * candidate_band_h * height
                        grip0 = item["grip0"]
                        center = item["center"]
                        ux = (grip0.x - center.x) / current_radius
                        uy = (grip0.y - center.y) / current_radius
                        radial_change = target_radius - current_radius
                        total_offset_delta_h += abs(radial_change) / height
                        forecast[handle] = translate_obb(
                            text_boxes[handle], ux * radial_change, uy * radial_change
                        ).expanded(gap)
                        target_grip = VectorPoint(
                            center.x + ux * target_radius,
                            center.y + uy * target_radius,
                        )
                        source_row = geometry[key]
                        for endpoint in (
                            Point(float(source_row["START_X"]), float(source_row["START_Y"])),
                            Point(float(source_row["END_X"]), float(source_row["END_Y"])),
                        ):
                            endpoint_radius = distance(center, endpoint)
                            if endpoint_radius <= 1.0e-9:
                                sandwich_failure_count += 1
                                continue
                            arrow_point = Point(
                                center.x
                                + (endpoint.x - center.x) / endpoint_radius * target_radius,
                                center.y
                                + (endpoint.y - center.y) / endpoint_radius * target_radius,
                            )
                            arrow_bodies.append(
                                square_obb(
                                    arrow_point,
                                    0.5 * vector_formula.geometry.arrow_size_h * height,
                                )
                            )
                        candidate_audit = audit_text_between_source_and_dimension(
                            center=VectorPoint(center.x, center.y),
                            grip0=target_grip,
                            text_polygon=vector_polygon(
                                translate_obb(
                                    text_boxes[handle], ux * radial_change, uy * radial_change
                                )
                            ),
                            source_radius=float(item["source_radius"]),
                            source_half_width=float(item["source_half_width"]),
                            text_height=height,
                            source_to_text_gap_h=sandwich_rule.source_to_text_gap_h,
                            text_to_dimension_gap_h=sandwich_rule.text_to_dimension_gap_h,
                            side_sign=int(candidate_side),
                        )
                        sandwich_failure_count += len(candidate_audit.failure_reasons)
                    boxes = list(forecast.items())
                    group_collision_count = sum(
                        obb_overlaps(first_box, second_box)
                        for index, (_first_handle, first_box) in enumerate(boxes)
                        for _second_handle, second_box in boxes[index + 1 :]
                    )
                    frozen_collision_count = sum(
                        obb_overlaps(candidate_box, frozen_box)
                        for candidate_box in forecast.values()
                        for frozen_box in frozen_boxes.values()
                    )
                    # Thin green curves may touch text under severe spatial
                    # constraint; the filled native arrow marker may not.
                    arrow_collision_count = sum(
                        obb_overlaps(candidate_box, arrow_box)
                        for candidate_box in forecast.values()
                        for arrow_box in arrow_bodies
                    )
                    frozen_arrow_collision_count = sum(
                        obb_overlaps(frozen_box, arrow_box)
                        for frozen_box in frozen_boxes.values()
                        for arrow_box in arrow_bodies
                    )
                    hard_count = (
                        sandwich_failure_count
                        + group_collision_count
                        + frozen_collision_count
                        + arrow_collision_count
                        + frozen_arrow_collision_count
                    )
                    side_switch_count = sum(
                        1
                        for key in group
                        if candidate_side
                        != (1.0 if float(state[key]["signed_band"]) >= 0.0 else -1.0)
                    )
                    band_steps = max(
                        0.0,
                        (candidate_band_h - base_target_h)
                        / vector_formula.endpoint_cluster.next_band_increment_h,
                    )
                    non_dominant = sum(
                        1 for key in group if candidate_side != dominant_side[key[0]]
                    )
                    soft_score = (
                        side_switch_count * vector_formula.weights.side_switch
                        + band_steps * vector_formula.weights.band_step
                        + total_offset_delta_h * vector_formula.weights.offset_delta
                        + non_dominant * vector_formula.weights.non_dominant_side
                    )
                    ranked_options.append(
                        (
                            (hard_count, soft_score, option_index),
                            (candidate_side, candidate_band_h, candidate_reason),
                        )
                    )
                ranked_options.sort(key=lambda item: item[0])
                best_score, best_option = ranked_options[0]
                chosen = best_option if best_score[0] == 0 else None
                cluster_id = f"ENDPOINT_CLUSTER_{cluster_index:03d}"
                if chosen is None:
                    for key in group:
                        current = float(state[key]["signed_band"])
                        sandwich_target[key] = (
                            1.0 if current >= 0.0 else -1.0,
                            abs(current) / height,
                            "PASS2_MANUAL_REVIEW_NO_ZERO_COLLISION_CANDIDATE",
                        )
                        cluster_metadata[key] = {
                            **cluster_metadata.get(key, {}),
                            "cluster_id": cluster_id,
                            "cluster_size": len(group),
                            "hard_count": best_score[0],
                            "soft_score": best_score[1],
                        }
                else:
                    for key in group:
                        sandwich_target[key] = chosen
                        cluster_metadata[key] = {
                            **cluster_metadata.get(key, {}),
                            "cluster_id": cluster_id,
                            "cluster_size": len(group),
                            "hard_count": best_score[0],
                            "soft_score": best_score[1],
                        }

    target_sandwich_audits: dict[tuple[str, int], object] = {}
    target_text_boxes: dict[str, OrientedBox] = {}
    target_collision_pairs: list[tuple[str, str]] = []
    if args.two_pass_sandwich:
        for key in selected_keys:
            item = state[key]
            handle = accepted[key]
            target_side, target_band_h, _target_reason = sandwich_target[key]
            target_radius = float(item["source_radius"]) + target_side * target_band_h * height
            current_radius = float(item["current_radius"])
            grip0 = item["grip0"]
            center = item["center"]
            ux = (grip0.x - center.x) / current_radius
            uy = (grip0.y - center.y) / current_radius
            radial_change = target_radius - current_radius
            text_box = text_boxes[handle]
            text_dx = text_box.center.x - center.x
            text_dy = text_box.center.y - center.y
            text_radius = math.hypot(text_dx, text_dy)
            if text_radius > 1.0e-9:
                text_ux = text_dx / text_radius
                text_uy = text_dy / text_radius
            else:
                text_ux = ux
                text_uy = uy
            # Native TDbDimension2 grip0 changes the common dimension radius.
            # The text grip follows the same scalar radius delta along its own
            # polar ray, not along grip0's ray.  This was measured in the live
            # Tianzheng pass01 evidence and avoids a false rigid-translation
            # forecast at roughly 90-degree corner text locations.
            target_box = translate_obb(
                text_box, text_ux * radial_change, text_uy * radial_change
            )
            target_text_boxes[handle] = target_box
            target_sandwich_audits[key] = audit_text_between_source_and_dimension(
                center=VectorPoint(center.x, center.y),
                grip0=VectorPoint(center.x + ux * target_radius, center.y + uy * target_radius),
                text_polygon=vector_polygon(target_box),
                source_radius=float(item["source_radius"]),
                source_half_width=float(item["source_half_width"]),
                text_height=height,
                source_to_text_gap_h=sandwich_rule.source_to_text_gap_h,
                text_to_dimension_gap_h=sandwich_rule.text_to_dimension_gap_h,
                side_sign=int(target_side),
            )
        for index, first_key in enumerate(selected_keys):
            first_handle = accepted[first_key]
            first_box = target_text_boxes[first_handle].expanded(gap)
            for second_key in selected_keys[index + 1 :]:
                second_handle = accepted[second_key]
                second_box = target_text_boxes[second_handle].expanded(gap)
                if obb_overlaps(first_box, second_box):
                    target_collision_pairs.append((first_handle, second_handle))

    plan_rows: list[dict[str, object]] = []
    audit_rows: list[dict[str, object]] = []
    for key in selected_keys:
        source, segment = key
        row = geometry[key]
        handle = accepted[key]
        native = grips.get(handle, {})
        if classes.get(handle) != "TDbDimension2" or not all(index in native for index in (0, 2, 3)):
            raise SystemExit(f"{handle}: incomplete native grips")
        item = state[key]
        center = item["center"]
        source_radius = float(item["source_radius"])
        arc_length = float(item["arc_length"])
        association_error = float(item["association_error"])
        grip0 = item["grip0"]
        current_radius = float(item["current_radius"])
        signed_band = float(item["signed_band"])
        side = dominant_side[source] if abs(signed_band) < 0.05 * height else (1.0 if signed_band > 0 else -1.0)
        short_arc = arc_length > 0 and (
            arc_length < args.short_length_h * height
            or source_radius < args.short_length_h * height
        )
        collision = handle in collision_handles

        # For a closed polyline, the visually useful "inside" at the arc
        # midpoint is defined by source traversal, not by the sign of
        # (dimension radius - source radius).  This is what prevents pointed
        # corners from being thrown to the wrong side of a kidney-shaped loop.
        sweep_sign = float(item["sweep_sign"])
        orientation = source_orientations[source]
        interior_radial_sign = (
            -orientation * sweep_sign
            if orientation != 0.0
            else -dominant_side[source]
        )
        current_inner_band = (current_radius - source_radius) * interior_radial_sign

        # The default feedback mode freezes clean objects.  Normalization mode
        # is the preceding coarse pass: it removes inherited arbitrary offsets
        # and establishes one coherent outer band before collision relief.
        reason = "KEEP_CLEAN"
        target_signed_band = signed_band
        collision_partners = {
            second if first == handle else first
            for first, second in collision_pairs
            if first == handle or second == handle
        }
        partner_has_short_arc = any(
            float(state[partner_key]["arc_length"]) < args.short_length_h * height
            or float(state[partner_key]["source_radius"]) < args.short_length_h * height
            for partner_key in selected_keys
            if accepted[partner_key] in collision_partners
        )
        insufficient_inner_band = current_inner_band < 0.55 * height
        minimum_remaining_radius = 0.45 * height
        requested_inner_band = (args.preferred_band_h + short_rank.get(key, 0) * args.band_step_h) * height
        inner_band_has_capacity = source_radius - requested_inner_band >= minimum_remaining_radius
        if args.two_pass_sandwich:
            target_side, target_band_h, reason = sandwich_target[key]
            target_signed_band = target_side * target_band_h * height
        elif args.normalize_layout and short_arc and inner_band_has_capacity:
            rank = short_rank.get(key, 0)
            target_inner_band = (args.preferred_band_h + rank * args.band_step_h) * height
            target_signed_band = interior_radial_sign * target_inner_band
            reason = "NORMALIZE_SHORT_INNER_NESTED_BAND"
        elif args.normalize_layout:
            # Outside is the opposite radial sign from the loop interior.
            # A short arc whose radius cannot hold text safely inside also
            # belongs here instead of collapsing around its curve centre.
            target_signed_band = -interior_radial_sign * args.preferred_band_h * height
            reason = "NORMALIZE_OUTER_BAND"
        elif short_arc and (collision or insufficient_inner_band):
            rank = short_rank.get(key, 0)
            target_inner_band = (args.preferred_band_h + rank * args.band_step_h) * height
            target_signed_band = interior_radial_sign * target_inner_band
            reason = "SHORT_ARC_INNER_NESTED_BAND"
        elif collision and not partner_has_short_arc:
            reason = "LONG_ARC_TEXT_COLLISION_RELIEF"
            preferred = max(args.preferred_band_h * height, abs(signed_band) + args.band_step_h * height)
            target_signed_band = dominant_side[source] * preferred
        elif collision:
            reason = "KEEP_FOR_SHORT_PARTNER"

        target_radius = source_radius + target_signed_band
        remaining = target_radius - current_radius
        max_step = args.max_step_h * height
        step = remaining if args.two_pass_sandwich else max(-max_step, min(max_step, remaining))
        frozen_reason = reason in {
            "KEEP_CLEAN",
            "KEEP_FOR_SHORT_PARTNER",
            "PASS1_FREEZE_CURRENT_SANDWICH_PASS",
            "PASS2_FREEZE_SANDWICH_PASS",
            "PASS2_MANUAL_REVIEW_NO_ZERO_COLLISION_CANDIDATE",
        }
        if not frozen_reason and abs(step) > 1e-6:
            unit_x = (grip0.x - center.x) / current_radius
            unit_y = (grip0.y - center.y) / current_radius
            destination = Point(grip0.x + unit_x * step, grip0.y + unit_y * step)
            plan_rows.append({"HANDLE": handle, "GRIP_INDEX": 0, "DX": destination.x - grip0.x, "DY": destination.y - grip0.y, "DZ": 0})

        audit_rows.append(
            {
                "SOURCE_HANDLE": source,
                "SEGMENT_INDEX": segment,
                "NATIVE_HANDLE": handle,
                "TEXT_HEIGHT": height,
                "ARC_LENGTH": arc_length,
                "SHORT_ARC": str(short_arc).upper(),
                "TEXT_COLLISION": str(collision).upper(),
                "REASON": reason,
                "SOURCE_RADIUS": source_radius,
                "SOURCE_HALF_WIDTH": item["source_half_width"],
                "SOURCE_WIDTH_MODE": item["source_width_mode"],
                "BASE_BAND_H": item["base_band_h"],
                "CURRENT_SIGNED_BAND": signed_band,
                "CURRENT_INNER_BAND": current_inner_band,
                "TARGET_SIGNED_BAND": target_signed_band,
                "COMMANDED_RADIAL_STEP": step,
                "ASSOCIATION_ERROR": association_error,
                "COLLISION_PARTNERS": ",".join(
                    second if first == handle else first
                    for first, second in collision_pairs
                    if first == handle or second == handle
                ),
                "SANDWICH_PASS": (
                    str(sandwich_audits[key].passed).upper()
                    if args.two_pass_sandwich
                    else "NOT_RUN"
                ),
                "SANDWICH_FAILURES": (
                    ",".join(sandwich_audits[key].failure_reasons)
                    if args.two_pass_sandwich
                    else ""
                ),
                "SOURCE_TEXT_GAP_H": (
                    sandwich_audits[key].source_text_gap / height
                    if args.two_pass_sandwich
                    else ""
                ),
                "TEXT_DIMENSION_GAP_H": (
                    sandwich_audits[key].text_dimension_gap / height
                    if args.two_pass_sandwich
                    else ""
                ),
                "ENDPOINT_CLUSTER_ID": cluster_metadata.get(key, {}).get(
                    "cluster_id", ""
                ),
                "ENDPOINT_PRECHECK_CLUSTER_ID": cluster_metadata.get(key, {}).get(
                    "precheck_cluster_id", ""
                ),
                "ENDPOINT_CLUSTER_SIZE": cluster_metadata.get(key, {}).get(
                    "cluster_size", ""
                ),
                "ENDPOINT_CLUSTER_PROMOTION_REASONS": ",".join(
                    cluster_metadata.get(key, {}).get("promotion_reasons", ())
                ),
                "CANDIDATE_HARD_COUNT": cluster_metadata.get(key, {}).get(
                    "hard_count", ""
                ),
                "CANDIDATE_SOFT_SCORE": cluster_metadata.get(key, {}).get(
                    "soft_score", ""
                ),
                "TARGET_SANDWICH_PASS": (
                    str(target_sandwich_audits[key].passed).upper()
                    if args.two_pass_sandwich
                    else "NOT_RUN"
                ),
                "TARGET_SANDWICH_FAILURES": (
                    ",".join(target_sandwich_audits[key].failure_reasons)
                    if args.two_pass_sandwich
                    else ""
                ),
                "TARGET_SOURCE_TEXT_GAP_H": (
                    target_sandwich_audits[key].source_text_gap / height
                    if args.two_pass_sandwich
                    else ""
                ),
                "TARGET_TEXT_DIMENSION_GAP_H": (
                    target_sandwich_audits[key].text_dimension_gap / height
                    if args.two_pass_sandwich
                    else ""
                ),
                "TARGET_TEXT_COLLISION_PARTNERS": ",".join(
                    second if first == handle else first
                    for first, second in target_collision_pairs
                    if first == handle or second == handle
                ),
            }
        )

    # Development pass 1 is deliberately monotonic: one failed target must not
    # suppress unrelated target moves that already have a zero-hard forecast.
    # Keep the successful subset executable and carry only the exact failed
    # handles into pass 2.  The final delivery gate can still require the full
    # set to pass, but exploration is allowed to converge object by object.
    target_failed_handles: set[str] = set()
    if args.two_pass_sandwich and args.pass_index == 1:
        target_failed_handles.update(
            accepted[key]
            for key, result in target_sandwich_audits.items()
            if not result.passed
        )
        target_failed_handles.update(
            handle for pair in target_collision_pairs for handle in pair
        )
    target_forecast_failed = bool(target_failed_handles)
    executable_plan_rows = [
        row for row in plan_rows if str(row["HANDLE"]).upper() not in target_failed_handles
    ]
    failed_plan_rows = [
        row for row in plan_rows if str(row["HANDLE"]).upper() in target_failed_handles
    ]
    diagnostic_plan_path: Path | None = None
    if target_forecast_failed:
        diagnostic_plan_path = args.output_plan.with_name(
            args.output_plan.stem + "_failed_subset_pending_pass2" + args.output_plan.suffix
        )
        write_tsv(
            diagnostic_plan_path,
            failed_plan_rows,
            ["HANDLE", "GRIP_INDEX", "DX", "DY", "DZ"],
        )
        write_tsv(
            args.output_plan,
            executable_plan_rows,
            ["HANDLE", "GRIP_INDEX", "DX", "DY", "DZ"],
        )
    else:
        write_tsv(args.output_plan, plan_rows, ["HANDLE", "GRIP_INDEX", "DX", "DY", "DZ"])
    write_tsv(
        args.output_audit,
        audit_rows,
        [
            "SOURCE_HANDLE",
            "SEGMENT_INDEX",
            "NATIVE_HANDLE",
            "TEXT_HEIGHT",
            "ARC_LENGTH",
            "SHORT_ARC",
            "TEXT_COLLISION",
            "REASON",
            "SOURCE_RADIUS",
            "SOURCE_HALF_WIDTH",
            "SOURCE_WIDTH_MODE",
            "BASE_BAND_H",
            "CURRENT_SIGNED_BAND",
            "CURRENT_INNER_BAND",
            "TARGET_SIGNED_BAND",
            "COMMANDED_RADIAL_STEP",
            "ASSOCIATION_ERROR",
            "COLLISION_PARTNERS",
            "SANDWICH_PASS",
            "SANDWICH_FAILURES",
            "SOURCE_TEXT_GAP_H",
            "TEXT_DIMENSION_GAP_H",
            "ENDPOINT_CLUSTER_ID",
            "ENDPOINT_PRECHECK_CLUSTER_ID",
            "ENDPOINT_CLUSTER_SIZE",
            "ENDPOINT_CLUSTER_PROMOTION_REASONS",
            "CANDIDATE_HARD_COUNT",
            "CANDIDATE_SOFT_SCORE",
            "TARGET_SANDWICH_PASS",
            "TARGET_SANDWICH_FAILURES",
            "TARGET_SOURCE_TEXT_GAP_H",
            "TARGET_TEXT_DIMENSION_GAP_H",
            "TARGET_TEXT_COLLISION_PARTNERS",
        ],
    )
    if args.two_pass_sandwich and args.pass_index == 1:
        receipt_payload = {
            "schema_version": 1,
            "status": (
                "PARTIAL_PASS1_SUCCESS_SUBSET_PREPARED"
                if target_forecast_failed and executable_plan_rows
                else "PASS1_FAILED_SUBSET_RETAINED_FOR_PASS2"
                if target_forecast_failed
                else "PREPARED_PASS1_PENDING_NATIVE_APPLY_AND_REINVENTORY"
            ),
            "formula_id": vector_formula.formula_id,
            "pass_index": 1,
            "pre_snapshot": snapshot_hashes,
            "target_handles": target_handles,
            "planned_move_count": len(executable_plan_rows),
            "failed_subset_move_count": len(failed_plan_rows),
            "diagnostic_plan_path": str(diagnostic_plan_path) if diagnostic_plan_path else "",
            "successful_subset_handles": sorted(
                str(row["HANDLE"]).upper() for row in executable_plan_rows
            ),
            "failed_subset_handles": sorted(target_failed_handles),
            "target_sandwich_fail_count": sum(
                1 for value in target_sandwich_audits.values() if not value.passed
            ),
            "target_text_collision_pair_count": len(target_collision_pairs),
            "output_plan_sha256": file_sha256(args.output_plan),
            "output_audit_sha256": file_sha256(args.output_audit),
        }
        args.output_receipt.parent.mkdir(parents=True, exist_ok=True)
        args.output_receipt.write_text(
            json.dumps(receipt_payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(
        json.dumps(
            {
                "status": (
                    "PARTIAL_PASS1_SUCCESS_SUBSET_PREPARED"
                    if target_forecast_failed and executable_plan_rows
                    else "PASS1_FAILED_SUBSET_RETAINED_FOR_PASS2"
                    if target_forecast_failed
                    else "PASS"
                ),
                "formula": (
                    vector_formula.formula_id
                    if args.two_pass_sandwich
                    else (
                        "GRIP0_NORMALIZE_THEN_FEEDBACK_V2"
                        if args.normalize_layout
                        else "GRIP0_FEEDBACK_BEAUTY_V1"
                    )
                ),
                "text_height": height,
                "source_count": len({key[0] for key in selected_keys}),
                "segment_count": len(selected_keys),
                "collision_handle_count": len(collision_handles),
                "planned_move_count": len(executable_plan_rows),
                "failed_subset_move_count": len(failed_plan_rows),
                "max_passes": 2 if args.two_pass_sandwich else 3,
                "pass_index": args.pass_index if args.two_pass_sandwich else None,
                "sandwich_pass_count": (
                    len(set(selected_keys) - effective_failed_keys)
                    if args.pass_index == 2
                    else sum(1 for value in sandwich_audits.values() if value.passed)
                    if args.two_pass_sandwich
                    else None
                ),
                "sandwich_fail_count": (
                    len(effective_failed_keys)
                    if args.pass_index == 2
                    else sum(1 for value in sandwich_audits.values() if not value.passed)
                    if args.two_pass_sandwich
                    else None
                ),
                "target_sandwich_pass_count": (
                    sum(1 for value in target_sandwich_audits.values() if value.passed)
                    if args.two_pass_sandwich
                    else None
                ),
                "target_sandwich_fail_count": (
                    sum(1 for value in target_sandwich_audits.values() if not value.passed)
                    if args.two_pass_sandwich
                    else None
                ),
                "target_text_collision_handle_count": (
                    len({handle for pair in target_collision_pairs for handle in pair})
                    if args.two_pass_sandwich
                    else None
                ),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
