"""Machine dependencies, separate from project drawings and live sessions.

Inspection only: this module never installs software, starts CAD or changes the registry.
"""
from __future__ import annotations
import os
import ctypes
from ctypes import wintypes
from pathlib import Path
import shutil
import sys
from .common import check
from .storage import read

PROFILE = "autocad2021-tarch20v10"
PATH_KEYS = ("acad_exe", "tianzheng_sys", "trusted_dll_dir", "powershell_exe",
             "python_exe", "capture_script", "compiler")
OTHER_KEYS = ("schema_version", "backend", "com_progid", "manual_dialog_registry")
ARX = ("tch_kernal.arx", "tch_utility.arx", "tch_pipewire.arx", "tch_pipebase.arx",
       "tch_initstart.arx", "tch_common.arx", "tch3_kernal.arx")
REFS = ("acdbmgd.dll", "acmgd.dll", "accoremgd.dll")

def binary_version(path):
    """Read PE product version without launching the application (CAD file version differs)."""
    if os.name != "nt": return None
    version=ctypes.WinDLL("version", use_last_error=True)
    version.GetFileVersionInfoSizeW.argtypes=[wintypes.LPCWSTR,ctypes.POINTER(wintypes.DWORD)]
    version.GetFileVersionInfoW.argtypes=[wintypes.LPCWSTR,wintypes.DWORD,wintypes.DWORD,ctypes.c_void_p]
    version.VerQueryValueW.argtypes=[ctypes.c_void_p,wintypes.LPCWSTR,ctypes.POINTER(ctypes.c_void_p),ctypes.POINTER(wintypes.UINT)]
    size=version.GetFileVersionInfoSizeW(str(path),None)
    if not size:return None
    data=ctypes.create_string_buffer(size)
    if not version.GetFileVersionInfoW(str(path),0,size,data):return None
    pointer=ctypes.c_void_p();length=wintypes.UINT()
    if not version.VerQueryValueW(data,"\\",ctypes.byref(pointer),ctypes.byref(length)) or length.value<24:return None
    info=ctypes.cast(pointer,ctypes.POINTER(wintypes.DWORD))
    if info[0]!=0xFEEF04BD:return None
    return [info[4]>>16,info[4]&65535,info[5]>>16,info[5]&65535]

def first_existing(paths):
    return next((str(Path(p).resolve()) for p in paths if Path(p).exists()), None)

def discover(runtime_dir):
    """Bounded local discovery; ambiguous/unsupported installations need an explicit profile."""
    home = Path.home()
    win = Path(os.environ.get("WINDIR", "C:/Windows"))
    program = Path(os.environ.get("ProgramFiles", "C:/Program Files"))
    appdata = Path(os.environ.get("APPDATA", home / "AppData/Roaming"))
    codex = Path(os.environ.get("CODEX_HOME", home / ".codex"))
    return {
        "schema_version": 1, "backend": PROFILE,
        "acad_exe": first_existing([program / "Autodesk/AutoCAD 2021/acad.exe"]),
        "tianzheng_sys": first_existing([Path("D:/Tangent/TArchT20V10/SYS24x64"),
                                         Path("C:/Tangent/TArchT20V10/SYS24x64"),
                                         program / "Tangent/TArchT20V10/SYS24x64"]),
        "trusted_dll_dir": first_existing([appdata / "Tangent/TArch20V10/sys"]),
        "powershell_exe": first_existing([win / "System32/WindowsPowerShell/v1.0/powershell.exe"]),
        "python_exe": str(Path(sys.executable).resolve()),
        "capture_script": first_existing([Path(runtime_dir) / "vendor/cad_capture_compat.ps1",
                                           codex / "skills/cad-check-review/scripts/cad_capture_compat.ps1"]),
        "compiler": first_existing([win / "Microsoft.NET/Framework64/v4.0.30319/csc.exe"]),
        "com_progid": "AutoCAD.Application.24",
        "manual_dialog_registry": r"HKCU:\Software\Autodesk\AutoCAD\R24.0\ACAD-4101:804\FixedProfile\General Configuration",
    }

def load_profile(path):
    path = Path(path).resolve()
    data = read(path)
    check(isinstance(data, dict), "ENV_PROFILE_OBJECT_REQUIRED")
    check(set(data) == set(PATH_KEYS + OTHER_KEYS), "ENV_PROFILE_FIELDS")
    check(data["schema_version"] == 1, "ENV_SCHEMA_UNSUPPORTED")
    check(data["backend"] == PROFILE, "ENV_BACKEND_UNVALIDATED: use a separate adapter for another CAD/Tianzheng ABI")
    for key in PATH_KEYS:
        value = data[key]
        check(isinstance(value, str) and value.strip(), "ENV_PATH_MISSING:" + key)
        p = Path(os.path.expandvars(value)).expanduser()
        data[key] = str((p if p.is_absolute() else path.parent / p).resolve())
    check(data["com_progid"] == "AutoCAD.Application.24", "ENV_COM_ABI_UNVALIDATED")
    check(isinstance(data["manual_dialog_registry"], str) and data["manual_dialog_registry"].startswith("HKCU:\\"), "ENV_REGISTRY_SCOPE")
    return data

def doctor(data):
    problems = []
    if os.name != "nt": problems.append("Windows required for this backend")
    if sys.version_info < (3, 11): problems.append("Python 3.11 or newer required")
    if sys.maxsize <= 2**32: problems.append("64-bit Python required")
    for key in PATH_KEYS:
        value = data.get(key)
        p = Path(value) if value else None
        directory = key in ("tianzheng_sys", "trusted_dll_dir")
        if not p or not (p.is_dir() if directory else p.is_file()): problems.append("Missing " + key)
    if data.get("tianzheng_sys"):
        problems += ["Missing ARX: " + n for n in ARX if not (Path(data["tianzheng_sys"]) / n).is_file()]
    if data.get("acad_exe"):
        problems += ["Missing managed reference: " + n for n in REFS if not (Path(data["acad_exe"]).parent / n).is_file()]
    actual_version=binary_version(data["acad_exe"]) if data.get("acad_exe") and Path(data["acad_exe"]).is_file() else None
    if actual_version is None or actual_version[:2]!=[24,0]:problems.append("AutoCAD binary ABI is not verified as 24.0")
    if data.get("backend") != PROFILE: problems.append("Unsupported backend profile")
    return {"status": "DEPENDENCIES_FOUND" if not problems else "DEPENDENCIES_INCOMPLETE",
            "backend": data.get("backend"), "acad_product_version":actual_version, "issues": problems,
            "starts_cad": False, "installs_software": False,
            "boundary": "Dependency presence only. Licensing, module loading, save/reopen and actual CAD images require a target-machine isolated acceptance run."}
