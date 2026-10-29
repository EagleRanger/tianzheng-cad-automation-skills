"""Plan collision-free native angle/radius annotation positions.

This planner is intentionally read-only.  It consumes the geometry and native
TDIMARC acceptance records from a previously accepted isolated-DWG run.  It
does not edit a DWG and it never infers success from object counts alone.

The output is a candidate placement contract for the next Tianzheng gate:

* every angle is associated by source handle + segment index;
* only accepted TDbDimension2/PUB_DIM/_TCH_ARROW angle objects are admitted;
* both sides of every source arc are sampled for usable corridor width;
* angles are solved first with a same-side/same-band rhythm preference;
* radii are then placed outside the angle band and may slide along the arc;
* text, arrow and dimension-body overlaps are hard failures.

Real acceptance still requires applying the plan to native objects in an
isolated DWG, then E4 object audit and E5 save-close-reopen verification.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from annotation_layout_model import (
    Box,
    HardViolationVector,
    LayoutWeights,
    LayoutResult,
    PlacementCandidate,
    Point,
    Segment,
    audit_annotation_collisions,
    candidate_intrinsic_hard_vector,
    candidate_intrinsic_penalty,
    candidate_pair_penalty,
    candidate_pair_hard_vector,
    choose_layout,
    segment_intersects_box,
    segments_intersect,
)
from annotation_layout_formula import VectorLayoutFormula, load_vector_layout_formula
from annotation_vector_geometry import (
    Polyline,
    VectorPoint,
    conservative_arrow,
    oriented_box,
    signed_near_edge_clearance,
)


TARGET_HANDLES = ("652B2", "652B4", "652B8", "652BA", "652BB")
MAX_CLEARANCE = 36.0
RAY_EPSILON = 0.20
DEFAULT_ANGLE_OFFSET_FACTORS = (1.60, 1.85, 2.10, 2.35)
DEFAULT_RADIUS_OFFSET_FACTORS = (4.09, 5.0, 5.91, 7.27)
SHORT_ARC_CAPACITY_RATIO = 1.25
SHORT_ARC_SUPPORT_RATIO = 2.50
SHORT_ARC_BAND_PENALTY = 850.0
DEFAULT_VECTOR_FORMULA_PATH = (
    Path(__file__).resolve().parents[1]
    / "config"
    / "annotation_vector_layout_formula_v2.json"
)


@dataclass(frozen=True)
class ArcRecord:
    source: str
    segment: int
    start: Point
    end: Point
    mid: Point
    center: Point
    sweep_degrees: float
    radius: float
    source_half_width: float = 0.0

    @property
    def key(self) -> str:
        return f"{self.source}:{self.segment}"


@dataclass(frozen=True)
class NativeAngle:
    source: str
    segment: int
    handle: str

    @property
    def key(self) -> str:
        return f"{self.source}:{self.segment}"


@dataclass(frozen=True)
class AngleLayoutPolicy:
    """Per-segment layout policy without changing the verified TDIMARC kernel.

    ``normal`` preserves the already accepted same-side/same-band candidate
    space. ``short_corner`` is only assigned to cramped sharp arcs and their
    immediately adjacent support arc.  Closed paths use the measured exterior
    side unless the versioned formula explicitly enables an interior fallback.
    """

    mode: str = "normal"
    allowed_sides: tuple[str, ...] = ("left", "right")
    preferred_side: str = ""
    preferred_band: int | None = None
    cluster_id: str = ""
    cluster_rank: int | None = None
    capacity_ratio: float | None = None


def _read_tsv(path: Path) -> list[dict[str, str]]:
    raw = path.read_bytes()
    for encoding in ("utf-8-sig", "gb18030"):
        try:
            text = raw.decode(encoding)
            return list(csv.DictReader(text.splitlines(), delimiter="\t"))
        except UnicodeDecodeError:
            continue
    raise ValueError(f"unsupported TSV encoding: {path}")


def _point(row: dict[str, str], x_name: str, y_name: str) -> Point:
    return Point(float(row[x_name]), float(row[y_name]))


def load_source_half_widths(path: Path | None) -> dict[str, float]:
    if path is None:
        return {}
    widths: dict[str, float] = {}
    for row in _read_tsv(path):
        handle = row.get("HANDLE", "").strip().upper()
        if not handle:
            continue
        widths[handle] = max(0.0, float(row.get("CONSTANT_WIDTH", "0") or 0.0)) * 0.5
    return widths


def load_arcs(
    path: Path,
    handles: Sequence[str],
    source_half_widths: dict[str, float] | None = None,
) -> tuple[ArcRecord, ...]:
    allowed = {value.upper() for value in handles}
    width_map = source_half_widths or {}
    arcs = []
    for row in _read_tsv(path):
        if "SourceHandle" in row:
            source_key = "SourceHandle"
        elif "SOURCE_HANDLE" in row:
            source_key = "SOURCE_HANDLE"
        else:
            source_key = "HANDLE"
        source = row[source_key].upper()
        if source not in allowed:
            continue
        if "StartX" in row:
            arc = ArcRecord(
                source=source,
                segment=int(row["SegmentIndex"]),
                start=_point(row, "StartX", "StartY"),
                end=_point(row, "EndX", "EndY"),
                mid=_point(row, "MidX", "MidY"),
                center=_point(row, "CenterX", "CenterY"),
                sweep_degrees=float(row["SweepDegrees"]),
                radius=float(row["Radius"]),
                source_half_width=width_map.get(source, 0.0),
            )
        elif "START_X" in row and all(
            key in row
            for key in ("CENTER_X", "CENTER_Y", "SWEEP_DEGREES", "RADIUS")
        ):
            arc = ArcRecord(
                source=source,
                segment=int(row["SEGMENT_INDEX"]),
                start=_point(row, "START_X", "START_Y"),
                end=_point(row, "END_X", "END_Y"),
                mid=_point(row, "MID_X", "MID_Y"),
                center=_point(row, "CENTER_X", "CENTER_Y"),
                sweep_degrees=float(row["SWEEP_DEGREES"]),
                radius=float(row["RADIUS"]),
                source_half_width=width_map.get(source, 0.0),
            )
        else:
            arc = _arc_from_bulge_row(row, source)
            if arc is None:
                continue
        arcs.append(arc)
    arcs.sort(key=lambda item: (handles.index(item.source), item.segment))
    if not arcs:
        raise ValueError("no target source arcs found")
    return tuple(arcs)


def _arc_from_bulge_row(row: dict[str, str], source: str) -> ArcRecord | None:
    """Convert an authoritative LWPOLYLINE bulge row into exact arc geometry.

    Zero-length or zero-bulge rows are deliberately excluded.  In the accepted
    blue-shore source, handle 652B4 contains one repeated terminal vertex with
    non-zero bulge but zero chord length; admitting it would create a false
    fortieth arc and break the proven 39-object native association.
    """

    if "START_X" in row:
        start = _point(row, "START_X", "START_Y")
        end = _point(row, "END_X", "END_Y")
    else:
        start = _point(row, "X", "Y")
        end = _point(row, "NEXT_X", "NEXT_Y")
    bulge = float(row["BULGE"])
    chord = _distance(start, end)
    if chord <= 1e-7 or abs(bulge) <= 1e-12:
        return None
    sweep = 4.0 * math.atan(bulge)
    radius = chord * (1.0 + bulge * bulge) / (4.0 * abs(bulge))
    chord_unit = Point((end.x - start.x) / chord, (end.y - start.y) / chord)
    left_normal = Point(-chord_unit.y, chord_unit.x)
    center_offset = chord * (1.0 - bulge * bulge) / (4.0 * bulge)
    chord_mid = Point((start.x + end.x) / 2.0, (start.y + end.y) / 2.0)
    center = _add(chord_mid, left_normal, center_offset)
    start_angle = math.atan2(start.y - center.y, start.x - center.x)
    mid_angle = start_angle + sweep / 2.0
    mid = Point(
        center.x + radius * math.cos(mid_angle),
        center.y + radius * math.sin(mid_angle),
    )
    return ArcRecord(
        source=source,
        segment=int(float(row["SEGMENT_INDEX"])),
        start=start,
        end=end,
        mid=mid,
        center=center,
        sweep_degrees=math.degrees(sweep),
        radius=radius,
    )


def load_native_angles(path: Path, handles: Sequence[str]) -> tuple[NativeAngle, ...]:
    allowed = {value.upper() for value in handles}
    accepted: list[NativeAngle] = []
    seen_keys: set[str] = set()
    seen_handles: set[str] = set()
    for row in _read_tsv(path):
        source = row["SOURCE_HANDLE"].upper()
        if source not in allowed:
            continue
        key = f"{source}:{int(row['SEGMENT_INDEX'])}"
        handle = row["ADDED_HANDLE"].upper()
        semantic_accepted = "semantic=ACCEPTED" in row.get("ATTEMPTS", "")
        valid = (
            row.get("STATUS") == "PASS"
            and row.get("SEGMENT_TYPE") == "ARC"
            and row.get("OBJECT_NAME") == "TDbDimension2"
            and row.get("LAYER") == "PUB_DIM"
            and row.get("DIM_STYLE") == "_TCH_ARROW"
            and semantic_accepted
            and bool(handle)
        )
        if not valid:
            raise ValueError(f"native angle failed strict semantic gate: {key}")
        if key in seen_keys or handle in seen_handles:
            raise ValueError(f"duplicate native association: {key}/{handle}")
        seen_keys.add(key)
        seen_handles.add(handle)
        accepted.append(NativeAngle(source, int(row["SEGMENT_INDEX"]), handle))
    accepted.sort(key=lambda item: (handles.index(item.source), item.segment))
    return tuple(accepted)


def _distance(a: Point, b: Point) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _add(point: Point, vector: Point, factor: float = 1.0) -> Point:
    return Point(point.x + vector.x * factor, point.y + vector.y * factor)


def _unit(vector: Point) -> Point:
    length = math.hypot(vector.x, vector.y)
    if length <= 1e-12:
        raise ValueError("zero-length vector")
    return Point(vector.x / length, vector.y / length)


def _arc_point_and_tangent(arc: ArcRecord, fraction: float) -> tuple[Point, Point]:
    start_angle = math.atan2(arc.start.y - arc.center.y, arc.start.x - arc.center.x)
    sweep = math.radians(arc.sweep_degrees)
    angle = start_angle + sweep * fraction
    point = Point(
        arc.center.x + arc.radius * math.cos(angle),
        arc.center.y + arc.radius * math.sin(angle),
    )
    sign = 1.0 if sweep >= 0 else -1.0
    tangent = Point(-math.sin(angle) * sign, math.cos(angle) * sign)
    return point, tangent


def _upright_axis(axis: Point) -> Point:
    """Return a unit text baseline whose screen-readable direction is upright."""

    text_axis = _unit(axis)
    if text_axis.x < -1.0e-12 or (
        abs(text_axis.x) <= 1.0e-12 and text_axis.y < 0.0
    ):
        text_axis = Point(-text_axis.x, -text_axis.y)
    return text_axis


def _radius_slide_fractions(
    arc: ArcRecord,
    text_height: float,
    formula: VectorLayoutFormula,
) -> tuple[float, ...]:
    """Sample grip-2 positions by arc length, bounded by the formula.

    A fixed seven-fraction list undersamples long arcs and overstates short-arc
    freedom.  This converts the native text height into an along-arc spacing,
    keeps an endpoint clearance, and deterministically caps the search size.
    """

    arc_length = abs(math.radians(arc.sweep_degrees)) * arc.radius
    if arc_length <= 1.0e-9:
        raise ValueError(f"zero-length radius source arc: {arc.key}")
    geometry = formula.geometry
    margin = min(
        0.40,
        geometry.radius_slide_endpoint_clearance_h * text_height / arc_length,
    )
    usable = max(0.0, arc_length * (1.0 - 2.0 * margin))
    intervals = max(
        2,
        int(
            math.ceil(
                usable / (geometry.radius_slide_sample_spacing_h * text_height)
            )
        ),
    )
    count = min(geometry.radius_slide_max_samples, intervals + 1)
    if count <= 1:
        adaptive = (0.5,)
    else:
        adaptive = tuple(
            margin + (1.0 - 2.0 * margin) * index / (count - 1)
            for index in range(count)
        )
    raw = sorted(
        {
            round(value, 12)
            for value in adaptive + geometry.radius_pick_fractions + (0.5,)
            if margin - 1.0e-12 <= value <= 1.0 - margin + 1.0e-12
        }
    )
    if len(raw) <= geometry.radius_slide_max_samples:
        return tuple(raw)
    targets = tuple(
        margin
        + (1.0 - 2.0 * margin) * index
        / (geometry.radius_slide_max_samples - 1)
        for index in range(geometry.radius_slide_max_samples)
    )
    remaining = list(raw)
    selected: list[float] = []
    for target in targets:
        value = min(remaining, key=lambda item: (abs(item - target), item))
        selected.append(value)
        remaining.remove(value)
    return tuple(sorted(selected))


def _sample_arc(arc: ArcRecord, step_degrees: float = 8.0) -> tuple[Point, ...]:
    count = max(3, int(math.ceil(abs(arc.sweep_degrees) / step_degrees)))
    return tuple(_arc_point_and_tangent(arc, index / count)[0] for index in range(count + 1))


def _sample_offset_dimension_arc(
    arc: ArcRecord,
    side: str,
    offset: float,
    step_degrees: float,
) -> tuple[Point, ...]:
    """Sample the actual locally offset dimension arc, never its end chord."""

    count = max(3, int(math.ceil(abs(arc.sweep_degrees) / step_degrees)))
    points: list[Point] = []
    for index in range(count + 1):
        point, tangent = _arc_point_and_tangent(arc, index / count)
        points.append(_add(point, _side_normal(tangent, side), offset))
    return tuple(points)


def _boundary_segments(arcs: Iterable[ArcRecord]) -> tuple[tuple[str, int, Segment], ...]:
    segments: list[tuple[str, int, Segment]] = []
    for arc in arcs:
        points = _sample_arc(arc)
        for index in range(len(points) - 1):
            segments.append((arc.source, arc.segment, Segment(points[index], points[index + 1], "source")))
    return tuple(segments)


def _cross(first: Point, second: Point) -> float:
    return first.x * second.y - first.y * second.x


def _ray_segment_distance(origin: Point, direction: Point, segment: Segment) -> float | None:
    edge = Point(segment.end.x - segment.start.x, segment.end.y - segment.start.y)
    delta = Point(segment.start.x - origin.x, segment.start.y - origin.y)
    denominator = _cross(direction, edge)
    if abs(denominator) <= 1e-9:
        return None
    ray_t = _cross(delta, edge) / denominator
    edge_t = _cross(delta, direction) / denominator
    if ray_t > RAY_EPSILON and -1e-9 <= edge_t <= 1.0 + 1e-9:
        return ray_t
    return None


def _side_normal(tangent: Point, side: str) -> Point:
    if side == "left":
        return Point(-tangent.y, tangent.x)
    if side == "right":
        return Point(tangent.y, -tangent.x)
    raise ValueError(f"unknown side: {side}")


def _tdimarc_command_offset(side: str, offset: float) -> float:
    """Encode the planner's tangent-normal side for the frozen TDIMARC adapter.

    The native adapter always constructs its placement point from the local
    *left* tangent normal multiplied by this signed value.  This sign is
    therefore a left/right command parameter; it must not be derived from
    whether a concave or convex circular segment gains or loses radius.
    """

    if side == "left":
        return offset
    if side == "right":
        return -offset
    raise ValueError(f"unknown side: {side}")


def _radial_offset(arc: ArcRecord, side: str, offset: float) -> float:
    """Return the signed radius delta used only for geometric QA."""

    outward = (
        (arc.sweep_degrees > 0 and side == "right")
        or (arc.sweep_degrees < 0 and side == "left")
    )
    return offset if outward else -offset


def _local_clearance(
    arc: ArcRecord,
    fraction: float,
    side: str,
    boundaries: Sequence[tuple[str, int, Segment]],
) -> float:
    origin, tangent = _arc_point_and_tangent(arc, fraction)
    normal = _side_normal(tangent, side)
    distances: list[float] = []
    for source, segment_index, segment in boundaries:
        if source == arc.source and abs(segment_index - arc.segment) <= 1:
            continue
        distance = _ray_segment_distance(origin, normal, segment)
        if distance is not None:
            distances.append(distance)
    return min(distances, default=MAX_CLEARANCE)


def robust_clearance(
    arc: ArcRecord,
    fraction: float,
    side: str,
    boundaries: Sequence[tuple[str, int, Segment]],
    sample_count: int = 5,
) -> float:
    if sample_count < 3 or sample_count % 2 == 0:
        raise ValueError("clearance sample count must be an odd integer >= 3")
    start = max(0.08, fraction - 0.12)
    end = min(0.92, fraction + 0.12)
    samples = tuple(
        start + (end - start) * index / (sample_count - 1)
        for index in range(sample_count)
    )
    return min(_local_clearance(arc, value, side, boundaries) for value in samples)


def _rotated_box(center: Point, tangent: Point, width: float, height: float, kind: str) -> Box:
    tangent = _unit(tangent)
    normal = Point(-tangent.y, tangent.x)
    corners = (
        _add(_add(center, tangent, width / 2), normal, height / 2),
        _add(_add(center, tangent, width / 2), normal, -height / 2),
        _add(_add(center, tangent, -width / 2), normal, height / 2),
        _add(_add(center, tangent, -width / 2), normal, -height / 2),
    )
    return Box(
        min(point.x for point in corners),
        min(point.y for point in corners),
        max(point.x for point in corners),
        max(point.y for point in corners),
        kind,
    )


def _small_box(center: Point, radius: float, kind: str) -> Box:
    return Box(center.x - radius, center.y - radius, center.x + radius, center.y + radius, kind)


def _angle_label_width(
    arc: ArcRecord,
    text_height: float,
    formula: VectorLayoutFormula | None = None,
) -> float:
    active_formula = formula or load_vector_layout_formula(DEFAULT_VECTOR_FORMULA_PATH)
    visible_text = f"{abs(arc.sweep_degrees):.2f}\N{DEGREE SIGN}"
    return max(
        active_formula.geometry.angle_text_min_width_h * text_height,
        len(visible_text)
        * active_formula.geometry.text_width_per_visible_character_h
        * text_height,
    )


def _arc_capacity_ratio(
    arc: ArcRecord,
    text_height: float,
    formula: VectorLayoutFormula | None = None,
) -> float:
    """Return usable source-arc length divided by native text width."""

    arc_length = arc.radius * math.radians(abs(arc.sweep_degrees))
    active_formula = formula or load_vector_layout_formula(DEFAULT_VECTOR_FORMULA_PATH)
    visible_text = f"{abs(arc.sweep_degrees):.2f}\N{DEGREE SIGN}"
    classification_width = max(
        active_formula.short_arc.classification_angle_text_min_width_h
        * text_height,
        len(visible_text)
        * active_formula.short_arc.classification_text_width_per_visible_character_h
        * text_height,
    )
    return arc_length / classification_width


def _closed_path_interior_side(arcs: Sequence[ArcRecord]) -> str:
    """Map sampled path orientation to the local tangent-normal side."""

    return "left" if _signed_path_area(arcs) >= 0.0 else "right"


def _closed_path_exterior_side(arcs: Sequence[ArcRecord]) -> str:
    """Return the tangent-normal side outside a closed source path."""

    return "right" if _closed_path_interior_side(arcs) == "left" else "left"


def _short_arc_layout_policies(
    arcs: Sequence[ArcRecord],
    text_height: float,
    formula: VectorLayoutFormula | None = None,
) -> dict[str, AngleLayoutPolicy]:
    """Classify only the unresolved short/sharp portion of a path.

    A primary short arc cannot carry its own label along the source sweep.
    One adjacent support arc is admitted only when it is also locally tight;
    this lets a sharp two-arc tip use two close inner bands while normal
    neighbours keep the frozen normal policy.  Closed-path wraparound is
    respected, and every cluster receives deterministic ranks.
    """

    if text_height <= 0:
        raise ValueError("native text height must be positive")
    if not arcs:
        return {}
    active_formula = formula or load_vector_layout_formula(DEFAULT_VECTOR_FORMULA_PATH)
    primary_threshold = active_formula.short_arc.capacity_primary_threshold
    support_threshold = active_formula.short_arc.capacity_support_threshold
    ordered = sorted(arcs, key=lambda item: item.segment)
    ratios = {
        arc.key: _arc_capacity_ratio(arc, text_height, active_formula)
        for arc in ordered
    }
    primary = {arc.key for arc in ordered if ratios[arc.key] < primary_threshold}
    if not primary:
        return {arc.key: AngleLayoutPolicy(capacity_ratio=ratios[arc.key]) for arc in ordered}

    selected = set(primary)
    closed = _is_closed(ordered)
    count = len(ordered)
    for index, arc in enumerate(ordered):
        neighbour_indices = []
        if index > 0:
            neighbour_indices.append(index - 1)
        elif closed:
            neighbour_indices.append(count - 1)
        if index + 1 < count:
            neighbour_indices.append(index + 1)
        elif closed:
            neighbour_indices.append(0)
        if (
            ratios[arc.key] < support_threshold
            and any(ordered[item].key in primary for item in neighbour_indices)
        ):
            selected.add(arc.key)

    # Build deterministic contiguous clusters in source order.  The first
    # selected arc after a non-selected gap starts a new cluster.  A selected
    # wraparound pair is merged for closed paths.
    raw_clusters: list[list[ArcRecord]] = []
    current: list[ArcRecord] = []
    for arc in ordered:
        if arc.key in selected:
            current.append(arc)
        elif current:
            raw_clusters.append(current)
            current = []
    if current:
        raw_clusters.append(current)
    if closed and len(raw_clusters) > 1 and ordered[0].key in selected and ordered[-1].key in selected:
        raw_clusters[0] = raw_clusters[-1] + raw_clusters[0]
        raw_clusters.pop()

    interior = _closed_path_interior_side(ordered) if closed else ""
    exterior = _closed_path_exterior_side(ordered) if closed else ""
    preferred_closed_side = (
        exterior
        if active_formula.short_arc.closed_path_preferred_side == "exterior"
        else interior
    )
    fallback_closed_side = interior if preferred_closed_side == exterior else exterior
    result = {
        arc.key: AngleLayoutPolicy(capacity_ratio=ratios[arc.key]) for arc in ordered
    }
    for cluster_number, cluster in enumerate(raw_clusters, start=1):
        cluster_id = f"{ordered[0].source}:short:{cluster_number}"
        for rank, arc in enumerate(cluster):
            result[arc.key] = AngleLayoutPolicy(
                mode="short_corner",
                allowed_sides=(
                    (
                        (preferred_closed_side, fallback_closed_side)
                        if active_formula.short_arc.closed_path_allow_interior_fallback
                        else (preferred_closed_side,)
                    )
                    if closed
                    else ("left", "right")
                ),
                preferred_side=preferred_closed_side,
                # A Tianzheng chained dimension reads as one continuous band.
                # Cluster rank records source order only; it must not force
                # each short arc into a successively more remote band.  The
                # vector hard gate first slides text along the shared band and
                # permits the native shared endpoint seam.  Only a real
                # text/text or text/arrow collision may escalate one failed
                # item to the next exterior band.
                preferred_band=(
                    active_formula.endpoint_cluster.preferred_band_rank
                    if active_formula.endpoint_cluster.same_band_first
                    else rank
                ),
                cluster_id=cluster_id,
                cluster_rank=rank,
                capacity_ratio=ratios[arc.key],
            )
    return result


def _layout_weights(formula: VectorLayoutFormula) -> LayoutWeights:
    """Map the versioned JSON coefficients into the solver's immutable type."""

    return LayoutWeights(
        **{
            name: float(getattr(formula.soft_weights, name))
            for name in LayoutWeights.__dataclass_fields__
        }
    )


