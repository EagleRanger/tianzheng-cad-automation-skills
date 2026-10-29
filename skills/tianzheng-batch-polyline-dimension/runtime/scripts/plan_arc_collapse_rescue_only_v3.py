#!/usr/bin/env python3
"""Select only measured native ARC collapse classes for grip0 rescue."""
from __future__ import annotations
import argparse,csv,json,math
from pathlib import Path
TARGET_FIELDS=["HANDLE","GRIP_INDEX","TARGET_X","TARGET_Y","TARGET_Z","TOLERANCE","AXIS_KIND","ANCHOR_X","ANCHOR_Y","AXIS_X","AXIS_Y","TARGET_SCALAR"]
def rows(path,encoding="utf-8-sig"):
    with open(path,"r",encoding=encoding,newline="") as stream:return list(csv.DictReader(stream,delimiter="\t"))
def write(path,data,fields):
    output=Path(path);output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("w",encoding="utf-8",newline="") as stream:
        writer=csv.DictWriter(stream,fieldnames=fields,delimiter="\t",lineterminator="\n");writer.writeheader();writer.writerows(data)
def point(row,prefix):return float(row[prefix+"_X"]),float(row[prefix+"_Y"])
def circle(a,b,c):
    x1,y1=a;x2,y2=b;x3,y3=c;d=2*(x1*(y2-y3)+x2*(y3-y1)+x3*(y1-y2))
    if abs(d)<=1e-12:return None
    cx=((x1*x1+y1*y1)*(y2-y3)+(x2*x2+y2*y2)*(y3-y1)+(x3*x3+y3*y3)*(y1-y2))/d
    cy=((x1*x1+y1*y1)*(x3-x2)+(x2*x2+y2*y2)*(x1-x3)+(x3*x3+y3*y3)*(x2-x1))/d
    return cx,cy,math.hypot(x2-cx,y2-cy)
