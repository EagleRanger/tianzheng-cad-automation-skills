"""Resolve existing CAD experience by object/work stage. Read-only; no CAD calls."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[2]
INDEX_PATH = Path(__file__).resolve().parents[1] / "references/cad-method-index.json"


def expand_path(value, index, skill_root=SKILL_ROOT):
    if value.startswith("@skills/"):
        return skill_root / value[len("@skills/"):]
    if value.startswith("@library/"):
        return expand_path(index["library_root"], index, skill_root) / value[len("@library/"):]
    return Path(value)


def match_modules(index, query):
    query = query.strip().casefold()
    ranked = []
    for key, item in index["modules"].items():
        hits = [tag for tag in item["tags"] if tag.casefold() in query]
        score = sum(len(tag) for tag in hits)
        if score:
            ranked.append((score, key, hits))
    ranked.sort(key=lambda row: (-row[0], row[1]))
    return [{"module": key, "score": score, "matched_terms": hits}
            for score, key, hits in ranked]


def resolve_module(index, key, skill_root=SKILL_ROOT):
    item = index["modules"][key]
    skill = expand_path(item["skill"], index, skill_root)
    sources = []
    for record in item.get("sources", []):
        path = expand_path(record["path"], index, skill_root)
        sources.append({**record, "path": str(path), "exists": path.is_file()})
    implementations = []
    for record in item.get("implementations", []):
        path = expand_path(record["path"], index, skill_root)
        implementations.append({**record, "path": str(path), "exists": path.is_file(),
                                "direct_execution_allowed": False})
    missing = ([str(skill)] if not skill.is_file() else []) + [
        row["path"] for row in sources + implementations if not row["exists"]]
    return {
        "module": key, "label": item["label"],
        "status": "READ_REQUIRED" if not missing else "METHOD_PATH_GAPS",
        "skill_path": str(skill), "sources": sources, "implementations": implementations,
        "required_current_facts": item["required_current_facts"],
        "acceptance": item["acceptance"], "missing_paths": missing,
        "runtime_authorization": False, "current_drawing_accepted": False,
    }


def workflow(index):
    """Dependencies are a method map, not a second completion/scheduling ledger."""
    modules = index["modules"]
    result = []
    for stage in index["workflow"]:
        for key in stage["modules"]:
            if key not in modules:
                raise ValueError("Unknown module in workflow: " + key)
        result.append({**stage, "labels": [modules[k]["label"] for k in stage["modules"]]})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--module", help="Stable module id from --workflow")
    mode.add_argument("--query", help="Object/task words; ambiguous results are returned, not executed")
    mode.add_argument("--workflow", action="store_true", help="Show full drawing stages and reuse routes")
    args = parser.parse_args()
    index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    identity = {"index_path": str(INDEX_PATH),
                "index_sha256": hashlib.sha256(INDEX_PATH.read_bytes()).hexdigest(),
                "read_only": True, "grants_runtime_authority": False}
    if args.workflow:
        result = {**identity, "status": "WORKFLOW_MAP", "stages": workflow(index)}
    elif args.module:
        if args.module not in index["modules"]:
            parser.error("Unknown module; use --workflow for stable ids")
        result = {**identity, **resolve_module(index, args.module)}
    else:
        matches = match_modules(index, args.query)
        result = {**identity, "status": "MATCHES_REQUIRE_OBJECT_CHECK" if matches else "NO_MATCH",
                  "query": args.query, "matches": matches[:5],
                  "routes": [resolve_module(index, row["module"]) for row in matches[:3]],
                  "next": "Read matched current Skill/sections and verify real object/type. No match is not no experience; use existing project CAD recall. Never replay historical jobs."}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