def _angle_candidates(
    arc: ArcRecord,
    native: NativeAngle,
    path_segment_count: int,
    path_closed: bool,
    path_preferred_side: str,
    boundaries: Sequence[tuple[str, int, Segment]],
    text_height: float = 2.2,
    offset_factors: Sequence[float] = DEFAULT_ANGLE_OFFSET_FACTORS,
    layout_policy: AngleLayoutPolicy | None = None,
    vector_formula: VectorLayoutFormula | None = None,
) -> tuple[PlacementCandidate, ...]:
    candidates: list[PlacementCandidate] = []
    if text_height <= 0:
        raise ValueError("native text height must be positive")
    formula = vector_formula or load_vector_layout_formula(DEFAULT_VECTOR_FORMULA_PATH)
    policy = layout_policy or AngleLayoutPolicy(
        capacity_ratio=_arc_capacity_ratio(arc, text_height, formula)
    )
    label_width = _angle_label_width(arc, text_height, formula)
    weights = _layout_weights(formula)
    text_line_distance = formula.geometry.text_to_dimension_target_h * text_height
    arrow_size = formula.geometry.arrow_size_h * text_height
    fractions = (
        formula.short_arc.pick_fractions
        if policy.mode == "short_corner"
        else formula.geometry.pick_fractions
    )
    effective_offset_factors = tuple(offset_factors)
    if policy.mode == "short_corner":
        # The manual reference treats a sharp inside tip as an independent
        # local annotation cluster.  Give that cluster close, H-normalised
        # bands before the ordinary reference bands; hard vector gates still
        # decide whether a close band is actually usable.
        effective_offset_factors = tuple(
            dict.fromkeys(
                formula.short_arc.inner_band_factors_h + tuple(offset_factors)
            )
        )
    allowed_sides = policy.allowed_sides
    if (
        path_closed
        and path_preferred_side
        and formula.short_arc.closed_path_preferred_side == "exterior"
        and not formula.short_arc.closed_path_allow_interior_fallback
    ):
        # Pass 1 is the deterministic reference-template pass.  A closed blue
        # source must keep one exterior dimension band around the complete
        # loop; letting ordinary arcs silently fall back to the interior made
        # one sharp segment receive the opposite signed offset and Tianzheng
        # could not create that native dimension.  Interior placement remains
        # a bounded pass-2 correction only after the exterior candidate has
        # failed the native/vector audit.
        allowed_sides = (path_preferred_side,)
    for side in allowed_sides:
        for fraction in fractions:
            point, tangent = _arc_point_and_tangent(arc, fraction)
            normal = _side_normal(tangent, side)
            text_axis = _upright_axis(tangent)
            clearance = robust_clearance(
                arc,
                fraction,
                side,
                boundaries,
                formula.geometry.clearance_footprint_samples,
            )
            # The approved manual template keeps one close dimension band: the
            # source-to-dimension gap is about one native text height.  Wider
            # bands remain fallbacks, not the default starting point.
            last_effective_offset: float | None = None
            for band, offset_factor in enumerate(effective_offset_factors):
                offset = offset_factor * text_height
                outward = (
                    (arc.sweep_degrees > 0 and side == "right")
                    or (arc.sweep_degrees < 0 and side == "left")
                )
                # A very short inside corner may have R < K*H.  The normal
                # reference band then crosses the circle centre and Tianzheng
                # produces the piled-up corner labels seen in the failed
                # screenshots.  Only the formula-classified short-inner case
                # is capped; normal arcs retain the measured reference bands.
                # The remaining dimension radius is the formula's explicit
                # inner-radius floor, so this is scale-independent and does
                # not introduce a handle/source-specific magic distance.
                if policy.mode == "short_corner" and not outward:
                    maximum_inner_offset = (
                        arc.radius
                        - formula.short_arc.inner_radius_floor_h * text_height
                    )
                    if maximum_inner_offset <= 0.0:
                        continue
                    offset = min(offset, maximum_inner_offset)
                    # Several wider reference bands can collapse to the same
                    # capped short-arc band.  Keep one deterministic candidate
                    # per fraction/text state instead of duplicating it with
                    # artificial band penalties.
                    if (
                        last_effective_offset is not None
                        and math.isclose(offset, last_effective_offset, abs_tol=1.0e-9)
                    ):
                        continue
                    last_effective_offset = offset
                target_dimension_radius = arc.radius + (offset if outward else -offset)
                if (
                    target_dimension_radius
                    < formula.short_arc.inner_radius_floor_h * text_height - 1.0e-9
                ):
                    continue
                dimension_center = _add(point, normal, offset)
                dimension_points = _sample_offset_dimension_arc(
                    arc,
                    side,
                    offset,
                    formula.geometry.dimension_arc_max_step_degrees,
                )
                start = dimension_points[0]
                end = dimension_points[-1]
                tangential_available_length: float | None = None
                tangential_required_length: float | None = None
                tangential_capacity_ratio: float | None = None
                if policy.mode == "short_corner":
                    tangential_available_length = (
                        target_dimension_radius
                        * math.radians(abs(arc.sweep_degrees))
                    )
                    # Manual references allow text to extend a little beyond
                    # a short dimension arc and to overlap its thin stroke.
                    # Requiring the full label plus two arrows inside the arc
                    # rejected every usable sharp-corner candidate.  The
                    # quantitative capacity gate therefore measures only the
                    # fraction of the label supported by the dimension arc;
                    # the exact text-vs-arrow polygons are checked separately
                    # by the intrinsic vector hard gate.
                    tangential_base_requirement = label_width
                    tangential_required_length = (
                        formula.short_arc.candidate_tangential_capacity_min
                        * tangential_base_requirement
                    )
                    tangential_capacity_ratio = (
                        tangential_available_length / tangential_base_requirement
                    )
                policy_cost = 0.0
                if policy.preferred_band is not None:
                    policy_cost = abs(band - policy.preferred_band) * weights.band_step
                text_bands = (
                    formula.short_arc.inner_text_band_factors_h
                    if policy.mode == "short_corner"
                    else (0.0,)
                )
                for text_state in formula.geometry.text_states:
                    text_sign = 1.0 if text_state == "BASELINE" else -1.0
                    for text_band, text_band_factor in enumerate(text_bands):
                        # Short-corner text follows a strict human fallback:
                        # first slide along the close dimension arc, then use
                        # the next radial text band only when the vector hard
                        # gap cannot be met.  Cluster rank therefore remains a
                        # soft cost; forcing rank as a minimum band made later
                        # labels jump inward before along-arc space was tried.
                        text_distance = (
                            text_line_distance + text_band_factor * text_height
                        )
                        center = _add(
                            dimension_center,
                            normal,
                            text_sign * text_distance,
                        )
                        body = _rotated_box(
                            center, text_axis, label_width, text_height, "angle_text"
                        )
                        vector_text = oriented_box(
                            VectorPoint(center.x, center.y),
                            VectorPoint(text_axis.x, text_axis.y),
                            label_width,
                            text_height,
                            "angle_text",
                        )
                        source_clearance = signed_near_edge_clearance(
                            VectorPoint(point.x, point.y),
                            vector_text,
                            VectorPoint(normal.x, normal.y),
                        )
                        required = max(
                            offset + arrow_size,
                            offset + text_sign * text_distance + 0.5 * text_height,
                        )
                        text_band_token = (
                            f":tb{text_band}"
                            if policy.mode == "short_corner"
                            else ""
                        )
                        text_band_cost = (
                            text_band * weights.band_step
                                if policy.mode == "short_corner"
                            else 0.0
                        )
                        candidates.append(
                        PlacementCandidate(
                            annotation_id=f"angle:{arc.key}",
                            candidate_id=(
                                f"{side}:f{fraction:.2f}:o{offset:.1f}"
                                f"{text_band_token}:t{text_state}"
                            ),
                            side=side,
                            offset=offset,
                            bodies=(
                                body,
                                _small_box(start, 0.5 * arrow_size, "arrow"),
                                _small_box(end, 0.5 * arrow_size, "arrow"),
                            ),
                            strokes=(Segment(start, end, "dimension"),),
                            annotation_kind="angle",
                            path_id=arc.source,
                            sequence_index=arc.segment,
                            band=band,
                            along_shift=(fraction - 0.5) * max(arc.radius, 1.0),
                            available_width=clearance,
                            required_width=required,
                            source_segment_key=arc.key,
                            path_closed=path_closed,
                            path_segment_count=path_segment_count,
                            path_preferred_side=(
                                policy.preferred_side or path_preferred_side
                            ),
                            preference_cost=(
                                abs(fraction - 0.5) * weights.profile_deviation
                                + policy_cost
                                + text_band_cost
                            ),
                            layout_policy=policy.mode,
                            short_cluster_id=policy.cluster_id,
                            short_band_rank=policy.cluster_rank,
                            capacity_ratio=policy.capacity_ratio,
                            tangential_available_length=tangential_available_length,
                            tangential_required_length=tangential_required_length,
                            tangential_capacity_ratio=tangential_capacity_ratio,
                            vector_bodies=(
                                vector_text,
                                conservative_arrow(
                                    VectorPoint(start.x, start.y),
                                    VectorPoint(tangent.x, tangent.y),
                                    arrow_size,
                                ),
                                conservative_arrow(
                                    VectorPoint(end.x, end.y),
                                    VectorPoint(-tangent.x, -tangent.y),
                                    arrow_size,
                                ),
                            ),
                            vector_strokes=(
                                Polyline(
                                    tuple(
                                        VectorPoint(item.x, item.y)
                                        for item in dimension_points
                                    ),
                                    "dimension",
                                ),
                            ),
                            dimension_anchor=VectorPoint(
                                dimension_center.x, dimension_center.y
                            ),
                            source_clearance=source_clearance,
                            minimum_source_clearance=(
                                arc.source_half_width
                                + formula.geometry.text_to_source_hard_h * text_height
                            ),
                            preferred_source_clearance=(
                                arc.source_half_width
                                + formula.geometry.source_visible_edge_to_text_preferred_h
                                * text_height
                            ),
                            minimum_available_width=clearance,
                            text_height=text_height,
                            text_axis=VectorPoint(text_axis.x, text_axis.y),
                            text_state=text_state,
                            minimum_body_gap=(
                                (
                                    formula.short_arc.text_text_hard_gap_h
                                    if policy.mode == "short_corner"
                                    else formula.geometry.text_text_hard_gap_h
                                )
                                * text_height
                            ),
                            preferred_body_gap=(
                                (
                                    formula.short_arc.text_text_preferred_gap_h
                                    if policy.mode == "short_corner"
                                    else formula.geometry.text_text_preferred_gap_h
                                )
                                * text_height
                            ),
                            sequence_seam_target=(
                                formula.geometry.sequence_seam_target_h * text_height
                            ),
                            sequence_seam_hard=(
                                formula.geometry.sequence_seam_hard_h * text_height
                            ),
                            minimum_dimension_gap=(
                                (
                                    formula.short_arc.dimension_dimension_hard_gap_h
                                    if policy.mode == "short_corner"
                                    else formula.geometry.dimension_dimension_hard_gap_h
                                )
                                * text_height
                            ),
                            preferred_dimension_gap=(
                                (
                                    formula.short_arc.dimension_dimension_preferred_gap_h
                                    if policy.mode == "short_corner"
                                    else formula.geometry.dimension_dimension_preferred_gap_h
                                )
                                * text_height
                            ),
                            shared_endpoint_exclusion=(
                                formula.geometry.dimension_shared_endpoint_exclusion_h
                                * text_height
                            ),
                            profile_target_offset=offset_factors[0] * text_height,
                            weights=weights,
                            formula_id=formula.formula_id,
                            thin_stroke_kinds=formula.geometry.thin_stroke_kinds,
                        )
                        )
    if not candidates:
        raise ValueError(f"no angle candidates: {native.key}")
    return tuple(candidates)


