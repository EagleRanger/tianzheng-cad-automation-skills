"""Read-only, dependency-free tree-chain checks; never opens or writes CAD.

The caller supplies verified world-space symbol centres, independently sourced
expected quantities (never len of the tested members), and project tolerances.
This validates those inputs, not their provenance or full visual layout.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

RULESET = "tree-centres-and-ends-20261101"
CENTER_BASES = {
    "native_symbol_center",
    "validated_block_basepoint",
    "transformed_native_crown_center",
}


def _point(value):
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        raise ValueError("Expected a world-XY pair")
    if any(isinstance(x, bool) or not isinstance(x, (int, float)) for x in value):
        raise ValueError("Non-numeric coordinate")
    if not all(math.isfinite(x) for x in value):
        raise ValueError("Non-finite coordinate")
    return tuple(value)


def audit_group(row, geometry_tolerance, angle_tolerance_degrees, allowed_elbow_degrees):
    errors, holds = [], []
    result = {"id": row.get("id"), "status": "HOLD", "errors": errors, "holds": holds}
    if row.get("status") == "hold":
        holds.append(row.get("reason") or "UNSPECIFIED_LOCAL_HOLD")
        return result
    if not row.get("id"):
        errors.append("MISSING_GROUP_ID")
    try:
        members = row["members"]
        if not isinstance(members, list) or not members:
            raise ValueError("No members")
        ids = [m["id"] for m in members]
        if any(not isinstance(x, str) or not x for x in ids) or len(set(ids)) != len(ids):
            errors.append("DUPLICATE_OR_INVALID_MEMBER_ID")
        centres = [_point(m["center"]) for m in members]
        if any(m.get("center_basis") not in CENTER_BASES for m in members):
            holds.append("UNVERIFIED_SYMBOL_CENTER_BASIS")
        chain = [_point(p) for p in row["chain"]]
        external = [_point(p) for p in row["external"]]
        if not chain:
            raise ValueError("Empty chain")
    except (KeyError, TypeError, ValueError) as exc:
        errors.append("MALFORMED_GEOMETRY:" + str(exc))
        result["status"] = "FAIL"
        return result
    quantity = row.get("quantity")
    if quantity is None:
        holds.append("GROUP_QUANTITY_UNRESOLVED")
    elif isinstance(quantity, bool) or not isinstance(quantity, int) or quantity != len(ids):
        errors.append("QUANTITY_MEMBER_MISMATCH")

    # Resolve every actual vertex to a unique verified member centre. A point
    # inside a canopy or a bbox is not a centre, nor an excuse for extra tails.
    assignments = []
    for i, point in enumerate(chain):
        hits = [j for j, centre in enumerate(centres)
                if math.dist(point, centre) <= geometry_tolerance]
        if not hits:
            errors.append(f"CHAIN_VERTEX_NOT_MEMBER_CENTER:{i}")
        elif len(hits) != 1:
            holds.append(f"AMBIGUOUS_MEMBER_CENTER:{i}")
        else:
            assignments.append(hits[0])
    if len(assignments) != len(set(assignments)):
        errors.append("REPEATED_MEMBER_IN_CHAIN")
    for i in range(len(members)):
        if i not in assignments:
            errors.append("MEMBER_CENTER_MISSING:" + str(ids[i]))
    if len(chain) != len(members):
        errors.append("CHAIN_VERTEX_MEMBER_COUNT_MISMATCH")

    if len(external) != 3:
        holds.append("UNSUPPORTED_EXTERNAL_TOPOLOGY")
    else:
        anchor, bend, end = external
        if min(math.dist(anchor, chain[0]), math.dist(anchor, chain[-1])) > geometry_tolerance:
            errors.append("EXTERNAL_ANCHOR_NOT_GROUP_ENDPOINT")
        first, second = math.dist(anchor, bend), math.dist(bend, end)
        if min(first, second) <= geometry_tolerance:
            errors.append("DEGENERATE_EXTERNAL")
        else:
            v = (anchor[0] - bend[0], anchor[1] - bend[1])
            w = (end[0] - bend[0], end[1] - bend[1])
            cosine = max(-1.0, min(1.0, (v[0] * w[0] + v[1] * w[1]) / (first * second)))
            angle = math.degrees(math.acos(cosine))
            result["actual_elbow_degrees"] = angle
            if not any(abs(angle - permitted) <= angle_tolerance_degrees
                       for permitted in allowed_elbow_degrees):
                errors.append("EXTERNAL_ELBOW_NOT_PERMITTED")
    result["status"] = "FAIL" if errors else "HOLD" if holds else "PASS"
    return result


def audit_bindings(bindings):
    """Verify an existing receipt once per revision; does not prove invocation."""
    issues = []
    for item in bindings:
        path = Path(item["path"])
        expected = item.get("sha256", "").lower()
        if len(expected) != 64 or any(c not in "0123456789abcdef" for c in expected):
            issues.append({"path": str(path), "error": "INVALID_EXPECTED_HASH"})
            continue
        if not path.is_file():
            issues.append({"path": str(path), "error": "BINDING_FILE_MISSING"})
            continue
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected:
            issues.append({"path": str(path), "error": "BINDING_HASH_CHANGED",
                           "expected": expected, "actual": digest.hexdigest()})
    return issues


def audit_batch(plan):
    tolerance = plan["geometry_tolerance"]
    angular = plan["angle_tolerance_degrees"]
    allowed = plan["allowed_elbow_degrees"]
    if (isinstance(tolerance, bool) or not isinstance(tolerance, (int, float))
            or not math.isfinite(tolerance) or tolerance <= 0):
        raise ValueError("Project geometry_tolerance must be a positive finite value")
    if (isinstance(angular, bool) or not isinstance(angular, (int, float))
            or not math.isfinite(angular) or angular < 0):
        raise ValueError("Invalid angle_tolerance_degrees")
    if not allowed or any(isinstance(x, bool) or not isinstance(x, (int, float))
                          or not math.isfinite(x) or x <= 0 or x > 180 for x in allowed):
        raise ValueError("Invalid project allowed_elbow_degrees")
    rows = plan["tree_groups"]
    if not isinstance(rows, list):
        raise ValueError("tree_groups must be an array")
    ids = [r.get("id") for r in rows]
    if any(not isinstance(x, str) or not x for x in ids) or len(ids) != len(set(ids)):
        raise ValueError("Each group requires a unique stable id")
    checks = [audit_group(r, tolerance, angular, allowed) for r in rows]
    ready = [r["id"] for r in checks if r["status"] == "PASS"]
    held = [r["id"] for r in checks if r["status"] == "HOLD"]
    failed = [r["id"] for r in checks if r["status"] == "FAIL"]
    status = "READY" if checks and len(ready) == len(checks) else "PARTIAL" if ready else "BLOCKED"
    return {"ruleset": RULESET, "status": status, "ready_ids": ready,
            "hold_ids": held, "failed_ids": failed, "checks": checks,
            "visual_and_native_provenance_accepted": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plan", type=Path, help="Existing job adapted to tree_groups")
    args = parser.parse_args()
    result = audit_batch(json.loads(args.plan.read_text(encoding="utf-8-sig")))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return {"READY": 0, "PARTIAL": 2, "BLOCKED": 3}[result["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
