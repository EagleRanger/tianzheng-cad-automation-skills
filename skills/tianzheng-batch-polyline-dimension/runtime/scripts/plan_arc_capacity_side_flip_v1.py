import argparse,csv,json,math,re
from pathlib import Path

def read_tsv(path, encoding="utf-8"):
    with open(path,"r",encoding=encoding,newline="") as f:return list(csv.DictReader(f,delimiter="\t"))
def circle(a,b,c):
    x1,y1=a;x2,y2=b;x3,y3=c;d=2*(x1*(y2-y3)+x2*(y3-y1)+x3*(y1-y2))
    if abs(d)<1e-12:return None
    ux=((x1*x1+y1*y1)*(y2-y3)+(x2*x2+y2*y2)*(y3-y1)+(x3*x3+y3*y3)*(y1-y2))/d
    uy=((x1*x1+y1*y1)*(x3-x2)+(x2*x2+y2*y2)*(x1-x3)+(x3*x3+y3*y3)*(x2-x1))/d
    return ux,uy,math.hypot(x1-ux,y1-uy)
def visible_text(raw):
    value=re.sub(r"\\A\d+;","",raw or "");value=value.replace("\\U+00B0","°")
    return value
def intrinsic_width(row,h,per_char,min_h):
    ex=float(row["MAX_X"])-float(row["MIN_X"]);ey=float(row["MAX_Y"])-float(row["MIN_Y"]);rot=float(row["ROTATION"]);c=abs(math.cos(rot));s=abs(math.sin(rot));den=c*c-s*s
    measured=abs((c*ex-s*ey)/den) if abs(den)>0.05 else max(ex,ey)
    conservative=max(min_h*h,len(visible_text(row.get("TEXT","")))*per_char*h)
    return max(measured,conservative),measured,conservative
