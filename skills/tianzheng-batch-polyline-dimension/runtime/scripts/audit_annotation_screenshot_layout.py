#!/usr/bin/env python3
"""Deterministic first-pass QA for isolated CAD annotation screenshots.

This gate deliberately detects only observable raster symptoms: missing colour
layers, white annotation ink touching the thick blue source, dense local text
hotspots, and extreme offset dispersion.  It does not claim to understand a
Tianzheng object or to replace a Codex visual review and E5 native-object audit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections import deque
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def component_boxes(mask: np.ndarray, minimum_pixels: int = 5) -> list[dict[str, int]]:
    height, width = mask.shape
    visited = np.zeros_like(mask, dtype=np.bool_)
    result: list[dict[str, int]] = []
    for y, x in zip(*np.nonzero(mask & ~visited)):
        if visited[y, x]:
            continue
        queue: deque[tuple[int, int]] = deque([(int(y), int(x))])
        visited[y, x] = True
        count = 0
        min_x = max_x = int(x)
        min_y = max_y = int(y)
        while queue:
            cy, cx = queue.popleft()
            count += 1
            min_x = min(min_x, cx)
            max_x = max(max_x, cx)
            min_y = min(min_y, cy)
            max_y = max(max_y, cy)
            for ny in range(max(0, cy - 1), min(height, cy + 2)):
                for nx in range(max(0, cx - 1), min(width, cx + 2)):
                    if not visited[ny, nx] and mask[ny, nx]:
                        visited[ny, nx] = True
                        queue.append((ny, nx))
        if count >= minimum_pixels:
            result.append(
                {
                    "x0": min_x,
                    "y0": min_y,
                    "x1": max_x + 1,
                    "y1": max_y + 1,
                    "pixels": count,
                }
            )
    return result


def distance_box_to_points(box: dict[str, int], points_xy: np.ndarray) -> float:
    if points_xy.size == 0:
        return math.inf
    x = points_xy[:, 0]
    y = points_xy[:, 1]
    dx = np.maximum(np.maximum(box["x0"] - x, 0), x - (box["x1"] - 1))
    dy = np.maximum(np.maximum(box["y0"] - y, 0), y - (box["y1"] - 1))
    return float(np.sqrt(dx * dx + dy * dy).min())


def hotspot_windows(mask: np.ndarray, window: int, stride: int) -> list[dict[str, float]]:
    h, w = mask.shape
    if h < window or w < window:
        return []
    integral = np.pad(mask.astype(np.int64).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    found: list[dict[str, float]] = []
    for y in range(0, h - window + 1, stride):
        y2 = y + window
        for x in range(0, w - window + 1, stride):
            x2 = x + window
            ink = integral[y2, x2] - integral[y, x2] - integral[y2, x] + integral[y, x]
            found.append({"x0": x, "y0": y, "x1": x2, "y1": y2, "ink_ratio": float(ink) / (window * window)})
    return sorted(found, key=lambda item: item["ink_ratio"], reverse=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--overlay", type=Path)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--text-height-px", type=float, default=0.0)
    args = parser.parse_args()

    profile = read_json(args.profile)
    if profile.get("schema_version") != 1:
        raise SystemExit("VISUAL_QA_PROFILE_SCHEMA_UNSUPPORTED")

    original = Image.open(args.image).convert("RGB")
    scale = min(1.0, float(profile["max_analysis_dimension"]) / max(original.size))
    analysis = original if scale == 1.0 else original.resize(
        (max(1, round(original.width * scale)), max(1, round(original.height * scale))),
        Image.Resampling.BOX,
    )
    rgb = np.asarray(analysis, dtype=np.int16)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mask_cfg = profile["mask"]
    blue = (b >= mask_cfg["blue_min"]) & (b - r >= mask_cfg["blue_dominance"]) & (b - g >= mask_cfg["blue_dominance"])
    green = (g >= mask_cfg["green_min"]) & (g - r >= mask_cfg["green_dominance"]) & (g - b >= mask_cfg["green_dominance"])
    chroma = rgb.max(axis=2) - rgb.min(axis=2)
    white = (rgb.min(axis=2) >= mask_cfg["white_min"]) & (chroma <= mask_cfg["white_chroma_max"])

    ignored_regions: list[dict[str, int]] = []
    for region in profile.get("ignored_regions_normalized", []):
        if len(region) != 4:
            raise SystemExit("VISUAL_QA_IGNORED_REGION_INVALID")
        x0 = max(0, min(analysis.width, int(round(float(region[0]) * analysis.width))))
        y0 = max(0, min(analysis.height, int(round(float(region[1]) * analysis.height))))
        x1 = max(x0, min(analysis.width, int(round(float(region[2]) * analysis.width))))
        y1 = max(y0, min(analysis.height, int(round(float(region[3]) * analysis.height))))
        blue[y0:y1, x0:x1] = False
        green[y0:y1, x0:x1] = False
        white[y0:y1, x0:x1] = False
        ignored_regions.append({"x0": x0, "y0": y0, "x1": x1, "y1": y1})

    text_h = args.text_height_px * scale if args.text_height_px > 0 else float(profile["default_text_height_px"]) * scale
    text_h = max(6.0, text_h)
    grouping = max(3, int(round(text_h * 0.16)))
    if grouping % 2 == 0:
        grouping += 1
    grouped_white = np.asarray(
        Image.fromarray((white * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(grouping))
    ) > 0
    boxes = component_boxes(grouped_white, minimum_pixels=max(5, int(text_h * 0.25)))

    blue_yx = np.column_stack(np.nonzero(blue))
    if len(blue_yx) > 12000:
        blue_yx = blue_yx[:: max(1, len(blue_yx) // 12000)]
    blue_xy = blue_yx[:, ::-1].astype(np.float64) if len(blue_yx) else np.empty((0, 2))
    clearances = [distance_box_to_points(box, blue_xy) / text_h for box in boxes]
    threshold = profile["thresholds"]
    near_indices = [index for index, value in enumerate(clearances) if value < threshold["minimum_text_source_clearance_h"]]

    finite = np.asarray([value for value in clearances if math.isfinite(value)], dtype=float)
    median = float(np.median(finite)) if finite.size else None
    mad = float(np.median(np.abs(finite - median))) if finite.size else None
    window = max(12, int(round(text_h * threshold["hotspot_window_h"])))
    stride = max(4, int(round(text_h * threshold["hotspot_stride_h"])))
    hotspots = hotspot_windows(white, min(window, analysis.width, analysis.height), stride)
    top_hotspots = hotspots[:5]
    max_hotspot = top_hotspots[0]["ink_ratio"] if top_hotspots else 0.0

    counts = {
        "blue_pixels": int(blue.sum()),
        "green_pixels": int(green.sum()),
        "white_pixels": int(white.sum()),
        "grouped_text_components": len(boxes),
    }
    reasons: list[str] = []
    if counts["blue_pixels"] < threshold["minimum_blue_pixels"]:
        reasons.append("BLUE_SOURCE_MASK_INSUFFICIENT_OR_SCREENSHOT_NOT_ISOLATED")
    if counts["green_pixels"] < threshold["minimum_green_pixels"]:
        reasons.append("GREEN_DIMENSION_MASK_INSUFFICIENT_OR_SCREENSHOT_NOT_ISOLATED")
    if counts["white_pixels"] < threshold["minimum_white_pixels"]:
        reasons.append("WHITE_TEXT_MASK_INSUFFICIENT_OR_SCREENSHOT_NOT_ISOLATED")
    if len(near_indices) > threshold["maximum_near_source_components"]:
        reasons.append("TEXT_TOUCHES_OR_CROSSES_BLUE_SOURCE")
    if max_hotspot > threshold["maximum_hotspot_ink_ratio"]:
        reasons.append("LOCAL_TEXT_INK_HOTSPOT")
    if mad is not None and mad > threshold["maximum_offset_mad_h"]:
        reasons.append("OFFSET_DISPERSION_EXCEEDS_PROFILE")

    status = "FAIL" if reasons else "REVIEW_REQUIRED"
    report: dict[str, Any] = {
        "schema_version": 1,
        "status": status,
        "gate_id": "SCREENSHOT_RASTER_QA",
        "image": str(args.image.resolve()),
        "image_sha256": sha256(args.image),
        "profile": str(args.profile.resolve()),
        "profile_id": profile["profile_id"],
        "analysis_scale": scale,
        "text_height_px_used": text_h / scale,
        "counts": counts,
        "metrics": {
            "near_source_component_count": len(near_indices),
            "text_source_clearance_median_h": median,
            "text_source_clearance_mad_h": mad,
            "maximum_hotspot_ink_ratio": max_hotspot,
        },
        "reason_codes": reasons,
        "near_source_boxes": [boxes[index] for index in near_indices],
        "hotspots": top_hotspots,
        "limits": threshold,
        "ignored_regions": ignored_regions,
        "boundary": "Deterministic raster triage only. CODEX_VISUAL_REVIEW and native E5 remain mandatory.",
    }
    if args.reference:
        report["reference"] = {"path": str(args.reference.resolve()), "sha256": sha256(args.reference)}

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if args.overlay:
        overlay = analysis.copy()
        draw = ImageDraw.Draw(overlay)
        for index in near_indices:
            box = boxes[index]
            draw.rectangle((box["x0"], box["y0"], box["x1"], box["y1"]), outline=(255, 0, 0), width=3)
        for hotspot in top_hotspots:
            if hotspot["ink_ratio"] > threshold["maximum_hotspot_ink_ratio"]:
                draw.rectangle((hotspot["x0"], hotspot["y0"], hotspot["x1"], hotspot["y1"]), outline=(255, 165, 0), width=2)
        if scale != 1.0:
            overlay = overlay.resize(original.size, Image.Resampling.NEAREST)
        args.overlay.parent.mkdir(parents=True, exist_ok=True)
        overlay.save(args.overlay)

    print(json.dumps({"status": status, "output": str(args.output), "reason_codes": reasons}, ensure_ascii=False))
    return 0 if status == "REVIEW_REQUIRED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
