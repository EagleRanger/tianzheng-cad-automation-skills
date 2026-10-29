"""Exact native LINE dependent-text audit; business commands remain frozen."""
import argparse
import importlib.util
import json
import math
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent / 'representative_command_batch_v1/process_batch.py'
spec = importlib.util.spec_from_file_location('frozen_functional_batch_v1', BASE)
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)
EPS = 1e-6


def corrected_adjust_audit(run):
    r = run / 'reports'
    mapping = legacy.new_mapping(r)
    line = next(x['NATIVE_HANDLE'] for x in mapping if x['SEGMENT_TYPE'] == 'LINE')
    baseline = {x['HANDLE']: x['RAW_ENTGET'] for x in legacy.mature.read(r / 'model_before.tsv', 'gbk')}
    model_rows = legacy.mature.read(r / 'model_after.tsv', 'gbk')
    current = {x['HANDLE']: x['RAW_ENTGET'] for x in model_rows}
    classes = {x['HANDLE']: x['CLASS'] for x in model_rows}
    added = {x['NATIVE_HANDLE'] for x in mapping}
    if set(current) - set(baseline) != added or line in baseline or any(current.get(h) != raw for h, raw in baseline.items()):
        raise ValueError('PREEXISTING_MODEL_OR_NEW_OBJECT_SET_CHANGED')
    if classes.get(line) != 'TDbDimension2':
        raise ValueError('LINKED_TEXT_REQUIRES_NATIVE_TDBDIMENSION2')
    metrics = [x for x in legacy.mature.read(r / 'text_metrics_generated.tsv') if x['HANDLE'] == line]
    if len(metrics) != 1 or metrics[0]['STATUS'] != 'PASS' or metrics[0]['SEGMENT_COUNT'] != '1':
        raise ValueError('LINKED_TEXT_REQUIRES_SINGLE_SEGMENT_LINE')
    if legacy.mature.read(r / 'source_geometry_before.tsv', 'gbk') != legacy.mature.read(r / 'source_geometry_after.tsv', 'gbk'):
        raise ValueError('SOURCE_GEOMETRY_CHANGED')
    old = legacy.point_index(legacy.mature.read(r / 'grips_before.tsv'))
    seed = legacy.point_index(legacy.mature.read(r / 'grips_generated.tsv'))
    after = legacy.point_index(legacy.mature.read(r / 'grips_after.tsv'))
    if {i for h, i in seed if h == line} != set(range(5)) or {i for h, i in after if h == line} != set(range(5)):
        raise ValueError('LINKED_TEXT_ROLE_UNVERIFIED_UNKNOWN_GRIP')
    if any(key not in after or math.dist(value, after[key]) > EPS for key, value in old.items()):
        raise ValueError('PREEXISTING_NATIVE_GRIP_DRIFT')
    plan = json.loads((r / 'functional_adjust_plan.json').read_text(encoding='utf-8'))
    delta = plan['delta_wcs']
    if plan['new_line'] != line or len(delta) != 3 or not all(math.isfinite(v) for v in delta) or abs(math.dist(delta, [0, 0, 0]) - 1) > EPS:
        raise ValueError('FUNCTIONAL_PLAN_IDENTITY_OR_DELTA')
    moves = {i: tuple(after[(line, i)][j] - seed[(line, i)][j] for j in range(3)) for i in range(5)}
    for key, value in seed.items():
        # Only this native single-segment LINE's text4 may follow controlled
        # grip0. No explicit grip4 command; every other role remains frozen.
        if key[0] == line and key[1] in (0, 1):
            expected = tuple(a + b for a, b in zip(value, delta))
        elif key == (line, 4):
            expected = tuple(a + b for a, b in zip(value, moves[0]))
        else:
            expected = value
        if key not in after or math.dist(expected, after[key]) > EPS:
            raise ValueError('LINKED_TEXT_OR_PROTECTED_GRIP_MISMATCH')
    applied = [x for x in legacy.mature.read(r / 'line_recovery_apply.tsv') if x['HANDLE'] != 'SUMMARY']
    if len(applied) != 1 or applied[0]['HANDLE'] != line or applied[0]['STATUS'] != 'PASS':
        raise ValueError('NATIVE_DUAL_GRIP_APPLY_NOT_PASS')
    row = applied[0]
    for index, prefix in ((0, 'GRIP0'), (1, 'GRIP1'), (4, 'TEXT')):
        native = tuple(float(row[prefix + '_D' + axis]) for axis in 'XY')
        if not all(math.isfinite(x) for x in native) or math.dist(native, moves[index][:2]) > EPS:
            raise ValueError('NATIVE_REPORTED_LINKAGE_DISAGREES_WITH_INVENTORY')
    if not math.isfinite(float(row['SOURCE_DRIFT'])) or float(row['SOURCE_DRIFT']) > EPS:
        raise ValueError('NATIVE_SOURCE_DRIFT')
    proof = {'status': 'PASS', 'source_effect': 'ALREADY_EXECUTED_NO_NEW_MOVE', 'old_model_count': len(baseline),
             'new_handles': sorted(added), 'new_line': line, 'old_objects_and_all_source_geometry_unchanged': True,
             'commanded_indices': [0, 1], 'dependent_native_text_index': 4,
             'dependent_text_rule': 'SAME_ACTUAL_GRIP0_DELTA_ONLY', 'unknown_grips_allowed': False,
             'new_line_0_1_delta_verified': delta, 'grip0_target_error': math.dist(moves[0], delta),
             'grip1_target_error': math.dist(moves[1], delta), 'text4_target_error': math.dist(moves[4], delta),
             'text4_actual_grip0_delta_error': math.dist(moves[4], moves[0]),
             'source_2_3_max_drift': max(math.dist(moves[i], [0, 0, 0]) for i in (2, 3)),
             'all_old_objects_and_new_arc_unchanged': True, 'tolerance': EPS, 'aesthetic_acceptance': False}
    legacy.dump(run / 'protection_and_adjustment.json', proof)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['corrected_adjust_audit', 'final', 'preview', 'checkpoint'])
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    if args.stage == 'corrected_adjust_audit':
        corrected_adjust_audit(args.run)
    else:
        getattr(legacy, args.stage)(args.run)
