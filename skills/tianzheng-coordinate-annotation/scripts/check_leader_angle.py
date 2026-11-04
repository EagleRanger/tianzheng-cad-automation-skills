"""Check annotation-leader elbow rays in the actual display plane.

Inputs are projected 2D native points, not guessed bounding-box corners.
This function neither edits a drawing nor infers native grip roles.
"""
from math import acos, degrees, hypot, isfinite


def check_leader_angle(anchor, elbow, free_end, tolerance_deg=1e-6):
    """Accept a right/obtuse angle at elbow; reject acute or degenerate rays."""
    if not 0 <= tolerance_deg <= 1e-6:
        raise ValueError("tolerance is only for floating-point roundoff")
    points = [tuple(float(v) for v in p) for p in (anchor, elbow, free_end)]
    if any(len(p) != 2 or not all(isfinite(v) for v in p) for p in points):
        raise ValueError("three finite projected 2D points are required")
    p, e, t = points
    u = (p[0] - e[0], p[1] - e[1])
    v = (t[0] - e[0], t[1] - e[1])
    lu, lv = hypot(*u), hypot(*v)
    if lu == 0 or lv == 0:
        return {"ok": False, "angle_degrees": None, "reason": "zero_length_ray"}
    cosine = max(-1.0, min(1.0, (u[0]/lu)*(v[0]/lv) + (u[1]/lu)*(v[1]/lv)))
    angle = degrees(acos(cosine))
    if angle < 90.0 - tolerance_deg:
        reason = "acute_elbow"
    elif angle >= 180.0 - tolerance_deg:
        reason = "straight_degenerate"
    else:
        reason = "right_or_obtuse"
    return {"ok": reason == "right_or_obtuse", "angle_degrees": angle, "reason": reason}


def check_leader_joint(leader_segment, bearing_segment,
                       connection_tolerance=1e-6, tolerance_deg=1e-6):
    """Check two actual native segments meeting at a bearing-line endpoint.

    Each segment is its pair of projected 2D endpoints; endpoint order is
    immaterial. The caller identifies the actual leader and the text-side
    bearing segment from native topology, not a universal grip-number recipe.
    The two rays both start at their unique shared endpoint and point into
    their respective segments. No ray is extended or reversed for scoring.
    Multi-branch objects call this for each actual bearing/leader junction.
    Explicit straight 0-degree mode uses check_horizontal_leader instead.
    """
    if not 0 <= connection_tolerance <= 1e-6:
        raise ValueError("connection tolerance is only for numeric roundoff")
    segments = [tuple(tuple(float(v) for v in p) for p in s)
                for s in (leader_segment, bearing_segment)]
    if any(len(s) != 2 or any(len(p) != 2 or
                              not all(isfinite(v) for v in p) for p in s)
           for s in segments):
        raise ValueError("two finite projected 2D endpoint pairs are required")
    a, b = segments
    if any(hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]) <=
           connection_tolerance for s in segments):
        return {"ok": False, "angle_degrees": None,
                "reason": "zero_length_segment"}
    matches = [(i, j) for i in (0, 1) for j in (0, 1)
               if hypot(a[i][0] - b[j][0], a[i][1] - b[j][1]) <=
               connection_tolerance]
    if len(matches) != 1:
        return {"ok": False, "angle_degrees": None,
                "reason": ("no_shared_endpoint" if not matches else
                           "ambiguous_shared_endpoints")}
    i, j = matches[0]
    e, p, t = a[i], a[1-i], b[1-j]
    result = check_leader_angle(p, e, t, tolerance_deg)
    u = (p[0] - e[0], p[1] - e[1])
    v = (t[0] - e[0], t[1] - e[1])
    lu, lv = hypot(*u), hypot(*v)
    return {**result, "joint": e, "leader_neighbor": p,
            "bearing_neighbor": t,
            "normalized_dot": (u[0]/lu)*(v[0]/lv) +
                              (u[1]/lu)*(v[1]/lv)}


def check_horizontal_leader(points, tolerance=1e-6):
    """Check explicit 0-degree mode from ordered visible 2D line points.

    This separate straight-line mode does not relax the bent-elbow check.
    Points must follow the actual display line, with no foldback or zero leg.
    """
    if not 0 <= tolerance <= 1e-6:
        raise ValueError("tolerance is only for floating-point roundoff")
    pts = [tuple(float(v) for v in p) for p in points]
    if (len(pts) < 2 or any(len(p) != 2 or not all(isfinite(v) for v in p)
                            for p in pts)):
        raise ValueError("at least two finite projected 2D points are required")
    if max(p[1] for p in pts) - min(p[1] for p in pts) > tolerance:
        return {"ok": False, "reason": "not_horizontal"}
    dx = [b[0] - a[0] for a, b in zip(pts, pts[1:])]
    if any(abs(v) <= tolerance for v in dx):
        return {"ok": False, "reason": "zero_length_segment"}
    if any(v * dx[0] < 0 for v in dx):
        return {"ok": False, "reason": "horizontal_foldback"}
    return {"ok": True, "reason": "horizontal_straight",
            "direction": "right" if dx[0] > 0 else "left"}
