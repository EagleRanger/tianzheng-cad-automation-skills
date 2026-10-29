#!/usr/bin/env python3
import argparse, csv, json, math, re
from pathlib import Path

DEGREE = re.compile(r"(?:\\U\+00B0|°)", re.I)
def read_tsv(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as f: return list(csv.DictReader(f, delimiter="\t"))
def num(row, name): return float(row[name])
def h(value): return str(value or "").strip().upper()
def k(row): return h(row["SOURCE_HANDLE"]), int(row["SEGMENT_INDEX"])
def pt(row, prefix): return num(row, prefix+"_X"), num(row, prefix+"_Y")
def dist(a,b): return math.hypot(a[0]-b[0],a[1]-b[1])
def center(row):
    if row.get("CENTER_X") not in (None,"") and row.get("CENTER_Y") not in (None,""): return num(row,"CENTER_X"),num(row,"CENTER_Y")
    a,b,c=pt(row,"START"),pt(row,"MID"),pt(row,"END"); d=2*(a[0]*(b[1]-c[1])+b[0]*(c[1]-a[1])+c[0]*(a[1]-b[1]))
    if abs(d)<1e-12: raise ValueError("ARC_CENTER_DEGENERATE")
    aa,bb,cc=a[0]**2+a[1]**2,b[0]**2+b[1]**2,c[0]**2+c[1]**2
    return ((aa*(b[1]-c[1])+bb*(c[1]-a[1])+cc*(a[1]-b[1]))/d,(aa*(c[0]-b[0])+bb*(a[0]-c[0])+cc*(b[0]-a[0]))/d)
def normal(geometry,g0):
    c=center(geometry); dx,dy=g0[0]-c[0],g0[1]-c[1]; length=math.hypot(dx,dy)
    if length<1e-9: raise ValueError("NORMAL_DEGENERATE")
    return dx/length,dy/length
def rotation_delta(a,b):
    d=abs((a-b)%math.pi); return min(d,math.pi-d)
def adjacent(a,b,tol=1e-5): return min(dist(pt(a,x),pt(b,y)) for x in ("START","END") for y in ("START","END"))<=tol

def main():
    ap=argparse.ArgumentParser()
    for arg in ("mapping","grips","geometry","text-bboxes","formula","output-plan","output-summary"): ap.add_argument("--"+arg,required=True)
    ap.add_argument("--current-grips")
    a=ap.parse_args(); mapping,grips,geometry,bboxes=map(read_tsv,(a.mapping,a.grips,a.geometry,a.text_bboxes)); current_grips=read_tsv(a.current_grips) if a.current_grips else grips; formula=json.loads(Path(a.formula).read_text(encoding="utf-8-sig"))
    if formula.get("formula_id")!="CAD-SPECIAL-TEXT-PEER-NORMAL-RESTORE-V2": raise SystemExit("FORMULA_ID_INVALID")
    geos={k(r):r for r in geometry if str(r.get("SEGMENT_TYPE","")).upper()=="ARC"}; gs={(h(r.get("HANDLE")),int(r["GRIP_INDEX"])):(num(r,"GRIP_X"),num(r,"GRIP_Y")) for r in grips}; current_gs={(h(r.get("HANDLE")),int(r["GRIP_INDEX"])):(num(r,"GRIP_X"),num(r,"GRIP_Y")) for r in current_grips}; boxes={h(r.get("SOURCE_HANDLE")):r for r in bboxes}
    rows=[r for r in mapping if str(r.get("STATUS","")).upper()=="PASS" and str(r.get("SEGMENT_TYPE","")).upper()=="ARC"]
    targets=[r for r in rows if str(r.get("SECOND_PASS_TEXT_FOLLOW","")).upper()=="YES" and DEGREE.search(str(boxes.get(h(r.get("NATIVE_HANDLE")),{}).get("TEXT","")))]
    if len(targets)!=int(formula["target_gate"]["expected_runtime_target_count"]): raise SystemExit(f"TARGET_COUNT_INVALID:{len(targets)}")
    target=targets[0]; tk,th=k(target),h(target["NATIVE_HANDLE"]); tg,tb=geos.get(tk),boxes.get(th)
    if tg is None or tb is None or (th,0) not in gs or (th,4) not in gs: raise SystemExit("TARGET_EVIDENCE_MISSING")
    g0,g4,height=gs[(th,0)],gs[(th,4)],num(tb,"HEIGHT"); tn=normal(tg,g0)
    if height<=0: raise SystemExit("TARGET_HEIGHT_INVALID")
    current=((g4[0]-g0[0])*tn[0]+(g4[1]-g0[1])*tn[1])/height; candidates=[]
    for peer in rows:
        ph,pk=h(peer.get("NATIVE_HANDLE")),k(peer); pb,pg=boxes.get(ph),geos.get(pk)
        if peer is target or h(peer.get("SOURCE_HANDLE"))!=tk[0] or int(peer.get("RANK") or 0)<2: continue
        if pg is None or pb is None or not DEGREE.search(str(pb.get("TEXT",""))) or not adjacent(tg,pg) or (ph,0) not in gs or (ph,4) not in gs or num(pb,"HEIGHT")<=0: continue
        p0,p4=gs[(ph,0)],gs[(ph,4)]; pn=normal(pg,p0); gap=((p4[0]-p0[0])*pn[0]+(p4[1]-p0[1])*pn[1])/num(pb,"HEIGHT")
        score=(rotation_delta(num(tb,"ROTATION"),num(pb,"ROTATION")),abs(math.log(max(num(tg,"SEGMENT_LENGTH"),1e-9)/max(num(pg,"SEGMENT_LENGTH"),1e-9))),abs(tk[1]-pk[1])); candidates.append((score,peer,pb,gap))
    if not candidates: raise SystemExit("ADJACENT_ACCEPTED_PEER_MISSING")
    candidates.sort(key=lambda x:x[0]); score,peer,pb,desired=candidates[0]; delta=(desired-current)*height; mx,my=g4[0]+delta*tn[0],g4[1]+delta*tn[1]
    if (th,4) not in current_gs: raise SystemExit("CURRENT_TARGET_GRIP4_MISSING")
    dx,dy=mx-current_gs[(th,4)][0],my-current_gs[(th,4)][1]
    plan={"STATUS":"PASS","SOURCE_HANDLE":tk[0],"SEGMENT_TYPE":"ARC","SEGMENT_INDEX":str(tk[1]),"NATIVE_HANDLE":th,"GRIP_INDEX":"4","MOVE_X":f"{mx:.12f}","MOVE_Y":f"{my:.12f}","DX":f"{dx:.12f}","DY":f"{dy:.12f}","CURRENT_GAP_H":f"{current:.12f}","TARGET_GAP_H":f"{desired:.12f}","REFERENCE_NATIVE_HANDLE":h(peer["NATIVE_HANDLE"]),"REFERENCE_SEGMENT_INDEX":str(int(peer["SEGMENT_INDEX"])),"REFERENCE_TEXT":str(pb["TEXT"]),"NORMAL_X":f"{tn[0]:.12f}","NORMAL_Y":f"{tn[1]:.12f}","TEXT_HEIGHT":f"{height:.12f}","SELECTION_SCORE_ROTATION":f"{score[0]:.12f}"}
    with open(a.output_plan,"w",encoding="utf-8",newline="") as f:
        w=csv.DictWriter(f,fieldnames=list(plan),delimiter="\t",lineterminator="\n"); w.writeheader(); w.writerow(plan)
    summary={"schema_version":1,"status":"PASS","formula_id":formula["formula_id"],"target_count":1,"peer_candidate_count":len(candidates),"selected_target":{"source_handle":tk[0],"segment_index":tk[1],"native_handle":th},"selected_peer":{"native_handle":plan["REFERENCE_NATIVE_HANDLE"],"segment_index":int(plan["REFERENCE_SEGMENT_INDEX"])},"current_gap_h":current,"target_gap_h":desired,"move_distance":abs(delta),"commanded_grip":4,"planner_output_semantics":"DX_DY_WCS_DELTA_VECTOR","dx":dx,"dy":dy,"board_specific_algorithm_literals":0,"cross_structure_dwg":"UNVERIFIED"}
    Path(a.output_summary).write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding="utf-8")
if __name__=="__main__": main()
