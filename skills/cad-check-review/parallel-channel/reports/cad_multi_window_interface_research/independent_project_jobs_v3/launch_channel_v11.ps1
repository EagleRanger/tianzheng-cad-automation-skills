# Called only inside the original executor guard after READY/claim validation.
function Start-FixedV3Host($Boot,[string]$BootPath,[string]$BootHash,[string]$Root){
 $ErrorActionPreference='Stop'
 if(-not('FixedV3PrivateLaunch'-as[type])){Add-Type @'
using System;using System.Text;using System.Runtime.InteropServices;
public static class FixedV3PrivateLaunch {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]public struct SI{public int cb;public string reserved,desktop,title;public uint x,y,xsize,ysize,xchars,ychars,fill,flags;public short show,reserved2;public IntPtr reservedPtr,stdin,stdout,stderr;}
 [StructLayout(LayoutKind.Sequential)]public struct PI{public IntPtr process,thread;public uint pid,tid;}
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern IntPtr CreateDesktop(string name,IntPtr device,IntPtr mode,uint flags,uint access,IntPtr sa);
 [DllImport("user32.dll")]public static extern bool CloseDesktop(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]public static extern bool CreateProcess(string app,StringBuilder command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref SI si,out PI pi);
 [DllImport("kernel32.dll")]public static extern bool CloseHandle(IntPtr h);
}
'@}
 $acad='C:/Program Files/Autodesk/AutoCAD 2021/acad.exe';$sys=$Boot.machine_sys
 $trusted=Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Tangent/TArch20V10/sys'
 foreach($p in @($acad,$sys,$trusted)){if(-not(Test-Path -LiteralPath $p)){throw ('FIXED_V3_MACHINE_DEPENDENCY:'+ $p)}}
 if((Get-FileHash -LiteralPath $BootPath).Hash-cne$BootHash){throw 'FIXED_V3_BOOT_CHANGED'}
 foreach($arx in $Boot.machine_arx){if((Get-FileHash -LiteralPath $arx.path).Hash-cne$arx.sha256){throw 'FIXED_V3_MACHINE_ARX_CHANGED'}}
 $copies=@();foreach($relative in @(($script:FixedV3Prefix+'bin/CadChannelV11.dll'))){
  $source=Join-Path $Root $relative;$destination=Join-Path $trusted ('CXResearchV3_'+$BootHash.Substring(0,16)+'_'+[IO.Path]::GetFileName($source))
  [IO.File]::Copy($source,$destination,$false);if((Get-FileHash -LiteralPath $source).Hash-cne(Get-FileHash -LiteralPath $destination).Hash){throw 'FIXED_V3_STAGING_HASH'};$copies+=@{path=$destination;sha256=(Get-FileHash -LiteralPath $destination).Hash}
 }
 $desktopName='CXResearchV3_'+$BootHash.Substring(0,16)
 $scriptPath=Join-Path $Boot.session_dir 'boot.scr'
 $lines=@('_.ARX','_L',('"'+(Join-Path $sys 'tch_kernal.arx').Replace('\','/')+'"'))
 foreach($f in $copies){$lines+=@('_.NETLOAD',('"'+$f.path.Replace('\','/')+'"'))};$lines+='CXRESEARCHBOOTV3'
 $encoding=[Text.Encoding]::GetEncoding(936,[Text.EncoderExceptionFallback]::new(),[Text.DecoderExceptionFallback]::new())
 [IO.File]::WriteAllBytes($scriptPath,$encoding.GetBytes(($lines-join"`r`n")+"`r`n"))
 $desktop=[FixedV3PrivateLaunch]::CreateDesktop($desktopName,[IntPtr]::Zero,[IntPtr]::Zero,0,0x01FF,[IntPtr]::Zero)
 if($desktop-eq[IntPtr]::Zero){throw ('FIXED_V3_PRIVATE_DESKTOP_FAILED:'+ [Runtime.InteropServices.Marshal]::GetLastWin32Error())}
 $si=[FixedV3PrivateLaunch+SI]::new();$si.cb=[Runtime.InteropServices.Marshal]::SizeOf($si);$si.desktop=$desktopName;$si.flags=1;$si.show=4
 $pi=[FixedV3PrivateLaunch+PI]::new();$command=[Text.StringBuilder]::new(('"'+$acad+'" /nologo /b "'+$scriptPath+'"'))
 $before=[FixedV3PrivateLaunch]::GetForegroundWindow().ToInt64();$oldPath=$env:CX_RESEARCH_BOOT_V3;$oldHash=$env:CX_RESEARCH_BOOT_SHA256_V3
 try{$env:CX_RESEARCH_BOOT_V3=$BootPath;$env:CX_RESEARCH_BOOT_SHA256_V3=$BootHash;$ok=[FixedV3PrivateLaunch]::CreateProcess($acad,$command,[IntPtr]::Zero,[IntPtr]::Zero,$false,0x08000400,[IntPtr]::Zero,$sys,[ref]$si,[ref]$pi)}finally{$env:CX_RESEARCH_BOOT_V3=$oldPath;$env:CX_RESEARCH_BOOT_SHA256_V3=$oldHash}
 if(-not$ok){[void][FixedV3PrivateLaunch]::CloseDesktop($desktop);throw ('FIXED_V3_START_FAILED:'+ [Runtime.InteropServices.Marshal]::GetLastWin32Error())}
 [void][FixedV3PrivateLaunch]::CloseHandle($pi.thread);[void][FixedV3PrivateLaunch]::CloseHandle($pi.process)
 $p=Get-Process -Id $pi.pid
 $receipt=@{status='PRIVATE_DESKTOP_PROCESS_STARTED_NATIVE_READY_UNVERIFIED';pid=$pi.pid;created=$p.StartTime.ToFileTimeUtc();image=$p.Path;desktop=$desktopName;boot_path=$BootPath;boot_sha256=$BootHash;staged_dlls=$copies;foreground_before=$before;foreground_after=[FixedV3PrivateLaunch]::GetForegroundWindow().ToInt64();utc=[DateTimeOffset]::UtcNow.ToString('o')}
 Write-FixedV3NewJson (Join-Path $Boot.session_dir 'launch.json') $receipt
 [pscustomobject]@{receipt=$receipt;desktop_handle=$desktop;boot=$Boot;session=$Boot.session_dir;native=$null;clock=[Diagnostics.Stopwatch]::StartNew()}
}




