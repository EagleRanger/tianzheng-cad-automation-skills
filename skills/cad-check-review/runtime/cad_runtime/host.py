"""Read-only Windows host identity, including PID reuse protection."""
import ctypes, os
from ctypes import wintypes
from pathlib import Path
from .common import check


def process_identity(pid):
    """只读PID及创建时间，防止进程退出后PID重用；不附着COM/不碰前台。"""
    check(os.name == "nt", "HOST_PLATFORM: CAD宿主检查需要Windows")
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
    kernel.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(0x1000, False, int(pid))
    check(bool(handle), "HOST_UNAVAILABLE: 当前PID不存在或不可读；不据旧READY续发")
    try:
        exit_code = wintypes.DWORD()
        check(kernel.GetExitCodeProcess(handle, ctypes.byref(exit_code)) and exit_code.value == 259, "HOST_EXITED: 旧READY不代表宿主仍在运行")
        times = [wintypes.FILETIME() for _ in range(4)]
        check(kernel.GetProcessTimes(handle, *[ctypes.byref(t) for t in times]), "HOST_TIMES_UNAVAILABLE")
        size = wintypes.DWORD(32768); name = ctypes.create_unicode_buffer(size.value)
        check(kernel.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size)), "HOST_IMAGE_UNAVAILABLE")
        check(Path(name.value).name.lower() == "acad.exe", "HOST_NOT_AUTOCAD")
        return {"pid": int(pid), "created": (times[0].dwHighDateTime << 32) | times[0].dwLowDateTime,
                "image": name.value}
    finally:
        kernel.CloseHandle(handle)

