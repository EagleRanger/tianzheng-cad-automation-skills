param(
    [Parameter(Mandatory)][int]$HostProcessId,
    [Parameter(Mandatory)][long]$HostWindowHandle,
    [Parameter(Mandatory)][string]$DesktopName,
    [Parameter(Mandatory)][string]$DocumentPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ReceiptPath,
    [string]$JobId,
    [switch]$UnchangedView,
    [ValidateRange(0,12000)][int]$SettleMilliseconds = 300
)
# A completed command receipt and CAD idle are different requirements. Neither
# a blind delay nor SendCommand's return proves that a new view is ready.
$ErrorActionPreference='Stop'
$timer=[Diagnostics.Stopwatch]::StartNew()
$timing=[ordered]@{status='STARTED';settle_ms=$SettleMilliseconds;unchanged_view=[bool]$UnchangedView}
$shown=$false
$h=[IntPtr]$HostWindowHandle
try {
    if(-not $UnchangedView){
        if(!$ReceiptPath -or !$JobId){throw 'COMPLETION_RECEIPT_REQUIRED'}
        $receipt=Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
        if($receipt.job_id -ne $JobId -or $receipt.status -notmatch '^(DONE|PARTIAL|PASS|COMPLETE|AUDIT)'){throw 'COMMAND_NOT_COMPLETED'}
    }
    if(-not ('PrivateCadCapture' -as [type])){
        Add-Type -TypeDefinition @"
using System;using System.Text;using System.Runtime.InteropServices;
public static class PrivateCadCapture {
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]public static extern IntPtr GetThreadDesktop(uint t);
 [DllImport("user32.dll")]public static extern IntPtr OpenInputDesktop(uint f,bool i,uint a);
 [DllImport("user32.dll")]public static extern bool CloseDesktop(IntPtr h);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetUserObjectInformation(IntPtr h,int n,StringBuilder s,int len,out int needed);
 [DllImport("ole32.dll",CharSet=CharSet.Unicode)]static extern int CLSIDFromProgID(string p,out Guid g);
 [DllImport("oleaut32.dll",PreserveSig=false)]static extern void GetActiveObject(ref Guid g,IntPtr r,[MarshalAs(UnmanagedType.IUnknown)]out object o);
 public static object Acad(){Guid g;CLSIDFromProgID("AutoCAD.Application.24",out g);object o;GetActiveObject(ref g,IntPtr.Zero,out o);return o;}
 public static string Name(IntPtr h){int n;var s=new StringBuilder(512);if(!GetUserObjectInformation(h,2,s,s.Capacity*2,out n))throw new Exception("DESKTOP_NAME");return s.ToString();}
 public static string Input(){var h=OpenInputDesktop(0,false,1);try{return Name(h);}finally{CloseDesktop(h);}}
}
"@
    }
    [uint32]$foundPid=0
    $thread=[PrivateCadCapture]::GetWindowThreadProcessId($h,[ref]$foundPid)
    $actualDesk=[PrivateCadCapture]::Name([PrivateCadCapture]::GetThreadDesktop($thread))
    $inputBefore=[PrivateCadCapture]::Input()
    if($foundPid -ne $HostProcessId -or $actualDesk -ne $DesktopName -or $actualDesk -eq $inputBefore -or $inputBefore -ne 'Default'){throw 'PRIVATE_HOST_IDENTITY'}
    $cad=[PrivateCadCapture]::Acad()
    if([long]$cad.HWND -ne $HostWindowHandle){throw 'COM_HOST_IDENTITY'}
    $doc=$cad.ActiveDocument
    if(![string]::Equals($doc.FullName,$DocumentPath,[StringComparison]::OrdinalIgnoreCase)){throw 'DOCUMENT_IDENTITY'}
    $deadline=[DateTime]::UtcNow.AddSeconds(5)
    while(!$cad.GetAcadState().IsQuiescent -or [int]$doc.GetVariable('CMDACTIVE') -ne 0){
        if([DateTime]::UtcNow -ge $deadline){throw 'CAD_NOT_IDLE'}
        Start-Sleep -Milliseconds 100
    }
    $timing.ready_ms=$timer.Elapsed.TotalMilliseconds
    $timing.document=$doc.FullName
    $timing.saved_before=[bool]$doc.Saved
    $timing.layout=$doc.ActiveLayout.Name
    $timing.input_desktop_before=$inputBefore
    $timing.host_desktop=$actualDesk
    $initialVisible=[PrivateCadCapture]::IsWindowVisible($h)
    if(!$initialVisible){[void][PrivateCadCapture]::ShowWindow($h,4);$shown=$true}
    if($SettleMilliseconds){Start-Sleep -Milliseconds $SettleMilliseconds}
    $timing.capture_start_ms=$timer.Elapsed.TotalMilliseconds
    & (Join-Path $PSScriptRoot 'cad_capture_compat.ps1') -OutputPath $OutputPath -WindowHandle $HostWindowHandle -ProcessId $HostProcessId -TitleContains ([IO.Path]::GetFileName($DocumentPath)) -Backend PrintWindow | Out-Null
    $timing.capture_end_ms=$timer.Elapsed.TotalMilliseconds
    $timing.saved_after=[bool]$doc.Saved
    $timing.status='PASS'
} catch {
    $timing.status='FAIL';$timing.error=$_.Exception.Message
} finally {
    if($shown){[void][PrivateCadCapture]::ShowWindow($h,0)}
    if('PrivateCadCapture' -as [type]){
        $timing.input_desktop_after=[PrivateCadCapture]::Input()
        $timing.visible_after=[PrivateCadCapture]::IsWindowVisible($h)
        if($timing.input_desktop_after -ne 'Default'){$timing.status='FAIL';$timing.error='INPUT_DESKTOP_CHANGED'}
    }
    $timing.total_ms=$timer.Elapsed.TotalMilliseconds
    $timing | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ([IO.Path]::ChangeExtension($OutputPath,'.timing.json')) -Encoding utf8
}
if($timing.status -ne 'PASS'){throw $timing.error}
$timing | ConvertTo-Json -Compress
