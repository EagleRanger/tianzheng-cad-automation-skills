"""Adopt a verified committed paper transform after the original draw-order false alarm; never replay."""
import argparse,json,subprocess
from pathlib import Path
from cad_runtime.storage import read,digest,atomic_new,lock,same
from cad_runtime.common import check
from cad_runtime.host import process_identity
from cad_runtime.receipts import request_records
from cad_runtime.bound_edits import require_entry,verified_release

ROOT=Path(__file__).resolve().parent
FAILED_HASH='a6b706d000a68cf0cc65c414d56a762adff006b8c239001aee80f0df62b529b4'

def run(state,request_id):
    binding=read(state)['session_client']; folder=Path(binding['session_dir'])
    with lock(folder):
        check(process_identity(binding['host']['pid'])==binding['host'],'HOST_IDENTITY')
        records=[r for r in request_records(folder) if r.get('id')==request_id and r.get('kind')=='paper_transform']
        check(len(records)==1,'EXACT_FAILED_PAPER_REQUEST_REQUIRED')
        rec=records[0];request=Path(rec['request']); q=read(request);job=read(q['job_path']);failure=Path(job['receipt'])
        resolution=Path(str(failure)+'.resolution.json')
        if resolution.exists():return {'status':'RECOVERY_ALREADY_RECORDED','receipt':str(resolution),'replayed':False}
        check(digest(q['job_path'])==q['job_sha256'],'JOB_CHANGED')
        f=read(failure); check(f.get('status')=='BOUND_MODULE_FAILED' and f.get('write_started') is True and 'UNSELECTED_OBJECT_MODIFIED_AT_COMMIT:' in f.get('error',''),'EXPECTED_PAPER_COMMIT_FAILURE')
        if Path(job['output']).exists():check(digest(job['output'])==digest(f['emergency']),'EXISTING_OUTPUT_IS_DIFFERENT')
        s=read(folder/'session_status.json')
        check(s['last_saved']==job['input'] and s['last_sha256']==job['input_sha256'] and digest(job['input'])==job['input_sha256'],'CURRENT_SAVED_SOURCE_CHANGED')
        old=read(folder/(request_id+'.dispatch.json'))
        check(same(old['request'],request) and old['dll_sha256']==FAILED_HASH and digest(old['dll'])==FAILED_HASH,'ORIGINAL_FAILED_MODULE_REQUIRED')
        for p in (failure,Path(job['output']),Path(f['emergency'])):check(same(p.parent,folder),'OUTPUT_SCOPE')
        release=verified_release(binding,'paper_transform');entry='HLCADPAPERTRANSFORMRECOVERV2';require_entry(release['dll'],entry)
        manifest=folder/(request_id+'.paper-recovery-v2.dispatch.json');check(not manifest.exists(),'ALREADY_DISPATCHED_DO_NOT_REPLAY')
        atomic_new(manifest,{**binding,'request':str(request),'request_sha256':digest(request),'failure':str(failure),'failure_sha256':digest(failure),'failed_module':old['dll'],'failed_module_sha256':FAILED_HASH,'emergency_sha256':digest(f['emergency']),'receipt':str(resolution),'document':s['live_document'],'saved_path':s['last_saved'],'source_sha256':s['last_sha256'],'dll':release['dll'],'dll_sha256':release['sha256'],'entry':entry,'dispatch_receipt':str(folder/(request_id+'.paper-recovery-v2.dispatch.receipt.json'))})
        quote=lambda x:"'"+str(x).replace("'","''")+"'"
        script=manifest.with_suffix('.ps1')
        with script.open('x',encoding='utf-8-sig') as out:out.write("$ErrorActionPreference='Stop'\n& "+quote(ROOT/'invoke_bound_cad_module.ps1')+' -Manifest '+quote(manifest)+'\nif($LASTEXITCODE){exit $LASTEXITCODE}\n')
        result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'run_private_cad_script.ps1'),'-Desktop','HLBase736_'+binding['base_job_sha256'][:12],'-Script',str(script)],capture_output=True,timeout=20,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        check(result.returncode==0,'RECOVERY_DISPATCH_FAILED_CHECK_RECEIPT_NO_REPLAY')
        return {'status':'RECOVERY_DISPATCHED_PENDING_RECEIPT','receipt':str(resolution),'replayed':False}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state',required=True);p.add_argument('--id',required=True);a=p.parse_args();print(json.dumps(run(a.state,a.id),ensure_ascii=False))
