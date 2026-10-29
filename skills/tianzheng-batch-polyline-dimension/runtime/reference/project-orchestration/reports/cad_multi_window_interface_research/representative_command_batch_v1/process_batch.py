"""Functional adapters over frozen business modules; no new layout algorithm."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[5]
BUSINESS = ROOT / 'reports/dimension_background_reproduction_v8'
sys.path.insert(0, str(BUSINESS))
import process_artifacts as mature


def dump(path, data):
    with path.open('x', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def point_index(rows):
    result = {}
    for row in rows:
        key = row['HANDLE'], int(row['GRIP_INDEX'])
        xyz = tuple(float(row['GRIP_' + a]) for a in 'XYZ')
        if key in result or not all(math.isfinite(v) for v in xyz):
            raise ValueError('DUPLICATE_OR_NONFINITE_NATIVE_GRIP')
        result[key] = xyz
    return result


def new_mapping(r):
    mapping = mature.read(r / 'typed_source_mapping.tsv')
    if len(mapping) != 2 or sorted(x['SEGMENT_TYPE'] for x in mapping) != ['ARC', 'LINE'] or any(x['STATUS'] != 'PASS' for x in mapping):
        raise ValueError('REAL_NEW_ARC_LINE_MAPPING_REQUIRED')
    return mapping


def adjust_plan(run):
    r = run / 'reports'
    mature.metrics_adapter(r / 'text_metrics_generated.tsv', r / 'native_text_generated.tsv')
    mapping = new_mapping(r)
    line = next(x['NATIVE_HANDLE'] for x in mapping if x['SEGMENT_TYPE'] == 'LINE')
    baseline = {x['HANDLE'] for x in mature.read(r / 'model_before.tsv', 'gbk')}
    if line in baseline:
        raise ValueError('REFUSE_ADJUSTING_PREEXISTING_OBJECT')
    points = point_index(mature.read(r / 'grips_generated.tsv'))
    if any((line, i) not in points for i in (0, 1, 2, 3)):
        raise ValueError('NEW_LINE_DUAL_GRIP_TOPOLOGY_REQUIRED')
    # Reuse the mature axis producer unchanged; do not invent a direction or
    # assume WCS X is movable for this LINE. Its band aesthetics are not a gate.
    mature.plan(run)
    targets = [x for x in mature.read(r / 'scalar_targets.tsv') if x['HANDLE'] == line]
    if len(targets) != 1 or targets[0]['AXIS_KIND'] != 'LINE_NORMAL_DISTANCE':
        raise ValueError('MATURE_LINE_AXIS_REQUIRED')
    dx, dy = float(targets[0]['AXIS_X']), float(targets[0]['AXIS_Y'])
    if not all(math.isfinite(v) for v in (dx, dy)) or abs(math.hypot(dx, dy) - 1) > 1e-6:
        raise ValueError('MATURE_LINE_AXIS_NOT_UNIT')
    # One drawing unit is explicit functional input, not a new layout formula
    # or a mm claim, and never applies to an accepted/existing object.
    row = {'HANDLE': line, 'GRIP_INDEX': '0', 'DX': repr(dx), 'DY': repr(dy), 'DZ': '0'}
    mature.write_table(r / 'line_recovery_plan.tsv', [row], list(row))
    dump(r / 'functional_adjust_plan.json', {'new_line': line, 'delta_wcs': [dx, dy, 0],
         'actual_moved_indices': [0, 1], 'protected_source_indices': [2, 3],
         'production_layout_formula': False, 'aesthetic_claim': False})


def adjust_audit(run):
    r = run / 'reports'
    mapping = new_mapping(r)
    baseline = {x['HANDLE']: x['RAW_ENTGET'] for x in mature.read(r / 'model_before.tsv', 'gbk')}
    current = {x['HANDLE']: x['RAW_ENTGET'] for x in mature.read(r / 'model_after.tsv', 'gbk')}
    added = {x['NATIVE_HANDLE'] for x in mapping}
    if set(current) - set(baseline) != added or any(current.get(h) != raw for h, raw in baseline.items()):
        raise ValueError('PREEXISTING_MODEL_OR_NEW_OBJECT_SET_CHANGED')
    if mature.read(r / 'source_geometry_before.tsv', 'gbk') != mature.read(r / 'source_geometry_after.tsv', 'gbk'):
        raise ValueError('SOURCE_GEOMETRY_CHANGED')
    old = point_index(mature.read(r / 'grips_before.tsv'))
    seed = point_index(mature.read(r / 'grips_generated.tsv'))
    after = point_index(mature.read(r / 'grips_after.tsv'))
    if any(key not in after or math.dist(value, after[key]) > 1e-6 for key, value in old.items()):
        raise ValueError('PREEXISTING_NATIVE_GRIP_DRIFT')
    line = next(x['NATIVE_HANDLE'] for x in mapping if x['SEGMENT_TYPE'] == 'LINE')
    plan = json.loads((r / 'functional_adjust_plan.json').read_text(encoding='utf-8'))
    delta = plan['delta_wcs']
    if plan['new_line'] != line or len(delta) != 3 or not all(math.isfinite(v) for v in delta) or abs(math.dist(delta, [0, 0, 0]) - 1) > 1e-6:
        raise ValueError('FUNCTIONAL_PLAN_IDENTITY_OR_DELTA')
    for key, value in seed.items():
        expected = tuple(a + b for a, b in zip(value, delta)) if key[0] == line and key[1] in (0, 1) else value
        if key not in after or math.dist(expected, after[key]) > 1e-6:
            raise ValueError('FUNCTIONAL_MOVE_OR_PROTECTED_GRIP_MISMATCH')
    applied = [x for x in mature.read(r / 'line_recovery_apply.tsv') if x['HANDLE'] != 'SUMMARY']
    if len(applied) != 1 or applied[0]['HANDLE'] != line or applied[0]['STATUS'] != 'PASS':
        raise ValueError('NATIVE_DUAL_GRIP_APPLY_NOT_PASS')
    dump(run / 'protection_and_adjustment.json', {'status': 'PASS', 'old_model_count': len(baseline),
         'new_handles': sorted(added), 'old_objects_and_all_source_geometry_unchanged': True,
         'new_line_0_1_delta_verified': delta, 'new_arc_and_all_other_grips_unchanged': True,
         'aesthetic_acceptance': False})


def final(run):
    r = run / 'reports'
    mature.metrics_adapter(r / 'text_metrics_after.tsv', r / 'native_text_after.tsv')
    mature.call('scripts/audit_native_dimension_semantics_v1.py', '--geometry', r / 'selected_geometry.tsv',
                '--mapping', r / 'typed_source_mapping.tsv', '--text-inventory', r / 'native_text_after.tsv',
                '--output-audit', r / 'semantics_audit.tsv', '--output-summary', r / 'semantics_summary.json')
    if json.loads((run / 'protection_and_adjustment.json').read_text(encoding='utf-8'))['status'] != 'PASS':
        raise ValueError('PRIOR_PROTECTION_NOT_PASS')
    dump(run / 'functional_business_audit.json', {'status': 'PASS', 'native_ARC_degrees_LINE_length': True,
         'real_new_object_adjustment': True, 'protected_old_objects': True, 'layout_quality': 'OUT_OF_SCOPE'})


def preview(run):
    r = run / 'reports'
    receipt = json.loads((r / 'preview_receipt.json').read_text(encoding='utf-8-sig'))
    if receipt['status'] != 'PASS' or not (r / 'dimensions_preview.png').is_file():
        raise ValueError('REAL_PREVIEW_CALL_OR_OUTPUT_MISSING')
    dump(run / 'preview_function_receipt.json', {'status': 'PASS_CALL_AND_OUTPUT_ONLY', 'pixels_reviewed': False,
         'clarity_or_aesthetics_gate': False})


def checkpoint(run):
    path = run / 'dimension_test_checkpoint.dwg'
    with path.open('rb') as f:
        magic = f.read(6)
    if not magic.startswith(b'AC10') or path.stat().st_size < 1024:
        raise ValueError('REAL_DWG_COPY_MISSING')
    dump(run / 'checkpoint_receipt.json', {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
         'reopen': 'NOT_TESTED_CHECKPOINT_ONLY', 'formal_delivery': False})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['prepare', 'after_generation', 'adjust_plan', 'adjust_audit', 'final', 'preview', 'checkpoint'])
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    if args.stage in ('prepare', 'after_generation'):
        getattr(mature, args.stage)(args.run)
    else:
        globals()[args.stage](args.run)
