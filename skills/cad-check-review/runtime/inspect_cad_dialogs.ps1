param([Parameter(Mandatory=$true)][string]$Manifest)
$ErrorActionPreference='Stop'
$m=[IO.File]::ReadAllText($Manifest)|ConvertFrom-Json
$p=[Diagnostics.Process]::GetProcessById([int]$m.host.pid)
if($p.StartTime.ToUniversalTime().ToFileTimeUtc() -ne [int64]$m.host.created){throw 'HOST_REUSED'}
if(Test-Path -LiteralPath $m.receipt){throw 'RECEIPT_EXISTS'}
Add-Type @'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class CadDialogRead {
 public delegate bool CB(IntPtr h,IntPtr l);
 [DllImport("user32.dll")]static extern bool EnumWindows(CB f,IntPtr x);
 [DllImport("user32.dll")]static extern bool EnumChildWindows(IntPtr p,CB f,IntPtr x);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 static object Row(IntPtr h){var t=new StringBuilder(2000);var c=new StringBuilder(128);GetWindowText(h,t,t.Capacity);GetClassName(h,c,c.Capacity);return new{handle=h.ToInt64(),kind=c.ToString(),text=t.ToString(),visible=IsWindowVisible(h)};}
 public static object[] Read(uint pid){var rows=new List<object>();EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p!=pid||!IsWindowVisible(h))return true;var children=new List<object>();EnumChildWindows(h,(c,z)=>{children.Add(Row(c));return true;},IntPtr.Zero);rows.Add(new{window=Row(h),children});return true;},IntPtr.Zero);return rows.ToArray();}
}
'@
$r=@{status='READ_ONLY_DIALOGS';pid=$m.host.pid;windows=[CadDialogRead]::Read([uint32]$m.host.pid)}
[IO.File]::WriteAllText($m.receipt,($r|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
