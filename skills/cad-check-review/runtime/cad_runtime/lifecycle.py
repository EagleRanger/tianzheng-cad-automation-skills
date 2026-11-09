"""Finish an already protected native close, without guessing or touching other hosts."""
from pathlib import Path
import subprocess
from .common import ClientError,check
from .storage import read,digest,lock
from .host import process_identity
from .receipts import request_records

ROOT=Path(__file__).resolve().parent.parent

def finish_close(binding,request_id):
    folder=Path(binding['session_dir'])
    with lock(folder):
        matches=[r for r in request_records(folder) if r.get('id')==request_id and r['kind']=='close']
        check(len(matches)==1,'EXACT_CLOSE_REQUEST_REQUIRED')
        receipt=Path(matches[0]['receipt']); proof=read(receipt)
        check(proof.get('status')=='DOCUMENTS_CLOSED_AWAITING_ORDINARY_WINDOW_CLOSE' and proof['pid']==binding['host']['pid'],'NATIVE_CLOSE_NOT_READY')
        check(bool(proof.get('documents')) and all(d.get('closed') and digest(d['snapshot'])==d['sha256'] for d in proof['documents']),'PROTECTED_DOCUMENT_MISMATCH')
        if proof.get('result'):check(digest(proof['result'])==proof['result_hash'],'SAVED_RESULT_CHANGED')
        try:identity=process_identity(binding['host']['pid'])
        except ClientError as e:
            if 'HOST_UNAVAILABLE' not in str(e) and 'HOST_EXITED' not in str(e):raise
            return {'status':'PROTECTED_HOST_EXITED','pid':binding['host']['pid'],'protection_receipt':str(receipt),'process_present':False}
        check(identity==binding['host'],'HOST_IDENTITY_CHANGED')
        requested=folder/(request_id+'.window-close.json')
        if requested.exists():return {'status':'CLOSE_REQUESTED_WAIT_EXIT','request':str(requested),'replayed':False}
        quote=lambda x:"'"+str(x).replace("'","''")+"'"
        desktop='HLBase736_'+binding['base_job_sha256'][:12]
        script=folder/(request_id+'.finish-close.ps1')
        check(not script.exists(),'CLOSE_HELPER_ALREADY_PREPARED: read its existing result; do not replay')
        with script.open('x',encoding='utf-8-sig') as f:f.write("$ErrorActionPreference='Stop'\n& "+quote(ROOT/'close_owned_after_receipt_utf8.ps1')+' -Desktop '+quote(desktop)+' -CloseReceipt '+quote(receipt)+' -RequestReceipt '+quote(requested)+'\nif($LASTEXITCODE){exit $LASTEXITCODE}\n')
        r=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',str(ROOT/'run_private_cad_script.ps1'),'-Desktop',desktop,'-Script',str(script)],capture_output=True,timeout=20,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        check(r.returncode==0,'CLOSE_HELPER_FAILED: '+r.stderr.decode(errors='replace')[-1000:])
        check(requested.exists(),'CLOSE_REQUEST_NOT_CONFIRMED: helper completion is not a close receipt; inspect the prepared helper')
    return {'status':'CLOSE_REQUESTED_WAIT_EXIT','request':str(requested),'replayed':False}
