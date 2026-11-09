"""Exact native saved-DWG geometry export, independent of the production host."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import ctypes
import os
from cad_runtime.storage import digest, atomic_new, read
from cad_runtime.machine import load_profile, REFS

ROOT = Path(__file__).resolve().parent

def run(environment, request, workdir, operation="geometry"):
    profile = load_profile(environment)
    request = Path(request).resolve()
    data = read(request)
    operations={"geometry":(["NativeGeometryReadV1.cs"],"HLCADGEOMETRYREADV1"),
                "display_state":(["NativeDisplayStateReadV1.cs","NativeGeometryReadV1.cs"],"HLCADDISPLAYSTATEREADV1"),
                "hatch_split":(["NativeHatchSplitV1.cs","NativeGeometryReadV1.cs"],"HLCADHATCHSPLITREADV1")}
    assert operation in operations, 'UNKNOWN_READ_ONLY_OPERATION'
    native_sources,entry=operations[operation]
    sources=data.get('sources') if operation in ("geometry","display_state") else [
        {"path":data['input'],"sha256":data['input_sha256'],"handles":[i['handle'] for i in data['items']]},
        {"path":data['clips_input'],"sha256":data['clips_sha256'],"handles":[b['handle'] for b in data['boundaries']]}]
    assert sources, 'SOURCES_REQUIRED'
    for source in sources:
        assert Path(source['path']).is_file() and digest(source['path']) == source['sha256'], 'SOURCE_CHANGED'
        assert source.get('handles') and all(re.fullmatch(r'[0-9A-Fa-f]+', h) for h in source['handles']), 'HANDLES_REQUIRED'
    folder = Path(workdir).resolve()
    folder.mkdir(parents=True, exist_ok=False)
    output = Path(data['receipt']).resolve()
    assert not output.exists(), 'OUTPUT_EXISTS'
    dll = folder / 'NativeGeometryReadV1.dll'
    command = [profile['compiler'], '/nologo', '/target:library', '/out:' + str(dll),
               *['/reference:' + str(Path(profile['acad_exe']).parent / n) for n in REFS],
               '/reference:System.Web.Extensions.dll', *native_sources]
    compile_result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60)
    if compile_result.returncode:
        raise RuntimeError(compile_result.stdout.decode(errors='replace'))
    trusted = Path(profile['trusted_dll_dir']) / ('HLGeometryRead_' + digest(dll)[:12] + '.dll')
    if not trusted.exists(): shutil.copy2(dll, trusted)
    assert digest(trusted) == digest(dll), 'BINARY_CHANGED'
    # AutoCAD 2021 reads SCR command input using the Windows ANSI code page.
    # JSON stays UTF-8; encoding the SCR as UTF-8 corrupts Chinese request paths.
    native_request = folder / 'request.json'
    native_request.write_bytes(request.read_bytes())
    for path in [trusted, native_request]: assert not any(c in str(path) for c in '\r\n"'), 'UNSAFE_SCRIPT_PATH'
    script = folder / 'run.scr'
    script_encoding = 'cp'+str(ctypes.windll.kernel32.GetACP()) if os.name == 'nt' else 'utf-8'
    script.write_text('_NETLOAD\n"' + trusted.as_posix() + '"\n'+entry+'\n"' + native_request.as_posix() + '"\n_QUIT\n_Y\n', encoding=script_encoding)
    exe = Path(profile['acad_exe']).with_name('accoreconsole.exe')
    # A no-input Core startup can fail in default-document creation (exit 53)
    # before NETLOAD. Use an explicit disposable copy; never open the source as
    # the active document, and never depend on the user's default template.
    bootstrap = folder / 'bootstrap.dwg'
    shutil.copy2(sources[0]['path'], bootstrap)
    assert digest(bootstrap) == sources[0]['sha256'], 'BOOTSTRAP_COPY_CHANGED'
    with (folder / 'core.log').open('wb') as out, (folder / 'core.err').open('wb') as err:
        process = subprocess.run([str(exe), '/i', str(bootstrap), '/s', str(script), '/isolate', 'HLGeometryRead_' + digest(request)[:12], str(folder), '/readonly'],
                                 cwd=exe.parent, stdout=out, stderr=err, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0), timeout=180)
    result = read(output) if output.exists() else {'status':'NO_NATIVE_RECEIPT'}
    proof = {'status': result['status'], 'receipt': str(output), 'receipt_sha256':digest(output) if output.exists() else None,
             'input_request':str(request), 'input_request_sha256':digest(request), 'dll_sha256':digest(dll),
             'source_sha256':digest(ROOT / native_sources[0]), 'native_sources':{n:digest(ROOT/n) for n in native_sources},'operation':operation,'core_exit':process.returncode,
             'production_host_used':False, 'design_interpretation':False}
    proof['bootstrap_document'] = str(bootstrap)
    proof['source_hashes_unchanged'] = all(digest(s['path']) == s['sha256'] for s in sources)
    atomic_new(folder / 'run.receipt.json', proof)
    return proof

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--environment', required=True)
    parser.add_argument('--request', required=True)
    parser.add_argument('--workdir', required=True)
    parser.add_argument('--operation', choices=['geometry', 'display_state'], default='geometry')
    args = parser.parse_args()
    print(json.dumps(run(args.environment, args.request, args.workdir, args.operation), ensure_ascii=False, indent=2))
