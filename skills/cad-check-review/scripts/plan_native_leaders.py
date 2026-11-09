"""Plan a bounded array of native leader edits from one inspect receipt.

This is placement math, not engineering-source inference. The caller supplies
qualified source identities and sheet-specific sizes. Unknowns remain pending.
No CAD calls, screenshots, DWG scans, or writes occur in this module.
"""
import argparse
import json
import math
from pathlib import Path

ROLES = {"coord3-model": (0, 1, 2), "leader4-paper": (2, 0, 1), "index-paper": (2, 1, 0)}


def paper(p, vp):
    x, y = p[0] - vp["target"][0], p[1] - vp["target"][1]
    c, s = math.cos(vp["twist"]), math.sin(vp["twist"])
    return [vp["center"][0] + vp["scale"] * (c*x-s*y-vp["view_center"][0]),
            vp["center"][1] + vp["scale"] * (s*x+c*y-vp["view_center"][1]), 0]


def angle(anchor, elbow, bearing):
    u = [anchor[i]-elbow[i] for i in range(2)]
    v = [bearing[i]-elbow[i] for i in range(2)]
    den = math.hypot(*u) * math.hypot(*v)
    if den < 1e-12 or not all(math.isfinite(n) for p in (anchor, elbow, bearing) for n in p):
        raise ValueError("DEGENERATE_OR_NONFINITE")
    return math.degrees(math.acos(max(-1, min(1, sum(a*b for a, b in zip(u, v))/den))))


def inside(p, box):
    return box[0] <= p[0] <= box[2] and box[1] <= p[1] <= box[3]


def valid_box(box):
    return (len(box) == 4 and all(math.isfinite(n) for n in box)
            and box[0] <= box[2] and box[1] <= box[3])


def segment_hits_box(a, b, box):
    # Liang-Barsky, in sheet coordinates. Only explicit hard obstacles qualify.
    lo, hi = 0., 1.
    dx, dy = b[0]-a[0], b[1]-a[1]
    for p, q in ((-dx, a[0]-box[0]), (dx, box[2]-a[0]),
                 (-dy, a[1]-box[1]), (dy, box[3]-a[1])):
        if abs(p) < 1e-12:
            if q < 0: return False
        elif p < 0: lo = max(lo, q/p)
        else: hi = min(hi, q/p)
        if lo > hi: return False
    return True