def _radius_candidates(
    arc: ArcRecord,
    boundaries: Sequence[tuple[str, int, Segment]],
    text_height: float = 2.2,
    offset_factors: Sequence[float] = DEFAULT_RADIUS_OFFSET_FACTORS,
    vector_formula: VectorLayoutFormula | None = None,
    dense_marker_slide: bool = True,
    allowed_sides: Sequence[str] = ("left", "right"),
) -> tuple[PlacementCandidate, ...]:
    """Build native radius candidates around the source marker.

    ``offset_factors`` is retained only for backward-compatible profile
    reporting.  Actual marker-to-text distance is owned by the versioned
    vector formula, calibrated from the user-accepted native reference.  The
    marker slides along the source arc first; the text then stays collinear
    with the radial leader in the measured exterior band.
    """
    candidates: list[PlacementCandidate] = []
    if text_height <= 0:
        raise ValueError("native text height must be positive")
    radius_text = f"R{arc.radius:.2f}"
    formula = vector_formula or load_vector_layout_formula(DEFAULT_VECTOR_FORMULA_PATH)
    label_width = max(
        formula.geometry.radius_text_min_width_h * text_height,
        len(radius_text)
        * formula.geometry.text_width_per_visible_character_h
        * text_height,
    )
    weights = _layout_weights(formula)
    arrow_size = formula.geometry.arrow_size_h * text_height
    arc_length = abs(math.radians(arc.sweep_degrees)) * arc.radius
    marker_fractions = (
        _radius_slide_fractions(arc, text_height, formula)
        if dense_marker_slide
        else formula.geometry.radius_pick_fractions
    )
    local_text_offset_factors = formula.geometry.radius_marker_to_text_offsets_h
    if not allowed_sides or any(side not in {"left", "right"} for side in allowed_sides):
        raise ValueError(f"invalid radius sides: {allowed_sides}")
    for side in allowed_sides:
        for fraction in marker_fractions:
            anchor, tangent = _arc_point_and_tangent(arc, fraction)
            normal = _side_normal(tangent, side)
            clearance = robust_clearance(
                arc,
                fraction,
                side,
                boundaries,
                formula.geometry.clearance_footprint_samples,
            )
            for band, offset_factor in enumerate(local_text_offset_factors):
                offset = offset_factor * text_height
                center = _add(anchor, normal, offset)
                leader_axis = _unit(Point(center.x - anchor.x, center.y - anchor.y))
                # Tianzheng radius text is laid out on the radius leader, not
                # perpendicular to it.  Keep the same radial baseline while
                # only flipping its direction to preserve readable text.
                text_axis = _upright_axis(leader_axis)
                body = _rotated_box(
                    center, text_axis, label_width, text_height, "radius_text"
                )
                vector_text = oriented_box(
                    VectorPoint(center.x, center.y),
                    VectorPoint(text_axis.x, text_axis.y),
                    label_width,
                    text_height,
                    "radius_text",
                )
                source_clearance = signed_near_edge_clearance(
                    VectorPoint(anchor.x, anchor.y),
                    vector_text,
                    VectorPoint(normal.x, normal.y),
                )
                leader_direction = Point(-leader_axis.x, -leader_axis.y)
                leader_stop = _add(
                    center,
                    leader_direction,
                    (0.5 + formula.geometry.radius_leader_text_gap_h) * text_height,
                )
                required = offset + max(0.82 * text_height, arrow_size)
                candidates.append(
                    PlacementCandidate(
                        annotation_id=f"radius:{arc.key}",
                        candidate_id=f"{side}:f{fraction:.4f}:o{offset:.1f}",
                        side=side,
                        offset=offset,
                        bodies=(body, _small_box(anchor, 0.25 * text_height, "arrow")),
                        strokes=(Segment(anchor, leader_stop, "leader"),),
                        annotation_kind="radius",
                        path_id=arc.source,
                        sequence_index=arc.segment,
                        band=band,
                        along_shift=(fraction - 0.5) * arc_length,
                        available_width=clearance,
                        required_width=required,
                        source_segment_key=arc.key,
                        preference_cost=(
                            abs(fraction - 0.5) * weights.profile_deviation
                            + band * weights.band_step
                        ),
                        vector_bodies=(
                            vector_text,
                            conservative_arrow(
                                VectorPoint(anchor.x, anchor.y),
                                VectorPoint(leader_direction.x, leader_direction.y),
                                arrow_size,
                            ),
                        ),
                        vector_strokes=(
                            Polyline(
                                (
                                    VectorPoint(anchor.x, anchor.y),
                                    VectorPoint(leader_stop.x, leader_stop.y),
                                ),
                                "leader",
                            ),
                        ),
                        # For TDbRadiusDim this is native grip-2, the point that
                        # slides on the source arc.  The text centre is body[0].
                        dimension_anchor=VectorPoint(anchor.x, anchor.y),
                        source_pick_fraction=fraction,
                        leader_axis=VectorPoint(leader_axis.x, leader_axis.y),
                        text_axis=VectorPoint(text_axis.x, text_axis.y),
                        native_adjustment_stage=(
                            "GRIP2_ARC_SLIDE_COUPLED_ROTATION_THEN_OPTIONAL_GRIP3"
                        ),
                        native_control_grip_index=2,
                        native_coupled_grip_indices=(1, 3),
                        native_text_fine_grip_index=3,
                        source_clearance=source_clearance,
                        minimum_source_clearance=(
                            arc.source_half_width
                            + formula.geometry.text_to_source_hard_h * text_height
                        ),
                        preferred_source_clearance=(
                            arc.source_half_width
                            + formula.geometry.source_visible_edge_to_text_preferred_h
                            * text_height
                        ),
                        minimum_available_width=clearance,
                        text_height=text_height,
                        minimum_body_gap=(
                            formula.geometry.text_text_hard_gap_h * text_height
                        ),
                        preferred_body_gap=(
                            formula.geometry.text_text_preferred_gap_h * text_height
                        ),
                        weights=weights,
                        formula_id=formula.formula_id,
                        thin_stroke_kinds=formula.geometry.thin_stroke_kinds,
                    )
                )
    return tuple(candidates)


