param([Parameter(Mandatory=$true)][string]$Launch,[Parameter(Mandatory=$true)][string]$Session)
$ErrorActionPreference='Stop'
$m=Get-Content -LiteralPath $Launch -Raw -Encoding UTF8|ConvertFrom-Json
Add-Type @'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class CadStartupTip {
 public delegate bool CB(IntPtr h,IntPtr l);
 static readonly HashSet<long> sent=new HashSet<long>();
 [DllImport("user32.dll")]static extern bool EnumWindows(CB c,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static int Handle(uint pid){int count=0;EnumWindows((h,l)=>{uint p;GetWindowThreadProcessId(h,out p);if(p!=pid)return true;var t=new StringBuilder(256);var c=new StringBuilder(256);GetWindowText(h,t,256);GetClassName(h,c,256);if(c.ToString()=="#32770"&&t.ToString()=="日积月累"&&sent.Add(h.ToInt64())){if(PostMessage(h,0x10,IntPtr.Zero,IntPtr.Zero))count++;}return true;},IntPtr.Zero);return count;}
}
'@
$end=[DateTime]::UtcNow.AddSeconds(60);$closed=0
while([DateTime]::UtcNow -lt $end){
 if(Test-Path -LiteralPath (Join-Path $Session 'session_status.json')){break}
 if(-not (Get-Process -Id $m.pid -ErrorAction SilentlyContinue)){break}
 $closed+=[CadStartupTip]::Handle([uint32]$m.pid)
 Start-Sleep -Milliseconds 500
}
@{pid=$m.pid;known_tips_closed=$closed;ready=(Test-Path -LiteralPath (Join-Path $Session 'session_status.json'));unknown_dialogs_untouched=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Session 'startup_helper.json') -Encoding UTF8
