"""Dispatch tested, fixed native extensions through the existing bound private host.

Uses the original request/receipt registry and lock, not a second queue or scheduler.
"""
from pathlib import Path
import subprocess,uuid,re
from .common import check
from .storage import read,digest,atomic_new

RUNTIME=Path(__file__).resolve().parent.parent
RELEASE=RUNTIME/'BoundCadEditsV1.release.json'

def require_entry(dll, entry):
    """Catch a stale source command name before anything reaches the CAD host."""
    check(bool(re.fullmatch(r'HLCAD[A-Z0-9]+',entry)), 'INVALID_FIXED_ENTRY')
    commands={b.decode('ascii') for b in re.findall(rb'HLCAD[A-Z0-9]+',Path(dll).read_bytes())}
    check(entry in commands, 'MODULE_ENTRY_NOT_FOUND: '+entry+'; available='+','.join(sorted(commands)))
    return sorted(commands)

def verified_release(binding,kind=None):
    path=RUNTIME/'BaseReplaceV1.release.json' if kind=='base_replace' else (RUNTIME/'BoundViewportOpsV1.release.json' if kind in ('viewport_camera','viewport_layers') else (RUNTIME/'PresentationOpsV1.release.json' if kind in ('paper_copy','paper_note','entity_display','layer_patch') else RELEASE))
    if kind in ("native_details","viewport_details"):path=RUNTIME/"NativeDetailsV1.release.json"
    if kind=="viewport_layers":path=RUNTIME/"ViewportLayersV1.release.json"
    if kind=="coord_create":path=RUNTIME/"NativeCoordCreateV1.release.json"
    if kind=="coord_update":path=RUNTIME/"NativeCoordUpdateV1.release.json"
    if kind=="plant_layers":path=RUNTIME/"PlantLayerSplitV1.release.json"
    if kind=='viewport_freeze':path=RUNTIME/'PresentationPatchV1.release.json'
    if kind=='text_patch':path=RUNTIME/'NativeTextPatchV1.release.json'
    if kind=='paper_transform':path=RUNTIME/'NativePaperTransformV1.release.json'
    if kind=='entity_display':path=RUNTIME/'EntityDisplayV2.release.json'
    if kind=='inspect':path=RUNTIME/'NativeViewV1.release.json'
    if kind=='hatch':path=RUNTIME/'HatchWorkplaneV2.release.json'
    if kind=="groundcover_create":path=RUNTIME/"NativeGroundcoverV1.release.json"
    if kind in ("native_details","table_read"):path=RUNTIME/"NativePlantDetailsV1.release.json"
    if kind=="table_patch":path=RUNTIME/"NativeTablePatchV1.release.json"
    if kind=="table_read":path=RUNTIME/"NativeTableReadV1.release.json"
    if kind=="groundcover_update":path=RUNTIME/"NativeGroundcoverUpdateV1.release.json"
    if kind in ("text_read","text_format","text_style_import","erase"):path=RUNTIME/"NativeTextFormatV1.release.json"
    if kind=='table_expand':path=RUNTIME/'NativeTableExpandV1.release.json'
    if kind=='table_rows_move':path=RUNTIME/'NativeTableRowsMoveV1.release.json'
    if kind=='paper_patch':path=RUNTIME/'NativePaperPatchV1.release.json'
    if kind in ('paper_roots_copy','paper_roots_activate'):path=RUNTIME/'NativePaperRootsCopyV1.release.json'
    if kind=='paper_leaders_copy':path=RUNTIME/'NativePaperLeadersCopyV1.release.json'
    if kind=='paper_index_create':path=RUNTIME/'NativePaperIndexCreateV1.release.json'
    if kind=='source_register':path=RUNTIME/'NativeSourceRegisterV1.release.json'
    if kind=='native_annotation_update':path=RUNTIME/'NativeAnnotationUpdateV1.release.json'
    if kind in ("layout_import","purge_unused","viewport_restore","layout_delete"):path=RUNTIME/"NativeLayoutOpsV1.release.json"
    release=read(path)
    check(release.get('status')=='ISOLATED_NATIVE_VERIFIED' or (kind=='source_register' and release.get('status')=='NATIVE_METADATA_VERIFIED'),'BOUND_MODULE_NOT_VALIDATED')
    check(not release.get('kinds') or kind in release['kinds'],'BOUND_OPERATION_NOT_RELEASED')
    if kind == 'viewport_freeze':
        check(bool(re.fullmatch(r'HLCADVIEWPORTFREEZEV[0-9]+', release.get('entry', ''))),
              'VIEWPORT_FREEZE_REQUIRES_DEDICATED_ENTRY')
    if release.get('adapter_contract'):
        check(release['adapter_contract']=='V736_NATIVE_EXTENSION_V1','UNKNOWN_ADAPTER_CONTRACT')
    else:
        check(binding['loaded_dll_sha256'] in release['compatible_adapters'],'BOUND_ADAPTER_NOT_VALIDATED')
    check(digest(release['dll'])==release['sha256'],'BOUND_MODULE_BINARY_CHANGED')
    require_entry(release['dll'],release.get('entry','HLCADBOUNDAPPLYV1'))
    return release

def publish(binding,envelope,job_path,point):
    release=verified_release(binding,envelope['kind'])
    folder=Path(binding['session_dir']);request_id=envelope['client_request_id']
    # Archive registration is already an accepted request. Never feed an unknown
    # kind to the older idle-pump's request.json, and never replay this dispatch.
    request=folder/('request_bound_'+uuid.uuid4().hex+'.json')
    atomic_new(request,envelope)
    manifest_path=folder/(request_id+'.dispatch.json')
    manifest={'request':str(request),'request_sha256':digest(request),
              'loaded_dll':binding['loaded_dll'],'loaded_dll_sha256':binding['loaded_dll_sha256'],
              'session_dir':str(folder),'host':binding['host'],'document':point['live_document'],
              'source_sha256':point['last_sha256'],'saved_path':point['last_saved'],
              'dll':release['dll'],'dll_sha256':release['sha256'],
              'dispatch_receipt':str(folder/(request_id+'.dispatch.receipt.json'))}
    if 'entry' in release:manifest['entry']=release['entry']
    atomic_new(manifest_path,manifest)
    q=lambda s:"'"+str(s).replace("'","''")+"'"
    script=folder/(request_id+'.dispatch.ps1')
    with script.open('x',encoding='utf-8-sig') as f:
        f.write("$ErrorActionPreference='Stop'\n& "+q(RUNTIME/'invoke_bound_cad_module.ps1')+' -Manifest '+q(manifest_path)+'\nif($LASTEXITCODE){exit $LASTEXITCODE}\n')
    result=subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',
        str(RUNTIME/'run_private_cad_script.ps1'),'-Desktop','HLBase736_'+binding['base_job_sha256'][:12],'-Script',str(script)],
        capture_output=True,timeout=20,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    check(result.returncode==0,'BOUND_DISPATCH_FAILED: 已登记请求，禁止重发；检查其dispatch回执')
    return {'transport':'bound_native_extension','request':str(request),'dispatch':str(manifest_path),'replayed':False}