def _is_closed(arcs: Sequence[ArcRecord], tolerance: float = 0.10) -> bool:
    if not arcs:
        return False
    return _distance(arcs[0].start, arcs[-1].end) <= tolerance


def _signed_path_area(arcs: Sequence[ArcRecord]) -> float:
    """Return sampled signed area for a continuous closed arc path."""

    points: list[Point] = []
    for arc in arcs:
        sampled = list(_sample_arc(arc, step_degrees=6.0))
        if points and sampled and _distance(points[-1], sampled[0]) <= 1.0e-6:
            sampled = sampled[1:]
        points.extend(sampled)
    if len(points) < 3:
        return 0.0
    return 0.5 * sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    )


def _radius_allowed_sides(
    arcs: Sequence[ArcRecord],
    boundaries: Sequence[tuple[str, int, Segment]],
) -> tuple[str, ...]:
    """Return the drafting side used by native radius annotations.

    For a closed blue shoreline the user's accepted reference keeps every
    radius label outside the water/shore loop.  Winding gives that side
    deterministically: counter-clockwise paths have exterior on the right,
    clockwise paths on the left.  Open paths have no topological exterior, so
    they use the already measured wider continuous corridor.
    """

    if _is_closed(arcs):
        return ("right" if _signed_path_area(arcs) > 0.0 else "left",)
    return (_path_preferred_side(arcs, boundaries),)


def _path_preferred_side(
    arcs: Sequence[ArcRecord],
    boundaries: Sequence[tuple[str, int, Segment]],
) -> str:
    """Choose one human-readable dominant side for a complete path.

    Both open and closed paths compare robust usable space across the complete
    chain.  The approved manual reference places several closed-path angle bands
    inside the blue source line because that is the wider continuous corridor;
    therefore topology alone must never force the exterior side.
    """

    side_scores: dict[str, tuple[float, float]] = {}
    for side in ("left", "right"):
        widths = sorted(robust_clearance(arc, 0.5, side, boundaries) for arc in arcs)
        lower_index = max(0, int(math.floor((len(widths) - 1) * 0.25)))
        side_scores[side] = (widths[lower_index], sum(widths) / len(widths))
    return max(("left", "right"), key=lambda side: (side_scores[side], side == "right"))


def _candidate_center(candidate: PlacementCandidate) -> Point:
    box = candidate.bodies[0]
    return Point((box.xmin + box.xmax) / 2, (box.ymin + box.ymax) / 2)


def _choose_partitioned_layout(
    handles: Sequence[str],
    angle_groups: Sequence[Sequence[PlacementCandidate]],
    radius_groups: Sequence[Sequence[PlacementCandidate]],
    beam_width: int = 24,
) -> LayoutResult:
    """Solve each independent source path, then stage radii around all angles.

    A single 78-annotation beam spent most of its time comparing spatially
    unrelated polylines.  The source-handle partition preserves the human
    operation order (one continuous polyline at a time), while every radius
    stage still sees all fixed angle annotations and all previously accepted
    radii.  The final global hard-collision audit remains the acceptance gate.
    """

    angles_by_path = {
        handle: [group for group in angle_groups if group[0].path_id == handle]
        for handle in handles
    }
    radii_by_path = {
        handle: [group for group in radius_groups if group[0].path_id == handle]
        for handle in handles
    }
    chosen_angles: list[PlacementCandidate] = []
    score = 0.0
    diagnostics: tuple[str, ...] = ()
    hard_violations = None
    for handle in handles:
        if not angles_by_path[handle]:
            continue
        result = choose_layout(_prune_groups(angles_by_path[handle], 10), (), beam_width)
        chosen_angles.extend(result.placements)
        score += result.score
        diagnostics += result.diagnostics
        hard_violations = (
            result.hard_violations
            if hard_violations is None
            else hard_violations.plus(result.hard_violations)
        )

    fixed: list[PlacementCandidate] = list(chosen_angles)
    for handle in handles:
        groups = radii_by_path[handle]
        if not groups:
            continue
        fixed_groups = tuple((candidate,) for candidate in fixed)
        result = choose_layout(fixed_groups + _prune_groups(groups, 14), (), beam_width)
        newly_chosen = result.placements[len(fixed) :]
        fixed.extend(newly_chosen)
        score = result.score
        diagnostics += result.diagnostics
        hard_violations = result.hard_violations
    return LayoutResult(
        tuple(fixed),
        score,
        diagnostics,
        hard_violations or HardViolationVector(),
    )


