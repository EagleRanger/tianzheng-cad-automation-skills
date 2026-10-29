#!/usr/bin/env python3
"""Adapt runtime bulge geometry to the established vector probe audits."""
from __future__ import annotations
import argparse,csv,math
from pathlib import Path

def read(path:Path,encoding:str)->list[dict[str,str]]:
    with path.open('r',encoding=encoding,newline='') as stream:return list(csv.DictReader(stream,delimiter='\t'))

def write(path:Path,items:list[dict[str,object]],fields:list[str])->None:
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=fields,delimiter='\t',lineterminator='\n',extrasaction='ignore');writer.writeheader();writer.writerows(items)

def circle(a:tuple[float,float],b:tuple[float,float],c:tuple[float,float])->tuple[float,float,float]:
    x1,y1=a;x2,y2=b;x3,y3=c;d=2*(x1*(y2-y3)+x2*(y3-y1)+x3*(y1-y2))
    if abs(d)<=1e-12:raise RuntimeError('ARC_FRAME_DEGENERATE')
    cx=((x1*x1+y1*y1)*(y2-y3)+(x2*x2+y2*y2)*(y3-y1)+(x3*x3+y3*y3)*(y1-y2))/d
    cy=((x1*x1+y1*y1)*(x3-x2)+(x2*x2+y2*y2)*(x1-x3)+(x3*x3+y3*y3)*(x2-x1))/d
    return cx,cy,math.hypot(x2-cx,y2-cy)

def main()->int:
    p=argparse.ArgumentParser();p.add_argument('--geometry',required=True,type=Path);p.add_argument('--mapping',required=True,type=Path);p.add_argument('--details',required=True,type=Path);p.add_argument('--output-directory',required=True,type=Path);a=p.parse_args()
    geometry=read(a.geometry,'cp936');mapping=read(a.mapping,'utf-8-sig');details=read(a.details,'utf-8-sig')
    arcs=[]
    for row in geometry:
        if row.get('SEGMENT_TYPE','').upper()!='ARC':continue
        start=(float(row['START_X']),float(row['START_Y']));mid=(float(row['MID_X']),float(row['MID_Y']));end=(float(row['END_X']),float(row['END_Y']));cx,cy,radius=circle(start,mid,end);out=dict(row);out.update({'CENTER_X':f'{cx:.12f}','CENTER_Y':f'{cy:.12f}','RADIUS':f'{radius:.12f}','SWEEP_DEGREES':f'{math.degrees(4*math.atan(float(row["BULGE"]))):.12f}'});arcs.append(out)
    arc_keys={(r['SOURCE_HANDLE'].upper(),int(r['SEGMENT_INDEX'])) for r in arcs}
    arc_mapping=[r for r in mapping if r.get('STATUS','').upper()=='PASS' and (r['SOURCE_HANDLE'].upper(),int(r['SEGMENT_INDEX'])) in arc_keys]
    arc_details=[r for r in details if r.get('STATUS','').upper()=='PASS' and (r['SOURCE_HANDLE'].upper(),int(r['SEGMENT_INDEX'])) in arc_keys]
    mapping_keys={(r['SOURCE_HANDLE'].upper(),int(r['SEGMENT_INDEX'])) for r in arc_mapping};detail_keys={(r['SOURCE_HANDLE'].upper(),int(r['SEGMENT_INDEX'])) for r in arc_details}
    if arc_keys!=mapping_keys or arc_keys!=detail_keys:raise RuntimeError('ARC_PROBE_KEY_SET_MISMATCH')
    out=a.output_directory;geometry_fields=list(arcs[0]);mapping_fields=list(arc_mapping[0]);detail_fields=list(arc_details[0]);write(out/'arc_geometry_expanded.tsv',arcs,geometry_fields);write(out/'arc_mapping.tsv',arc_mapping,mapping_fields);write(out/'arc_details.tsv',arc_details,detail_fields)
    print(f'PASS ARC_COUNT={len(arcs)} MAPPING_COUNT={len(arc_mapping)} DETAIL_COUNT={len(arc_details)}')
    return 0
if __name__=='__main__':raise SystemExit(main())
