"""Two independent adapters over the frozen compiler, mapping and semantic audit."""
import argparse
import importlib.util
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True

BASE = Path(__file__).resolve().parent.parent / 'representative_command_batch_v3/process_batch.py'
spec = importlib.util.spec_from_file_location('dual_frozen_v3', BASE)
v3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v3)
legacy = v3.legacy
mature = legacy.mature


def audit_protection(run):
    r = run / 'reports'
    mapping = legacy.new_mapping(r)
    rows_before = mature.read(r / 'model_before.tsv', 'gbk')
    rows_after = mature.read(r / 'model_after.tsv', 'gbk')
    before = {x['HANDLE']: x['RAW_ENTGET'] for x in rows_before}
    after = {x['HANDLE']: x['RAW_ENTGET'] for x in rows_after}
    added = {x['NATIVE_HANDLE'] for x in mapping}
    if len(before) != len(rows_before) or len(after) != len(rows_after):
        raise ValueError('DUPLICATE_MODEL_HANDLE')
    if len(added) != 2 or set(after) - set(before) != added or set(before) - set(after) or any(after[h] != raw for h, raw in before.items()):
        raise ValueError('OLD_OBJECT_OR_EXACT_ADDED_SET_DRIFT')
    if any(x['CLASS'] != 'TDbDimension2' for x in rows_after if x['HANDLE'] in added):
        raise ValueError('NEW_OBJECT_NATIVE_CLASS')
    if mature.read(r / 'source_geometry_before.tsv', 'gbk') != mature.read(r / 'source_geometry_after.tsv', 'gbk'):
        raise ValueError('SOURCE_GEOMETRY_CHANGED')
    old = legacy.point_index(mature.read(r / 'grips_before.tsv'))
    seed = legacy.point_index(mature.read(r / 'grips_generated.tsv'))
    end = legacy.point_index(mature.read(r / 'grips_after.tsv'))
    if not old or set(old) - set(seed) or set(seed) != set(end):
        raise ValueError('GRIP_INVENTORY_COVERAGE')
    # No grip movement in this experiment. Even LINE text4 is frozen here;
    # V3's text4 follows actual grip0 exception applies only after a real move.
    if any(math.dist(p, seed[k]) > 1e-6 for k, p in old.items()) or any(math.dist(p, end[k]) > 1e-6 for k, p in seed.items()):
        raise ValueError('UNCOMMANDED_OLD_OR_NEW_GRIP_DRIFT')
    metrics = mature.read(r / 'text_metrics_after.tsv')
    line = next(x['NATIVE_HANDLE'] for x in mapping if x['SEGMENT_TYPE'] == 'LINE')
    line_metrics = [x for x in metrics if x['HANDLE'] == line]
    if len(line_metrics) != 1 or line_metrics[0]['SEGMENT_COUNT'] != '1' or {i for h, i in seed if h == line} != set(range(5)):
        raise ValueError('LINE_SINGLE_SEGMENT_FIVE_GRIP_ROLES_REQUIRED')
    return {'status': 'PASS', 'old_count': len(before), 'new_handles': sorted(added), 'all_old_raw_dxf_unchanged': True,
            'source_geometry_unchanged': True, 'all_grips_unchanged_after_generation': True,
            'line_text4_policy': 'FROZEN_NO_COMMAND__V3_DEPENDENT_RULE_NOT_TRIGGERED', 'commanded_grip_move_count': 0}


def final(run):
    r = run / 'reports'
    proof = audit_protection(run)
    mature.metrics_adapter(r / 'text_metrics_after.tsv', r / 'native_text_after.tsv')
    mature.call('scripts/audit_native_dimension_semantics_v1.py', '--geometry', r / 'selected_geometry.tsv', '--mapping', r / 'typed_source_mapping.tsv',
                '--text-inventory', r / 'native_text_after.tsv', '--output-audit', r / 'semantics_audit.tsv', '--output-summary', r / 'semantics_summary.json')
    summary = json.loads((r / 'semantics_summary.json').read_text(encoding='utf-8-sig'))
    # The frozen semantic auditor exits nonzero on failure. Preserve its full
    # verdict as well as the independent old/new/source/grip audit.
    proof['semantic_summary'] = summary
    proof['native_ARC_degrees_LINE_length'] = True
    proof['aesthetic_acceptance'] = False
    mature.dump(run / 'functional_business_audit.json', proof)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['prepare', 'after_generation', 'final'])
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    results = []
    for owner in ('A', 'B'):
        local = args.run / owner
        try:
            if args.stage == 'final':
                final(local)
            else:
                getattr(mature, args.stage)(local)
            results.append({'owner': owner, 'status': 'PASS'})
        except Exception as error:
            results.append({'owner': owner, 'status': 'FAIL', 'error': repr(error)})
    mature.dump(args.run / ('process_' + args.stage + '.json'), {'stage': args.stage, 'owners': results})
    if any(x['status'] != 'PASS' for x in results):
        raise SystemExit(1)
