"""User-approved local annotation policy. Geometry stays in drawing units.

Use actual text glyph envelopes, not whole native entity extents. The latter
include arrows and extension lines and cannot represent text collision.
"""
from math import hypot

POLICY_REVISION = "2026-10-21-native-source-first"


def road_annotation_semantics(values):
    """Read NY_ROAD_SEMANTICS values; an unclassified line stays unclassified.

    The current DWG stores [app, class, nominal_width, evidence_version].
    A layer name or proximity to an old label is not evidence of material.
    This reads a verified binding; it does not classify an unseen drawing.
    """
    from math import isfinite
    unknown = {"class": "REVIEW_REQUIRED", "width": None,
               "eligible_road_dimension": False}
    if not values or len(values) < 4 or values[0] != "NY_ROAD_SEMANTICS":
        return unknown
    kind = values[1]
    if kind not in {"MAIN_3M", "GRAY_2M", "STEPPING_STONE",
                    "BOARDWALK_STAIR_CONNECTOR", "REVIEW_REQUIRED"}:
        return unknown
    try:
        width = float(values[2])
    except (TypeError, ValueError):
        return unknown
    if not isfinite(width) or width < 0 or not values[3]:
        return unknown
    expected = {"MAIN_3M": 3.0, "GRAY_2M": 2.0}
    if kind in expected and abs(width - expected[kind]) > 1e-8:
        return unknown
    return {"class": kind, "width": width,
            "eligible_road_dimension": kind in expected}


def road_centerline_offset(nominal_width, edge_clearance):
    """Convert accepted edge clearance to an offset from the true centerline.

    Both arguments use drawing units. Width must be verified at the local
    road cross-section; 0.6 is a tested project choice, not a global default.
    """
    from math import isfinite
    if (not isfinite(nominal_width) or not isfinite(edge_clearance)
            or nominal_width <= 0 or edge_clearance < 0):
        raise ValueError("Verified width and nonnegative clearance required")
    return nominal_width / 2 + edge_clearance


def native_ccw_arc_endpoints(start, end, bulge):
    """Endpoint order for this project's verified CCW native angle template.

    Swapping an already-built reflex dimension in place is not a reset.
    Use a clean same-type template, then read its actual measured angle.
    """
    if not bulge:
        raise ValueError("A straight segment has no included arc angle")
    return (start, end) if bulge > 0 else (end, start)


def local_paving_anchor(region, visible_region=None):
    """Use the visible paving interior, with a guaranteed interior point.

    A curved or concave paving centroid can be outside the paving; snapping
    it back to an edge is not a valid repair. The caller verifies material,
    native tip binding and a suitable local clearance after choosing this.
    """
    local = region if visible_region is None else region.intersection(visible_region)
    return interior_anchor(local)

def radius_pair_targets(center, radius, unit, native_line_length):
    """Only the measured point and dimension-line end; never a text grip.

    The caller chooses a free angular station after freezing the angle band.
    native_line_length is calibrated from the accepted native vector sample.
    It must not enlarge the angle band's offset. Positive means inward.
    """
    n=hypot(*unit)
    if n == 0 or radius <= 0 or native_line_length <= 0:
        raise ValueError("Invalid native radius line")
    u=[v/n for v in unit]
    tip=[center[i]+radius*u[i] for i in (0,1)]
    end=[tip[i]-native_line_length*u[i] for i in (0,1)]
    return {2:tip,1:end}

def collision_reasons(body, foreign_texts=(), effective_content=None,
                      foreign_lines=(), clearance=0.0):
    """Text matters; ordinary line/line crossings and low-priority grass don't.

    Do not supply the annotation's own supporting line as a foreign line.
    Source-arrow contact is expected and is not a text collision.
    Contours, grid lines and GRASS glyphs are not effective-content obstacles.
    """
    b=body.buffer(clearance) if clearance else body
    reasons=[]
    if any(b.intersects(t) for t in foreign_texts):reasons.append("text_text")
    if effective_content is not None and b.intersects(effective_content):
        reasons.append("text_effective_content")
    if any(b.intersects(line) for line in foreign_lines):
        reasons.append("foreign_line_through_text")
    return reasons

def interior_anchor(region, old_tip=None):
    """Choose a central point guaranteed inside the effective planting patch."""
    from shapely.ops import polylabel
    if region.is_empty:raise ValueError("No effective planting region")
    regions=list(region.geoms) if region.geom_type=="MultiPolygon" else [region]
    region=max(regions,key=lambda g:g.area)
    centroid=region.centroid
    deepest=polylabel(region,tolerance=max(.02,min(.1,region.area**.5/60)))
    if region.covers(centroid) and centroid.distance(region.boundary)>=deepest.distance(region.boundary)*.6:
        return centroid
    return deepest

