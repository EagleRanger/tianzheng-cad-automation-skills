"""Build/export verified CAD components without copying drawings or live session state."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from cad_runtime import __version__
from cad_runtime.common import check
from cad_runtime.storage import encode, digest, atomic_new
from cad_runtime.machine import discover, load_profile, doctor, REFS

ROOT = Path(__file__).resolve().parent
MODULE_SOURCES = {'textformat':['NativeTextStylesV1.cs','NativeTextFormatV1.cs','NativeDetailsReadV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs'],'table':['NativeTablePatchV1.cs','NativeTableOutlineV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs'],'groundcover':['GroundcoverSavedRecoveryV1.cs','NativeGroundcoverCreateV1.cs','PaperGroundcoverTestsV1.cs','NativeDetailsReadV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs','CadValueCompareV1.cs'],'hatch':['HatchWorkplaneV2.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs'],'session':['V736BaseSession.cs','SafeCadSessionLifecycleV42.cs'],
             'offset_dispatch_check':['OffsetDispatchCheckV1.cs','NativeGeometryReadV1.cs','CadValueCompareV1.cs','CadAdapterContractV1.cs'],
             'bound':['NativeAnnotationUpdateV1.cs','IndexAnchorV1.cs','PaperEntitiesTestsV1.cs','CadValueCompareV1.cs','BoundCadEditsV1.cs','BoundCadEditsTestsV1.cs','PolylineEndpointTestsV1.cs','PolylineGeometryV1.cs','PolylineGeometryTestsV1.cs','HatchPatternPatchV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs'],
             'base':['BaseReplaceV3.cs','BaseReplaceTestsV3.cs','BaseReplaceDiagnosticV3.cs','CadAdapterContractV1.cs'],
             'presentation':['EntityScaleTestsV1.cs','NativeDbTextFormatV1.cs','PaperTransformRecoveryV1.cs','PaperTransformOpsV1.cs','NativeTextStylesV1.cs','BoundCadEditsV6.cs','BoundViewportOpsV5.cs','EntityDisplayOpsV1.cs','PresentationTestsV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs','PresentationPatchV1.cs','NativeTitleTextV1.cs','NativeDetailsReadV1.cs','CadValueCompareV1.cs'],
             'viewport':['NativeDbTextFormatV1.cs','PaperTransformRecoveryV1.cs','PaperTransformOpsV1.cs','NativeTextStylesV1.cs','ViewportDocumentV2.cs','ViewportCameraDataV3.cs','BoundCadEditsV6.cs','BoundViewportOpsV5.cs','EntityDisplayOpsV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs','PresentationPatchV1.cs','NativeTitleTextV1.cs','NativeDetailsReadV1.cs','CadValueCompareV1.cs'],
             'coord':['NativeCoordUpdateV1.cs','NativeCoordCreateV1.cs','NativeDetailsReadV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs','CadValueCompareV1.cs'],
             'plant':['PlantLayerSplitV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs','CadValueCompareV1.cs'],
             'details':['NativeDetailsReadV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs'],
             'view':['NativeViewV1.cs','CadAdapterContractV1.cs','NativeGeometryReadV1.cs'],
             'geometry':['NativeGeometryReadV1.cs'],
             'source_register':['NativeSourceRegisterV1.cs','CadAdapterContractV1.cs']}

EXPORT_FILES = [
    "cad_session_client.py", "cad_components.py", "cad_geometry_read.py", "V736BaseSession.cs", "SafeCadSessionLifecycleV42.cs",
    "start_cad_module.ps1", "run_private_cad_script.ps1", "capture_private_session.ps1", "handle_cad_startup.ps1",
    "test_cad_session_client.py", "test_cad_components.py", "CAD组件接入.md", "PaperTransformTestsV1.cs", "recover_cad_paper_transform.py", "NativeDbTextFormatTestsV1.cs", "NativeTableReadFormatTestsV1.cs",
    "cad_runtime/__init__.py", "cad_runtime/common.py", "cad_runtime/storage.py", "cad_runtime/host.py",
    "cad_runtime/protocol.py", "cad_runtime/machine.py", "cad_runtime/components.json",
    'cad_runtime/binding.py', 'cad_runtime/receipts.py', 'cad_runtime/session.py', 'cad_runtime/planning.py', 'cad_runtime/submission.py', 'cad_runtime/evidence.py', 'cad_runtime/workflow.py',
    "test_cad_module_steps.py", "test_text_format.py", "test_groundcover_update.py", "test_table_patch.py",
    "cad_runtime/layers.py", "read_cad_layers.ps1", "test_cad_layers.py", "cad_runtime/lifecycle.py", "close_owned_after_receipt_utf8.ps1",
    "BoundCadEditsV1.cs", "BoundCadEditsTestsV1.cs", "BaseReplaceV3.cs", "BaseReplaceTestsV3.cs", "BaseReplaceDiagnosticV3.cs",
    "invoke_bound_cad_module.ps1", "cad_runtime/bound_edits.py", "cad_runtime/project_flow.py", "cad_runtime/review_contract.py", "test_review_contract_20261108.py",
    "test_bound_cad_edits.py", "test_polyline_geometry.py", "test_project_flow.py", "test_supervision.py", "test_finish_check.py", "Session客户端说明.md",
]
MODULE_SOURCES['table_expand'] = ['NativeTableExpandV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs']
EXPORT_FILES += ['cad_runtime/table_expand.py','test_table_expand.py']
MODULE_SOURCES['paper_patch'] = ['NativePaperPatchV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs']
MODULE_SOURCES['paper_checkpoint_recovery'] = ['RecoverPaperCheckpointV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs']
MODULE_SOURCES['table_rows_move'] = ['NativeTableRowsMoveV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs']
MODULE_SOURCES['layout_native'] = ['CadValueCompareV1.cs','NativeViewportRestoreV1.cs','NativeLayoutDeleteV1.cs','NativeLayoutOpsV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs']
MODULE_SOURCES['paper_roots_copy'] = ['NativePaperRootsCopyV1.cs','NativePaperLeadersCopyV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs']
MODULE_SOURCES['display_state_read'] = ['NativeDisplayStateReadV1.cs','NativeGeometryReadV1.cs']
EXPORT_FILES += ['cad_runtime/paper_roots_copy.py','test_paper_roots_copy.py','test_layout_native.py']
MODULE_SOURCES['paper_index_create'] = ['NativePaperIndexCreateV1.cs','NativeGeometryReadV1.cs','CadAdapterContractV1.cs','CadValueCompareV1.cs']
EXPORT_FILES += ['cad_runtime/paper_index_create.py','test_paper_index_create.py']
for group in ('presentation','viewport'):
    MODULE_SOURCES[group] += ['NativeTDbTextV1.cs']
MODULE_SOURCES['native_tdbtext_test'] = MODULE_SOURCES['presentation'] + ['NativeTDbTextTestsV1.cs']
MODULE_SOURCES['text_patch'] = MODULE_SOURCES['presentation'] + ['TextPatchDispatchV30.cs']
EXPORT_FILES += ['cad_runtime/table_rows_move.py','test_table_rows_move.py']
EXPORT_FILES += ['cad_runtime/paper_patch.py','test_paper_patch.py']
EXPORT_FILES += ['recover_cad_paper_checkpoint.py','test_viewport_camera_move.py']

MODULE_SOURCES['entity_display'] = MODULE_SOURCES['presentation'] + ['EntityDisplayDispatchV29.cs']
MODULE_SOURCES['viewport_freeze'] = MODULE_SOURCES['presentation'] + ['ViewportFreezeDispatchV1.cs']

MODULE_SOURCES['paper_transfer_test'] = list(dict.fromkeys(MODULE_SOURCES['paper_patch']+MODULE_SOURCES['coord']+['NativeViewportRestoreV1.cs','NativePaperTransferTestsV1.cs']))

# Build and export consume the same dependency list. No module can compile here
# while silently disappearing from the portable source package.
EXPORT_FILES = sorted(set(EXPORT_FILES) | {name for group in MODULE_SOURCES.values() for name in group} | {"recover_cad_checkpoint.py", "recover_cad_read_hold.py", "test_read_hold_recovery.py", "recover_cad_saved_text.py", "recover_cad_saved_groundcover.py", "inspect_cad_dialogs.ps1", "BoundPreflightRecoveryV1.cs", "cad_module_diagnostic.py", "test_cad_diagnostic.py"})


# Portable export closure: source dependencies and corresponding offline regressions.
EXPORT_FILES = sorted(set(EXPORT_FILES) | set(['BaseReplaceDiagnosticV3.cs', 'BaseReplaceTestsV3.cs', 'BaseReplaceV3.cs', 'BoundCadEditsTestsV1.cs', 'BoundCadEditsV1.cs', 'BoundCadEditsV6.cs', 'BoundPreflightRecoveryV1.cs', 'BoundViewportOpsV5.cs', 'CAD组件接入.md', 'CadAdapterContractV1.cs', 'CadValueCompareV1.cs', 'EntityDisplayDispatchV29.cs', 'EntityDisplayOpsV1.cs', 'EntityScaleTestsV1.cs', 'GroundcoverSavedRecoveryV1.cs', 'HatchPatternPatchV1.cs', 'HatchWorkplaneV2.cs', 'IndexAnchorV1.cs', 'NativeAnnotationUpdateV1.cs', 'NativeCoordCreateV1.cs', 'NativeCoordUpdateV1.cs', 'NativeDbTextFormatTestsV1.cs', 'NativeDbTextFormatV1.cs', 'NativeDetailsReadV1.cs', 'NativeDisplayStateReadV1.cs', 'NativeGeometryReadV1.cs', 'NativeGroundcoverCreateV1.cs', 'NativeHatchSplitV1.cs', 'NativeLayoutDeleteV1.cs', 'NativeLayoutOpsV1.cs', 'NativePaperIndexCreateV1.cs', 'NativePaperLeadersCopyV1.cs', 'NativePaperPatchV1.cs', 'NativePaperRootsCopyV1.cs', 'NativePaperTransferTestsV1.cs', 'NativeSourceRegisterV1.cs', 'NativeTDbTextTestsV1.cs', 'NativeTDbTextV1.cs', 'NativeTableExpandV1.cs', 'NativeTableOutlineV1.cs', 'NativeTablePatchV1.cs', 'NativeTableReadFormatTestsV1.cs', 'NativeTableRowsMoveV1.cs', 'NativeTextFormatV1.cs', 'NativeTextStylesV1.cs', 'NativeTitleTextV1.cs', 'NativeViewV1.cs', 'NativeViewportRestoreV1.cs', 'OffsetDispatchCheckV1.cs', 'PaperEntitiesTestsV1.cs', 'PaperGroundcoverTestsV1.cs', 'PaperTransformOpsV1.cs', 'PaperTransformRecoveryV1.cs', 'PaperTransformTestsV1.cs', 'PlantLayerSplitV1.cs', 'PolylineEndpointTestsV1.cs', 'PolylineGeometryTestsV1.cs', 'PolylineGeometryV1.cs', 'PresentationPatchV1.cs', 'PresentationTestsV1.cs', 'README.md', 'RecoverPaperCheckpointV1.cs', 'SafeCadSessionLifecycleV42.cs', 'Session客户端说明.md', 'TextPatchDispatchV30.cs', 'V736BaseSession.cs', 'ViewportCameraDataV3.cs', 'ViewportDocumentV2.cs', 'ViewportFreezeDispatchV1.cs', 'cad_components.py', 'cad_geometry_read.py', 'cad_hatch_split.py', 'cad_module_diagnostic.py', 'cad_runtime/__init__.py', 'cad_runtime/binding.py', 'cad_runtime/bound_edits.py', 'cad_runtime/common.py', 'cad_runtime/components.json', 'cad_runtime/evidence.py', 'cad_runtime/host.py', 'cad_runtime/layers.py', 'cad_runtime/lifecycle.py', 'cad_runtime/machine.py', 'cad_runtime/paper_index_create.py', 'cad_runtime/paper_patch.py', 'cad_runtime/paper_roots_copy.py', 'cad_runtime/planning.py', 'cad_runtime/project_flow.py', 'cad_runtime/protocol.py', 'cad_runtime/receipts.py', 'cad_runtime/review_contract.py', 'cad_runtime/scoped_waits.py', 'cad_runtime/session.py', 'cad_runtime/storage.py', 'cad_runtime/submission.py', 'cad_runtime/table_expand.py', 'cad_runtime/table_rows_move.py', 'cad_runtime/workflow.py', 'cad_session_client.py', 'capture_private_session.ps1', 'close_owned_after_receipt_utf8.ps1', 'handle_cad_startup.ps1', 'inspect_cad_dialogs.ps1', 'invoke_bound_cad_module.ps1', 'read_cad_layers.ps1', 'recover_cad_checkpoint.py', 'recover_cad_paper_checkpoint.py', 'recover_cad_paper_transform.py', 'recover_cad_read_hold.py', 'recover_cad_saved_groundcover.py', 'recover_cad_saved_text.py', 'run_private_cad_script.ps1', 'source-manifest.json', 'start_cad_module.ps1', 'test_bound_cad_edits.py', 'test_cad_components.py', 'test_cad_diagnostic.py', 'test_cad_layers.py', 'test_cad_module_steps.py', 'test_cad_session_client.py', 'test_correction_continuity.py', 'test_elevation_rotation.py', 'test_finish_check.py', 'test_groundcover_update.py', 'test_index_bearing7.py', 'test_layout_native.py', 'test_native_transfer_contracts.py', 'test_paper_index_create.py', 'test_paper_patch.py', 'test_paper_roots_copy.py', 'test_polyline_geometry.py', 'test_project_flow.py', 'test_read_hold_recovery.py', 'test_review_contract_20261108.py', 'test_review_coverage.py', 'test_scoped_waits.py', 'test_supervision.py', 'test_table_expand.py', 'test_table_patch.py', 'test_table_rows_move.py', 'test_text_format.py', 'test_viewport_camera_move.py', 'vendor/cad_capture_compat.ps1']))

def build(profile, output, module="session"):
    output = Path(output).resolve()
    check(not output.exists(), "BUILD_OUTPUT_EXISTS")
    check(doctor(profile)["status"] == "DEPENDENCIES_FOUND", "BUILD_DEPENDENCIES_INCOMPLETE")
    refs = ["/reference:" + str(Path(profile["acad_exe"]).parent / n) for n in REFS]
    sources=MODULE_SOURCES[module]
    command = [profile["compiler"], "/nologo", "/target:library", "/out:" + str(output), *refs,
               "/reference:System.Web.Extensions.dll", "/reference:System.Drawing.dll",
               *sources]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=60)
    check(result.returncode == 0 and output.is_file(), "COMPILE_FAILED:" + (result.stdout + result.stderr).decode(errors="replace")[-1800:])
    import re
    commands=sorted({b.decode('ascii') for b in re.findall(rb'HLCAD[A-Z0-9]+',output.read_bytes())})
    proof = {"status":"COMPILED_NOT_LOADED", "backend":profile["backend"], "dll":str(output), "sha256":digest(output), "commands":commands,
             "module":module,"sources":{n:digest(ROOT/n) for n in sources}}
    atomic_new(output.with_suffix(".build.json"), proof)
    return proof

def export_bundle(profile, destination):
    destination = Path(destination).resolve()
    check(not destination.exists(), "EXPORT_EXISTS")
    files = {n:ROOT/n for n in EXPORT_FILES}
    files["vendor/cad_capture_compat.ps1"] = Path(profile["capture_script"])
    check(all(p.is_file() for p in files.values()), "EXPORT_COMPONENT_MISSING")
    # Snapshot exact bytes once; the archive and its hashes must describe the same revision.
    payloads = {n:p.read_bytes() for n,p in files.items()}
    import hashlib
    manifest = {"schema_version":1, "package":"cad-session-components", "version":__version__,
                "files":{n:hashlib.sha256(v).hexdigest() for n,v in payloads.items()},
                "excluded":["DWG", "live queues", "project/checklist state", "machine profile", "credentials", "licensed Autodesk/Tianzheng binaries"],
                "target_machine_acceptance":"not performed"}
    with zipfile.ZipFile(destination, "x", zipfile.ZIP_DEFLATED) as archive:
        for name,data in payloads.items(): archive.writestr(name,data)
        archive.writestr("package-manifest.json", encode(manifest))
    return {"status":"EXPORTED_NOT_INSTALLED", "path":str(destination), "sha256":digest(destination), "file_count":len(payloads)+1}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    p=subs.add_parser("discover"); p.add_argument("--output", type=Path)
    p=subs.add_parser("doctor"); p.add_argument("--environment", required=True)
    p=subs.add_parser("build"); p.add_argument("--environment", required=True); p.add_argument("--output", required=True);p.add_argument('--module',choices=list(MODULE_SOURCES),default='session')
    p=subs.add_parser("export"); p.add_argument("--environment", required=True); p.add_argument("--output", required=True)
    args=parser.parse_args()
    try:
        if args.command == "discover":
            profile=discover(ROOT); result={"environment":profile, "preflight":doctor(profile)}
            if args.output: atomic_new(args.output,profile)
        else:
            profile=load_profile(args.environment)
            if args.command=="doctor":result=doctor(profile)
            elif args.command=="build":result=build(profile,args.output,args.module)
            else:result=export_bundle(profile,args.output)
        print(json.dumps(result,ensure_ascii=False,indent=2))
        return 2 if result.get("status")=="DEPENDENCIES_INCOMPLETE" else 0
    except (ValueError,OSError,KeyError,subprocess.SubprocessError) as exc:
        print(json.dumps({"status":"REJECTED", "error":str(exc)},ensure_ascii=False));return 2

if __name__=="__main__": sys.exit(main())