def main():
    p=argparse.ArgumentParser();p.add_argument("--mapping",required=True);p.add_argument("--source",required=True);p.add_argument("--grips",required=True);p.add_argument("--text-bboxes",required=True);p.add_argument("--formula",required=True);p.add_argument("--targets",required=True);p.add_argument("--audit-tsv",required=True);p.add_argument("--summary",required=True);a=p.parse_args()
    formula=json.load(open(a.formula,"r",encoding="utf-8"))["arc_capacity_side_flip"]
    mappings=read_tsv(a.mapping);sources=read_tsv(a.source,"cp936");grips=read_tsv(a.grips);bboxes=read_tsv(a.text_bboxes)
    src={(r["SOURCE_HANDLE"].upper(),int(r["SEGMENT_INDEX"])):r for r in sources};gp={(r["HANDLE"].upper(),int(r["GRIP_INDEX"])):r for r in grips};bb={r["SOURCE_HANDLE"].upper():r for r in bboxes}
    audit=[];targets=[]
    for m in mappings:
        if m["STATUS"].upper()!="PASS" or m["SEGMENT_TYPE"].upper()!="ARC":continue
        handle=m["NATIVE_HANDLE"].upper();srow=src.get((m["SOURCE_HANDLE"].upper(),int(m["SEGMENT_INDEX"])));grow=gp.get((handle,0));trow=bb.get(handle)
        if not(srow and grow and trow and trow.get("HEIGHT") and trow.get("ROTATION")):continue
        pts=[(float(srow[k+"_X"]),float(srow[k+"_Y"])) for k in ("START","MID","END")];geom=circle(*pts)
        if not geom:continue
        cx,cy,radius=geom;gx=float(grow["GRIP_X"]);gy=float(grow["GRIP_Y"]);current=math.hypot(gx-cx,gy-cy);h=float(trow["HEIGHT"]);theta=4*math.atan(abs(float(srow["BULGE"])))
        width,measured,conservative=intrinsic_width(trow,h,float(formula["conservative_text_width_per_visible_character_h"]),float(formula["minimum_angle_text_width_h"]))
        required=width+2*float(formula["arrow_size_h"])*h+2*float(formula["text_arrow_hard_gap_h"])*h;opposite=2*radius-current
        current_capacity=theta*current/required;opposite_capacity=theta*opposite/required;advantage=opposite_capacity-current_capacity
        inner=current<radius-0.05*h;selected=inner and current_capacity<float(formula["current_capacity_fail_below"]) and opposite_capacity>=float(formula["opposite_capacity_hard_pass_at_or_above"]) and advantage>=float(formula["minimum_capacity_advantage"])
        reason="SELECT_INNER_CAPACITY_FAIL_OPPOSITE_HARD_PASS" if selected else "KEEP"
        audit.append({"HANDLE":handle,"SOURCE_HANDLE":m["SOURCE_HANDLE"].upper(),"SEGMENT_INDEX":m["SEGMENT_INDEX"],"TEXT":visible_text(trow.get("TEXT","")),"THETA_DEG":f"{math.degrees(theta):.9f}","H":f"{h:.12f}","SOURCE_RADIUS":f"{radius:.12f}","CURRENT_RADIUS":f"{current:.12f}","OPPOSITE_RADIUS":f"{opposite:.12f}","TEXT_WIDTH":f"{width:.12f}","MEASURED_TEXT_WIDTH":f"{measured:.12f}","CONSERVATIVE_TEXT_WIDTH":f"{conservative:.12f}","REQUIRED_LENGTH":f"{required:.12f}","CURRENT_CAPACITY":f"{current_capacity:.12f}","OPPOSITE_CAPACITY":f"{opposite_capacity:.12f}","CAPACITY_ADVANTAGE":f"{advantage:.12f}","INNER_SIDE":str(inner).upper(),"STATUS":reason})
        if selected:
            ux=(gx-cx)/current;uy=(gy-cy)/current;targets.append({"HANDLE":handle,"GRIP_INDEX":"0","TARGET_X":f"{cx+ux*opposite:.12f}","TARGET_Y":f"{cy+uy*opposite:.12f}","TARGET_Z":"0.0","TOLERANCE":"1e-06","AXIS_KIND":"ARC_RADIUS_OPPOSITE_CAPACITY","ANCHOR_X":f"{cx:.12f}","ANCHOR_Y":f"{cy:.12f}","AXIS_X":f"{ux:.15f}","AXIS_Y":f"{uy:.15f}","TARGET_SCALAR":f"{opposite:.12f}"})
    target_fields=["HANDLE","GRIP_INDEX","TARGET_X","TARGET_Y","TARGET_Z","TOLERANCE","AXIS_KIND","ANCHOR_X","ANCHOR_Y","AXIS_X","AXIS_Y","TARGET_SCALAR"]
    audit_fields=["HANDLE","SOURCE_HANDLE","SEGMENT_INDEX","TEXT","THETA_DEG","H","SOURCE_RADIUS","CURRENT_RADIUS","OPPOSITE_RADIUS","TEXT_WIDTH","MEASURED_TEXT_WIDTH","CONSERVATIVE_TEXT_WIDTH","REQUIRED_LENGTH","CURRENT_CAPACITY","OPPOSITE_CAPACITY","CAPACITY_ADVANTAGE","INNER_SIDE","STATUS"]
    for path,rows,fields in ((a.targets,targets,target_fields),(a.audit_tsv,audit,audit_fields)):
        Path(path).parent.mkdir(parents=True,exist_ok=True)
        with open(path,"w",encoding="utf-8",newline="") as f:w=csv.DictWriter(f,fieldnames=fields,delimiter="\t",lineterminator="\n");w.writeheader();w.writerows(rows)
    summary={"status":"PASS" if targets else "NO_CANDIDATE","mapping_count":len(mappings),"arc_audit_count":len(audit),"selected_count":len(targets),"selected_handles":[r["HANDLE"] for r in targets],"formula_id":"CAD-ANNOTATION-QUANTIZED-LAYOUT-V6","business_literals":{"handle":0,"coordinate":0,"source_key":0,"bbox":0,"object_count":0},"cross_structure_dwg":"UNVERIFIED"}
    Path(a.summary).write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
if __name__=="__main__":main()