def _prune_groups(
    groups: Sequence[Sequence[PlacementCandidate]], limit: int
) -> tuple[tuple[PlacementCandidate, ...], ...]:
    """Keep deterministic, wide-space-first candidates for the coarse solve."""

    return tuple(
        tuple(
            sorted(
                group,
                key=lambda candidate: (
                    candidate_intrinsic_hard_vector(candidate),
                    candidate_intrinsic_penalty(candidate),
                    candidate.candidate_id,
                ),
            )[:limit]
        )
        for group in groups
    )


def _hard_collision_pairs(
    placements: Sequence[PlacementCandidate],
) -> tuple[tuple[str, str, str], ...]:
    conflicts: set[tuple[str, str, str]] = set()
    for left_index in range(len(placements)):
        for right_index in range(left_index + 1, len(placements)):
            first, second = placements[left_index], placements[right_index]
            hard = candidate_pair_hard_vector(first, second)
            if hard.body_overlap:
                conflicts.add((first.annotation_id, second.annotation_id, "body_overlap"))
            if hard.heavy_stroke_body:
                conflicts.add((first.annotation_id, second.annotation_id, "heavy_geometry"))
            if hard.sequence_seam:
                conflicts.add((first.annotation_id, second.annotation_id, "sequence_seam"))
            if hard.dimension_spacing:
                conflicts.add(
                    (first.annotation_id, second.annotation_id, "dimension_spacing")
                )
    return tuple(sorted(conflicts))


def _hard_count(placements: Sequence[PlacementCandidate]) -> int:
    return sum(
        candidate_intrinsic_hard_vector(candidate).total
        for candidate in placements
    ) + sum(
        _hard_pair_count(placements[left], placements[right])
        for left in range(len(placements))
        for right in range(left + 1, len(placements))
    )


def _hard_pair_count(first: PlacementCandidate, second: PlacementCandidate) -> int:
    hard = candidate_pair_hard_vector(first, second)
    return (
        hard.body_overlap
        + hard.heavy_stroke_body
        + hard.sequence_seam
        + hard.dimension_spacing
    )


def _audit_hard_vector(
    placements: Sequence[PlacementCandidate],
) -> HardViolationVector:
    """Recompute the hard vector from the final repaired placement set."""

    hard = HardViolationVector()
    for candidate in placements:
        hard = hard.plus(candidate_intrinsic_hard_vector(candidate))
    for left in range(len(placements)):
        for right in range(left + 1, len(placements)):
            hard = hard.plus(
                candidate_pair_hard_vector(placements[left], placements[right])
            )
    return hard


def _repair_hard_collisions(
    initial: Sequence[PlacementCandidate],
    candidate_groups: Sequence[Sequence[PlacementCandidate]],
    max_rounds: int = 24,
) -> tuple[tuple[PlacementCandidate, ...], int]:
    """Use full candidate sets to repair the few conflicts from coarse solve.

    A single annotation move is preferred because it changes the manual
    rhythm least.  If every single move is trapped at the same hard count,
    evaluate the two annotations that actually collide as one bounded local
    unit.  This mirrors a designer moving an angle and its radius together,
    instead of declaring a collision unavoidable after trying each alone.
    """

    by_id = {group[0].annotation_id: tuple(group) for group in candidate_groups}
    placements = list(initial)
    repair_count = 0
    for _ in range(max_rounds):
        current_count = _hard_count(placements)
        if current_count == 0:
            break
        involved = {
            annotation_id
            for first, second, _kind in _hard_collision_pairs(placements)
            for annotation_id in (first, second)
        }
        involved.update(
            candidate.annotation_id
            for candidate in placements
            if not candidate_intrinsic_hard_vector(candidate).is_clear
        )
        conflict_pairs = _hard_collision_pairs(placements)
        radius_slide_ids = {
            radius_id
            for first_id, second_id, _kind in conflict_pairs
            for radius_id, other_id in ((first_id, second_id), (second_id, first_id))
            # A native radius mark is first repaired by sliding grip-2 along
            # its own source arc.  That rule applies both when it collides
            # with an angle mark and when two adjacent radius marks collide.
            # Restricting dense slide to angle-radius pairs left neighbouring
            # radius labels pinned to the same midpoint and produced the
            # remaining 652B4:5/6 overlap in the real-vector preview.
            if radius_id.startswith("radius:")
            and (
                other_id.startswith("angle:")
                or other_id.startswith("radius:")
            )
        }
        best: tuple[
            int, int, int, float, float, int, PlacementCandidate
        ] | None = None
        for index, current in enumerate(placements):
            if current.annotation_id not in involved:
                continue
            others = placements[:index] + placements[index + 1 :]
            current_local_hard = candidate_intrinsic_hard_vector(current).total + sum(
                _hard_pair_count(current, other) for other in others
            )
            for candidate in by_id[current.annotation_id]:
                if candidate.candidate_id == current.candidate_id:
                    continue
                candidate_local_hard = candidate_intrinsic_hard_vector(candidate).total + sum(
                    _hard_pair_count(candidate, other) for other in others
                )
                hard = current_count - current_local_hard + candidate_local_hard
                if hard >= current_count:
                    continue
                local_score = candidate_intrinsic_penalty(candidate) + sum(
                    candidate_pair_penalty(candidate, other) for other in others
                )
                prefer_radius_slide = current.annotation_id in radius_slide_ids
                preserve_native_band = int(
                    not (
                        prefer_radius_slide
                        and candidate.side == current.side
                        and candidate.band == current.band
                    )
                )
                slide_distance = (
                    abs(
                        (candidate.source_pick_fraction or 0.5)
                        - (current.source_pick_fraction or 0.5)
                    )
                    if prefer_radius_slide
                    else 0.0
                )
                option = (
                    hard,
                    0 if prefer_radius_slide else 1,
                    preserve_native_band,
                    slide_distance,
                    local_score,
                    index,
                    candidate,
                )
                if best is None or option[:5] < best[:5]:
                    best = option
        if best is not None:
            placements[best[5]] = best[6]
            repair_count += 1
            continue

        # Local minima can require two coordinated changes: A1 still hits B0
        # and A0 still hits B1, while A1+B1 is clear.  Search only current
        # conflicting pairs.  Do not truncate to a fixed "best N": that old
        # shortcut could keep only the preferred side and silently remove the
        # one opposite-side/band combination which resolves a real corner.
        # The search is still bounded by exactly the two candidate groups that
        # currently collide (at present <= 100 x 56), so this is deterministic
        # without introducing an arbitrary aesthetic blind spot.
        index_by_id = {
            candidate.annotation_id: index
            for index, candidate in enumerate(placements)
        }
        pair_best: tuple[
            int, float, int, int, PlacementCandidate, PlacementCandidate
        ] | None = None
        conflict_ids = sorted(
            {
                tuple(sorted((first, second)))
                for first, second, _kind in _hard_collision_pairs(placements)
            }
        )
        for first_id, second_id in conflict_ids:
            first_index = index_by_id[first_id]
            second_index = index_by_id[second_id]
            current_first = placements[first_index]
            current_second = placements[second_index]
            others = [
                candidate
                for index, candidate in enumerate(placements)
                if index not in {first_index, second_index}
            ]
            current_local_hard = (
                candidate_intrinsic_hard_vector(current_first).total
                + candidate_intrinsic_hard_vector(current_second).total
                + _hard_pair_count(current_first, current_second)
                + sum(_hard_pair_count(current_first, item) for item in others)
                + sum(_hard_pair_count(current_second, item) for item in others)
            )

            def bounded(annotation_id: str) -> tuple[PlacementCandidate, ...]:
                return tuple(
                    candidate
                    for candidate in sorted(
                        by_id[annotation_id],
                        key=lambda item: (
                            candidate_intrinsic_hard_vector(item),
                            candidate_intrinsic_penalty(item),
                            item.candidate_id,
                        ),
                    )
                    if candidate_intrinsic_hard_vector(candidate).is_clear
                )

            for first_candidate in bounded(first_id):
                for second_candidate in bounded(second_id):
                    candidate_local_hard = (
                        candidate_intrinsic_hard_vector(first_candidate).total
                        + candidate_intrinsic_hard_vector(second_candidate).total
                        + _hard_pair_count(first_candidate, second_candidate)
                        + sum(
                            _hard_pair_count(first_candidate, item)
                            for item in others
                        )
                        + sum(
                            _hard_pair_count(second_candidate, item)
                            for item in others
                        )
                    )
                    hard = current_count - current_local_hard + candidate_local_hard
                    if hard >= current_count:
                        continue
                    local_score = (
                        candidate_intrinsic_penalty(first_candidate)
                        + candidate_intrinsic_penalty(second_candidate)
                        + candidate_pair_penalty(first_candidate, second_candidate)
                        + sum(
                            candidate_pair_penalty(first_candidate, item)
                            + candidate_pair_penalty(second_candidate, item)
                            for item in others
                        )
                    )
                    option = (
                        hard,
                        local_score,
                        first_index,
                        second_index,
                        first_candidate,
                        second_candidate,
                    )
                    if pair_best is None or option[:2] < pair_best[:2]:
                        pair_best = option
        if pair_best is None:
            cluster = _repair_local_conflict_cluster(
                placements,
                by_id,
                beam_width=2048,
            )
            if cluster is None:
                break
            placements, changed = cluster
            repair_count += changed
            continue
        placements[pair_best[2]] = pair_best[4]
        placements[pair_best[3]] = pair_best[5]
        repair_count += 2
    return tuple(placements), repair_count


