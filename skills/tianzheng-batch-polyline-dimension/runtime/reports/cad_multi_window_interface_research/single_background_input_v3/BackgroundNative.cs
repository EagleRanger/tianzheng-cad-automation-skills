using System;
using System.Runtime.InteropServices;
namespace CadSingleBackgroundV1 {
    public static class Native {
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
        public sealed class Snapshot { public long hwnd; public uint pid; public uint thread; public bool target_minimized; }
        public static Snapshot Read(long target) {
            IntPtr hwnd=GetForegroundWindow(); uint pid;
            uint thread=GetWindowThreadProcessId(hwnd,out pid);
            return new Snapshot { hwnd=hwnd.ToInt64(),pid=pid,thread=thread,target_minimized=IsIconic(new IntPtr(target)) };
        }
    }
}
