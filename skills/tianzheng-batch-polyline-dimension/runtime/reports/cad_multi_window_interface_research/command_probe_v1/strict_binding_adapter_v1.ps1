. (Join-Path $PSScriptRoot '../v3/cad_multi_owner_preflight_contract_v3.ps1')
function Assert-ReadWorkerLeaseV1 {
    $controller = Get-Process -Id $LeaseControllerPid -ErrorAction Stop
    if ((ConvertTo-CadTargetV1StartTicks $controller.StartTime.ToUniversalTime().ToString('o')) -ne (ConvertTo-CadTargetV1StartTicks $LeaseControllerStartUtc)) { throw 'LEASE_CONTROLLER_REUSED_OR_GONE' }
    $lease = Get-Content -LiteralPath (Join-Path $root '.cad-operation-owner.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$lease.process_id -ne $LeaseControllerPid -or [string]$lease.operation_id -cne $script:validated.run_id) { throw 'LEASE_RECORD_MISMATCH' }
    $mutex = [Threading.Mutex]::OpenExisting('Local\Codex.TianzhengCad.Exclusive.v1')
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if ($acquired) { throw 'SERIAL_LEASE_NOT_HELD_BY_CONTROLLER' }
    } finally { if ($acquired) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Get-ReadWorkerSnapshotV1($Owner) {
    Assert-ReadWorkerLeaseV1
    $process = Get-Process -Id ([int]$Owner.process_id) -ErrorAction Stop
    $hwnd = [IntPtr]([long]$Owner.window_handle)
    [pscustomobject]@{
        process_id=$process.Id;process_start_time_utc=$process.StartTime.ToUniversalTime().ToString('o');process_image_path=$process.Path
        window_handle=[long]$hwnd;window_process_id=[CadMultiOwnerReadBridgeV1]::WindowPid($hwnd)
        window_valid=[CadMultiOwnerReadBridgeV1]::IsWindow($hwnd);window_enabled=[CadMultiOwnerReadBridgeV1]::IsWindowEnabled($hwnd)
        modal_state=[CadMultiOwnerReadBridgeV1]::ModalState([uint32]$process.Id,$hwnd)
        responding=[bool]$process.Responding;serial_lease_held=$true
    }
}

function Get-ReadWorkerBindingV1($Owner) {
    $snapshot = Get-ReadWorkerSnapshotV1 $Owner
    $entries = @([CadMultiOwnerReadBridgeV1]::Enumerate())
    $result = Select-CadExactTargetCandidateV1 -Entries $entries -Expected $Owner -Snapshot $snapshot -Intent Execute
    if ($result.status -cne 'PASS') { throw "STRICT_BINDING_BLOCKED:$($result.code)" }
    # ROT getters may take time; refresh the OS tuple after COM admission too.
    $fresh = Get-ReadWorkerSnapshotV1 $Owner
    foreach ($field in @('process_id','process_start_time_utc','process_image_path','window_handle','window_process_id','window_valid','window_enabled','modal_state','responding')) {
        if ([string]$snapshot.$field -cne [string]$fresh.$field) { throw "OWNER_CHANGED_DURING_BIND:$field" }
    }
    $result
}
function Initialize-CadProbeBridgeV1 {
    if(-not('CadMultiOwnerReadBridgeV1'-as[type])) {
        Add-Type -TypeDefinition @'
using System;using System.Collections.Generic;using System.Runtime.InteropServices;using System.Runtime.InteropServices.ComTypes;using System.Text;
public static class CadMultiOwnerReadBridgeV1 {
 [DllImport("ole32.dll")] static extern int GetRunningObjectTable(int r,out IRunningObjectTable t);
 [DllImport("ole32.dll")] static extern int CreateBindCtx(int r,out IBindCtx c);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h,uint cmd);
 delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb,IntPtr p);
 public static uint WindowPid(IntPtr h){uint p;GetWindowThreadProcessId(h,out p);return p;}
 public static string ModalState(uint p,IntPtr main){
  if(!IsWindow(main))return "UNKNOWN";if(!IsWindowEnabled(main))return "PRESENT";
  bool blocked=false;bool ok=EnumWindows((h,x)=>{if(h!=main&&WindowPid(h)==p&&IsWindowVisible(h)){var s=new StringBuilder(256);GetClassName(h,s,256);if(s.ToString()=="#32770"||GetWindow(h,4)==main)blocked=true;}return true;},IntPtr.Zero);
  return !ok?"UNKNOWN":blocked?"PRESENT":"NONE";
 }
 public sealed class Entry{public string Name;public object Instance;}
 public static List<Entry> Enumerate(){
  IRunningObjectTable t=null;IBindCtx c=null;IEnumMoniker e=null;var result=new List<Entry>();
  try {Marshal.ThrowExceptionForHR(GetRunningObjectTable(0,out t));Marshal.ThrowExceptionForHR(CreateBindCtx(0,out c));t.EnumRunning(out e);var m=new IMoniker[1];int hr;
   while((hr=e.Next(1,m,IntPtr.Zero))==0){try{string n;object o;m[0].GetDisplayName(c,null,out n);t.GetObject(m[0],out o);if(o!=null)result.Add(new Entry{Name=n,Instance=o});}catch(COMException){/* unavailable entry cannot be used as identity */}finally{if(m[0]!=null){Marshal.ReleaseComObject(m[0]);m[0]=null;}}}
   if(hr!=1)Marshal.ThrowExceptionForHR(hr);return result;
  }finally{if(e!=null)Marshal.ReleaseComObject(e);if(c!=null)Marshal.ReleaseComObject(c);if(t!=null)Marshal.ReleaseComObject(t);}
 }
}
'@
    }
}

