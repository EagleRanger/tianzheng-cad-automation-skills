"""Prepare an exact saved-checkpoint recovery after the bound private host exited.

Copies known files only; never kills/starts CAD, replays requests or chooses a
business drawing by timestamp. The original failed session remains untouched.
"""
import argparse,json,shutil,os
from pathlib import Path
from cad_runtime.binding import load_binding
from cad_runtime.storage import read,digest,atomic_new,same
from cad_runtime.host import process_identity
from cad_runtime.common import check
from cad_runtime.machine import discover

def stop_fatal(receipt, dialogs):
    """Protect a verified checkpoint, then stop only its fatal-error private host."""
    import ctypes
    binding=load_binding();folder=Path(binding['session_dir']);proof=read(dialogs)
    check(process_identity(binding['host']['pid'])==binding['host'],'HOST_IDENTITY')
    check(proof['status']=='READ_ONLY_DIALOGS' and proof['pid']==binding['host']['pid'],'DIALOG_HOST_IDENTITY')
    fatal=[x['window'] for x in proof['windows'] if x['window']['kind']=='#32770' and x['window']['text']=='AutoCAD 错误中断']
    check(len(fatal)==1,'EXACT_FATAL_DIALOG_REQUIRED')
    user32=ctypes.windll.user32;hwnd=ctypes.c_void_p(fatal[0]['handle']);pid=ctypes.c_ulong();user32.GetWindowThreadProcessId(hwnd,ctypes.byref(pid))
    title=ctypes.create_unicode_buffer(256);user32.GetWindowTextW(hwnd,title,256)
    check(pid.value==binding['host']['pid'] and title.value=='AutoCAD 错误中断','FATAL_DIALOG_CHANGED')
    checkpoint=read(receipt);source=Path(checkpoint['output']).resolve()
    check(same(source.parent,folder) and checkpoint['status']=='SAVED_STILL_OPEN' and digest(source)==checkpoint['sha256'],'CHECKPOINT_IDENTITY')
    protection=folder/'fatal_recovery_protection';protection.mkdir(exist_ok=False)
    target=protection/source.name;shutil.copy2(source,target);check(digest(target)==checkpoint['sha256'],'PROTECTION_HASH')
    autosaves=[]
    config=read(binding['base_job'])
    stems={source.stem,Path(config['planting']).stem,Path(config['garden']).stem}
    for parent in (folder,Path(os.environ['TEMP'])):
        for path in parent.iterdir():
            if not any(path.name.startswith(stem) for stem in stems):continue
            if path.is_file() and path.suffix.lower() in ('.sv$','.bak','.ac$'):
                dest=protection/(str(len(autosaves))+'_'+path.name);shutil.copy2(path,dest);autosaves.append({'source':str(path),'copy':str(dest),'sha256':digest(dest)})
    record={'status':'PROTECTED_BEFORE_FATAL_STOP','host':binding['host'],'dialog_evidence':str(dialogs),'checkpoint':str(target),'sha256':checkpoint['sha256'],'autosaves':autosaves}
    atomic_new(protection/'protection.json',record)
    kernel=ctypes.windll.kernel32;kernel.OpenProcess.restype=ctypes.c_void_p
    handle=kernel.OpenProcess(0x00100001,False,binding['host']['pid']);check(bool(handle),'OPEN_PROCESS_FAILED')
    try:
        check(process_identity(binding['host']['pid'])==binding['host'],'HOST_CHANGED_BEFORE_STOP')
        check(bool(kernel.TerminateProcess(ctypes.c_void_p(handle),1)),'TERMINATE_FAILED')
        check(kernel.WaitForSingleObject(ctypes.c_void_p(handle),10000)==0,'HOST_EXIT_NOT_CONFIRMED')
    finally:kernel.CloseHandle(ctypes.c_void_p(handle))
    record['status']='FATAL_HOST_STOPPED_CHECKPOINT_PROTECTED';atomic_new(protection/'stop.json',record);return record

