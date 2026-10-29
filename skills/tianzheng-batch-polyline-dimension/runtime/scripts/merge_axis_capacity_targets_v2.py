import argparse
import csv
import json
from pathlib import Path


def read_rows(path: Path):
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        fields = list(reader.fieldnames or [])
        rows = list(reader)
    if not fields or "HANDLE" not in fields or "GRIP_INDEX" not in fields:
        raise RuntimeError("AXIS_CAPACITY_MERGE_SCHEMA_INVALID")
    return fields, rows


def key(row):
    return row["HANDLE"].strip().upper(), int(row["GRIP_INDEX"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--capacity", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary", required=True)
    args = parser.parse_args()
    base_path, capacity_path = Path(args.base), Path(args.capacity)
    base_fields, base_rows = read_rows(base_path)
    capacity_fields, capacity_rows = read_rows(capacity_path)
    if base_fields != capacity_fields:
        raise RuntimeError("AXIS_CAPACITY_MERGE_SCHEMA_MISMATCH")
    base_map = {}
    order = []
    for row in base_rows:
        item_key = key(row)
        if item_key in base_map:
            raise RuntimeError("AXIS_CAPACITY_MERGE_BASE_DUPLICATE")
        base_map[item_key] = row
        order.append(item_key)
    replacements = []
    additions = []
    seen_capacity = set()
    for row in capacity_rows:
        item_key = key(row)
        if item_key in seen_capacity:
            raise RuntimeError("AXIS_CAPACITY_MERGE_CAPACITY_DUPLICATE")
        seen_capacity.add(item_key)
        if int(row["GRIP_INDEX"]) != 0 or row["AXIS_KIND"] != "ARC_RADIUS":
            raise RuntimeError("AXIS_CAPACITY_MERGE_CONTRACT_INVALID")
        if item_key not in base_map:
            order.append(item_key)
            additions.append(item_key[0])
        else:
            replacements.append(item_key[0])
        base_map[item_key] = row
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=base_fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(base_map[item_key] for item_key in order)
    summary = {
        "schema_version": 2,
        "status": "PASS",
        "base_target_count": len(base_rows),
        "capacity_replacement_count": len(capacity_rows),
        "capacity_override_count": len(replacements),
        "capacity_addition_count": len(additions),
        "final_target_count": len(order),
        "count_preserved": len(order) == len(base_rows),
        "unique_keys": len(base_map) == len(order),
        "replaced_handles": replacements,
        "added_handles": additions,
        "allowed_grip_indexes": [0],
    }
    Path(args.summary).write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
