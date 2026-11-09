"""Exact paper vertices and native index clones; no camera or engineering inference."""
import math
import re
from .common import check


def validate_paper_index_create(p):
    check(isinstance(p['layout'], str) and p['layout'].strip() and p['layout'].lower() != 'model', 'PAPER_LAYOUT_ONLY')
    for k in ('boundary_template', 'index_template'):
        t = p[k]
        check(isinstance(t, dict) and set(t) == {'handle', 'layer'}, 'EXACT_TEMPLATE_FIELDS')
        check(isinstance(t['handle'], str) and re.fullmatch('[0-9A-Fa-f]+', t['handle']) and isinstance(t['layer'], str) and t['layer'].strip(), 'TEMPLATE_IDENTITY')
    check(p['boundary_template']['handle'].upper() != p['index_template']['handle'].upper(), 'DISTINCT_TEMPLATE_TYPES')
    check(isinstance(p['expected_index_label'], str), 'EXPECTED_INDEX_LABEL')
    check(isinstance(p['items'], list) and p['items'], 'INDEX_ITEMS_REQUIRED')
    seen = set()
    def xy(v):
        return isinstance(v, list) and len(v) == 2 and all(type(n) in (int, float) and math.isfinite(n) for n in v)
    for i in p['items']:
        check(isinstance(i, dict) and {'key', 'vertices', 'position', 'index_label'} <= set(i) <= {'key', 'vertices', 'position', 'index_label', 'drawing_label'}, 'INDEX_ITEM_FIELDS')
        check(isinstance(i['key'], str) and i['key'].strip() and i['key'] not in seen, 'UNIQUE_INDEX_KEY')
        seen.add(i['key'])
        for k in ('index_label', 'drawing_label'):
            if k in i:
                check(isinstance(i[k], str) and not any(ord(c) < 32 for c in i[k]) and (k != 'index_label' or i[k].strip()), 'INDEX_LABEL_STRING')
        v = i['vertices']
        check(isinstance(v, list) and len(v) >= 3 and all(xy(a) for a in v), 'EXACT_PAPER_XY_VERTICES')
        check(all(v[k] != v[(k+1) % len(v)] for k in range(len(v))), 'ZERO_LENGTH_SEGMENT')
        check(xy(i['position']), 'INDEX_CENTER_XY')