def prepare(receipt,failed_id,destination):
    binding=load_binding();old=Path(binding['session_dir']);receipt=Path(receipt).resolve();destination=Path(destination).resolve()
    check(same(receipt.parent,old) and same(destination.parent,old.parent) and not destination.exists(),'RECOVERY_SCOPE_OR_OUTPUT')
    try:running=process_identity(binding['host']['pid'])
    except (OSError,ValueError,KeyError):running=None
    check(running!=binding['host'],'BOUND_HOST_STILL_RUNNING')
    exit_path=Path(binding['launch']).parent/'exit.json';ex=read(exit_path)
    check(ex['pid']==binding['host']['pid'],'EXIT_RECEIPT_IDENTITY')
    saved=read(receipt);check(saved['status']=='SAVED_STILL_OPEN' and digest(saved['output'])==saved['sha256'],'SAVED_CHECKPOINT_IDENTITY')
    candidates=[]
    for p in old.glob('request*.json'):
        q=read(p)
        if q.get('client_request_id')==failed_id:candidates.append((p,q))
    check(len(candidates)==1,'EXACT_FAILED_REQUEST_REQUIRED')
    request,q=candidates[0];job=read(q['job_path'])
    check(not Path(job['receipt']).exists() and not Path(job.get('output','')).is_file(),'FAILED_REQUEST_MAY_HAVE_OUTPUT')
    config=read(binding['base_job']);destination.mkdir()
    copied={}
    def copy(path,expected):
        path=Path(path).resolve();check(same(path.parent,old) and digest(path)==expected,'RECOVERY_INPUT_IDENTITY')
        target=destination/path.name;check(not target.exists(),'RECOVERY_FILENAME_COLLISION');shutil.copy2(path,target);check(digest(target)==expected,'RECOVERY_COPY_HASH');copied[str(path)]=str(target);return str(target)
    new={k:v for k,v in config.items() if k not in ('references',)}
    for k in ('garden','terrain'):new[k]=copy(config[k],config[k+'_sha256'])
    new['planting']=copy(saved['output'],saved['sha256']);new['planting_sha256']=saved['sha256'];new['initial_role']='planting';new['references']={}
    for path,sha in config.get('references',{}).items():
        new['references'][copied.get(str(Path(path).resolve())) or copy(path,sha)]=sha
    changes=saved.get('changes',{});baseline=changes.get('input_snapshot')
    if baseline:new['references'][copied.get(str(Path(baseline).resolve())) or copy(baseline,changes['input_snapshot_sha256'])]=changes['input_snapshot_sha256']
    new['recovery_parent']={'session':str(old),'receipt':str(receipt),'receipt_sha256':digest(receipt),'failed_request':str(request),'failed_request_sha256':digest(request),'failed_request_replayed':False}
    atomic_new(destination/'base_job.json',new)
    environment=destination/'machine.json';atomic_new(environment,discover(Path(__file__).parent))
    # Preserve exact-name recoverable saves, if any; do not scan other projects.
    protections=[]
    live_name=Path(read(old/'session_status.json')['live_document']).stem
    for folder in (old,Path(os.environ['TEMP'])):
        for p in folder.glob(live_name+'*'):
            if p.is_file() and p.suffix.lower() in ('.sv$','.bak','.ac$'):
                target=destination/(p.name+'.protected');check(not target.exists(),'AUTOSAVE_NAME_COLLISION');shutil.copy2(p,target);protections.append({'source':str(p),'copy':str(target),'sha256':digest(target)})
    result={'status':'PREPARED_NOT_STARTED','job':str(destination/'base_job.json'),'job_sha256':digest(destination/'base_job.json'),'environment':str(environment),'saved_checkpoint':new['planting'],'sha256':saved['sha256'],'old_exit':str(exit_path),'old_failed_request_replayed':False,'copied':copied,'autosaves':protections}
    atomic_new(destination/'recovery.json',result);return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--receipt',required=True);p.add_argument('--failed-id');p.add_argument('--destination');p.add_argument('--stop-fatal',action='store_true');p.add_argument('--dialogs');a=p.parse_args()
    print(json.dumps(stop_fatal(a.receipt,a.dialogs) if a.stop_fatal else prepare(a.receipt,a.failed_id,a.destination),ensure_ascii=False,indent=2))
