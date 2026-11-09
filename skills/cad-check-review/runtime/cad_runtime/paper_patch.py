"""Narrow paper-space edit contract; the native module owns target validation."""
import math
import re
from .common import check


def validate_paper_patch(params):
    rows = params['items']
    check(isinstance(rows, list) and rows, 'PAPER_ITEMS_REQUIRED')
    seen = set()
    identity = {'handle', 'layout', 'type', 'layer', 'action'}
    fields = {'before_color', 'color', 'before_linetype', 'linetype',
              'before_linetype_scale', 'linetype_scale'}
    for row in rows:
        check(isinstance(row, dict) and identity <= set(row) <= identity | fields | {'offset','target_layout','before_width','before_height','width','height'}, 'PAPER_ITEM_FIELDS')
        check(all(isinstance(row[k], str) and row[k].strip() for k in identity), 'PAPER_IDENTITY_REQUIRED')
        h = row['handle'].upper()
        check(re.fullmatch('[0-9A-F]+', h) and h not in seen, 'UNIQUE_PAPER_HANDLE_REQUIRED')
        seen.add(h)
        check(row['layout'].lower() != 'model', 'PAPER_LAYOUT_ONLY')
        check(row['action'] in ('display', 'erase', 'move','copy','resize'), 'PAPER_ACTION')
        sizes={'before_width','before_height','width','height'}
        if row['action']=='resize':
            check(set(row)==identity|sizes and row['type']=='AcDbViewport','VIEWPORT_RESIZE_FIELDS')
            check(all(type(row[k]) in (int,float) and math.isfinite(row[k]) and row[k]>0 for k in sizes),'POSITIVE_VIEWPORT_DIMENSIONS_REQUIRED')
            continue
        check(not set(row)&sizes,'SIZE_FIELDS_ONLY_FOR_RESIZE')
        if row['action'] in ('move','copy'):
            v=row.get('offset')
            check(identity|{'offset'}<=set(row)<=identity|{'offset','target_layout'} and isinstance(v,list) and len(v)==2 and all(type(x) in (int,float) and math.isfinite(x) for x in v) and (any(v) or row.get('target_layout')),'PAPER_OFFSET_REQUIRED')
            if 'target_layout' in row:
                target=row['target_layout']
                check(isinstance(target,str) and target.strip() and target.lower()!='model','TARGET_PAPER_LAYOUT_REQUIRED')
                check(row['action']=='copy' or target!=row['layout'],'DISTINCT_TARGET_PAPER_LAYOUT_REQUIRED')
            if row['action']=='copy':check(row['type'] in ('AcDbBlockReference','TDbSymbNorthThumb'),'COPY_NATIVE_BLOCK_OR_NORTH_REQUIRED')
            continue
        check('offset' not in row and 'target_layout' not in row,'OFFSET_ONLY_FOR_MOVE')
        if row['action'] == 'erase':
            check(set(row) == identity, 'ERASE_HAS_NO_DISPLAY_FIELDS')
            continue
        check(bool(set(row) & fields), 'DISPLAY_CHANGE_REQUIRED')
        for key in ('color', 'linetype', 'linetype_scale'):
            before = 'before_' + key
            check((key in row) == (before in row), 'DISPLAY_BEFORE_AFTER_PAIR')
            if key not in row:
                continue
            for k in (key, before):
                v = row[k]
                if key == 'color':
                    check(type(v) is int and 0 <= v <= 256, 'ACI_COLOR_REQUIRED')
                elif key == 'linetype':
                    check(isinstance(v, str) and v.strip(), 'LINETYPE_NAME_REQUIRED')
                else:
                    check(type(v) in (int, float) and math.isfinite(v) and v > 0, 'POSITIVE_LINETYPE_SCALE_REQUIRED')