def planting_leader(tip, text_bounds, gap=.25, margin=.2):
    """One diagonal lead plus one horizontal shelf; text style unchanged."""
    x0,y0,x1,y1=text_bounds
    y=y0-gap
    left=tip[0] <= (x0+x1)/2
    elbow=(x0-margin,y) if left else (x1+margin,y)
    end=(x1+margin,y) if left else (x0-margin,y)
    return [tuple(tip),elbow,end]


def planting_leader_angle(points):
    """Interior angle at the shelf elbow, not the direction of the diagonal."""
    from math import acos, degrees
    a,b,c=points[:3]
    u=(a[0]-b[0],a[1]-b[1]);v=(c[0]-b[0],c[1]-b[1])
    n=hypot(*u)*hypot(*v)
    if n<=1e-12:return 0.0
    return degrees(acos(max(-1,min(1,(u[0]*v[0]+u[1]*v[1])/n))))


def planting_standard_leaders(text_bounds, lengths, gap=.25, margin=.2):
    """Candidate tips for exactly 90 or 135 degree shrub/herb shelf elbows.

    The caller must test effective-fill interior clearance, nearby length,
    whole-group viewport coverage, and text/shelf clearance from dense fills.
    A point merely inside a fill is not a sufficiently central anchor.
    """
    x0,y0,x1,y1=text_bounds
    y=y0-gap
    for elbow,end,outward in [((x0-margin,y),(x1+margin,y),-1),
                              ((x1+margin,y),(x0-margin,y),1)]:
        for length in lengths:
            if length<=0:continue
            for vertical in (-1,1):
                yield [(elbow[0],y+vertical*length),elbow,end]
                d=length/(2**.5)
                yield [(elbow[0]+outward*d,y+vertical*d),elbow,end]

def preserve_clean(current_reasons, explicitly_rejected=False):
    return not current_reasons and not explicitly_rejected

def complete_in_each_visible_view(body, views, area_tolerance=1e-6):
    """A narrow overlap is valid. A visible text fragment is not.

    Only text must be complete. Dimension/leader lines may be clipped.
    """
    return all(v.covers(body) or v.intersection(body).area <= area_tolerance
               for v in views)


def planting_group_visibility(body, leader, views, tolerance=1e-6):
    """Shared planting labels must show the entire group in each visible view.

    This applies to the current small-sheet shrub/herb supplementation task.
    The generic text-only clipping rule remains available for other families.
    A nearby blank, GRASS or contour background is allowed. No distant leader
    is justified merely by avoiding terrain or by historical label visibility.
    """
    group=body.union(leader)
    complete=[];partial=[]
    for key,view in views.items():
        if view.buffer(tolerance).covers(group):
            complete.append(key)
        elif view.intersects(group):
            hit=view.intersection(group)
            if hit.area>tolerance or hit.length>tolerance:
                partial.append(key)
    return {"complete":complete,"partial":partial}


def planting_supplement_required(region, viewport, minimum_fraction=.25):
    """Current 1:200 shrub/herb rule; never implicitly apply to tree labels.

    Use the effective fill, including retained patch components after grouping.
    Below one quarter does not trigger a dedicated supplement. A main label
    is still required for the planting group, independently of this test.
    """
    if region.is_empty or region.area<=0:
        raise ValueError("Effective planting area is empty")
    fraction=region.intersection(viewport).area/region.area
    return fraction+1e-9>=minimum_fraction


def occupied_architecture(components, connection_gap, clearance):
    """Build separate occupied footprints from nearby architectural components.

    Supplying wall lines alone leaves rooms falsely available for annotation.
    Include windows, columns, equipment and preserved building geometry; block
    references need their transformed geometric bounds. The caller binds the
    semantic inventory and local grouping distances to the actual drawing.
    Terrain, GRASS and grid entities must never enter this component collection.
    """
    from shapely.ops import unary_union
    items=[g for g in components if not g.is_empty]
    if not items:return unary_union([])
    connected=unary_union([g.buffer(connection_gap/2) for g in items])
    groups=list(connected.geoms) if hasattr(connected,"geoms") else [connected]
    return unary_union([
        unary_union([g for g in items if group.intersects(g)]).convex_hull.buffer(clearance)
        for group in groups
    ])
