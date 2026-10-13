#!/usr/bin/env python3
"""Generate guarded AutoLISP apply/audit bundles from a CAD issue JSON file."""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
from typing import Any


TARGET_FILES = (
    "apply_markup.lsp",
    "audit_markup.lsp",
    "run_apply.scr",
    "run_audit.scr",
    "normalized_config.json",
)


def fail(message: str) -> None:
    raise ValueError(message)


def finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        fail(f"{field} must be a number")
    number = float(value)
    if not math.isfinite(number):
        fail(f"{field} must be finite")
    return number


def positive_number(value: Any, field: str) -> float:
    number = finite_number(value, field)
    if number <= 0:
        fail(f"{field} must be greater than zero")
    return number


def ascii_only(value: str, field: str) -> None:
    try:
        value.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ValueError(f"{field} must use an ASCII-only runtime value") from exc


def forward_slashes(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/")


def lisp_string(value: str) -> str:
    value = value.replace("\\", "\\\\").replace('"', '\\"')
    value = value.replace("\r\n", "\\P").replace("\n", "\\P").replace("\r", "\\P")
    return f'"{value}"'


def number(value: float) -> str:
    text = format(value, ".12f").rstrip("0").rstrip(".")
    if "." not in text:
        text += ".0"
    return text


def validate_config(raw: dict[str, Any], output_dir: Path) -> dict[str, Any]:
    expected_name = str(raw.get("expected_dwg_name", "")).strip()
    if not expected_name or not expected_name.lower().endswith(".dwg"):
        fail("expected_dwg_name must be a DWG file name")
    if Path(expected_name).name != expected_name:
        fail("expected_dwg_name must not contain a directory")
    ascii_only(expected_name, "expected_dwg_name")

    runtime_raw = str(raw.get("runtime_dir", "")).strip()
    if not runtime_raw:
        fail("runtime_dir is required")
    ascii_only(runtime_raw, "runtime_dir")
    runtime_dir = Path(runtime_raw).resolve()
    if os.path.normcase(str(runtime_dir)) != os.path.normcase(str(output_dir.resolve())):
        fail("runtime_dir must resolve to --output-dir")

    layer = str(raw.get("layer", "00-自动检查")).strip()
    if not layer:
        fail("layer must not be empty")

    layer_color = int(raw.get("layer_color_aci", 1))
    if layer_color < 1 or layer_color > 255:
        fail("layer_color_aci must be between 1 and 255")
    layer_lw = int(raw.get("layer_lineweight", 70))
    text_lw = int(raw.get("text_lineweight", 18))
    polyline_width = positive_number(raw.get("polyline_width", 0.30), "polyline_width")

    raw_issues = raw.get("issues")
    if not isinstance(raw_issues, list) or not raw_issues:
        fail("issues must be a non-empty list")

    seen_ids: set[str] = set()
    issues: list[dict[str, Any]] = []
    for index, item in enumerate(raw_issues, start=1):
        if not isinstance(item, dict):
            fail(f"issues[{index}] must be an object")
        issue_id = str(item.get("id", "")).strip()
        if not issue_id:
            fail(f"issues[{index}].id is required")
        if issue_id in seen_ids:
            fail(f"duplicate issue id: {issue_id}")
        seen_ids.add(issue_id)

        status = str(item.get("status", "错误")).strip()
        text = str(item.get("text", "")).strip()
        if not status or not text:
            fail(f"issues[{index}] status and text are required")

        bbox_raw = item.get("bbox")
        if not isinstance(bbox_raw, list) or len(bbox_raw) != 4:
            fail(f"issues[{index}].bbox must contain four numbers")
        bbox = [finite_number(value, f"issues[{index}].bbox") for value in bbox_raw]
        if bbox[0] >= bbox[2] or bbox[1] >= bbox[3]:
            fail(f"issues[{index}].bbox must satisfy xmin<xmax and ymin<ymax")

        note_raw = item.get("note")
        if not isinstance(note_raw, list) or len(note_raw) != 2:
            fail(f"issues[{index}].note must contain two numbers")
        note = [finite_number(value, f"issues[{index}].note") for value in note_raw]

        issues.append(
            {
                "id": issue_id,
                "status": status,
                "bbox": bbox,
                "note": note,
                "note_width": positive_number(item.get("note_width"), f"issues[{index}].note_width"),
                "text_height": positive_number(item.get("text_height"), f"issues[{index}].text_height"),
                "text": text,
            }
        )

    return {
        "schema_version": 1,
        "expected_dwg_name": expected_name,
        "runtime_dir": forward_slashes(runtime_dir),
        "layer": layer,
        "layer_color_aci": layer_color,
        "layer_lineweight": layer_lw,
        "text_lineweight": text_lw,
        "polyline_width": polyline_width,
        "issues": issues,
    }


def balanced_lisp(source: str) -> bool:
    depth = 0
    in_string = False
    escaped = False
    in_comment = False
    for char in source:
        if in_comment:
            if char == "\n":
                in_comment = False
            continue
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == ";":
            in_comment = True
        elif char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0 and not in_string


def build_apply(config: dict[str, Any]) -> str:
    layer = lisp_string(config["layer"])
    report = lisp_string(config["runtime_dir"] + "/apply_report.tsv")
    error_log = lisp_string(config["runtime_dir"] + "/apply_error.txt")
    expected_dwg = lisp_string(config["expected_dwg_name"].upper())

    header = f'''(vl-load-com)

(setq cxcr:success nil)
(setq cxcr:layer {layer})
(setq cxcr:report {report})
(setq cxcr:error-log {error_log})
(setq cxcr:layer-color {config["layer_color_aci"]})
(setq cxcr:layer-lineweight {config["layer_lineweight"]})
(setq cxcr:text-lineweight {config["text_lineweight"]})
(setq cxcr:polyline-width {number(config["polyline_width"])})

(defun cxcr:set-code (data code value / pair)
  (setq pair (assoc code data))
  (if pair (subst (cons code value) pair data)
    (append data (list (cons code value)))))

(defun cxcr:ensure-layer (/ data)
  (setq data (tblsearch "LAYER" cxcr:layer))
  (if data
    (progn
      (setq data (cxcr:set-code data 62 cxcr:layer-color))
      (setq data (cxcr:set-code data 370 cxcr:layer-lineweight))
      (entmod data))
    (entmake
      (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
        '(100 . "AcDbLayerTableRecord") (cons 2 cxcr:layer)
        '(70 . 0) (cons 62 cxcr:layer-color) '(6 . "Continuous")
        (cons 370 cxcr:layer-lineweight)))))

(defun cxcr:handle (entity) (cdr (assoc 5 (entget entity))))

(defun cxcr:add-polyline (points closed / data point entity)
  (setq data
    (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity")
      (cons 330 (tblobjname "BLOCK" "*Model_Space"))
      (cons 8 cxcr:layer) '(67 . 0) '(410 . "Model")
      '(62 . 256) '(370 . -1) '(100 . "AcDbPolyline")
      (cons 90 (length points)) (cons 70 (if closed 1 0))
      (cons 43 cxcr:polyline-width)))
  (foreach point points (setq data (append data (list (cons 10 point)))))
  (setq entity (entmakex data))
  (if (null entity) (error "LWPOLYLINE entmakex returned nil"))
  entity)

(defun cxcr:add-rectangle (xmin ymin xmax ymax)
  (cxcr:add-polyline
    (list (list xmin ymin) (list xmax ymin) (list xmax ymax) (list xmin ymax)) T))

(defun cxcr:clamp (value low high) (max low (min high value)))

(defun cxcr:add-leader (xmin ymin xmax ymax nx ny nwidth textheight / cx sx sy ex ey elbowx)
  (setq cx (/ (+ xmin xmax) 2.0))
  (if (>= nx cx) (setq sx xmax ex nx) (setq sx xmin ex (+ nx nwidth)))
  (setq ey (- ny (* textheight 0.65))
        sy (cxcr:clamp ey ymin ymax)
        elbowx (+ sx (* 0.55 (- ex sx))))
  (cxcr:add-polyline (list (list sx sy) (list elbowx sy) (list ex ey)) nil))

(defun cxcr:add-note (nx ny width height text / entity)
  (setq entity
    (entmakex
      (list '(0 . "MTEXT") '(100 . "AcDbEntity")
        (cons 330 (tblobjname "BLOCK" "*Model_Space"))
        (cons 8 cxcr:layer) '(67 . 0) '(410 . "Model")
        '(62 . 256) (cons 370 cxcr:text-lineweight) '(100 . "AcDbMText")
        (cons 10 (list nx ny 0.0)) (cons 40 height) (cons 41 width)
        '(71 . 1) (cons 1 text) (cons 7 (getvar "TEXTSTYLE")))))
  (if (null entity) (error "MTEXT entmakex returned nil"))
  entity)

(defun cxcr:write-row (stream values / row value)
  (setq row "")
  (foreach value values
    (setq row (strcat row (if (= row "") "" (chr 9))
      (if value (vl-princ-to-string value) ""))))
  (write-line row stream))

(defun cxcr:mark (stream id xmin ymin xmax ymax nx ny width height text / rect leader note)
  (setq rect (cxcr:add-rectangle xmin ymin xmax ymax)
        leader (cxcr:add-leader xmin ymin xmax ymax nx ny width height)
        note (cxcr:add-note nx ny width height text))
  (cxcr:write-row stream
    (list id (cxcr:handle rect) (cxcr:handle leader) (cxcr:handle note) text)))

(defun c:CXCADCHECKAPPLY (/ *error* old-error old-layer old-cmdecho old-lwdisplay stream error-stream existing)
  (setq cxcr:success nil
        old-error *error* old-layer (getvar "CLAYER")
        old-cmdecho (getvar "CMDECHO") old-lwdisplay (getvar "LWDISPLAY"))
  (defun *error* (message)
    (if stream (progn (close stream) (setq stream nil)))
    (setq error-stream (open cxcr:error-log "w"))
    (write-line (strcat "ERROR=" message) error-stream)
    (write-line (strcat "DWG=" (getvar "DWGNAME")) error-stream)
    (close error-stream)
    (setvar "CMDECHO" old-cmdecho)
    (setvar "LWDISPLAY" old-lwdisplay)
    (if (tblsearch "LAYER" old-layer) (setvar "CLAYER" old-layer))
    (setq *error* old-error cxcr:success nil)
    (princ (strcat "\\nCX_CAD_CHECK_ERROR: " message)) (princ))

  (if (/= (strcase (getvar "DWGNAME")) {expected_dwg})
    (*error* "unexpected active DWG; isolated runtime copy required")
    (progn
      (setvar "CMDECHO" 0) (setvar "TILEMODE" 1)
      (setq existing (ssget "_X" (list (cons 8 cxcr:layer))))
      (if existing
        (*error* "target review layer already contains objects; use a clean copy")
        (progn
          (cxcr:ensure-layer) (setvar "CLAYER" cxcr:layer) (setvar "LWDISPLAY" 1)
          (setq stream (open cxcr:report "w"))
          (cxcr:write-row stream '("ISSUE_ID" "RECT_HANDLE" "LEADER_HANDLE" "TEXT_HANDLE" "TEXT"))
'''

    marks: list[str] = []
    for issue in config["issues"]:
        xmin, ymin, xmax, ymax = issue["bbox"]
        nx, ny = issue["note"]
        label = f'[{issue["id"]}] {issue["status"]}：{issue["text"]}'
        marks.append(
            "          (cxcr:mark stream "
            + " ".join(
                [
                    lisp_string(issue["id"]),
                    number(xmin),
                    number(ymin),
                    number(xmax),
                    number(ymax),
                    number(nx),
                    number(ny),
                    number(issue["note_width"]),
                    number(issue["text_height"]),
                    lisp_string(label),
                ]
            )
            + ")"
        )

    footer = f'''
          (close stream) (setq stream nil)
          (command "_.REGEN")
          (setvar "CMDECHO" old-cmdecho)
          (setq *error* old-error cxcr:success T)
          (princ "\\nCX_CAD_CHECK_APPLY_OK") (princ))))))

(defun c:CXCADCHECKFINALIZE ()
  (if cxcr:success
    (progn (command "_.QSAVE") (command "_.QUIT"))
    (command "_.QUIT" "_N"))
  (princ))

(princ)
'''
    return header + "\n".join(marks) + footer


def build_audit(config: dict[str, Any]) -> str:
    layer = lisp_string(config["layer"])
    report = lisp_string(config["runtime_dir"] + "/audit_objects.tsv")
    summary = lisp_string(config["runtime_dir"] + "/audit_summary.txt")
    ids = " ".join(lisp_string(issue["id"]) for issue in config["issues"])
    count = len(config["issues"])
    total = count * 3
    polyline_count = count * 2

    return f'''(setq cxca:layer {layer})
(setq cxca:report {report})
(setq cxca:summary {summary})
(setq cxca:expected-ids '({ids}))
(setq cxca:expected-issues {count})
(setq cxca:expected-total {total})
(setq cxca:layer-color {config["layer_color_aci"]})
(setq cxca:layer-lineweight {config["layer_lineweight"]})
(setq cxca:text-lineweight {config["text_lineweight"]})

(defun cxca:clean (value / text)
  (setq text (if value (vl-princ-to-string value) ""))
  (vl-string-translate (strcat (chr 9) (chr 10) (chr 13)) "   " text))

(defun cxca:row (stream values / row value)
  (setq row "")
  (foreach value values
    (setq row (strcat row (if (= row "") "" (chr 9))
      (if (numberp value) (rtos value 2 6) (cxca:clean value)))))
  (write-line row stream))

(defun c:CXCADCHECKAUDIT (/ layer-entity layer-data layer-color layer-lw selection index entity data
  type flags space text stream summary total rects leaders notes other bylayer-color bylayer-lw
  modelspace-count text-lw-count found-ids issue-id dbmod-before dbmod-after pass)
  (setq dbmod-before (getvar "DBMOD") total 0 rects 0 leaders 0 notes 0 other 0
        bylayer-color 0 bylayer-lw 0 modelspace-count 0 text-lw-count 0 found-ids nil
        layer-entity (tblobjname "LAYER" cxca:layer)
        layer-data (if layer-entity (entget layer-entity) nil))
  (if (null layer-data)
    (progn
      (setq summary (open cxca:summary "w"))
      (write-line "PASS=NO" summary) (write-line "REASON=LAYER_MISSING" summary)
      (close summary))
    (progn
      (setq layer-color (abs (cdr (assoc 62 layer-data)))
            layer-lw (cdr (assoc 370 layer-data))
            selection (ssget "_X" (list (cons 8 cxca:layer)))
            stream (open cxca:report "w"))
      (cxca:row stream '("HANDLE" "TYPE" "LAYER" "SPACE" "COLOR" "LINEWEIGHT" "FLAGS" "X" "Y" "TEXT"))
      (if selection
        (progn
          (setq index 0)
          (repeat (sslength selection)
            (setq entity (ssname selection index) data (entget entity)
                  type (cdr (assoc 0 data))
                  space (if (assoc 410 data) (cdr (assoc 410 data)) "")
                  flags (if (assoc 70 data) (cdr (assoc 70 data)) 0)
                  text (if (assoc 1 data) (cdr (assoc 1 data)) "")
                  total (1+ total))
            (if (= (strcase space) "MODEL") (setq modelspace-count (1+ modelspace-count)))
            (if (or (null (assoc 62 data)) (= 256 (cdr (assoc 62 data))))
              (setq bylayer-color (1+ bylayer-color)))
            (if (or (null (assoc 370 data)) (= -1 (cdr (assoc 370 data))))
              (setq bylayer-lw (1+ bylayer-lw)))
            (cond
              ((= type "MTEXT")
                (setq notes (1+ notes))
                (if (and (assoc 370 data) (= cxca:text-lineweight (cdr (assoc 370 data))))
                  (setq text-lw-count (1+ text-lw-count)))
                (foreach issue-id cxca:expected-ids
                  (if (and (vl-string-search (strcat "[" issue-id "]") text)
                           (not (member issue-id found-ids)))
                    (setq found-ids (cons issue-id found-ids)))))
              ((and (= type "LWPOLYLINE") (= 1 (logand flags 1))) (setq rects (1+ rects)))
              ((= type "LWPOLYLINE") (setq leaders (1+ leaders)))
              (T (setq other (1+ other))))
            (cxca:row stream
              (list (cdr (assoc 5 data)) type (cdr (assoc 8 data)) space
                (if (assoc 62 data) (cdr (assoc 62 data)) 256)
                (if (assoc 370 data) (cdr (assoc 370 data)) -1) flags
                (if (assoc 10 data) (car (cdr (assoc 10 data))) "")
                (if (assoc 10 data) (cadr (cdr (assoc 10 data))) "") text))
            (setq index (1+ index)))))
      (close stream)
      (setq dbmod-after (getvar "DBMOD")
            pass (and (= layer-color cxca:layer-color) (= layer-lw cxca:layer-lineweight)
              (= total cxca:expected-total) (= rects cxca:expected-issues)
              (= leaders cxca:expected-issues) (= notes cxca:expected-issues) (= other 0)
              (= bylayer-color cxca:expected-total) (= bylayer-lw {polyline_count})
              (= text-lw-count cxca:expected-issues) (= modelspace-count cxca:expected-total)
              (= (length found-ids) cxca:expected-issues)
              (= dbmod-before 0) (= dbmod-after 0))
            summary (open cxca:summary "w"))
      (write-line (strcat "DWG=" (getvar "DWGNAME")) summary)
      (write-line (strcat "LAYER=" cxca:layer) summary)
      (write-line (strcat "LAYER_COLOR=" (itoa layer-color)) summary)
      (write-line (strcat "LAYER_LINEWEIGHT=" (itoa layer-lw)) summary)
      (write-line (strcat "TOTAL=" (itoa total)) summary)
      (write-line (strcat "RECTANGLES=" (itoa rects)) summary)
      (write-line (strcat "LEADERS=" (itoa leaders)) summary)
      (write-line (strcat "NOTES=" (itoa notes)) summary)
      (write-line (strcat "OTHER=" (itoa other)) summary)
      (write-line (strcat "BYLAYER_COLOR_OBJECTS=" (itoa bylayer-color)) summary)
      (write-line (strcat "BYLAYER_LINEWEIGHT_OBJECTS=" (itoa bylayer-lw)) summary)
      (write-line (strcat "TEXT_LINEWEIGHT_OBJECTS=" (itoa text-lw-count)) summary)
      (write-line (strcat "MODELSPACE_OBJECTS=" (itoa modelspace-count)) summary)
      (write-line (strcat "ISSUE_IDS_FOUND=" (itoa (length found-ids))) summary)
      (write-line (strcat "DBMOD_BEFORE=" (itoa dbmod-before)) summary)
      (write-line (strcat "DBMOD_AFTER=" (itoa dbmod-after)) summary)
      (write-line (strcat "PASS=" (if pass "YES" "NO")) summary)
      (close summary)))
  (princ))

(princ)
'''


def write_bundle(config: dict[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    existing = [name for name in TARGET_FILES if (output_dir / name).exists()]
    if existing:
        fail("refusing to overwrite generated files: " + ", ".join(existing))

    apply_lisp = build_apply(config)
    audit_lisp = build_audit(config)
    if not balanced_lisp(apply_lisp):
        fail("generated apply_markup.lsp has unbalanced parentheses")
    if not balanced_lisp(audit_lisp):
        fail("generated audit_markup.lsp has unbalanced parentheses")

    runtime = config["runtime_dir"]
    run_apply = (
        f'(load "{runtime}/apply_markup.lsp")\n'
        "(c:CXCADCHECKAPPLY)\n"
        "(c:CXCADCHECKFINALIZE)\n"
    )
    run_audit = (
        f'(load "{runtime}/audit_markup.lsp")\n'
        "(c:CXCADCHECKAUDIT)\n"
        "_.QUIT\n_N\n"
    )

    files = {
        "apply_markup.lsp": apply_lisp,
        "audit_markup.lsp": audit_lisp,
        "run_apply.scr": run_apply,
        "run_audit.scr": run_audit,
        "normalized_config.json": json.dumps(config, ensure_ascii=False, indent=2) + "\n",
    }
    for name, content in files.items():
        (output_dir / name).write_text(content, encoding="utf-8", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="UTF-8 issue JSON")
    parser.add_argument("--output-dir", required=True, type=Path, help="ASCII runtime directory")
    args = parser.parse_args()

    raw = json.loads(args.config.read_text(encoding="utf-8-sig"))
    if not isinstance(raw, dict):
        fail("config root must be an object")
    output_dir = args.output_dir.resolve()
    ascii_only(str(output_dir), "--output-dir")
    config = validate_config(raw, output_dir)
    write_bundle(config, output_dir)

    print(
        json.dumps(
            {
                "status": "PASS",
                "output_dir": str(output_dir),
                "issue_count": len(config["issues"]),
                "expected_objects": len(config["issues"]) * 3,
                "files": list(TARGET_FILES),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
