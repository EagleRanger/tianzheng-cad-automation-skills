"""Native table expansion: explicit layout, preserving old columns in order."""
import math,re
from .common import check

def positive(v):
    return type(v) in (int,float) and math.isfinite(v) and v>0

def validate_table_expand(params):
    rows=params['tables'];check(isinstance(rows,list) and rows,'TABLES_REQUIRED');seen=set()
    required={'handle','layout','layer','row_count','column_count','column_map','column_widths','row_heights'}
    optional={'text_height','title_height','text_style','position','cells','cell_alignment','legend_fits','row_height_mode'}
    for t in rows:
        check(isinstance(t,dict) and required<=set(t)<=required|optional,'TABLE_EXPAND_FIELDS')
        check(all(isinstance(t[k],str) and t[k].strip() for k in ('handle','layout','layer')),'TABLE_IDENTITY')
        h=t['handle'].upper();check(re.fullmatch('[0-9A-F]+',h) and h not in seen,'UNIQUE_TABLE_HANDLE');seen.add(h)
        nr,nc=t['row_count'],t['column_count'];check(type(nr) is int and nr>=2 and type(nc) is int and nc>=1,'TABLE_SIZE')
        m=t['column_map'];check(isinstance(m,list) and m and m[0]==0 and all(v is None or type(v) is int for v in m) and [v for v in m if v is not None]==list(range(nc)),'PRESERVE_ALL_COLUMNS_IN_ORDER')
        for k,n in (('column_widths',len(m)),('row_heights',nr)):
            check(isinstance(t[k],list) and len(t[k])==n and all(positive(v) for v in t[k]),'EXACT_POSITIVE_TABLE_DIMENSIONS')
        for k in ('text_height','title_height'):
            if k in t:check(positive(t[k]),'POSITIVE_TABLE_TEXT_HEIGHT')
        if 'text_style' in t:check(isinstance(t['text_style'],str) and t['text_style'].strip(),'TEXT_STYLE_NAME')
        if 'position' in t:check(isinstance(t['position'],list) and len(t['position'])==3 and all(type(v) in (int,float) and math.isfinite(v) for v in t['position']),'TABLE_POSITION')
        if 'row_height_mode' in t:check(t['row_height_mode'] in ('exact','at_least'),'ROW_HEIGHT_MODE')
        if 'cell_alignment' in t:check(t['cell_alignment']=='MiddleCenter','CELL_ALIGNMENT_SUPPORTED')
        fits=t.get('legend_fits',[]);check(isinstance(fits,list),'LEGEND_FITS_LIST');seen_fits=set()
        for f in fits:
            check(isinstance(f,dict) and set(f)=={'row','column','block','fit_ratio'},'LEGEND_FIT_FIELDS')
            rr,cc=f['row'],f['column'];check(type(rr) is int and type(cc) is int and 1<=rr<nr and 0<=cc<len(m) and m[cc] is not None and (rr,cc) not in seen_fits,'UNIQUE_EXISTING_LEGEND_CELL');seen_fits.add((rr,cc))
            check(isinstance(f['block'],str) and re.fullmatch('[0-9A-Fa-f]+',f['block']) and positive(f['fit_ratio']) and f['fit_ratio']<1,'LEGEND_FIT_ID_OR_RATIO')
        cells=t.get('cells',[]);check(isinstance(cells,list),'TABLE_CELL_LIST');coords=set()
        for c in cells:
            check(isinstance(c,dict) and set(c)=={'row','column','before','after'},'TABLE_CELL_FIELDS')
            rr,cc=c['row'],c['column'];check(type(rr) is int and type(cc) is int and 0<=rr<nr and 0<=cc<len(m) and (rr,cc) not in coords,'UNIQUE_RESULT_CELL');coords.add((rr,cc))
            check(all(isinstance(c[k],str) and '\x00' not in c[k] for k in ('before','after')),'TABLE_CELL_TEXT')
            if m[cc] is None:check(c['before']=='','NEW_COLUMN_BEFORE_EMPTY')
