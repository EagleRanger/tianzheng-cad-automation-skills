"""Copy caller-selected paper roots unchanged; no subdivision or scale inference."""
import re
from .common import check

TYPES = {'AcDbHatch','TDbSymbNorthThumb','TDbSymbArrow','AcDbViewport','AcDbBlockReference','AcDbPolyline','AcDbLine','AcDbArc','AcDbCircle','AcDbEllipse','AcDbSpline','AcDbText','AcDbMText','TDbText','TDbDrawingName','TDbSymbDrawingIndex','TDbSymbMultiLeader','TDbSymbCoord'}

def validate_paper_roots_copy(p):
    check(isinstance(p['source'], str) and p['source'].lower().endswith('.dwg'), 'SOURCE_DWG_REQUIRED')
    for k in ('source_layout','target_layout'):
        check(isinstance(p[k],str) and p[k].strip() and p[k].lower() != 'model', 'PAPER_LAYOUT_ONLY')
    check(isinstance(p['source_targets'],list) and p['source_targets'], 'EXPLICIT_PAPER_ROOTS_REQUIRED')
    seen=set()
    for t in p['source_targets']:
        check(isinstance(t,dict) and set(t)=={'handle','type','layer'}, 'EXACT_ROOT_HANDLE_TYPE_LAYER')
        h=t['handle']
        check(isinstance(h,str) and re.fullmatch('[0-9A-Fa-f]+',h) and h.upper() not in seen, 'UNIQUE_ROOT_HANDLE')
        seen.add(h.upper())
        check(t['type'] in TYPES and isinstance(t['layer'],str) and t['layer'].strip(), 'PAPER_ROOT_TYPE_LAYER')

    pairs=p.get('frozen_layer_pairs',[])
    check(isinstance(pairs,list), 'FROZEN_LAYER_PAIRS_LIST')
    seen=set()
    for pair in pairs:
        check(isinstance(pair,dict) and set(pair)=={'source','target'} and all(isinstance(pair[k],str) and pair[k].strip() for k in pair), 'EXACT_FROZEN_LAYER_PAIR')
        check(pair['source'].casefold() not in seen, 'DUPLICATE_FROZEN_LAYER_SOURCE')
        seen.add(pair['source'].casefold())
