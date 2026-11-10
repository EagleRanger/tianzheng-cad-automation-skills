# BINDING TEMPLATE ONLY: replace PID/created/HWND=0, DBMOD=-1, root/run/desktop/hash from current evidence; never infer or replay.
param([Parameter(Mandatory)][string]$JobName)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$dll='C:\RECEIVER\CAD_ROOT\reports\cad_multi_window_interface_research\independent_project_jobs_v3\bin\OwnStartupJobV4.dll'
$null=[Reflection.Assembly]::LoadFrom($dll)
[CadResearchStartupJobV4.OwnHelperJob]::VerifyOwnMembership($JobName)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OwnedCloseoutCandidate {
 [DllImport("oleaut32.dll", PreserveSig=false)] static extern void GetActiveObject(ref Guid clsid, IntPtr reserved, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 public static object Application() { var t=Type.GetTypeFromProgID("AutoCAD.Application.24",true); Guid g=t.GUID;object o;GetActiveObject(ref g,IntPtr.Zero,out o);return o; }
}
'@
$result=[ordered]@{status='UNKNOWN';phase='IDENTITY';target_pid=0;expected_hwnd=0;documents=@();error=$null;cad_mutation=$false;close_attempted=$false}
try {
 $p=Get-Process -Id 0 -ErrorAction Stop
 if($p.StartTime.ToUniversalTime().ToFileTimeUtc() -ne 0 -or $p.Path -ine 'C:\Program Files\Autodesk\AutoCAD 2021\acad.exe'){throw 'PROCESS_IDENTITY_MISMATCH'}
 $w=[IntPtr]0;$wpid=[uint32]0
 if(-not [OwnedCloseoutCandidate]::IsWindow($w)){throw 'WINDOW_MISSING'}
 $null=[OwnedCloseoutCandidate]::GetWindowThreadProcessId($w,[ref]$wpid)
 if($wpid -ne 0){throw 'WINDOW_OWNER_MISMATCH'}
 $result.phase='CANDIDATE_HWND'
 $app=[OwnedCloseoutCandidate]::Application()
 $actual=[int64]$app.HWND;$result.candidate_hwnd=$actual
 if($actual -ne 0){throw 'CANDIDATE_HWND_MISMATCH_NO_DOCUMENT_ACCESS'}
 $result.phase='DOCUMENT_READ'
 $state=$app.GetAcadState();$result.is_quiescent=[bool]$state.IsQuiescent
 $active=$app.ActiveDocument;$result.active_name=[string]$active.Name;$result.active_full_name=[string]$active.FullName
 $docs=@();foreach($doc in $app.Documents){$docs+= [ordered]@{name=[string]$doc.Name;full_name=[string]$doc.FullName;saved=[bool]$doc.Saved;dbmod=[int]$doc.GetVariable('DBMOD')}}
 $result.documents=$docs;$result.document_count=$docs.Count
 $result.cmdactive=[int]$active.GetVariable('CMDACTIVE');$result.cmdnames=[string]$active.GetVariable('CMDNAMES')
 $result.phase='READ_COMPLETE';$result.status='READ_COMPLETE_NO_CLOSE'
} catch {$result.error=$_.Exception.ToString()}
$result | ConvertTo-Json -Depth 8 -Compress
