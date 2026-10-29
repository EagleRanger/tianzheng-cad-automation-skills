#!/usr/bin/env python3
"""Extract the dominant black CAD drawing canvas from a full window capture.

The Tianzheng/AutoCAD window may include ribbons, palettes and status bars.
Raster annotation QA must not analyse those UI regions as drawing text.  This
tool finds the longest row/column runs dominated by the black model-space
background and emits one bounded canvas image plus a hash-bound receipt.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def longest_run(indexes: Iterable[int]) -> tuple[int, int] | None:
    values = list(indexes)
    if not values:
        return None
    best = (values[0], values[0])
    start = previous = values[0]
    for value in values[1:]:
        if value != previous + 1:
            if previous - start > best[1] - best[0]:
                best = (start, previous)
            start = value
        previous = value
    if previous - start > best[1] - best[0]:
        best = (start, previous)
    return best


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--dark-maximum", type=int, default=24)
    parser.add_argument("--dominance", type=float, default=0.55)
    parser.add_argument("--minimum-width", type=int, default=640)
    parser.add_argument("--minimum-height", type=int, default=360)
    args = parser.parse_args()

    source = Image.open(args.image).convert("RGB")
    rgb = np.asarray(source)
    dark = rgb.max(axis=2) <= args.dark_maximum

    row_run = longest_run(np.flatnonzero(dark.mean(axis=1) >= args.dominance))
    if row_run is None:
        raise SystemExit("CAD_CANVAS_ROW_RUN_NOT_FOUND")
    y0, y1 = (int(row_run[0]), int(row_run[1]))

    # Derive columns only from the accepted row band. This avoids a dark ribbon
    # above the canvas widening the ROI into palettes or navigation controls.
    column_run = longest_run(np.flatnonzero(dark[y0 : y1 + 1, :].mean(axis=0) >= args.dominance))
    if column_run is None:
        raise SystemExit("CAD_CANVAS_COLUMN_RUN_NOT_FOUND")
    x0, x1 = (int(column_run[0]), int(column_run[1]))

    width = x1 - x0 + 1
    height = y1 - y0 + 1
    if width < args.minimum_width or height < args.minimum_height:
        raise SystemExit(f"CAD_CANVAS_ROI_TOO_SMALL:{width}x{height}")

    canvas = source.crop((x0, y0, x1 + 1, y1 + 1))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output)
    receipt = {
        "schema_version": 1,
        "status": "PASS",
        "gate_id": "CAD_CANVAS_ROI_ISOLATION",
        "source": str(args.image.resolve()),
        "source_sha256": sha256(args.image),
        "canvas": str(args.output.resolve()),
        "canvas_sha256": sha256(args.output),
        "roi_xyxy": [x0, y0, x1 + 1, y1 + 1],
        "source_size": list(source.size),
        "canvas_size": list(canvas.size),
        "dark_maximum": args.dark_maximum,
        "dominance": args.dominance,
    }
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"status": "PASS", "canvas": str(args.output), "roi_xyxy": receipt["roi_xyxy"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
