using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
namespace CadCommandUiaV2 {
 // Port of the project's verified atomic JOB_LIST/stdio-handle boundary.
 // No CAD API, arbitrary PID attachment, breakaway or process-tree killing.
 public sealed class OwnHelperJob : IDisposable {
  [StructLayout(LayoutKind.Sequential)] struct Basic { public long processTime,jobTime;public uint flags;public UIntPtr min,max;public uint active;public UIntPtr affinity;public uint priority,scheduling; }
  [StructLayout(LayoutKind.Sequential)] struct Io {public ulong a,b,c,d,e,f;}
  [StructLayout(LayoutKind.Sequential)] struct Limits {public Basic basic;public Io io;public UIntPtr processMemory,jobMemory,peakProcess,peakJob;}
  [StructLayout(LayoutKind.Sequential)] struct Accounting {public long a,b,c,d;public uint faults,total,active,terminated;}
  [StructLayout(LayoutKind.Sequential)] struct Security {public int length;public IntPtr descriptor;public bool inherit;}
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Startup {public int size;public string reserved,desktop,title;public uint x,y,xs,ys,xc,yc,fill,flags;public ushort show,cb;public IntPtr ptr,input,output,error;}
  [StructLayout(LayoutKind.Sequential)] struct StartupEx {public Startup info;public IntPtr attributes;}
  [StructLayout(LayoutKind.Sequential)] struct Pi {public IntPtr process,thread;public uint pid,tid;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr sa,string name);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr OpenJobObject(uint access,bool inherit,string name);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int cls,ref Limits limits,int size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job,int cls,IntPtr data,int size,IntPtr length);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool member);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool CreatePipe(out IntPtr read,out IntPtr write,ref Security sa,uint size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateFile(string name,uint access,uint share,ref Security sa,uint disposition,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool InitializeProcThreadAttributeList(IntPtr list,int count,uint flags,ref IntPtr size);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool UpdateProcThreadAttribute(IntPtr list,uint flags,IntPtr attr,IntPtr value,IntPtr size,IntPtr old,IntPtr ret);
  [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,StringBuilder command,IntPtr psa,IntPtr tsa,bool inherit,uint flags,IntPtr env,string cwd,ref StartupEx startup,out Pi pi);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h,uint ms);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool PeekNamedPipe(IntPtr h,IntPtr b,uint n,IntPtr read,out uint available,IntPtr remain);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadFile(IntPtr h,byte[] b,uint n,out uint read,IntPtr overlap);
  IntPtr job,process,thread,outRead,errRead;
  MemoryStream stdout=new MemoryStream(),stderr=new MemoryStream();
  public string JobName {get;private set;} public uint ProcessId {get;private set;}
  public bool Resumed {get;private set;} public bool JobBoundBeforeResume {get;private set;}
  public bool StdoutEof {get;private set;} public bool StderrEof {get;private set;}
  public bool OwnJobStopAttempted {get;private set;} public bool OutputLimit {get;private set;}
  public bool Disposed {get;private set;}
  static void Need(bool ok,string name){if(!ok)throw new Win32Exception(Marshal.GetLastWin32Error(),name);}
  static T Query<T>(IntPtr j,int cls) where T:struct {
   IntPtr p=Marshal.AllocHGlobal(Marshal.SizeOf(typeof(T)));
   try{Need(QueryInformationJobObject(j,cls,p,Marshal.SizeOf(typeof(T)),IntPtr.Zero),"QueryOwnJob");return (T)Marshal.PtrToStructure(p,typeof(T));}
   finally{Marshal.FreeHGlobal(p);}
  }
  public static void VerifyOwnMembership(string name){
   if(name==null||!name.StartsWith("Local\\Codex.CadCommandUia.",StringComparison.Ordinal)||name.Length!=58)throw new InvalidOperationException("JOB_NAME_INVALID");
   IntPtr j=OpenJobObject(4,false,name);Need(j!=IntPtr.Zero,"OpenExactJob");
   try{bool member;Need(IsProcessInJob(GetCurrentProcess(),j,out member),"IsSelfInExactJob");if(!member)throw new InvalidOperationException("SELF_NOT_IN_EXACT_JOB");CheckLimits(Query<Limits>(j,9));}
   finally{CloseHandle(j);}
  }
  static void CheckLimits(Limits l){
   if(l.basic.flags!=8968||l.basic.active!=1||l.processMemory.ToUInt64()!=536870912UL||l.jobMemory.ToUInt64()!=536870912UL)throw new InvalidOperationException("JOB_LIMITS_CHANGED");
  }
  public long PeakJobBytes {get{return checked((long)Query<Limits>(job,9).peakJob.ToUInt64());}}
  public uint ActiveProcesses {get{return Query<Accounting>(job,1).active;}}
  public bool RootExited {get{return process!=IntPtr.Zero&&WaitForSingleObject(process,0)==0;}}
  public uint ExitCode {get{uint c;Need(GetExitCodeProcess(process,out c),"OwnExitCode");return c;}}
  public string Stdout {get{return Encoding.UTF8.GetString(stdout.ToArray());}}
  public string Stderr {get{return Encoding.UTF8.GetString(stderr.ToArray());}}
  public int StdoutBytes {get{return (int)stdout.Length;}} public int StderrBytes {get{return (int)stderr.Length;}}
  static string Quote(string s){
   if(s==null||s.IndexOf('\0')>=0)throw new ArgumentException("BAD_ARGUMENT");
   StringBuilder b=new StringBuilder("\"");int slash=0;
   foreach(char c in s){if(c=='\\'){slash++;continue;}if(c=='"'){b.Append('\\',slash*2+1);b.Append(c);slash=0;continue;}b.Append('\\',slash);slash=0;b.Append(c);}
   b.Append('\\',slash*2);b.Append('"');return b.ToString();
  }
  public static OwnHelperJob Start(string executable,string script,string[] arguments,string directory){
   string system=Environment.GetEnvironmentVariable("CAD_POWERSHELL"); if(String.IsNullOrWhiteSpace(system))system=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"PowerShell","7","pwsh.exe"); system=Path.GetFullPath(system);
   if(!Path.GetFullPath(executable).Equals(system,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("FIXED_WORKER_IMAGE_REQUIRED");
   string leaf=Path.GetFileName(script);
   if(leaf!="command_worker_v1.ps1"&&leaf!="job_fixture_v1.ps1")throw new InvalidOperationException("FIXED_WORKER_SCRIPT_REQUIRED");
   OwnHelperJob x=new OwnHelperJob();List<IntPtr> temp=new List<IntPtr>();IntPtr attrs=IntPtr.Zero,stdioList=IntPtr.Zero,jobList=IntPtr.Zero;bool initialized=false;
   try{
    x.JobName="Local\\Codex.CadCommandUia."+Guid.NewGuid().ToString("N");
    x.job=CreateJobObject(IntPtr.Zero,x.JobName);Need(x.job!=IntPtr.Zero,"CreateOwnJob");
    Limits limits=new Limits();limits.basic.flags=8968;limits.basic.active=1;limits.processMemory=new UIntPtr(536870912U);limits.jobMemory=new UIntPtr(536870912U);
    Need(SetInformationJobObject(x.job,9,ref limits,Marshal.SizeOf(typeof(Limits))),"SetOwnJobLimits");CheckLimits(Query<Limits>(x.job,9));
    Security sa=new Security();sa.length=Marshal.SizeOf(typeof(Security));sa.inherit=true;
    IntPtr ow,ew;Need(CreatePipe(out x.outRead,out ow,ref sa,4096),"StdoutPipe");temp.Add(ow);Need(SetHandleInformation(x.outRead,1,0),"OwnStdoutNoInherit");
    Need(CreatePipe(out x.errRead,out ew,ref sa,4096),"StderrPipe");temp.Add(ew);Need(SetHandleInformation(x.errRead,1,0),"OwnStderrNoInherit");
    IntPtr input=CreateFile("NUL",0x80000000,3,ref sa,3,0,IntPtr.Zero);Need(input!=new IntPtr(-1),"NullInput");temp.Add(input);
    IntPtr required=IntPtr.Zero;InitializeProcThreadAttributeList(IntPtr.Zero,2,0,ref required);
    if(required.ToInt64()<=0||required.ToInt64()>65536)throw new InvalidOperationException("ATTR_SIZE");
    attrs=Marshal.AllocHGlobal(required);Need(InitializeProcThreadAttributeList(attrs,2,0,ref required),"InitOwnAttributes");initialized=true;
    stdioList=Marshal.AllocHGlobal(IntPtr.Size*3);Marshal.WriteIntPtr(stdioList,0,input);Marshal.WriteIntPtr(stdioList,IntPtr.Size,ow);Marshal.WriteIntPtr(stdioList,IntPtr.Size*2,ew);
    jobList=Marshal.AllocHGlobal(IntPtr.Size);Marshal.WriteIntPtr(jobList,x.job);
    Need(UpdateProcThreadAttribute(attrs,0,new IntPtr(0x20002),stdioList,new IntPtr(IntPtr.Size*3),IntPtr.Zero,IntPtr.Zero),"ExplicitStdioOnly");
    Need(UpdateProcThreadAttribute(attrs,0,new IntPtr(0x2000D),jobList,new IntPtr(IntPtr.Size),IntPtr.Zero,IntPtr.Zero),"AtomicOwnJobList");
    StartupEx si=new StartupEx();si.info.size=Marshal.SizeOf(typeof(StartupEx));si.info.flags=0x101;si.info.show=0;si.info.input=input;si.info.output=ow;si.info.error=ew;si.attributes=attrs;
    List<string> args=new List<string>(new string[]{executable,"-NoProfile","-NonInteractive","-MTA","-File",script,"-JobName",x.JobName});args.AddRange(arguments);
    StringBuilder cmd=new StringBuilder();foreach(string a in args){if(cmd.Length>0)cmd.Append(' ');cmd.Append(Quote(a));}
    Pi pi;Need(CreateProcess(executable,cmd,IntPtr.Zero,IntPtr.Zero,true,0x08000000|0x00080000|4,IntPtr.Zero,directory,ref si,out pi),"CreateSuspendedInOwnJob");
    x.process=pi.process;x.thread=pi.thread;x.ProcessId=pi.pid;
    foreach(IntPtr h in temp)Need(CloseHandle(h),"CloseParentStdioWriter");temp.Clear();
    bool member;Need(IsProcessInJob(x.process,x.job,out member),"VerifyCreatedChildJob");if(!member)throw new InvalidOperationException("CHILD_NOT_BOUND");
    x.JobBoundBeforeResume=true;Need(ResumeThread(x.thread)!=0xffffffff,"ResumeOwnedThread");x.Resumed=true;return x;
   }catch{x.Dispose();throw;}
   finally{if(initialized)DeleteProcThreadAttributeList(attrs);if(attrs!=IntPtr.Zero)Marshal.FreeHGlobal(attrs);if(stdioList!=IntPtr.Zero)Marshal.FreeHGlobal(stdioList);if(jobList!=IntPtr.Zero)Marshal.FreeHGlobal(jobList);foreach(IntPtr h in temp)CloseHandle(h);}
  }
  bool ReadOne(IntPtr h,MemoryStream capture){
   uint count;if(!PeekNamedPipe(h,IntPtr.Zero,0,IntPtr.Zero,out count,IntPtr.Zero)){if(Marshal.GetLastWin32Error()==109)return true;Need(false,"PeekOwnPipe");}
   if(count>0){byte[] b=new byte[Math.Min(count,4096)];uint n;Need(ReadFile(h,b,(uint)b.Length,out n,IntPtr.Zero),"ReadOwnPipe");int keep=(int)Math.Min(n,Math.Max(0,32768-capture.Length));capture.Write(b,0,keep);if(n>keep)OutputLimit=true;}
   return false;
  }
  public void Pump(){if(!StdoutEof)StdoutEof=ReadOne(outRead,stdout);if(!StderrEof)StderrEof=ReadOne(errRead,stderr);}
  public void StopOwnJob(){if(job!=IntPtr.Zero&&ActiveProcesses>0){OwnJobStopAttempted=true;Need(TerminateJobObject(job,124),"TerminateOnlyOwnJob");}}
  public void Dispose(){if(Disposed)return;Disposed=true;try{StopOwnJob();}finally{foreach(IntPtr h in new IntPtr[]{thread,process,outRead,errRead,job})if(h!=IntPtr.Zero)CloseHandle(h);job=process=thread=outRead=errRead=IntPtr.Zero;stdout.Dispose();stderr.Dispose();}}
 }
}