def _repair_local_conflict_cluster(
    placements: Sequence[PlacementCandidate],
    by_id: dict[str, tuple[PlacementCandidate, ...]],
    beam_width: int = 2048,
) -> tuple[list[PlacementCandidate], int] | None:
    """Reflow one collision plus its immediately adjacent angle labels.

    A tight corner often has no two-object solution: the angle can only move
    inward after the preceding/following angle labels are shifted as well.
    This is the vector equivalent of a designer "顺延一组".  Only the current
    conflict and direct same-path angle neighbours are mutable; every other
    accepted annotation remains a hard obstacle.
    """

    conflicts = _hard_collision_pairs(placements)
    if not conflicts:
        return None
    seed_ids = set(conflicts[0][:2])
    current_by_id = {candidate.annotation_id: candidate for candidate in placements}
    direct_angle_seeds = [
        current_by_id[item]
        for item in seed_ids
        if current_by_id[item].annotation_kind == "angle"
    ]
    angle_seeds = list(direct_angle_seeds)
    cluster_ids = set(seed_ids)
    # A radius-radius collision may have no clear single slide because each
    # radius label immediately lands on the angle label of the same segment.
    # Bring those paired angle labels into the local reflow before adding their
    # direct neighbours.  This keeps the repair bounded to the actual corner
    # and mirrors the manual operation: slide radius grip-2, then make room by
    # nudging only the angle labels attached to the same local arcs.
    radius_seeds = [
        current_by_id[item]
        for item in seed_ids
        if current_by_id[item].annotation_kind == "radius"
    ]
    for radius_seed in radius_seeds:
        for candidate in placements:
            if (
                candidate.annotation_kind == "angle"
                and candidate.path_id == radius_seed.path_id
                and candidate.sequence_index == radius_seed.sequence_index
            ):
                cluster_ids.add(candidate.annotation_id)
                angle_seeds.append(candidate)
    # Only a directly colliding angle brings its adjacent angle labels into
    # the cluster.  Angles admitted solely to clear a radius-radius collision
    # stay limited to their own segments; expanding their neighbours made the
    # four-object repair both slower and less solvable.
    for seed in direct_angle_seeds:
        for candidate in placements:
            if (
                candidate.annotation_kind == "angle"
                and candidate.path_id == seed.path_id
                and candidate.sequence_index is not None
                and seed.sequence_index is not None
                and abs(candidate.sequence_index - seed.sequence_index) <= 1
            ):
                cluster_ids.add(candidate.annotation_id)

    cluster_indices = [
        index
        for index, candidate in enumerate(placements)
        if candidate.annotation_id in cluster_ids
    ]
    if len(cluster_indices) <= 2:
        return None
    outside = [
        candidate
        for index, candidate in enumerate(placements)
        if index not in set(cluster_indices)
    ]

    # Process the most constrained group first.  A candidate which collides
    # with frozen outside annotations can never become valid later, so it is
    # safely removed without an arbitrary "top N" aesthetic cutoff.
    viable_groups: list[tuple[str, tuple[PlacementCandidate, ...]]] = []
    for annotation_id in cluster_ids:
        viable = tuple(
            candidate
            for candidate in by_id[annotation_id]
            if candidate_intrinsic_hard_vector(candidate).is_clear
            and all(_hard_pair_count(candidate, item) == 0 for item in outside)
        )
        if not viable:
            return None
        viable_groups.append((annotation_id, viable))
    viable_groups.sort(key=lambda item: (len(item[1]), item[0]))

    states: list[tuple[float, tuple[PlacementCandidate, ...]]] = [(0.0, ())]
    for _annotation_id, candidates in viable_groups:
        expanded: list[tuple[float, tuple[PlacementCandidate, ...]]] = []
        for score, chosen in states:
            for candidate in candidates:
                if any(_hard_pair_count(candidate, item) for item in chosen):
                    continue
                soft = (
                    candidate_intrinsic_penalty(candidate)
                    + sum(candidate_pair_penalty(candidate, item) for item in chosen)
                    + sum(candidate_pair_penalty(candidate, item) for item in outside)
                )
                expanded.append((score + soft, chosen + (candidate,)))
        if not expanded:
            return None
        expanded.sort(
            key=lambda item: (
                item[0],
                tuple(candidate.candidate_id for candidate in item[1]),
            )
        )
        states = expanded[: max(1, beam_width)]

    best = states[0][1]
    replacement_by_id = {candidate.annotation_id: candidate for candidate in best}
    result = [replacement_by_id.get(item.annotation_id, item) for item in placements]
    if _hard_count(result) >= _hard_count(placements):
        return None
    changed = sum(
        result[index].candidate_id != placements[index].candidate_id
        for index in cluster_indices
    )
    return result, changed