def endpoint_error(start,end,g2,g3):return min(max(math.dist(start,g2),math.dist(end,g3)),max(math.dist(start,g3),math.dist(end,g2)))
def main():
    parser=argparse.ArgumentParser()
    for name in ("mapping","source","grips","text-bboxes","base-targets","formula","targets","audit-tsv","summary"):parser.add_argument("--"+name,required=True)
    args=parser.parse_args();formula=json.loads(Path(args.formula).read_text(encoding="utf-8"));activation=formula["activation"];double_rule=activation["double_inward_collapse"];split_rule=activation["short_reflex_capacity_split"]
    mappings=rows(args.mapping);sources=rows(args.source,"cp936");grips=rows(args.grips);bboxes=rows(args.text_bboxes);base_targets=rows(args.base_targets)
    source_by_key={(r["SOURCE_HANDLE"].upper(),int(r["SEGMENT_INDEX"])):r for r in sources};grip_by_key={(r["HANDLE"].upper(),int(r["GRIP_INDEX"])):r for r in grips};bbox_by_handle={r["SOURCE_HANDLE"].upper():r for r in bboxes};target_by_handle={}
    for row in base_targets:
        handle=row["HANDLE"].upper()
        if int(row["GRIP_INDEX"])!=0 or row["AXIS_KIND"]!="ARC_RADIUS":continue
        if handle in target_by_handle:raise RuntimeError("COLLAPSE_RESCUE_BASE_TARGET_DUPLICATE:"+handle)
        target_by_handle[handle]=row
    audit=[];selected=[];class_counts={"DOUBLE_INWARD_COLLAPSE":0,"SHORT_REFLEX_CAPACITY_SPLIT":0}
    for mapping in mappings:
        if mapping.get("STATUS","").upper()!=activation["required_mapping_status"] or mapping.get("SEGMENT_TYPE","").upper()!=activation["required_segment_type"]:continue
        handle=mapping["NATIVE_HANDLE"].upper();key=(mapping["SOURCE_HANDLE"].upper(),int(mapping["SEGMENT_INDEX"]));source=source_by_key.get(key);bbox=bbox_by_handle.get(handle);g0r=grip_by_key.get((handle,0));g2r=grip_by_key.get((handle,2));g3r=grip_by_key.get((handle,3));g4r=grip_by_key.get((handle,4))
        if not all((source,bbox,g0r,g2r,g3r,g4r)):raise RuntimeError("COLLAPSE_RESCUE_RUNTIME_EVIDENCE_MISSING:"+handle)
        height=float(bbox["HEIGHT"])
        if not math.isfinite(height) or height<=0:raise RuntimeError("COLLAPSE_RESCUE_TEXT_HEIGHT_INVALID:"+handle)
        start=point(source,"START");mid=point(source,"MID");end=point(source,"END");frame=circle(start,mid,end)
        if frame is None:raise RuntimeError("COLLAPSE_RESCUE_ARC_FRAME_INVALID:"+handle)
        cx,cy,radius=frame;ux=(mid[0]-cx)/radius;uy=(mid[1]-cy)/radius
        def grip(row):return float(row["GRIP_X"]),float(row["GRIP_Y"])
        g0=grip(g0r);g2=grip(g2r);g3=grip(g3r);g4=grip(g4r);curve_h=(((g0[0]-cx)*ux+(g0[1]-cy)*uy)-radius)/height;text_h=(((g4[0]-cx)*ux+(g4[1]-cy)*uy)-radius)/height;separation_h=curve_h-text_h;endpoint=endpoint_error(start,end,g2,g3);endpoint_ok=endpoint<=float(activation["endpoint_association_max"]);angle_deg=abs(4*math.atan(float(source["BULGE"]))*180/math.pi);length_h=float(source["SEGMENT_LENGTH"])/height
        double_collapse=endpoint_ok and curve_h<=float(double_rule["maximum_curve_radial_clearance_h"]) and text_h<=float(double_rule["maximum_text_radial_clearance_h"]) and separation_h>=float(double_rule["minimum_curve_text_radial_separation_h"])
        capacity_split=endpoint_ok and angle_deg>=float(split_rule["minimum_arc_angle_deg"]) and length_h<=float(split_rule["maximum_arc_length_h"]) and curve_h<=float(split_rule["maximum_curve_radial_clearance_h"]) and text_h>=float(split_rule["minimum_text_radial_clearance_h"]) and text_h<=float(split_rule["maximum_text_radial_clearance_h"]) and separation_h<=float(split_rule["maximum_curve_text_radial_separation_h"])
        rescue_class="DOUBLE_INWARD_COLLAPSE" if double_collapse else ("SHORT_REFLEX_CAPACITY_SPLIT" if capacity_split else "NONE");selected_now=rescue_class!="NONE"
        audit.append({"HANDLE":handle,"SOURCE_HANDLE":key[0],"SEGMENT_INDEX":key[1],"ENDPOINT_ERROR":f"{endpoint:.12f}","ENDPOINT_OK":str(endpoint_ok).upper(),"TEXT_HEIGHT_H":f"{height:.12f}","ARC_ANGLE_DEG":f"{angle_deg:.12f}","ARC_LENGTH_H":f"{length_h:.12f}","CURVE_RADIAL_CLEARANCE_H":f"{curve_h:.12f}","TEXT_RADIAL_CLEARANCE_H":f"{text_h:.12f}","CURVE_TEXT_RADIAL_SEPARATION_H":f"{separation_h:.12f}","RESCUE_CLASS":rescue_class,"STATUS":"SELECT_COLLAPSED_NATIVE_ARC" if selected_now else "KEEP_NORMAL_FROZEN"})
        if selected_now:
            target=target_by_handle.get(handle)
            if target is None:raise RuntimeError("COLLAPSE_RESCUE_STANDARD_TARGET_MISSING:"+handle)
            selected.append(target);class_counts[rescue_class]+=1
    fields=["HANDLE","SOURCE_HANDLE","SEGMENT_INDEX","ENDPOINT_ERROR","ENDPOINT_OK","TEXT_HEIGHT_H","ARC_ANGLE_DEG","ARC_LENGTH_H","CURVE_RADIAL_CLEARANCE_H","TEXT_RADIAL_CLEARANCE_H","CURVE_TEXT_RADIAL_SEPARATION_H","RESCUE_CLASS","STATUS"]
    write(args.targets,selected,TARGET_FIELDS);write(args.audit_tsv,audit,fields);summary={"schema_version":3,"status":"PASS","formula_id":formula["formula_id"],"mapping_count":len(mappings),"arc_audit_count":len(audit),"selected_count":len(selected),"selected_handles":[r["HANDLE"] for r in selected],"rescue_class_counts":class_counts,"normal_frozen_count":len(audit)-len(selected),"commanded_grip_indices":[0] if selected else [],"commanded_grip4_count":0,"theoretical_capacity_branch_count":0,"board_specific_algorithm_literals":0,"cross_structure_dwg":"UNVERIFIED"};Path(args.summary).write_text(json.dumps(summary,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
if __name__=="__main__":main()
