import re
from .common import check

def validate_table_rows_move(p):
    for name in ('source_table','target_table'):
        t=p[name]
        check(isinstance(t,dict) and set(t)=={'handle','layout','layer','row_count','column_count'},'TABLE_IDENTITY_FIELDS')
        check(all(isinstance(t[k],str) and t[k].strip() for k in ('handle','layout','layer')) and re.fullmatch('[0-9A-Fa-f]+',t['handle']),'TABLE_IDENTITY')
        check(type(t['row_count']) is int and t['row_count']>=3 and type(t['column_count']) is int and t['column_count']>=1,'TABLE_SIZE')
    s,t=p['source_table'],p['target_table']
    check(s['handle'].upper()!=t['handle'].upper() and s['column_count']==t['column_count'],'DISTINCT_TABLES_IDENTICAL_COLUMNS')
    rows=p['rows'];check(isinstance(rows,list) and rows and all(type(r) is int and 2<=r<s['row_count'] for r in rows) and len(set(rows))==len(rows),'UNIQUE_ORIGINAL_DATA_ROWS')
    check(type(p['insert_before']) is int and 2<=p['insert_before']<=t['row_count'],'TARGET_INSERT_ROW')
    check(type(p['renumber']) is bool,'EXPLICIT_RENUMBER_REQUIRED')