def _write_tsv(path: Path, rows: Sequence[dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise ValueError(f"refuse empty TSV: {path}")
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def _load_seed_candidate_ids(paths: Sequence[Path]) -> dict[str, str]:
    """Load accepted offline candidate identities without trusting geometry.

    Candidate geometry is always regenerated from the current formula.  Seed
    files only select a stable candidate id from that freshly generated set,
    so a stale plan cannot smuggle legacy vector bodies into a new solve.
    """

    result: dict[str, str] = {}
    for path in paths:
        for row in _read_tsv(path):
            kind = row["KIND"].strip().lower()
            annotation_id = f'{kind}:{row["SOURCE_SEGMENT"].strip().upper()}'
            candidate_id = row["CANDIDATE_ID"].strip()
            if annotation_id in result and result[annotation_id] != candidate_id:
                raise ValueError(f"conflicting seed candidate: {annotation_id}")
            result[annotation_id] = candidate_id
    return result


def _render_preview(
    path: Path,
    arcs: Sequence[ArcRecord],
    placements: Sequence[PlacementCandidate],
) -> None:
    from PIL import Image, ImageDraw, ImageFont

    all_points = [point for arc in arcs for point in _sample_arc(arc)]
    for placement in placements:
        all_points.append(_candidate_center(placement))
        for body in placement.vector_bodies:
            all_points.extend(Point(point.x, point.y) for point in body.points)
        if placement.vector_strokes:
            all_points.extend(
                Point(point.x, point.y)
                for stroke in placement.vector_strokes
                for point in stroke.points
            )
        else:
            for stroke in placement.strokes:
                all_points.extend((stroke.start, stroke.end))
    xmin = min(point.x for point in all_points)
    xmax = max(point.x for point in all_points)
    ymin = min(point.y for point in all_points)
    ymax = max(point.y for point in all_points)
    margin = 28
    width, height = 1800, 900
    scale = min((width - 2 * margin) / max(xmax - xmin, 1), (height - 2 * margin) / max(ymax - ymin, 1))

    def pixel(point: Point) -> tuple[int, int]:
        return (
            int(margin + (point.x - xmin) * scale),
            int(height - margin - (point.y - ymin) * scale),
        )

    image = Image.new("RGB", (width, height), "black")
    draw = ImageDraw.Draw(image)
    arc_by_key = {arc.key: arc for arc in arcs}

    def preview_label(placement: PlacementCandidate) -> str:
        _kind, key = placement.annotation_id.split(":", 1)
        arc = arc_by_key[key]
        if placement.annotation_kind == "angle":
            return f"{abs(arc.sweep_degrees):.2f}\N{DEGREE SIGN}"
        return f"R{arc.radius:.2f}"

    def preview_text_angle(placement: PlacementCandidate) -> float:
        if not placement.vector_bodies:
            return 0.0
        polygon = placement.vector_bodies[0]
        first, second = polygon.points[0], polygon.points[1]
        return math.degrees(math.atan2(second.y - first.y, second.x - first.x))

    def draw_rotated_label(
        center: Point,
        label: str,
        angle: float,
        font_size: int,
    ) -> None:
        font_path = Path("C:/Windows/Fonts/simhei.ttf")
        font = (
            ImageFont.truetype(str(font_path), font_size)
            if font_path.exists()
            else ImageFont.load_default()
        )
        scratch = Image.new("RGBA", (max(360, font_size * 12), font_size * 4), (0, 0, 0, 0))
        scratch_draw = ImageDraw.Draw(scratch)
        bounds = scratch_draw.textbbox((0, 0), label, font=font)
        text_width = bounds[2] - bounds[0]
        text_height_px = bounds[3] - bounds[1]
        scratch_draw.text(
            ((scratch.width - text_width) / 2, (scratch.height - text_height_px) / 2 - bounds[1]),
            label,
            font=font,
            fill=(245, 245, 245, 255),
        )
        rotated = scratch.rotate(angle, expand=True, resample=Image.Resampling.BICUBIC)
        px, py = pixel(center)
        image.paste(rotated, (px - rotated.width // 2, py - rotated.height // 2), rotated)
    for arc in arcs:
        draw.line([pixel(point) for point in _sample_arc(arc)], fill=(20, 70, 255), width=5)
    for placement in placements:
        color = (0, 230, 90) if placement.annotation_kind == "angle" else (100, 210, 255)
        if placement.vector_strokes:
            for stroke in placement.vector_strokes:
                draw.line(
                    [pixel(Point(point.x, point.y)) for point in stroke.points],
                    fill=color,
                    width=2,
                )
        else:
            for stroke in placement.strokes:
                draw.line((pixel(stroke.start), pixel(stroke.end)), fill=color, width=2)
        center = _candidate_center(placement)
        font_size = max(22, min(72, int(round(placement.text_height * scale))))
        draw_rotated_label(
            center,
            preview_label(placement),
            preview_text_angle(placement),
            font_size,
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def plan(
    geometry_path: Path,
    native_path: Path,
    output_dir: Path,
    handles: Sequence[str] = TARGET_HANDLES,
    text_height: float = 2.2,
    angle_offset_factors: Sequence[float] = DEFAULT_ANGLE_OFFSET_FACTORS,
    radius_offset_factors: Sequence[float] = DEFAULT_RADIUS_OFFSET_FACTORS,
    contract_id: str = "legacy-default",
    vector_formula_path: Path = DEFAULT_VECTOR_FORMULA_PATH,
    radius_source_handles: Sequence[str] | None = None,
    seed_plan_paths: Sequence[Path] = (),
    unseed_annotation_ids: Sequence[str] = (),
    polyline_inventory_path: Path | None = None,
    text_height_source: str = "layout_profile_fallback",
) -> dict[str, object]:
    if text_height <= 0:
        raise ValueError("native text height must be positive")
    if contract_id == "legacy-default":
        raise ValueError("a measured annotation layout contract is required")
    vector_formula = load_vector_layout_formula(vector_formula_path)
    radius_handle_set = (
        {value.upper() for value in radius_source_handles}
        if radius_source_handles is not None
        else {value.upper() for value in handles}
    )
    unknown_radius_handles = sorted(radius_handle_set - {value.upper() for value in handles})
    if unknown_radius_handles:
        raise ValueError(f"radius sources are outside selected handles: {unknown_radius_handles}")
    source_half_widths = load_source_half_widths(polyline_inventory_path)
    arcs = load_arcs(geometry_path, handles, source_half_widths)
    native_angles = load_native_angles(native_path, handles)
    arc_by_key = {arc.key: arc for arc in arcs}
    native_by_key = {item.key: item for item in native_angles}
    missing_native = sorted(set(arc_by_key) - set(native_by_key))
    extra_native = sorted(set(native_by_key) - set(arc_by_key))
    if missing_native or extra_native:
        raise ValueError(f"strict association mismatch missing={missing_native} extra={extra_native}")

    by_source: dict[str, list[ArcRecord]] = {handle: [] for handle in handles}
    for arc in arcs:
        by_source[arc.source].append(arc)
    boundaries = _boundary_segments(arcs)
    angle_groups = []
    radius_groups = []
    policies_by_source = {
        source: _short_arc_layout_policies(source_arcs, text_height, vector_formula)
        for source, source_arcs in by_source.items()
        if source_arcs
    }
    radius_sides_by_source = {
        source: _radius_allowed_sides(source_arcs, boundaries)
        for source, source_arcs in by_source.items()
        if source_arcs
    }
    for arc in arcs:
        source_arcs = by_source[arc.source]
        preferred_side = (
            _closed_path_exterior_side(source_arcs)
            if _is_closed(source_arcs)
            else _path_preferred_side(source_arcs, boundaries)
        )
        source_policies = policies_by_source[arc.source]
        angle_groups.append(
            _angle_candidates(
                arc,
                native_by_key[arc.key],
                len(source_arcs),
                _is_closed(source_arcs),
                preferred_side,
                boundaries,
                text_height,
                angle_offset_factors,
                source_policies[arc.key],
                vector_formula,
            )
        )
        if arc.source in radius_handle_set:
            radius_groups.append(
                _radius_candidates(
                    arc,
                    boundaries,
                    text_height,
                    radius_offset_factors,
                    vector_formula,
                    # Global solve stays deliberately coarse.  Dense grip-2
                    # sampling is introduced only for a radius annotation that
                    # actually collides with an angle annotation; otherwise the
                    # search grows without adding visual information.
                    dense_marker_slide=False,
                    allowed_sides=radius_sides_by_source[arc.source],
                )
            )

    # Strict layout is only meaningful when every selectable candidate was
    # generated by the same measured formula and exposes real vector bodies
    # and strokes.  A silent legacy AABB candidate would otherwise create a
    # mixed-geometry blind spot and could be reported as a visual PASS.
    all_candidates = tuple(
        candidate
        for group in tuple(angle_groups) + tuple(radius_groups)
        for candidate in group
    )
    incomplete_candidates = tuple(
        candidate.candidate_id
        for candidate in all_candidates
        if candidate.formula_id != vector_formula.formula_id
        or not candidate.vector_bodies
        or not candidate.vector_strokes
    )
    if incomplete_candidates:
        raise ValueError(
            "strict vector formula coverage incomplete: "
            + ",".join(incomplete_candidates[:10])
        )

    seed_candidate_ids = _load_seed_candidate_ids(seed_plan_paths)
    requested_unseeds = {
        value.strip().casefold() for value in unseed_annotation_ids if value.strip()
    }
    seed_key_by_folded = {key.casefold(): key for key in seed_candidate_ids}
    missing_unseeds = sorted(requested_unseeds - set(seed_key_by_folded))
    if missing_unseeds:
        raise ValueError(f"unseed annotations are absent from seed plans: {missing_unseeds}")
    for annotation_id in requested_unseeds:
        seed_candidate_ids.pop(seed_key_by_folded[annotation_id], None)
    candidates_by_annotation = {
        group[0].annotation_id: {candidate.candidate_id: candidate for candidate in group}
        for group in tuple(angle_groups) + tuple(radius_groups)
    }
    unknown_seed_annotations = sorted(set(seed_candidate_ids) - set(candidates_by_annotation))
    if unknown_seed_annotations:
        raise ValueError(f"seed annotations are outside current solve: {unknown_seed_annotations[:10]}")
    seeded_placements: dict[str, PlacementCandidate] = {}
    for annotation_id, candidate_id in seed_candidate_ids.items():
        candidate = candidates_by_annotation[annotation_id].get(candidate_id)
        if candidate is None:
            raise ValueError(f"seed candidate is absent from current formula: {annotation_id}/{candidate_id}")
        seeded_placements[annotation_id] = candidate

    # Finish and lock one continuous polyline before moving to the next.  The
    # previous implementation solved each path coarsely, but then fed every
    # annotation back into one global full-candidate repair.  Five unrelated
    # water loops therefore created an exponential search even though their
    # geometry was far apart.  Human Tianzheng work is path-local as well:
    # finish one polyline, then start a fresh command on the next polyline.
    repaired_paths: list[PlacementCandidate] = []
    repair_count = 0
    score = 0.0
    diagnostics: tuple[str, ...] = ()
    for handle in handles:
        local_arcs = tuple(arc for arc in arcs if arc.source == handle)
        generated_local_angle_groups = tuple(
            group for group in angle_groups if group[0].path_id == handle
        )
        generated_local_radius_groups = tuple(
            group for group in radius_groups if group[0].path_id == handle
        )
        # A seed is a frozen, previously accepted placement rather than merely
        # an initial hint.  Earlier code discarded every seed on a path as soon
        # as one neighbouring short arc was intentionally unseeded.  That
        # reopened dozens of already accepted angle/radius candidates, caused
        # combinatorial blow-ups, and allowed a local short-arc repair to move
        # unrelated mature annotations.  Convert every retained seed into a
        # singleton group; only explicitly unseeded annotation ids remain
        # mutable.
        local_angle_groups = tuple(
            (seeded_placements[group[0].annotation_id],)
            if group[0].annotation_id in seeded_placements
            else group
            for group in generated_local_angle_groups
        )
        local_radius_groups = tuple(
            (seeded_placements[group[0].annotation_id],)
            if group[0].annotation_id in seeded_placements
            else group
            for group in generated_local_radius_groups
        )
        if not local_angle_groups:
            continue
        local_groups = local_angle_groups + local_radius_groups
        if local_groups and all(group[0].annotation_id in seeded_placements for group in local_groups):
            local_result = LayoutResult(
                tuple(seeded_placements[group[0].annotation_id] for group in local_groups),
                0.0,
                (f"seeded:{handle}",),
                HardViolationVector(),
            )
        else:
            local_result = _choose_partitioned_layout(
                (handle,), local_angle_groups, local_radius_groups, beam_width=8
            )
        local_repaired, local_moves = _repair_hard_collisions(
            local_result.placements,
            local_groups,
        )
        local_conflicts = _hard_collision_pairs(local_repaired)
        dense_radius_ids = {
            radius_id
            for first_id, second_id, _kind in local_conflicts
            for radius_id, other_id in ((first_id, second_id), (second_id, first_id))
            if radius_id.startswith("radius:")
            and (
                other_id.startswith("angle:")
                or other_id.startswith("radius:")
            )
        }
        if dense_radius_ids:
            dense_local_radius_groups = tuple(
                _radius_candidates(
                    arc,
                    boundaries,
                    text_height,
                    radius_offset_factors,
                    vector_formula,
                    dense_marker_slide=True,
                    allowed_sides=radius_sides_by_source[arc.source],
                )
                if f"radius:{arc.key}" in dense_radius_ids
                else local_radius_groups[index]
                for index, arc in enumerate(local_arcs)
            )
            local_repaired, dense_moves = _repair_hard_collisions(
                local_repaired,
                local_angle_groups + dense_local_radius_groups,
            )
            local_moves += dense_moves
        repaired_paths.extend(local_repaired)
        repair_count += local_moves
        score += local_result.score
        diagnostics += local_result.diagnostics

    repaired = tuple(repaired_paths)
    cross_path_conflicts = tuple(
        conflict
        for conflict in _hard_collision_pairs(repaired)
        if next(
            item.path_id for item in repaired if item.annotation_id == conflict[0]
        )
        != next(
            item.path_id for item in repaired if item.annotation_id == conflict[1]
        )
    )
    if cross_path_conflicts:
        involved = {
            annotation_id
            for first, second, _kind in cross_path_conflicts
            for annotation_id in (first, second)
        }
        full_groups = {
            group[0].annotation_id: tuple(group)
            for group in tuple(angle_groups) + tuple(radius_groups)
        }
        # Only cross-path participants remain mutable.  Every already accepted
        # local result is a singleton obstacle, so a global repair cannot undo
        # unrelated successful paths or reintroduce the old combinatorial fanout.
        bounded_groups = tuple(
            full_groups[item.annotation_id]
            if item.annotation_id in involved
            else (item,)
            for item in repaired
        )
        repaired, cross_moves = _repair_hard_collisions(
            repaired, bounded_groups, max_rounds=8
        )
        repair_count += cross_moves
    result = LayoutResult(
        repaired,
        score,
        diagnostics,
        _audit_hard_vector(repaired),
    )
    audit = audit_annotation_collisions(result.placements)
    hard_pass = (
        result.hard_violations.is_clear
        and
        audit.body_overlaps == 0
        and audit.stroke_body_hits == 0
        and audit.heavy_stroke_crossings == 0
        and audit.dimension_spacing_failures == 0
    )
    native_by_key = {item.key: item for item in native_angles}
    rows = []
    for placement in result.placements:
        kind, key = placement.annotation_id.split(":", 1)
        center = _candidate_center(placement)
        dimension_anchor = placement.dimension_anchor
        source_arc = arc_by_key[key]
        target_dimension_radius = None
        signed_dimension_offset = None
        if kind == "angle":
            signed_dimension_offset = _tdimarc_command_offset(
                placement.side, placement.offset
            )
            target_dimension_radius = source_arc.radius + _radial_offset(
                source_arc, placement.side, placement.offset
            )
            if target_dimension_radius <= 0:
                raise ValueError(f"non-positive target dimension radius: {key}")
        rows.append(
            {
                "KIND": kind.upper(),
                "SOURCE_SEGMENT": key,
                "NATIVE_HANDLE": native_by_key[key].handle if kind == "angle" else "",
                "CANDIDATE_ID": placement.candidate_id,
                "SIDE": placement.side,
                "PATH_PREFERRED_SIDE": placement.path_preferred_side,
                "OFFSET": f"{placement.offset:.3f}",
                "ALONG_SHIFT": f"{placement.along_shift:.3f}",
                "AVAILABLE_WIDTH": f"{placement.available_width or 0:.3f}",
                "REQUIRED_WIDTH": f"{placement.required_width:.3f}",
                "SOURCE_CENTER_X": f"{source_arc.center.x:.6f}",
                "SOURCE_CENTER_Y": f"{source_arc.center.y:.6f}",
                "SOURCE_RADIUS": f"{source_arc.radius:.6f}",
                "SWEEP_DEGREES": f"{source_arc.sweep_degrees:.6f}",
                "SIGNED_DIMENSION_OFFSET": (
                    f"{signed_dimension_offset:.6f}" if signed_dimension_offset is not None else ""
                ),
                "TARGET_DIMENSION_RADIUS": (
                    f"{target_dimension_radius:.6f}" if target_dimension_radius is not None else ""
                ),
                "TARGET_X": f"{center.x:.6f}",
                "TARGET_Y": f"{center.y:.6f}",
                "DIMENSION_X": (
                    "" if dimension_anchor is None else f"{dimension_anchor.x:.6f}"
                ),
                "DIMENSION_Y": (
                    "" if dimension_anchor is None else f"{dimension_anchor.y:.6f}"
                ),
                "SOURCE_PICK_FRACTION": (
                    ""
                    if placement.source_pick_fraction is None
                    else f"{placement.source_pick_fraction:.9f}"
                ),
                "LEADER_AXIS_X": (
                    "" if placement.leader_axis is None else f"{placement.leader_axis.x:.9f}"
                ),
                "LEADER_AXIS_Y": (
                    "" if placement.leader_axis is None else f"{placement.leader_axis.y:.9f}"
                ),
                "TEXT_AXIS_X": (
                    "" if placement.text_axis is None else f"{placement.text_axis.x:.9f}"
                ),
                "TEXT_AXIS_Y": (
                    "" if placement.text_axis is None else f"{placement.text_axis.y:.9f}"
                ),
                "NATIVE_ADJUSTMENT_STAGE": placement.native_adjustment_stage,
                "NATIVE_CONTROL_GRIP_INDEX": (
                    ""
                    if placement.native_control_grip_index is None
                    else str(placement.native_control_grip_index)
                ),
                "NATIVE_COUPLED_GRIP_INDICES": ",".join(
                    str(index) for index in placement.native_coupled_grip_indices
                ),
                "NATIVE_TEXT_FINE_GRIP_INDEX": (
                    ""
                    if placement.native_text_fine_grip_index is None
                    else str(placement.native_text_fine_grip_index)
                ),
                "TEXT_STATE": placement.text_state,
                "SOURCE_CLEARANCE_H": (
                    ""
                    if placement.source_clearance is None
                    else f"{placement.source_clearance / text_height:.6f}"
                ),
                "LAYOUT_POLICY": placement.layout_policy,
                "SHORT_CLUSTER_ID": placement.short_cluster_id,
                "SHORT_BAND_RANK": (
                    "" if placement.short_band_rank is None else str(placement.short_band_rank)
                ),
                "CAPACITY_RATIO": (
                    "" if placement.capacity_ratio is None else f"{placement.capacity_ratio:.6f}"
                ),
                "FORMULA_ID": placement.formula_id,
            }
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    _write_tsv(output_dir / "strict_layout_plan.tsv", rows)
    summary = {
        "status": (
            "PASS_OFFLINE"
            if hard_pass
            else vector_formula.no_zero_hard_solution_status
        ),
        "scope": "annotation_internal_only",
        "source_handles": list(handles),
        "radius_source_handles": [
            handle for handle in handles if handle.upper() in radius_handle_set
        ],
        "seed_plan_paths": [str(path) for path in seed_plan_paths],
        "unseed_annotation_ids": sorted(requested_unseeds),
        "seeded_annotation_count": len(seeded_placements),
        "native_text_height": text_height,
        "native_text_height_source": text_height_source,
        "spacing_model": "text_height_relative",
        "layout_contract_id": contract_id,
        "vector_formula_id": vector_formula.formula_id,
        "formula_coverage": {
            "status": "COMPLETE",
            "candidate_count": len(all_candidates),
            "covered_candidate_count": len(all_candidates),
            "formula_ids": [vector_formula.formula_id],
        },
        "formula_candidate_geometry": {
            "angle_pick_fractions": list(vector_formula.geometry.pick_fractions),
            "radius_pick_fractions": list(
                vector_formula.geometry.radius_pick_fractions
            ),
            "radius_slide_sample_spacing_h": (
                vector_formula.geometry.radius_slide_sample_spacing_h
            ),
            "radius_slide_endpoint_clearance_h": (
                vector_formula.geometry.radius_slide_endpoint_clearance_h
            ),
            "radius_slide_max_samples": (
                vector_formula.geometry.radius_slide_max_samples
            ),
            "radius_leader_text_gap_h": (
                vector_formula.geometry.radius_leader_text_gap_h
            ),
            "radius_marker_to_text_offsets_h": list(
                vector_formula.geometry.radius_marker_to_text_offsets_h
            ),
            "text_states": list(vector_formula.geometry.text_states),
            "text_to_dimension_target_h": (
                vector_formula.geometry.text_to_dimension_target_h
            ),
            "text_to_source_hard_h": (
                vector_formula.geometry.text_to_source_hard_h
            ),
            "text_to_source_preferred_h": (
                vector_formula.geometry.text_to_source_preferred_h
            ),
            "source_visible_edge_to_text_preferred_h": (
                vector_formula.geometry.source_visible_edge_to_text_preferred_h
            ),
            "source_half_widths": {
                key: source_half_widths.get(key, 0.0) for key in handles
            },
            "text_text_hard_gap_h": (
                vector_formula.geometry.text_text_hard_gap_h
            ),
            "text_text_preferred_gap_h": (
                vector_formula.geometry.text_text_preferred_gap_h
            ),
            "sequence_seam_target_h": (
                vector_formula.geometry.sequence_seam_target_h
            ),
            "sequence_seam_hard_h": (
                vector_formula.geometry.sequence_seam_hard_h
            ),
            "dimension_dimension_hard_gap_h": (
                vector_formula.geometry.dimension_dimension_hard_gap_h
            ),
            "dimension_dimension_preferred_gap_h": (
                vector_formula.geometry.dimension_dimension_preferred_gap_h
            ),
            "dimension_shared_endpoint_exclusion_h": (
                vector_formula.geometry.dimension_shared_endpoint_exclusion_h
            ),
        },
        "formula_short_arc": {
            "capacity_primary_threshold": (
                vector_formula.short_arc.capacity_primary_threshold
            ),
            "capacity_support_threshold": (
                vector_formula.short_arc.capacity_support_threshold
            ),
            "inner_radius_floor_h": vector_formula.short_arc.inner_radius_floor_h,
            "pick_fractions": list(vector_formula.short_arc.pick_fractions),
            "inner_band_factors_h": list(
                vector_formula.short_arc.inner_band_factors_h
            ),
            "inner_text_band_factors_h": list(
                vector_formula.short_arc.inner_text_band_factors_h
            ),
            "text_text_hard_gap_h": vector_formula.short_arc.text_text_hard_gap_h,
            "text_text_preferred_gap_h": (
                vector_formula.short_arc.text_text_preferred_gap_h
            ),
            "dimension_dimension_hard_gap_h": (
                vector_formula.short_arc.dimension_dimension_hard_gap_h
            ),
            "dimension_dimension_preferred_gap_h": (
                vector_formula.short_arc.dimension_dimension_preferred_gap_h
            ),
        },
        "angle_offset_factors": list(angle_offset_factors),
        "radius_profile_leader_extension_factors": list(radius_offset_factors),
        "radius_profile_factor_semantics": (
            "compatibility-only profile field; actual collinear exterior text "
            "placement is formula_candidate_geometry.radius_marker_to_text_offsets_h"
        ),
        "source_arc_count": len(arcs),
        "strict_native_angle_count": len(native_angles),
        "planned_angle_count": sum(row["KIND"] == "ANGLE" for row in rows),
        "planned_radius_count": sum(row["KIND"] == "RADIUS" for row in rows),
        "body_overlaps": audit.body_overlaps,
        "stroke_body_hits": audit.stroke_body_hits,
        "heavy_stroke_crossings": audit.heavy_stroke_crossings,
        "thin_leader_crossings": audit.thin_leader_crossings,
        "leader_dimension_crossings": audit.leader_dimension_crossings,
        "dimension_spacing_failures": audit.dimension_spacing_failures,
        "repair_move_count": repair_count,
        "remaining_conflicts": [list(item) for item in _hard_collision_pairs(result.placements)],
        "score": result.score,
        "hard_violation_vector": {
            "source_or_locked": result.hard_violations.source_or_locked,
            "body_overlap": result.hard_violations.body_overlap,
            "text_source": result.hard_violations.text_source,
            "heavy_stroke_body": result.hard_violations.heavy_stroke_body,
            "insufficient_corridor": result.hard_violations.insufficient_corridor,
            "sequence_seam": result.hard_violations.sequence_seam,
            "dimension_spacing": result.hard_violations.dimension_spacing,
        },
        "real_dwg_acceptance": "PENDING_E4_E5",
    }
    (output_dir / "strict_layout_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    _render_preview(output_dir / "strict_layout_preview.png", arcs, result.placements)
    preview_dir = output_dir / "source_previews"
    for source in handles:
        source_arcs = tuple(arc for arc in arcs if arc.source == source)
        source_placements = tuple(
            placement for placement in result.placements if placement.path_id == source
        )
        if source_arcs and source_placements:
            _render_preview(
                preview_dir / f"{source}_layout_preview.png",
                source_arcs,
                source_placements,
            )
    return summary


def load_layout_contract(path: Path, profile: str) -> tuple[float, tuple[float, ...], tuple[float, ...], str]:
    """Load a measured annotation profile without changing the native kernel.

    The contract contains only scale-normalised candidate priors.  Tianzheng
    still creates and owns the native annotation objects; E4/E5 remain the
    acceptance gates after the selected candidates are applied.
    """

    payload = json.loads(path.read_text(encoding="utf-8"))
    profiles = payload.get("profiles", {})
    if profile not in profiles:
        raise ValueError(f"layout contract profile not found: {profile}")
    selected = profiles[profile]
    scale = float(selected["scale_denominator"])
    paper_height = float(selected["paper_text_height_mm"])
    text_height = scale * paper_height / 1000.0
    angle_factors = tuple(float(value) for value in selected["angle_offset_factors_h"])
    radius_factors = tuple(
        float(value)
        for value in selected.get(
            "radius_offset_factors_h", DEFAULT_RADIUS_OFFSET_FACTORS
        )
    )
    if text_height <= 0 or not angle_factors or not radius_factors:
        raise ValueError("invalid layout contract profile")
    return text_height, angle_factors, radius_factors, str(payload.get("contract_id", path.stem))


def resolve_layout_profile(
    path: Path,
    profile: str,
    text_height_override: float | None = None,
) -> tuple[float, tuple[float, ...], tuple[float, ...], str]:
    """Resolve measured layout priors, optionally using the DWG's real text height.

    The contract remains authoritative for scale-normalised offset bands.  A
    caller-supplied height is authoritative for the current native annotation
    objects; previously the CLI accepted this value and then silently replaced
    it with the profile height, which broke all H-relative clearance formulas.
    """

    text_height, angle_factors, radius_factors, contract_id = load_layout_contract(
        path, profile
    )
    if text_height_override is not None:
        text_height_override = float(text_height_override)
        if not math.isfinite(text_height_override) or text_height_override <= 0:
            raise ValueError("text height override must be a positive finite value")
        text_height = text_height_override
    return text_height, angle_factors, radius_factors, contract_id


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", type=Path, required=True)
    parser.add_argument("--native-angles", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--source-handles", default=",".join(TARGET_HANDLES))
    parser.add_argument(
        "--radius-source-handles",
        default=None,
        help=(
            "Comma-separated subset that receives radius annotations. "
            "Omit to preserve the legacy all-selected-sources behavior; "
            "pass an empty string for angle-only planning."
        ),
    )
    parser.add_argument(
        "--seed-plans",
        default="",
        help="Semicolon-separated prior strict_layout_plan.tsv files used as candidate-id seeds.",
    )
    parser.add_argument(
        "--unseed-annotations",
        default="",
        help=(
            "Comma-separated annotation ids intentionally re-solved even when "
            "present in seed plans, for example angle:652BB:2."
        ),
    )
    parser.add_argument(
        "--text-height",
        type=float,
        default=None,
        help=(
            "Actual native annotation text height. Omit to use the measured "
            "layout profile height."
        ),
    )
    parser.add_argument("--layout-contract", type=Path, required=True)
    parser.add_argument(
        "--vector-formula",
        type=Path,
        default=DEFAULT_VECTOR_FORMULA_PATH,
    )
    parser.add_argument("--layout-profile", default="water_axis_1_600")
    parser.add_argument(
        "--polyline-inventory",
        type=Path,
        default=None,
        help="TSV containing HANDLE and CONSTANT_WIDTH for visible-edge clearance.",
    )
    args = parser.parse_args()
    handles = tuple(value.strip().upper() for value in args.source_handles.split(",") if value.strip())
    radius_handles = None
    if args.radius_source_handles is not None:
        radius_handles = tuple(
            value.strip().upper()
            for value in args.radius_source_handles.split(",")
            if value.strip()
        )
    seed_plan_paths = tuple(
        Path(value.strip()) for value in args.seed_plans.split(";") if value.strip()
    )
    unseed_annotation_ids = tuple(
        value.strip().lower()
        for value in args.unseed_annotations.split(",")
        if value.strip()
    )
    text_height, angle_factors, radius_factors, contract_id = resolve_layout_profile(
        args.layout_contract, args.layout_profile, args.text_height
    )
    summary = plan(
        args.geometry,
        args.native_angles,
        args.output_dir,
        handles,
        text_height,
        angle_factors,
        radius_factors,
        contract_id,
        args.vector_formula,
        radius_handles,
        seed_plan_paths,
        unseed_annotation_ids,
        args.polyline_inventory,
        (
            "explicit_measured_override"
            if args.text_height is not None
            else "layout_profile_fallback"
        ),
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary["status"] == "PASS_OFFLINE" else 2


if __name__ == "__main__":
    raise SystemExit(main())
