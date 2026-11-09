"""Build a native job from parameters and the bound checkpoint; no writes."""
from pathlib import Path
import os,re
from .common import check
from .storage import read,same,digest
from .protocol import validate,MUTATING_KINDS
from .receipts import request_records

def approved_sources(binding):
    config = read(binding["base_job"])
    result = {os.path.normcase(str(Path(config[k]).resolve())): config[k + "_sha256"] for k in ("garden", "planting")}
    for path,value in config.get('references',{}).items():
        check(same(Path(path).parent,binding['session_dir']),'REFERENCE_OUTSIDE_SESSION')
        result[os.path.normcase(str(Path(path).resolve()))]=value
    for rec in request_records(Path(binding["session_dir"])):
        if rec["state"] != "RECEIPTED": continue
        receipt = read(rec["receipt"])
        if rec['kind']=='source_register':
            # Only the same live adapter can consume its in-memory registration.
            dispatch=read(Path(binding['session_dir'])/(rec['id']+'.dispatch.json'))
            if dispatch['host']==binding['host'] and dispatch['loaded_dll_sha256']==binding['loaded_dll_sha256']:
                registered=receipt['registered_path']
                check(same(Path(registered).parent,binding['session_dir']),'REFERENCE_OUTSIDE_SESSION')
                result[os.path.normcase(str(Path(registered).resolve()))]=receipt['registered_sha256']
        saved = receipt.get("output") or receipt.get("saved")
        if saved: result[os.path.normcase(str(Path(saved).resolve()))] = receipt["sha256"]
        if rec['kind']=='base_replace':
            changes=receipt.get('changes',{});baseline=changes.get('input_snapshot')
            if baseline and same(Path(baseline).parent,binding['session_dir']):result[os.path.normcase(str(Path(baseline).resolve()))]=changes['input_snapshot_sha256']
    return result

def build_job(binding, kind, params, request_id, snap):
    validate(kind, params)
    check(re.fullmatch(r"[A-Za-z0-9_-]{1,72}", request_id) is not None, "REQUEST_ID: 使用本批稳定ID，同一动作不要换ID重试")
    check(snap["can_submit"], "SESSION_NOT_READY:" + ";".join(snap["issues"]))
    folder = Path(binding["session_dir"]); status = snap["saved_checkpoint"]
    job = {"input": status["last_saved"], "input_sha256": status["last_sha256"],
           "receipt": str(folder / (request_id + ".receipt.json"))}
    # 不重复哈希已被CAD独占的DWG；原生CheckLive仍逐次验同一输入/哈希/内存文档。
    job.update(params)
    if kind=='source_register':
        job['path']=str(Path(params['path']).resolve())
        check(same(Path(job['path']).parent,folder),'REFERENCE_OUTSIDE_SESSION')
        check(digest(job['path'])==params['expected_sha256'],'SOURCE_HASH_CHANGED')
    if kind == "groundcover_update":
        job["items"]=[{"template_handle":i["handle"],"layer":i["layer"],"expected":i["expected"],**{k:i[k] for k in ("grips","up_text","down_text","scale","layout","text_grip","rotation") if k in i}} for i in params["items"]]
    if kind == "inspect":
        job.pop("space")
        if "view" in job:
            job.update(job.pop("view")); job["image"] = str(folder / (request_id + ".png"))
    if kind in MUTATING_KINDS:
        job["output"] = str(folder / (request_id + ".dwg"))
    if kind in ("layout_import", "viewport_restore", "paper_roots_copy", "paper_leaders_copy", "transfer", "switch", "paper_read", "paper_copy", "paper_entities_copy", "paper_note", "polyline_sync", "base_replace","viewport_camera","viewport_layers") or (kind in ("text_read","text_style_import") and "source" in params):
        key = "next_path" if kind == "switch" else "source"
        path = str(Path(job[key]).resolve()); allowed = approved_sources(binding); lookup = os.path.normcase(path)
        check(lookup in allowed and same(Path(path).parent, folder), "SOURCE_NOT_ALLOWLISTED")
        job[key] = path; job["next_sha256" if kind == "switch" else "source_sha256"] = allowed[lookup]
    if kind == "switch": job["save_path"] = str(folder / (request_id + ".dwg"))
    if kind == "close": job["recovery_dir"] = str(folder / (request_id + ".recovery"))
    for key in ("receipt", "output", "image", "save_path", "recovery_dir"):
        if key in job: check(not Path(job[key]).exists(), "OUTPUT_EXISTS:" + job[key])
    return job
