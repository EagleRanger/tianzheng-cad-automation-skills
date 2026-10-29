#!/usr/bin/env python3
"""Parse scalar-convergence TSV object rows and its terminal SUMMARY row."""
from __future__ import annotations
import argparse, csv, json, re
from pathlib import Path

HEX = re.compile(r"^[0-9A-F]+$")

def main() -> int:
    ap=argparse.ArgumentParser();ap.add_argument('--report',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);ap.add_argument('--expected-object-count',required=True,type=int);args=ap.parse_args()
    lines=args.report.read_text(encoding='utf-8-sig').splitlines()
    if len(lines)<3: raise SystemExit('SCALAR_REPORT_TOO_SHORT')
    header=lines[0].split('\t');required=('HANDLE','FINAL_ERROR','SOURCE_DRIFT_MAX','STATUS')
    if any(name not in header for name in required): raise SystemExit('SCALAR_REPORT_HEADER_INVALID')
    object_lines=[];summary_lines=[]
    for line in lines[1:]:
        if not line.strip(): continue
        fields=line.split('\t')
        if fields[0].upper()=='SUMMARY': summary_lines.append(fields)
        else: object_lines.append(line)
    if len(summary_lines)!=1: raise SystemExit('SCALAR_REPORT_SUMMARY_COUNT')
    rows=list(csv.DictReader(['\t'.join(header),*object_lines],delimiter='\t'))
    handles=[]
    for row in rows:
        handle=row['HANDLE'].upper()
        if not HEX.fullmatch(handle) or handle in handles: raise SystemExit('SCALAR_REPORT_OBJECT_HANDLE_INVALID_OR_DUPLICATE')
        handles.append(handle)
    summary={}
    for token in summary_lines[0][1:]:
        if '=' in token:
            name,value=token.split('=',1);summary[name.upper()]=value
        elif token.upper() in ('PASS','PARTIAL','FAIL'):
            summary['STATUS']=token.upper()
    pass_count=sum(row['STATUS'].upper()=='PASS' for row in rows);partial_count=sum(row['STATUS'].upper()=='PARTIAL' for row in rows);fail_count=len(rows)-pass_count-partial_count
    declared_pass=int(summary.get('PASS','-1'));declared_partial=int(summary.get('PARTIAL','-1'));declared_fail=int(summary.get('FAIL','-1'))
    valid=(len(rows)==args.expected_object_count and pass_count==args.expected_object_count and partial_count==0 and fail_count==0 and declared_pass==pass_count and declared_partial==0 and declared_fail==0 and summary.get('STATUS')=='PASS')
    result={'schema_version':1,'status':'PASS' if valid else 'FAIL','object_row_count':len(rows),'unique_handle_count':len(handles),'pass_count':pass_count,'partial_count':partial_count,'fail_count':fail_count,'summary_row_count':1,'summary_status':summary.get('STATUS'),'declared_pass_count':declared_pass,'declared_partial_count':declared_partial,'declared_fail_count':declared_fail,'final_error_max':max((float(row['FINAL_ERROR']) for row in rows),default=0.0),'source_drift_max':max((float(row['SOURCE_DRIFT_MAX']) for row in rows),default=0.0),'expected_object_count':args.expected_object_count,'summary_excluded_from_object_rows':True}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'status':result['status'],'object_row_count':len(rows)}));return 0 if valid else 2
if __name__=='__main__': raise SystemExit(main())
