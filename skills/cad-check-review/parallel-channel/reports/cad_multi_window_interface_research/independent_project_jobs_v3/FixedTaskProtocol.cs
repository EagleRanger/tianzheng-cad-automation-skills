using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace CadFixedResearchV3 {
 public sealed class FileRef { public string path; public string sha256; }
 public sealed class CaseInput { public string id; public string work; public string sha256; public string data_run; public string checkpoint; }
 public sealed class BootInput {
  public int schema_version; public string run_id; public string owner; public string root; public string session_dir;
  public string module_sha256; public string expires_utc; public string source; public string source_sha256;
  public CaseInput[] cases; public FileRef[] dependencies; public string machine_sys; public FileRef[] machine_arx;
 }
 public sealed class NativeTask {
  public int schema_version; public string run_id; public string owner; public string case_id; public string id; public string nonce;
  public string stage; public string expires_utc; public int pid; public long created; public long hwnd;
  public string document; public FileRef[] inputs;
 }
 public static class Protocol {
  public static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength=1048576, RecursionLimit=40 };
  public static readonly string[] Stages={"DISCOVER","GENERATE","POSTREAD","CHECKPOINT_READBACK"};
  public static void Require(bool ok,string code){if(!ok)throw new InvalidOperationException(code);}
  public static bool Equal(string a,string b){return String.Equals(a,b,StringComparison.OrdinalIgnoreCase);}
  public static void Token(string s){Require(s!=null&&Regex.IsMatch(s,@"\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z"),"TOKEN");}
  public static string Inside(string root,string path){
   Require(Path.IsPathRooted(path??""),"ABSOLUTE_PATH_REQUIRED");
   string r=Path.GetFullPath(root).TrimEnd('\\','/')+Path.DirectorySeparatorChar,p=Path.GetFullPath(path);
   Require(p.StartsWith(r,StringComparison.OrdinalIgnoreCase),"PATH_ESCAPE");
   string cursor=p;
   while(cursor.Length>=r.Length){if(File.Exists(cursor)||Directory.Exists(cursor))Require((File.GetAttributes(cursor)&FileAttributes.ReparsePoint)==0,"REPARSE_POINT");cursor=Path.GetDirectoryName(cursor);if(cursor==null)break;}
   return p;
  }
  public static string Hash(string path){using(var h=SHA256.Create())using(var f=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.Read))return BitConverter.ToString(h.ComputeHash(f)).Replace("-","");}
  public static void CheckFile(FileRef f){Require(f!=null&&Regex.IsMatch(f.sha256??"",@"\A[A-F0-9]{64}\z")&&Hash(f.path)==f.sha256,"FILE_HASH");}
  public static T Read<T>(string path){Require(new FileInfo(path).Length<=1048576,"JSON_SIZE");return Json.Deserialize<T>(File.ReadAllText(path,Encoding.UTF8));}
  public static void NewJson(string path,object value){
   string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
   using(var f=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None)){var bytes=new UTF8Encoding(false).GetBytes(Json.Serialize(value));f.Write(bytes,0,bytes.Length);f.Flush(true);}
   File.Move(temp,path);
  }
  public static DateTimeOffset Expiry(string value){return DateTimeOffset.ParseExact(value,"o",CultureInfo.InvariantCulture,DateTimeStyles.None);}
  public static bool Equivalent(object a,object b){
   if(a==null||b==null)return a==b;
   var x=a as Dictionary<string,object>;var y=b as Dictionary<string,object>;
   if(x!=null||y!=null){if(x==null||y==null||x.Count!=y.Count)return false;foreach(var k in x)if(!y.ContainsKey(k.Key)||!Equivalent(k.Value,y[k.Key]))return false;return true;}
   var aa=a as System.Collections.IList;var bb=b as System.Collections.IList;
   if(aa!=null||bb!=null){if(aa==null||bb==null||aa.Count!=bb.Count)return false;for(int i=0;i<aa.Count;i++)if(!Equivalent(aa[i],bb[i]))return false;return true;}
   if(a is string||b is string||a is bool||b is bool)return a.Equals(b);
   double na=Convert.ToDouble(a,CultureInfo.InvariantCulture),nb=Convert.ToDouble(b,CultureInfo.InvariantCulture);
   return !Double.IsNaN(na)&&!Double.IsInfinity(na)&&!Double.IsNaN(nb)&&!Double.IsInfinity(nb)&&Math.Abs(na-nb)<=0.000001;
  }
  public static void Fresh(string value){Require(DateTimeOffset.UtcNow<Expiry(value),"EXPIRED_NO_REPLAY");}
  public static CaseInput Case(BootInput b,string id){foreach(var c in b.cases)if(c.id==id)return c;throw new InvalidOperationException("CASE_NOT_ADMITTED");}
  public static void ValidateBoot(BootInput b,string bootPath,string selfHash){
   Require(b.schema_version==3&&b.module_sha256==selfHash,"BOOT_VERSION_OR_MODULE");Token(b.run_id);
   Require(b.owner=="A"||b.owner=="B","OWNER");Fresh(b.expires_utc);
   Require(Equal(Path.GetDirectoryName(bootPath),b.session_dir),"BOOT_DIRECTORY");Inside(b.root,b.session_dir);
   Require(b.cases!=null&&b.cases.Length==2,"CASE_COUNT");
   string single=b.owner=="A"?"A_ONLY":"B_ONLY";
   Require(b.cases[0].id==single&&b.cases[1].id=="AB","CASE_ORDER");
   CheckFile(new FileRef{path=b.source,sha256=b.source_sha256});
   var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(var c in b.cases){
    Inside(b.session_dir,c.work);Inside(b.session_dir,c.data_run);Inside(b.session_dir,c.checkpoint);
    Require(paths.Add(c.work)&&paths.Add(c.checkpoint)&&!Equal(c.work,b.source)&&!File.Exists(c.checkpoint),"CASE_PATH_OR_REPLAY");
    CheckFile(new FileRef{path=c.work,sha256=c.sha256});Require(c.sha256==b.source_sha256,"CLEAN_SOURCE_HASH");
   }
   Require(b.dependencies!=null&&b.dependencies.Length>=6,"DEPENDENCIES");
   foreach(var f in b.dependencies){Inside(b.root,f.path);Require(paths.Add(f.path),"DUPLICATE_DEPENDENCY");CheckFile(f);}
   string[] arx={"tch_kernal.arx","tch_utility.arx","tch_pipewire.arx","tch_pipebase.arx","tch_initstart.arx","tch_common.arx","tch3_kernal.arx"};
   Require(b.machine_arx!=null&&b.machine_arx.Length==arx.Length,"MACHINE_ARX_COUNT");
   for(int i=0;i<arx.Length;i++){var f=b.machine_arx[i];Inside(b.machine_sys,f.path);Require(Equal(f.path,Path.Combine(b.machine_sys,arx[i])),"MACHINE_ARX_PATH");CheckFile(f);}
  }
  public static void ValidateTask(BootInput b,NativeTask t,int pid,long created,long hwnd,int expectedStage){
   Require(t.schema_version==3&&t.run_id==b.run_id&&t.owner==b.owner,"TASK_OWNER_OR_RUN");Token(t.id);Token(t.nonce);
   Fresh(b.expires_utc);Fresh(t.expires_utc);
   Require(Expiry(t.expires_utc)<=Expiry(b.expires_utc),"EXTENDED_EXPIRY");
   Require(expectedStage>=0&&expectedStage<Stages.Length&&t.stage==Stages[expectedStage],"STAGE_ORDER_OR_REPLAY");
   var c=Case(b,t.case_id);Require(Equal(t.document,c.work),"DOCUMENT");
   Require(t.pid==pid&&t.created==created&&t.hwnd==hwnd&&hwnd!=0,"NATIVE_OWNER");
   Require(t.inputs!=null&&t.inputs.Length>0&&t.inputs.Length<=128,"INPUT_COUNT");
   var paths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(var f in t.inputs){Inside(c.data_run,f.path);Require(paths.Add(f.path),"DUPLICATE_INPUT");CheckFile(f);}
  }
 }
}
