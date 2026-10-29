"""Deterministic collision model for Tianzheng annotation placement.

This module is deliberately independent from AutoCAD/Tianzheng.  It evaluates
candidate placements produced from native annotation object parameters.  The
winning candidate can later be applied through TDbDimension2, TDbRadiusDim or
TDbSymbIndexPointer setters and then verified in an isolated DWG.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from math import hypot, isclose
from typing import Iterable, Sequence

from annotation_vector_geometry import (
    ConvexPolygon,
    Polyline,
    VectorPoint,
    polygons_overlap,
    polyline_intersects_polygon,
    polylines_intersect,
    minimum_polygon_distance,
    minimum_polyline_distance,
)


HARD_OVERLAP = 1_000_000_000.0
BODY_BASE_COLLISION = 10_000_000.0
STROKE_BODY_COLLISION = 1_000_000.0
DIMENSION_STROKE_COLLISION = 100_000.0
THIN_LEADER_CROSSING = 0.25
LEADER_DIMENSION_CROSSING = 250.0
INSUFFICIENT_WIDTH = HARD_OVERLAP
WIDE_SPACE_COST = 20_000.0
OFFSET_DISTANCE_COST = 1.0
# The approved Tianzheng examples read as one continuous annotation band, not
# as a collection of locally optimal labels.  These costs remain below real
# collisions, but are intentionally strong enough to keep a path on one side
# and one offset band until a local clearance/collision gate forces an escape.
ANGLE_SIDE_SWITCH = 25_000.0
ANGLE_BAND_STEP = 5_000.0
ANGLE_OFFSET_DELTA = 500.0
ANGLE_SHIFT_DELTA = 100.0
ANGLE_NON_DOMINANT_SIDE = 18_000.0
RADIUS_INSIDE_ANGLE = 250_000.0
RADIUS_ANGLE_GAP = 2_500.0


@dataclass(frozen=True)
class LayoutWeights:
    """Versionable soft-aesthetic weights; hard failures never use them."""

    profile_deviation: float = 1_200.0
    wide_space: float = WIDE_SPACE_COST
    side_switch: float = ANGLE_SIDE_SWITCH
    band_step: float = ANGLE_BAND_STEP
    offset_delta: float = ANGLE_OFFSET_DELTA
    along_shift: float = ANGLE_SHIFT_DELTA
    non_dominant_side: float = ANGLE_NON_DOMINANT_SIDE
    source_clearance_preference: float = 500_000.0
    text_line_target: float = 120.0
    radius_inside_angle: float = RADIUS_INSIDE_ANGLE
    radius_angle_gap: float = RADIUS_ANGLE_GAP
    dimension_spacing: float = 4_000.0
    # A thin dimension/extension/leader line crossing a label is undesirable,
    # but the user-approved reference allows it when a tight corner has no
    # clean alternative.  It must therefore remain below a band/side change
    # while still making a clean candidate win when one exists.
    text_thin_stroke_overlap: float = 1_500.0

    def __post_init__(self) -> None:
        if any(value < 0 for value in self.__dict__.values()):
            raise ValueError("layout weights cannot be negative")


DEFAULT_LAYOUT_WEIGHTS = LayoutWeights()


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class Box:
    xmin: float
    ymin: float
    xmax: float
    ymax: float
    kind: str = "text"

    def __post_init__(self) -> None:
        if self.xmax < self.xmin or self.ymax < self.ymin:
            raise ValueError("invalid box extents")

    def overlap_area(self, other: "Box") -> float:
        width = min(self.xmax, other.xmax) - max(self.xmin, other.xmin)
        height = min(self.ymax, other.ymax) - max(self.ymin, other.ymin)
        if width <= 0 or height <= 0:
            return 0.0
        return width * height

    def contains(self, point: Point) -> bool:
        return self.xmin <= point.x <= self.xmax and self.ymin <= point.y <= self.ymax


@dataclass(frozen=True)
class Segment:
    start: Point
    end: Point
    kind: str = "leader"


@dataclass(frozen=True)
class BaseObstacle:
    """A semantic base-drawing obstacle.

    Geometry may be a road/paving edge segment or a protected filled region.
    Priority scales penalties without making every hatch stroke a hard barrier.
    """

    geometry: Box | Segment | ConvexPolygon | Polyline
    semantic: str
    priority: float = 1.0


@dataclass(frozen=True)
class PlacementCandidate:
    annotation_id: str
    candidate_id: str
    side: str
    offset: float
    bodies: tuple[Box, ...] = ()
    strokes: tuple[Segment, ...] = ()
    preference_cost: float = 0.0
    annotation_kind: str = "generic"
    path_id: str = ""
    sequence_index: int | None = None
    band: int = 0
    along_shift: float = 0.0
    available_width: float | None = None
    required_width: float = 0.0
    source_segment_key: str = ""
    path_closed: bool = False
    path_segment_count: int | None = None
    path_preferred_side: str = ""
    layout_policy: str = "normal"
    short_cluster_id: str = ""
    short_band_rank: int | None = None
    capacity_ratio: float | None = None
    # Independent along-arc capacity gate for sharp corners.  Radial corridor
    # checks cannot detect labels and paired arrows collapsing at a pointed
    # turn, so strict candidates record both lengths explicitly.
    tangential_available_length: float | None = None
    tangential_required_length: float | None = None
    tangential_capacity_ratio: float | None = None
    vector_bodies: tuple[ConvexPolygon, ...] = ()
    vector_strokes: tuple[Polyline, ...] = ()
    # A non-empty formula id opts the candidate into the strict vector
    # contract.  Legacy unit tests and old read-only probes leave it empty and
    # continue to be normalised from Box/Segment geometry below.
    formula_id: str = ""
    thin_stroke_kinds: tuple[str, ...] = ("dimension", "leader", "extension")
    dimension_anchor: VectorPoint | None = None
    # Native TDbRadiusDim semantics.  Grip-2 is both the source-arc marker and
    # the radial direction control.  Moving it makes Tianzheng reproject the
    # auxiliary radial grip-1, recompute the default text grip-3, and keep the
    # rendered text baseline collinear with the radial leader.  Grip-3 is only
    # a later fine adjustment, so the solver must preserve this coupled state
    # explicitly instead of independently translating/rotating text.
    source_pick_fraction: float | None = None
    leader_axis: VectorPoint | None = None
    text_axis: VectorPoint | None = None
    native_adjustment_stage: str = ""
    native_control_grip_index: int | None = None
    native_coupled_grip_indices: tuple[int, ...] = ()
    native_text_fine_grip_index: int | None = None
    source_clearance: float | None = None
    minimum_source_clearance: float = 0.0
    preferred_source_clearance: float = 0.0
    minimum_available_width: float | None = None
    text_height: float = 1.0
    text_state: str = "BASELINE"
    minimum_body_gap: float = 0.0
    preferred_body_gap: float = 0.0
    sequence_seam_target: float = 0.0
    sequence_seam_hard: float = 0.0
    minimum_dimension_gap: float = 0.0
    preferred_dimension_gap: float = 0.0
    shared_endpoint_exclusion: float = 0.0
    profile_target_offset: float | None = None
    weights: LayoutWeights = DEFAULT_LAYOUT_WEIGHTS
    source_association_valid: bool = True
    locked_grips_unchanged: bool = True


@dataclass(frozen=True)
class LayoutResult:
    placements: tuple[PlacementCandidate, ...]
    score: float
    diagnostics: tuple[str, ...] = field(default_factory=tuple)
    hard_violations: "HardViolationVector" = field(
        default_factory=lambda: HardViolationVector()
    )


@dataclass(frozen=True, order=True)
class HardViolationVector:
    """Fail-closed vector; never traded against aesthetic soft costs."""

    source_or_locked: int = 0
    body_overlap: int = 0
    text_source: int = 0
    heavy_stroke_body: int = 0
    insufficient_corridor: int = 0
    sequence_seam: int = 0
    dimension_spacing: int = 0

    @property
    def total(self) -> int:
        return sum(
            (
                self.source_or_locked,
                self.body_overlap,
                self.text_source,
                self.heavy_stroke_body,
                self.insufficient_corridor,
                self.sequence_seam,
                self.dimension_spacing,
            )
        )

    @property
    def is_clear(self) -> bool:
        return self.total == 0

    def plus(self, other: "HardViolationVector") -> "HardViolationVector":
        return HardViolationVector(
            self.source_or_locked + other.source_or_locked,
            self.body_overlap + other.body_overlap,
            self.text_source + other.text_source,
            self.heavy_stroke_body + other.heavy_stroke_body,
            self.insufficient_corridor + other.insufficient_corridor,
            self.sequence_seam + other.sequence_seam,
            self.dimension_spacing + other.dimension_spacing,
        )


@dataclass(frozen=True)
class CollisionAudit:
    body_overlaps: int = 0
    stroke_body_hits: int = 0
    heavy_stroke_crossings: int = 0
    thin_leader_crossings: int = 0
    leader_dimension_crossings: int = 0
    dimension_spacing_failures: int = 0
    soft_text_stroke_hits: int = 0


def _box_polygon(box: Box) -> ConvexPolygon:
    return ConvexPolygon(
        (
            VectorPoint(box.xmin, box.ymin),
            VectorPoint(box.xmax, box.ymin),
            VectorPoint(box.xmax, box.ymax),
            VectorPoint(box.xmin, box.ymax),
        ),
        box.kind,
    )


def _segment_polyline(segment: Segment) -> Polyline:
    return Polyline(
        (
            VectorPoint(segment.start.x, segment.start.y),
            VectorPoint(segment.end.x, segment.end.y),
        ),
        segment.kind,
    )


def normalized_candidate_geometry(
    candidate: PlacementCandidate,
) -> tuple[tuple[ConvexPolygon, ...], tuple[Polyline, ...]]:
    """Return one complete vector representation for every candidate.

    Each side is normalised independently.  This is important during the
    migration window where an angle candidate already carries exact vector
    geometry while a radius candidate still carries legacy Box/Segment
    geometry.  The old all-or-nothing branch silently ignored the legacy side.
    """

    bodies = candidate.vector_bodies or tuple(_box_polygon(body) for body in candidate.bodies)
    strokes = candidate.vector_strokes or tuple(
        _segment_polyline(stroke) for stroke in candidate.strokes
    )
    return bodies, strokes


def _strict_vector_contract_valid(candidate: PlacementCandidate) -> bool:
    if not candidate.formula_id:
        return True
    return bool(candidate.vector_bodies and candidate.vector_strokes)


def _text_polygons(polygons: Sequence[ConvexPolygon]) -> tuple[ConvexPolygon, ...]:
    return tuple(polygon for polygon in polygons if "text" in polygon.kind.lower())


def _soft_text_stroke_intersection(
    first: PlacementCandidate,
    second: PlacementCandidate,
    stroke: Polyline,
    body: ConvexPolygon,
) -> bool:
    """Return true for the one user-approved collision downgrade.

    Only a strict, same-formula pair may downgrade a crossing, and only when
    the body is text and the crossing object is an explicitly configured thin
    stroke.  Arrow/filled bodies, text-text overlap, dimension-arc pile-up and
    the thick source line remain hard failures.
    """

    if (
        not first.formula_id
        or first.formula_id != second.formula_id
        or "text" not in body.kind.lower()
    ):
        return False
    allowed = set(first.thin_stroke_kinds) & set(second.thin_stroke_kinds)
    return stroke.kind.lower() in allowed


def _polygon_clearance(first: ConvexPolygon, second: ConvexPolygon) -> float:
    # minimum_polygon_distance is called in both directions so this model stays
    # exact even while older geometry helpers only considered one vertex-edge
    # direction.
    return min(
        minimum_polygon_distance(first, second),
        minimum_polygon_distance(second, first),
    )


def _mean_weight(
    first: PlacementCandidate, second: PlacementCandidate, name: str
) -> float:
    return (getattr(first.weights, name) + getattr(second.weights, name)) * 0.5


def _adjacent_path_angles(
    first: PlacementCandidate, second: PlacementCandidate
) -> bool:
    if first.annotation_kind != "angle" or second.annotation_kind != "angle":
        return False
    if not first.path_id or first.path_id != second.path_id:
        return False
    if first.sequence_index is None or second.sequence_index is None:
        return False
    delta = abs(first.sequence_index - second.sequence_index)
    if delta == 1:
        return True
    segment_count = first.path_segment_count or second.path_segment_count
    return bool(
        first.path_closed
        and second.path_closed
        and segment_count is not None
        and segment_count > 1
        and delta == segment_count - 1
    )


def _dimension_seam_distance(
    first: PlacementCandidate, second: PlacementCandidate
) -> float | None:
    if not _adjacent_path_angles(first, second):
        return None
    if bool(first.short_cluster_id) != bool(second.short_cluster_id):
        return None
    if (
        first.short_cluster_id
        and second.short_cluster_id
        and first.short_cluster_id != second.short_cluster_id
    ):
        # Only members of the same short-corner cluster may share the native
        # chained endpoint seam.  A normal/short transition or two unrelated
        # corner groups must still be checked as independent dimensions.
        return None
    # Human "首尾相继" for Tianzheng arc-angle dimensions means that normal
    # neighbouring arcs remain on the same path side and in the same offset
    # band.  The raw endpoints of two independently offset circular arcs need
    # not coincide at a change of curvature, so using their Euclidean endpoint
    # distance as the hard criterion produced a false seam failure and pushed
    # one label into a different band.  Once side and band agree, the native
    # extension marks provide the visual junction and the seam is accepted.
    _, first_strokes = normalized_candidate_geometry(first)
    _, second_strokes = normalized_candidate_geometry(second)
    first_dimension = next(
        (stroke for stroke in first_strokes if stroke.kind == "dimension"), None
    )
    second_dimension = next(
        (stroke for stroke in second_strokes if stroke.kind == "dimension"), None
    )
    if first_dimension is None or second_dimension is None:
        return None
    segment_count = first.path_segment_count or second.path_segment_count
    first_index = first.sequence_index or 0
    second_index = second.sequence_index or 0
    if (
        first.path_closed
        and second.path_closed
        and segment_count is not None
        and abs(first_index - second_index) == segment_count - 1
    ):
        earlier, later = (
            (first_dimension, second_dimension)
            if first_index > second_index
            else (second_dimension, first_dimension)
        )
    else:
        earlier, later = (
            (first_dimension, second_dimension)
            if first_index < second_index
            else (second_dimension, first_dimension)
        )
    left, right = earlier.points[-1], later.points[0]
    return hypot(left.x - right.x, left.y - right.y)


def _trim_polyline_endpoint(
    line: Polyline, *, trim_start: bool, distance: float
) -> Polyline | None:
    """Remove a physical-length neighbourhood around one construction seam."""

    if distance <= 0:
        return line
    points = list(line.points if trim_start else reversed(line.points))
    remaining = distance
    kept: list[VectorPoint] = []
    for index in range(len(points) - 1):
        start, end = points[index], points[index + 1]
        length = hypot(end.x - start.x, end.y - start.y)
        if length <= 1.0e-12:
            continue
        if remaining < length:
            ratio = remaining / length
            kept.append(
                VectorPoint(
                    start.x + (end.x - start.x) * ratio,
                    start.y + (end.y - start.y) * ratio,
                )
            )
            kept.extend(points[index + 1 :])
            break
        remaining -= length
    if len(kept) < 2:
        return None
    if not trim_start:
        kept.reverse()
    return Polyline(tuple(kept), line.kind)


def _dimension_curve_clearance(
    first: PlacementCandidate,
    second: PlacementCandidate,
    left: Polyline,
    right: Polyline,
) -> float | None:
    """Measure curve-to-curve clearance, excluding only a legal shared seam.

    The previous model exempted every intersection between adjacent dimensions.
    That hid the acute-corner pile-up seen in the user's rejected screenshots.
    Only a short H-relative neighbourhood of the true head-to-tail seam is now
    removed; the remaining sampled curves must still be separated.
    """

    if left.kind != "dimension" or right.kind != "dimension":
        return None
    if not _adjacent_path_angles(first, second):
        return minimum_polyline_distance(left, right)
    seam = _dimension_seam_distance(first, second)
    seam_limit = max(first.sequence_seam_hard, second.sequence_seam_hard, 1.0e-8)
    if seam is None or seam > seam_limit:
        return minimum_polyline_distance(left, right)
    segment_count = first.path_segment_count or second.path_segment_count
    first_index = first.sequence_index or 0
    second_index = second.sequence_index or 0
    # A closed path made from exactly two arcs is a special but valid case:
    # the same pair is adjacent at *both* source vertices.  Trimming only the
    # head-to-tail seam leaves the second legal construction joint behind and
    # falsely reports the two otherwise separated dimension arcs as crossing.
    # Remove one H-relative seam neighbourhood at both ends.  Longer paths
    # still share only one local vertex per adjacent pair and use the normal
    # directional trim below.
    if first.path_closed and second.path_closed and segment_count == 2:
        exclusion = max(
            first.shared_endpoint_exclusion,
            second.shared_endpoint_exclusion,
        )

        def trim_both(line: Polyline) -> Polyline | None:
            trimmed = _trim_polyline_endpoint(
                line, trim_start=True, distance=exclusion
            )
            if trimmed is None:
                return None
            return _trim_polyline_endpoint(
                trimmed, trim_start=False, distance=exclusion
            )

        left_trimmed = trim_both(left)
        right_trimmed = trim_both(right)
        if left_trimmed is None or right_trimmed is None:
            return float("inf")
        return minimum_polyline_distance(left_trimmed, right_trimmed)
    wraps = bool(
        first.path_closed
        and second.path_closed
        and segment_count is not None
        and abs(first_index - second_index) == segment_count - 1
    )
    if wraps:
        earlier_is_first = first_index > second_index
    else:
        earlier_is_first = first_index < second_index
    exclusion = max(
        first.shared_endpoint_exclusion,
        second.shared_endpoint_exclusion,
    )
    left_trimmed = _trim_polyline_endpoint(
        left, trim_start=not earlier_is_first, distance=exclusion
    )
    right_trimmed = _trim_polyline_endpoint(
        right, trim_start=earlier_is_first, distance=exclusion
    )
    if left_trimmed is None or right_trimmed is None:
        return float("inf")
    return minimum_polyline_distance(left_trimmed, right_trimmed)


def _allowed_adjacent_dimension_touch(
    first: PlacementCandidate,
    second: PlacementCandidate,
    left: Polyline,
    right: Polyline,
) -> bool:
    if left.kind != "dimension" or right.kind != "dimension":
        return False
    seam = _dimension_seam_distance(first, second)
    limit = max(first.sequence_seam_hard, second.sequence_seam_hard, 1.0e-8)
    clearance = _dimension_curve_clearance(first, second, left, right)
    minimum = max(first.minimum_dimension_gap, second.minimum_dimension_gap)
    return (
        seam is not None
        and seam <= limit
        and clearance is not None
        and clearance >= minimum
    )


def _allowed_adjacent_band_seam(
    first: PlacementCandidate,
    second: PlacementCandidate,
) -> bool:
    """Return true only for the intentional shared seam of one angle band.

    Consecutive Tianzheng angle dimensions duplicate an arrow/extension mark
    at their common source vertex.  Treating that local construction joint as
    an ordinary body collision forces the optimiser to throw one short arc
    into a remote band.  The exemption is deliberately narrow: same path,
    side and band, adjacent sequence items, no independent short-arc cluster,
    and an already acceptable dimension seam.  Text bodies are never exempt.
    """

    if not _adjacent_path_angles(first, second):
        return False
    if first.side != second.side or first.band != second.band:
        return False
    # Short-corner clusters are still one native chained dimension.  Their
    # shared endpoint arrows/extension marks are intentional construction
    # seams, not collisions.  Text bodies never use this exemption, so a
    # crowded corner still has to slide along the arc or escalate one failed
    # label to the next band.
    if bool(first.short_cluster_id) != bool(second.short_cluster_id):
        return False
    if (
        first.short_cluster_id
        and second.short_cluster_id
        and first.short_cluster_id != second.short_cluster_id
    ):
        return False
    seam = _dimension_seam_distance(first, second)
    limit = max(first.sequence_seam_hard, second.sequence_seam_hard, 1.0e-8)
    return seam is not None and seam <= limit


def _allowed_adjacent_arrow_touch(
    first: PlacementCandidate,
    second: PlacementCandidate,
    left: ConvexPolygon,
    right: ConvexPolygon,
) -> bool:
    return (
        left.kind == "arrow"
        and right.kind == "arrow"
        and _allowed_adjacent_band_seam(first, second)
    )


def _allowed_adjacent_dimension_arrow_touch(
    first: PlacementCandidate,
    second: PlacementCandidate,
    stroke: Polyline,
    body: ConvexPolygon,
) -> bool:
    return (
        stroke.kind == "dimension"
        and body.kind == "arrow"
        and _allowed_adjacent_band_seam(first, second)
    )


def _orientation(a: Point, b: Point, c: Point) -> float:
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


def _on_segment(a: Point, b: Point, p: Point) -> bool:
    return (
        min(a.x, b.x) <= p.x <= max(a.x, b.x)
        and min(a.y, b.y) <= p.y <= max(a.y, b.y)
        and isclose(_orientation(a, b, p), 0.0, abs_tol=1e-9)
    )


def segments_intersect(first: Segment, second: Segment) -> bool:
    a, b = first.start, first.end
    c, d = second.start, second.end
    o1 = _orientation(a, b, c)
    o2 = _orientation(a, b, d)
    o3 = _orientation(c, d, a)
    o4 = _orientation(c, d, b)
    if ((o1 > 0 > o2) or (o1 < 0 < o2)) and ((o3 > 0 > o4) or (o3 < 0 < o4)):
        return True
    return (
        (isclose(o1, 0.0, abs_tol=1e-9) and _on_segment(a, b, c))
        or (isclose(o2, 0.0, abs_tol=1e-9) and _on_segment(a, b, d))
        or (isclose(o3, 0.0, abs_tol=1e-9) and _on_segment(c, d, a))
        or (isclose(o4, 0.0, abs_tol=1e-9) and _on_segment(c, d, b))
    )


def segment_intersects_box(segment: Segment, box: Box) -> bool:
    if box.contains(segment.start) or box.contains(segment.end):
        return True
    corners = (
        Point(box.xmin, box.ymin),
        Point(box.xmax, box.ymin),
        Point(box.xmax, box.ymax),
        Point(box.xmin, box.ymax),
    )
    edges = tuple(
        Segment(corners[index], corners[(index + 1) % 4], "box_edge")
        for index in range(4)
    )
    return any(segments_intersect(segment, edge) for edge in edges)


def _stroke_pair_penalty(first: Segment, second: Segment) -> float:
    if not segments_intersect(first, second):
        return 0.0
    # User-approved exception: thin radius/coordinate leaders may cross.
    if first.kind == second.kind == "leader":
        return THIN_LEADER_CROSSING
    kinds = {first.kind, second.kind}
    if kinds == {"dimension", "leader"}:
        # A single-point crossing between a fine radius leader and an angle
        # dimension line is visually undesirable but not a large overlap.
        # Prefer to avoid it; do not reject an otherwise clean layout.
        return LEADER_DIMENSION_CROSSING
    if "dimension" in kinds:
        return DIMENSION_STROKE_COLLISION
    return STROKE_BODY_COLLISION


def candidate_pair_penalty(first: PlacementCandidate, second: PlacementCandidate) -> float:
    penalty = 0.0
    first_bodies, first_strokes = normalized_candidate_geometry(first)
    second_bodies, second_strokes = normalized_candidate_geometry(second)
    strict = bool(first.formula_id or second.formula_id)

    # Strict candidates are rejected by candidate_pair_hard_vector, so adding
    # billion-point pseudo-hard costs here only distorts aesthetic ranking.
    # Legacy candidates retain the old score for API/test compatibility.
    if not strict:
        penalty += sum(
            HARD_OVERLAP + BODY_BASE_COLLISION
            for left in first_bodies
            for right in second_bodies
            if polygons_overlap(left, right)
        )

    if strict:
        soft_text_stroke_hits = sum(
            1
            for stroke in first_strokes
            for body in second_bodies
            if polyline_intersects_polygon(stroke, body)
            and _soft_text_stroke_intersection(first, second, stroke, body)
        ) + sum(
            1
            for stroke in second_strokes
            for body in first_bodies
            if polyline_intersects_polygon(stroke, body)
            and _soft_text_stroke_intersection(first, second, stroke, body)
        )
        penalty += _mean_weight(
            first, second, "text_thin_stroke_overlap"
        ) * soft_text_stroke_hits
        # Do not re-add the old pseudo-hard stroke/body score here.  Any
        # non-approved stroke/body contact is rejected by
        # candidate_pair_hard_vector; the approved text/thin-line fallback
        # must remain a finite, explicitly weighted aesthetic cost.

    for left in first_strokes:
        for right in second_strokes:
            if not polylines_intersect(left, right):
                continue
            if left.kind == right.kind == "leader":
                penalty += _mean_weight(first, second, "text_line_target") / 480.0
            elif {left.kind, right.kind} == {"dimension", "leader"}:
                penalty += _mean_weight(first, second, "radius_angle_gap") / 10.0
            elif not strict:
                penalty += DIMENSION_STROKE_COLLISION

    first_text = _text_polygons(first_bodies)
    second_text = _text_polygons(second_bodies)
    preferred_gap = max(first.preferred_body_gap, second.preferred_body_gap)
    if preferred_gap > 0 and first_text and second_text:
        gap = min(
            _polygon_clearance(left, right)
            for left in first_text
            for right in second_text
        )
        deficit = max(0.0, preferred_gap - gap)
        scale = max(first.text_height, second.text_height, 1.0e-9)
        penalty += _mean_weight(first, second, "text_line_target") * (deficit / scale) ** 2

    preferred_dimension_gap = max(
        first.preferred_dimension_gap, second.preferred_dimension_gap
    )
    if preferred_dimension_gap > 0:
        dimension_clearances = tuple(
            clearance
            for left in first_strokes
            for right in second_strokes
            if (
                clearance := _dimension_curve_clearance(first, second, left, right)
            )
            is not None
        )
        if dimension_clearances:
            deficit = max(0.0, preferred_dimension_gap - min(dimension_clearances))
            scale = max(first.text_height, second.text_height, 1.0e-9)
            penalty += _mean_weight(first, second, "dimension_spacing") * (
                deficit / scale
            ) ** 2

    seam = _dimension_seam_distance(first, second)
    seam_target = max(first.sequence_seam_target, second.sequence_seam_target)
    if seam is not None and seam_target > 0:
        scale = max(first.text_height, second.text_height, 1.0e-9)
        penalty += _mean_weight(first, second, "offset_delta") * (
            max(0.0, seam - seam_target) / scale
        ) ** 2
    penalty += sequence_rhythm_penalty(first, second)
    penalty += angle_radius_relation_penalty(first, second)
    return penalty


def candidate_intrinsic_hard_vector(candidate: PlacementCandidate) -> HardViolationVector:
    association = int(
        not candidate.source_association_valid or not candidate.locked_grips_unchanged
        or not _strict_vector_contract_valid(candidate)
    )
    text_source = int(
        candidate.source_clearance is not None
        and candidate.source_clearance < candidate.minimum_source_clearance
    )
    hard_width = (
        candidate.minimum_available_width
        if candidate.minimum_available_width is not None
        else candidate.available_width
    )
    radial_corridor_failure = (
        hard_width is not None and hard_width < candidate.required_width
    )
    tangential_corridor_failure = (
        candidate.tangential_available_length is not None
        and candidate.tangential_required_length is not None
        and candidate.tangential_available_length
        < candidate.tangential_required_length
    )
    corridor = int(radial_corridor_failure or tangential_corridor_failure)
    # For the sharp-corner specialist the decisive visual failure is not a
    # thin dimension stroke crossing its own text (the accepted manual sample
    # permits that when space is tight), but the text colliding with either
    # heavy native arrow.  Test the actual OBB/arrow polygons instead of using
    # an oversized one-dimensional proxy length.
    internal_body_overlap = 0
    if candidate.layout_policy == "short_corner":
        bodies, _ = normalized_candidate_geometry(candidate)
        text_bodies = _text_polygons(bodies)
        arrow_bodies = tuple(
            body for body in bodies if "arrow" in body.kind.lower()
        )
        internal_body_overlap = sum(
            1
            for text_body in text_bodies
            for arrow_body in arrow_bodies
            if polygons_overlap(text_body, arrow_body)
        )
    return HardViolationVector(
        source_or_locked=association,
        body_overlap=internal_body_overlap,
        text_source=text_source,
        insufficient_corridor=corridor,
    )


def candidate_pair_hard_vector(
    first: PlacementCandidate, second: PlacementCandidate
) -> HardViolationVector:
    """Count real vector-body failures, falling back to legacy AABB geometry."""

    first_bodies, first_strokes = normalized_candidate_geometry(first)
    second_bodies, second_strokes = normalized_candidate_geometry(second)
    body_overlap = sum(
        1
        for left in first_bodies
        for right in second_bodies
        if polygons_overlap(left, right)
        and not _allowed_adjacent_arrow_touch(first, second, left, right)
    )
    first_text = _text_polygons(first_bodies)
    second_text = _text_polygons(second_bodies)
    minimum_gap = max(first.minimum_body_gap, second.minimum_body_gap)
    text_gap_failure = 0
    if body_overlap == 0 and minimum_gap > 0 and first_text and second_text:
        text_gap_failure = int(
            min(
                _polygon_clearance(left, right)
                for left in first_text
                for right in second_text
            )
            < minimum_gap
        )
    stroke_body = sum(
        1
        for stroke in first_strokes
        for body in second_bodies
        if polyline_intersects_polygon(stroke, body)
        and not _soft_text_stroke_intersection(first, second, stroke, body)
        and not _allowed_adjacent_dimension_arrow_touch(
            first, second, stroke, body
        )
    ) + sum(
        1
        for stroke in second_strokes
        for body in first_bodies
        if polyline_intersects_polygon(stroke, body)
        and not _soft_text_stroke_intersection(first, second, stroke, body)
        and not _allowed_adjacent_dimension_arrow_touch(
            first, second, stroke, body
        )
    )
    heavy_crossing = sum(
        1
        for left in first_strokes
        for right in second_strokes
        if polylines_intersect(left, right)
        and "leader" not in {left.kind, right.kind}
        and not _allowed_adjacent_dimension_touch(first, second, left, right)
    )
    # Endpoint separation between independently offset neighbouring circular
    # arcs is an aesthetic rhythm signal, not a physical collision.  Side,
    # band and offset continuity remain soft-ranked by sequence_rhythm_penalty;
    # vector overlap and minimum dimension spacing remain hard failures.
    seam_failure = 0
    minimum_dimension_gap = max(
        first.minimum_dimension_gap, second.minimum_dimension_gap
    )
    dimension_spacing = 0
    if minimum_dimension_gap > 0:
        dimension_spacing = sum(
            1
            for left in first_strokes
            for right in second_strokes
            if (
                clearance := _dimension_curve_clearance(first, second, left, right)
            )
            is not None
            and clearance < minimum_dimension_gap
        )
    return HardViolationVector(
        body_overlap=body_overlap + text_gap_failure,
        heavy_stroke_body=stroke_body + heavy_crossing,
        sequence_seam=seam_failure,
        dimension_spacing=dimension_spacing,
    )


def layout_hard_vector(
    placements: Iterable[PlacementCandidate],
) -> HardViolationVector:
    """Recompute the authoritative hard vector after any repair/mutation.

    Repair callers must not carry forward a pre-repair total.  This small
    public helper gives planners one deterministic recomputation point without
    exposing solver internals or relying on soft scores.
    """

    items = tuple(placements)
    total = HardViolationVector()
    for candidate in items:
        total = total.plus(candidate_intrinsic_hard_vector(candidate))
    for left in range(len(items)):
        for right in range(left + 1, len(items)):
            total = total.plus(candidate_pair_hard_vector(items[left], items[right]))
    return total


def candidate_intrinsic_penalty(candidate: PlacementCandidate) -> float:
    """Score one placement before annotation-to-annotation interactions.

    ``available_width`` is the robust usable corridor width measured on the
    candidate side across the complete label footprint (normally the lower
    quantile of several normal-ray samples).  A candidate that cannot contain
    its own text/arrow/dimension body is rejected at the same level as a body
    overlap.  Once it fits, wider continuous space is preferred before a small
    difference in offset distance.
    """

    weights = candidate.weights
    penalty = (
        candidate.preference_cost * weights.profile_deviation
        + abs(candidate.offset) * OFFSET_DISTANCE_COST
    )
    if candidate.profile_target_offset is not None:
        scale = max(candidate.text_height, 1.0e-9)
        penalty += weights.offset_delta * (
            (abs(candidate.offset) - candidate.profile_target_offset) / scale
        ) ** 2
    if (
        candidate.annotation_kind == "angle"
        and candidate.path_preferred_side
        and candidate.side != candidate.path_preferred_side
    ):
        penalty += weights.non_dominant_side
    if candidate.source_clearance is not None:
        source_deficit = max(
            0.0, candidate.preferred_source_clearance - candidate.source_clearance
        )
        scale = max(candidate.text_height, 1.0e-9)
        penalty += weights.source_clearance_preference * (source_deficit / scale) ** 2
    if candidate.available_width is None:
        return penalty
    deficit = candidate.required_width - candidate.available_width
    if deficit > 0:
        # Strict formula candidates report a corridor failure only through the
        # lexicographic hard vector.  Re-encoding it here as a huge soft score
        # lets old magic numbers distort pruning and repair order.
        if candidate.formula_id:
            scale = max(candidate.text_height, 1.0e-9)
            return penalty + weights.wide_space * (deficit / scale) ** 2
        return penalty + INSUFFICIENT_WIDTH + deficit * BODY_BASE_COLLISION
    margin = max(0.0, candidate.available_width - candidate.required_width)
    return penalty + weights.wide_space / (1.0 + margin)


def sequence_rhythm_penalty(first: PlacementCandidate, second: PlacementCandidate) -> float:
    """Keep neighbouring angle dimensions on one readable side/band.

    This is deliberately weaker than every body-collision penalty.  It creates
    the aligned rhythm visible in a hand-laid drawing, but immediately yields
    when the preferred side is too narrow or another annotation occupies it.
    """

    if not _adjacent_path_angles(first, second):
        return 0.0
    penalty = 0.0
    side_switch = _mean_weight(first, second, "side_switch")
    band_step = _mean_weight(first, second, "band_step")
    offset_delta = _mean_weight(first, second, "offset_delta")
    along_shift = _mean_weight(first, second, "along_shift")
    if first.side != second.side:
        penalty += side_switch
    penalty += abs(first.band - second.band) * band_step
    scale = max(first.text_height, second.text_height, 1.0e-9)
    penalty += abs(first.offset - second.offset) / scale * offset_delta
    penalty += abs(first.along_shift - second.along_shift) / scale * along_shift
    return penalty


def angle_radius_relation_penalty(
    first: PlacementCandidate, second: PlacementCandidate
) -> float:
    """Keep a radius annotation outside its corresponding angle band.

    Radius and angle dimensions may share the same source arc, but their text
    and heavy arrow/dimension bodies must remain separate.  On the same side,
    the radius dimension is expected to sit beyond the angle dimension.  The
    exact collision geometry remains authoritative; this relation only gives
    the solver the human drafting order visible in the approved sample.
    """

    kinds = {first.annotation_kind, second.annotation_kind}
    if kinds != {"angle", "radius"}:
        return 0.0
    if (
        not first.source_segment_key
        or first.source_segment_key != second.source_segment_key
    ):
        return 0.0
    angle = first if first.annotation_kind == "angle" else second
    radius = second if first.annotation_kind == "angle" else first
    if angle.side != radius.side:
        return 0.0
    minimum_radius_offset = angle.offset + max(
        angle.required_width * 0.5,
        radius.required_width * 0.5,
        1.0,
    )
    if radius.offset < minimum_radius_offset:
        return _mean_weight(first, second, "radius_inside_angle") + (
            minimum_radius_offset - radius.offset
        ) * _mean_weight(first, second, "radius_angle_gap")
    return 0.0


def obstacle_penalty(candidate: PlacementCandidate, obstacles: Sequence[BaseObstacle]) -> float:
    penalty = 0.0
    bodies, strokes = normalized_candidate_geometry(candidate)
    for obstacle in obstacles:
        geometry = obstacle.geometry
        obstacle_body = (
            _box_polygon(geometry)
            if isinstance(geometry, Box)
            else geometry if isinstance(geometry, ConvexPolygon) else None
        )
        obstacle_stroke = (
            _segment_polyline(geometry)
            if isinstance(geometry, Segment)
            else geometry if isinstance(geometry, Polyline) else None
        )
        if obstacle_body is not None:
            for body in bodies:
                if polygons_overlap(body, obstacle_body):
                    penalty += HARD_OVERLAP + BODY_BASE_COLLISION * obstacle.priority
            for stroke in strokes:
                if polyline_intersects_polygon(stroke, obstacle_body):
                    factor = 0.05 if stroke.kind == "leader" else 1.0
                    penalty += STROKE_BODY_COLLISION * obstacle.priority * factor
        elif obstacle_stroke is not None:
            for body in bodies:
                if polyline_intersects_polygon(obstacle_stroke, body):
                    penalty += BODY_BASE_COLLISION * obstacle.priority
            for stroke in strokes:
                if not polylines_intersect(stroke, obstacle_stroke):
                    continue
                factor = 0.02 if stroke.kind == "leader" else 1.0
                penalty += DIMENSION_STROKE_COLLISION * obstacle.priority * factor
    return penalty


def choose_layout(
    candidate_groups: Sequence[Sequence[PlacementCandidate]],
    obstacles: Sequence[BaseObstacle] = (),
    beam_width: int = 128,
) -> LayoutResult:
    """Select one candidate per annotation using deterministic beam search."""

    beam: list[
        tuple[HardViolationVector, float, tuple[PlacementCandidate, ...], tuple[str, ...]]
    ] = [(HardViolationVector(), 0.0, (), ())]
    for group in candidate_groups:
        if not group:
            raise ValueError("every annotation must provide at least one candidate")
        annotation_ids = {candidate.annotation_id for candidate in group}
        if len(annotation_ids) != 1:
            raise ValueError("a candidate group must belong to one annotation")
        expanded: list[
            tuple[HardViolationVector, float, tuple[PlacementCandidate, ...], tuple[str, ...]]
        ] = []
        for hard_vector, score, placed, diagnostics in beam:
            for candidate in group:
                increment = candidate_intrinsic_penalty(candidate) + obstacle_penalty(candidate, obstacles)
                pair_penalties = [candidate_pair_penalty(candidate, other) for other in placed]
                increment += sum(pair_penalties)
                candidate_hard = candidate_intrinsic_hard_vector(candidate)
                for other in placed:
                    candidate_hard = candidate_hard.plus(
                        candidate_pair_hard_vector(candidate, other)
                    )
                notes = diagnostics
                if (
                    candidate.available_width is not None
                    and candidate.available_width < candidate.required_width
                ):
                    notes += (f"{candidate.annotation_id}:{candidate.candidate_id}:insufficient-width",)
                if any(value >= HARD_OVERLAP for value in pair_penalties):
                    notes += (f"{candidate.annotation_id}:{candidate.candidate_id}:body-overlap",)
                expanded.append(
                    (
                        hard_vector.plus(candidate_hard),
                        score + increment,
                        placed + (candidate,),
                        notes,
                    )
                )
        expanded.sort(
            key=lambda item: (
                item[0],
                item[1],
                tuple(placement.candidate_id for placement in item[2]),
            )
        )
        beam = expanded[: max(1, beam_width)]
    hard_vector, score, placements, diagnostics = beam[0]
    if not hard_vector.is_clear:
        diagnostics += (
            "NEEDS_MANUAL_REVIEW:hard="
            f"{hard_vector.source_or_locked},"
            f"{hard_vector.body_overlap},"
            f"{hard_vector.text_source},"
            f"{hard_vector.heavy_stroke_body},"
            f"{hard_vector.insufficient_corridor}",
        )
    return LayoutResult(
        placements=placements,
        score=score,
        diagnostics=diagnostics,
        hard_violations=hard_vector,
    )


def choose_angle_then_radius_layout(
    angle_candidate_groups: Sequence[Sequence[PlacementCandidate]],
    radius_candidate_groups: Sequence[Sequence[PlacementCandidate]],
    beam_width: int = 128,
) -> LayoutResult:
    """Lay out native angles first, then radii around the fixed angle result.

    This intentionally excludes base-drawing obstacles.  It implements the
    current project gate: first obtain a coherent, collision-free angle band;
    only then place radius text/leaders around it.  Basemap avoidance is a later
    phase and must not silently perturb a verified annotation-only result.
    """

    angles = choose_layout(angle_candidate_groups, (), beam_width)
    fixed_angle_groups = tuple((candidate,) for candidate in angles.placements)
    combined = choose_layout(
        fixed_angle_groups + tuple(radius_candidate_groups), (), beam_width
    )
    return LayoutResult(
        placements=combined.placements,
        score=combined.score,
        diagnostics=angles.diagnostics + combined.diagnostics,
        hard_violations=combined.hard_violations,
    )


def audit_annotation_collisions(
    placements: Iterable[PlacementCandidate],
) -> CollisionAudit:
    """Count only annotation-to-annotation collisions for the current gate."""

    items = tuple(placements)
    body_overlaps = 0
    stroke_body_hits = 0
    heavy_stroke_crossings = 0
    thin_leader_crossings = 0
    leader_dimension_crossings = 0
    dimension_spacing_failures = 0
    soft_text_stroke_hits = 0
    for left_index in range(len(items)):
        for right_index in range(left_index + 1, len(items)):
            first, second = items[left_index], items[right_index]
            first_bodies, first_strokes = normalized_candidate_geometry(first)
            second_bodies, second_strokes = normalized_candidate_geometry(second)
            body_overlaps += sum(
                1
                for left in first_bodies
                for right in second_bodies
                if polygons_overlap(left, right)
                and not _allowed_adjacent_arrow_touch(first, second, left, right)
            )
            for stroke, body in tuple(
                (stroke, body)
                for stroke in first_strokes
                for body in second_bodies
            ) + tuple(
                (stroke, body)
                for stroke in second_strokes
                for body in first_bodies
            ):
                if not polyline_intersects_polygon(stroke, body):
                    continue
                if _soft_text_stroke_intersection(first, second, stroke, body):
                    soft_text_stroke_hits += 1
                elif not _allowed_adjacent_dimension_arrow_touch(
                    first, second, stroke, body
                ):
                    stroke_body_hits += 1
            for left in first_strokes:
                for right in second_strokes:
                    clearance = _dimension_curve_clearance(first, second, left, right)
                    minimum_gap = max(
                        first.minimum_dimension_gap, second.minimum_dimension_gap
                    )
                    if (
                        clearance is not None
                        and minimum_gap > 0
                        and clearance < minimum_gap
                    ):
                        dimension_spacing_failures += 1
                    if not polylines_intersect(left, right):
                        continue
                    if left.kind == right.kind == "leader":
                        thin_leader_crossings += 1
                    elif {left.kind, right.kind} == {"dimension", "leader"}:
                        leader_dimension_crossings += 1
                    elif not _allowed_adjacent_dimension_touch(first, second, left, right):
                        heavy_stroke_crossings += 1
    return CollisionAudit(
        body_overlaps=body_overlaps,
        stroke_body_hits=stroke_body_hits,
        heavy_stroke_crossings=heavy_stroke_crossings,
        thin_leader_crossings=thin_leader_crossings,
        leader_dimension_crossings=leader_dimension_crossings,
        dimension_spacing_failures=dimension_spacing_failures,
        soft_text_stroke_hits=soft_text_stroke_hits,
    )


def total_pair_penalty(placements: Iterable[PlacementCandidate]) -> float:
    items = tuple(placements)
    return sum(
        candidate_pair_penalty(items[left], items[right])
        for left in range(len(items))
        for right in range(left + 1, len(items))
    )