def plan_one(native, request):
    source = request.get("source", {})
    state = source.get("state")
    common = {k: native[k] for k in ("handle", "rxclass", "layer", "profile")}
    common.update(viewport=native["viewport"]["handle"], expected_grips=native["grips"],
                  expected_properties=native["properties"], source=source)
    if not source.get("feature_id") or not source.get("evidence"):
        return None, "SOURCE_EVIDENCE_REQUIRED"
    if state == "cancelled":
        if request.get("operation") != "delete_cancelled": return None, "CANCELLED_DELETE_INSTRUCTION_REQUIRED"
        common["operation"] = "delete_cancelled"
        return common, None
    if state != "active": return None, "SOURCE_PENDING_BEFORE_PLACEMENT"
    tolerance = source.get("tolerance")
    if (not source.get("handle") or not source.get("layer")
            or not isinstance(tolerance, (int, float))
            or not math.isfinite(tolerance) or not 0 <= tolerance <= .1):
        return None, "QUALIFIED_SOURCE_IDENTITY_REQUIRED"
    if native["profile"] not in ROLES or not native.get("joint", {}).get("native_segments_verified"):
        return None, "NATIVE_ROLE_NOT_VERIFIED"
    if request.get("mode", "elbow") != "elbow": return None, "STRAIGHT_OR_MULTI_SOURCE_USE_TYPED_RECIPE"
    roles, vp = ROLES[native["profile"]], native["viewport"]
    p, e, b = [native["grips"][i] for i in roles]
    if native["profile"] == "coord3-model": p, e, b = [paper(q, vp) for q in (p, e, b)]
    moved = False
    if request.get("target_world") is not None:
        target = paper(request["target_world"], vp)
        moved = math.dist(p, target) > 1e-6
        if moved and native["profile"] == "coord3-model":
            return None, "COORDINATE_VALUE_CHANGE_USE_TYPED_RECIPE"
        p = target
    if native["joint"].get("status") == "PASS" and not moved and not request.get("reposition"):
        return None, "KEEP_ACCEPTED_GEOMETRY"
    # Size and allowed extents are supplied from this project's actual sample.
    lengths = request.get("leader_lengths_paper", [])
    bar = request.get("bar_length_paper", 0)
    max_leader, max_bar = request.get("max_leader_paper", 0), request.get("max_bearing_paper", 0)
    sizes = [*lengths, bar, max_leader, max_bar]
    if (not lengths or not all(math.isfinite(n) for n in sizes)
            or any(n <= 0 or n > max_leader for n in lengths) or not 0 < bar <= max_bar):
        return None, "PROJECT_SIZE_REQUIRED"
    hard = [o["box"] for o in request.get("obstacles", []) if o.get("role") == "hard"]
    bounds = request.get("allowed_sheet_box")
    if any(not valid_box(box) for box in hard) or bounds is not None and not valid_box(bounds):
        return None, "INVALID_PROJECT_BOUNDS"
    candidates = []
    for rank, slanted in enumerate((False, True) if request.get("allow_obtuse_fallback") else (False,)):
        for length in lengths:
            for vertical in (-1, 1):
                for side in (-1, 1):
                    diagonal = length/math.sqrt(2) if slanted else 0
                    ee = [p[0]+side*diagonal, p[1]+vertical*(diagonal if slanted else length), 0]
                    bb = [ee[0]+side*bar, ee[1], 0]
                    deg = angle(p, ee, bb)
                    if not 90-1e-6 <= deg < 180-1e-6: continue
                    if bounds and not all(inside(q, bounds) for q in (ee, bb)): continue
                    if any(segment_hits_box(p, ee, box) or segment_hits_box(ee, bb, box) for box in hard): continue
                    # Near placement first within the preferred 90-degree family.
                    cost = math.dist(ee, e) + math.dist(bb, b)
                    candidates.append((rank, cost, ee, bb, deg))
    if not candidates: return None, "NO_BOUNDED_CANDIDATE"
    _, _, ee, bb, deg = min(candidates, key=lambda x: (x[0], x[1]))
    common.update(elbow_paper=ee, bearing_paper=bb, max_anchor_move=request.get("max_anchor_move", 0),
                  max_leader_paper=max_leader, max_bearing_paper=max_bar, planned_angle=deg)
    if "target_world" in request: common["target_world"] = request["target_world"]
    return common, None


def build(receipt, requests, job_id, mode):
    by_handle = {r["handle"].upper(): r.get("native") for r in receipt["rows"] if r.get("native")}
    actions, pending, keep = [], [], []
    for req in requests:
        h = str(req.get("handle", "")).upper() if isinstance(req, dict) else ""
        if h not in by_handle: pending.append({"handle": h, "reason": "MISSING_INSPECTED_OBJECT"}); continue
        try:
            action, reason = plan_one(by_handle[h], req)
        except (KeyError, TypeError, ValueError, IndexError, OverflowError) as exc:
            pending.append({"handle": h, "reason": "INVALID_LOCAL_INPUT", "detail": str(exc)})
            continue
        if action: actions.append(action)
        elif reason == "KEEP_ACCEPTED_GEOMETRY": keep.append(h)
        else: pending.append({"handle": h, "reason": reason})
    return {"job_id": job_id, "document": receipt["document"], "host_pid": receipt["host_pid"],
            "mode": mode, "actions": actions, "pending": pending, "unchanged": keep}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("inspect"); parser.add_argument("requests"); parser.add_argument("output")
    parser.add_argument("--job-id", required=True); parser.add_argument("--mode", choices=["probe", "apply"], default="probe")
    args = parser.parse_args()
    result = build(json.loads(Path(args.inspect).read_text(encoding="utf-8-sig")),
                   json.loads(Path(args.requests).read_text(encoding="utf-8-sig")), args.job_id, args.mode)
    output = Path(args.output)
    with output.open("x", encoding="utf-8") as f: json.dump(result, f, ensure_ascii=False, indent=2)
    print(json.dumps({"planned": len(result["actions"]), "pending": result["pending"], "unchanged": result["unchanged"]}, ensure_ascii=False))
