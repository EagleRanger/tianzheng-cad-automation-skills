"""Resolution-independent vector geometry for native annotation layout.

The layout solver must reason in drawing coordinates, not pixels.  This module
therefore contains only deterministic WCS geometry: oriented text boxes,
conservative arrow polygons and sampled native dimension arcs.  Screenshot QA
is a later acceptance gate and never changes these calculations.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import hypot
from typing import Iterable, Sequence


EPSILON = 1.0e-9


@dataclass(frozen=True)
class VectorPoint:
    x: float
    y: float


@dataclass(frozen=True)
class ConvexPolygon:
    points: tuple[VectorPoint, ...]
    kind: str = "body"

    def __post_init__(self) -> None:
        if len(self.points) < 3:
            raise ValueError("a polygon needs at least three points")


@dataclass(frozen=True)
class Polyline:
    points: tuple[VectorPoint, ...]
    kind: str = "dimension"

    def __post_init__(self) -> None:
        if len(self.points) < 2:
            raise ValueError("a polyline needs at least two points")


def _unit(point: VectorPoint) -> VectorPoint:
    length = hypot(point.x, point.y)
    if length <= EPSILON:
        raise ValueError("zero-length direction")
    return VectorPoint(point.x / length, point.y / length)


def oriented_box(
    center: VectorPoint,
    tangent: VectorPoint,
    width: float,
    height: float,
    kind: str = "text",
) -> ConvexPolygon:
    """Return the true OBB used by SAT; no AABB inflation is introduced."""

    if width <= 0 or height <= 0:
        raise ValueError("box dimensions must be positive")
    axis = _unit(tangent)
    normal = VectorPoint(-axis.y, axis.x)
    half_width = width * 0.5
    half_height = height * 0.5
    return ConvexPolygon(
        tuple(
            VectorPoint(
                center.x + axis.x * along + normal.x * across,
                center.y + axis.y * along + normal.y * across,
            )
            for along, across in (
                (-half_width, -half_height),
                (half_width, -half_height),
                (half_width, half_height),
                (-half_width, half_height),
            )
        ),
        kind,
    )


def conservative_arrow(
    tip: VectorPoint,
    tangent: VectorPoint,
    size: float,
    kind: str = "arrow",
) -> ConvexPolygon:
    """Return a conservative native-arrow triangle in WCS."""

    if size <= 0:
        raise ValueError("arrow size must be positive")
    axis = _unit(tangent)
    normal = VectorPoint(-axis.y, axis.x)
    base = VectorPoint(tip.x - axis.x * size, tip.y - axis.y * size)
    return ConvexPolygon(
        (
            tip,
            VectorPoint(base.x + normal.x * size * 0.55, base.y + normal.y * size * 0.55),
            VectorPoint(base.x - normal.x * size * 0.55, base.y - normal.y * size * 0.55),
        ),
        kind,
    )


def polygon_aabb(polygon: ConvexPolygon) -> tuple[float, float, float, float]:
    return (
        min(point.x for point in polygon.points),
        min(point.y for point in polygon.points),
        max(point.x for point in polygon.points),
        max(point.y for point in polygon.points),
    )


def projected_span(polygon: ConvexPolygon, axis: VectorPoint) -> float:
    """Return the exact OBB/polygon extent along ``axis`` in drawing units."""

    unit = _unit(axis)
    lower, upper = _project(polygon, unit)
    return upper - lower


def signed_near_edge_clearance(
    source_point: VectorPoint,
    polygon: ConvexPolygon,
    outward_normal: VectorPoint,
) -> float:
    """Distance from source point to the polygon edge nearest the source.

    Positive values mean the complete body is on the requested side.  This is
    the measured residual used after Tianzheng creates a native object; it
    replaces guessed top/bottom/left/right correction constants.
    """

    normal = _unit(outward_normal)
    values = tuple(
        (point.x - source_point.x) * normal.x
        + (point.y - source_point.y) * normal.y
        for point in polygon.points
    )
    return min(values)


def _axes(polygon: ConvexPolygon) -> Iterable[VectorPoint]:
    for index, start in enumerate(polygon.points):
        end = polygon.points[(index + 1) % len(polygon.points)]
        edge = VectorPoint(end.x - start.x, end.y - start.y)
        if hypot(edge.x, edge.y) > EPSILON:
            yield _unit(VectorPoint(-edge.y, edge.x))


def _project(polygon: ConvexPolygon, axis: VectorPoint) -> tuple[float, float]:
    values = tuple(point.x * axis.x + point.y * axis.y for point in polygon.points)
    return min(values), max(values)


def polygons_overlap(first: ConvexPolygon, second: ConvexPolygon) -> bool:
    """Exact SAT overlap for convex annotation bodies.

    Touching at a single boundary is not counted as body overlap.  Clearance
    requirements are modelled explicitly in H units by the formula contract.
    """

    for axis in tuple(_axes(first)) + tuple(_axes(second)):
        first_min, first_max = _project(first, axis)
        second_min, second_max = _project(second, axis)
        if first_max <= second_min + EPSILON or second_max <= first_min + EPSILON:
            return False
    return True


def _orientation(a: VectorPoint, b: VectorPoint, c: VectorPoint) -> float:
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)


def _on_segment(a: VectorPoint, b: VectorPoint, p: VectorPoint) -> bool:
    return (
        min(a.x, b.x) - EPSILON <= p.x <= max(a.x, b.x) + EPSILON
        and min(a.y, b.y) - EPSILON <= p.y <= max(a.y, b.y) + EPSILON
        and abs(_orientation(a, b, p)) <= EPSILON
    )


def segments_intersect(
    a: VectorPoint, b: VectorPoint, c: VectorPoint, d: VectorPoint
) -> bool:
    o1 = _orientation(a, b, c)
    o2 = _orientation(a, b, d)
    o3 = _orientation(c, d, a)
    o4 = _orientation(c, d, b)
    if ((o1 > EPSILON and o2 < -EPSILON) or (o1 < -EPSILON and o2 > EPSILON)) and (
        (o3 > EPSILON and o4 < -EPSILON) or (o3 < -EPSILON and o4 > EPSILON)
    ):
        return True
    return (
        (abs(o1) <= EPSILON and _on_segment(a, b, c))
        or (abs(o2) <= EPSILON and _on_segment(a, b, d))
        or (abs(o3) <= EPSILON and _on_segment(c, d, a))
        or (abs(o4) <= EPSILON and _on_segment(c, d, b))
    )


def polyline_intersects_polygon(line: Polyline, polygon: ConvexPolygon) -> bool:
    edges = tuple(
        (polygon.points[index], polygon.points[(index + 1) % len(polygon.points)])
        for index in range(len(polygon.points))
    )
    if any(point_in_convex_polygon(point, polygon) for point in line.points):
        return True
    for index in range(len(line.points) - 1):
        start, end = line.points[index], line.points[index + 1]
        if any(segments_intersect(start, end, left, right) for left, right in edges):
            return True
    return False


def point_in_convex_polygon(point: VectorPoint, polygon: ConvexPolygon) -> bool:
    """Return True for points inside or on a convex polygon boundary."""

    signs: list[bool] = []
    for index, start in enumerate(polygon.points):
        end = polygon.points[(index + 1) % len(polygon.points)]
        cross = _orientation(start, end, point)
        if abs(cross) <= EPSILON:
            continue
        signs.append(cross > 0)
    return not signs or all(value == signs[0] for value in signs)


def polylines_intersect(first: Polyline, second: Polyline) -> bool:
    return any(
        segments_intersect(
            first.points[left],
            first.points[left + 1],
            second.points[right],
            second.points[right + 1],
        )
        for left in range(len(first.points) - 1)
        for right in range(len(second.points) - 1)
    )


def minimum_point_distance(first: Sequence[VectorPoint], second: Sequence[VectorPoint]) -> float:
    """Conservative sampled clearance used for deterministic QA diagnostics."""

    if not first or not second:
        raise ValueError("point collections cannot be empty")
    return min(hypot(a.x - b.x, a.y - b.y) for a in first for b in second)


def minimum_polyline_distance(first: Polyline, second: Polyline) -> float:
    """Return exact segment-to-segment clearance for sampled dimension curves."""

    if polylines_intersect(first, second):
        return 0.0
    first_edges = tuple(zip(first.points, first.points[1:]))
    second_edges = tuple(zip(second.points, second.points[1:]))
    return min(
        min(
            _point_segment_distance(point, start, end)
            for point in first.points
            for start, end in second_edges
        ),
        min(
            _point_segment_distance(point, start, end)
            for point in second.points
            for start, end in first_edges
        ),
    )


def _point_segment_distance(
    point: VectorPoint, start: VectorPoint, end: VectorPoint
) -> float:
    dx = end.x - start.x
    dy = end.y - start.y
    denominator = dx * dx + dy * dy
    if denominator <= EPSILON:
        return hypot(point.x - start.x, point.y - start.y)
    ratio = max(
        0.0,
        min(1.0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / denominator),
    )
    closest = VectorPoint(start.x + ratio * dx, start.y + ratio * dy)
    return hypot(point.x - closest.x, point.y - closest.y)


def minimum_polygon_distance(first: ConvexPolygon, second: ConvexPolygon) -> float:
    """Exact boundary clearance for two convex annotation bodies."""

    if polygons_overlap(first, second):
        return 0.0
    first_edges = tuple(
        (first.points[index], first.points[(index + 1) % len(first.points)])
        for index in range(len(first.points))
    )
    second_edges = tuple(
        (second.points[index], second.points[(index + 1) % len(second.points)])
        for index in range(len(second.points))
    )
    return min(
        min(
            _point_segment_distance(point, start, end)
            for point in first.points
            for start, end in second_edges
        ),
        min(
            _point_segment_distance(point, start, end)
            for point in second.points
            for start, end in first_edges
        ),
    )
