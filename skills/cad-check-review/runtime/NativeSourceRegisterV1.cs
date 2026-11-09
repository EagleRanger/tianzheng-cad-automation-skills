// Management source intake: metadata only. Never opens, saves or edits a DWG.
using System;using System.IO;using System.Linq;using System.Reflection;using System.Collections.Generic;using System.Security.Cryptography;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.EditorInput;using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class NativeSourceRegisterV1 {
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;public Host host;}
 public class Request{public string kind,job_path,job_sha256;}
 public class Job{public string input,input_sha256,receipt,path,expected_sha256,role;}
 static readonly BindingFlags F=BindingFlags.Static|BindingFlags.NonPublic;
 static readonly JavaScriptSerializer J=new JavaScriptSerializer();
 static void Need(bool value,string message){if(!value)throw new InvalidOperationException(message);}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static string Hash(string p){using(var h=SHA256.Create())using(var f=File.Open(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))return BitConverter.ToString(h.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
 static object Get(Type t,string n){return t.GetField(n,F).GetValue(null);}
 static object Call(Type t,string n,params object[] a){return t.GetMethod(n,F).Invoke(null,a);}
 static void Write(string p,object v){using(var f=new FileStream(p,FileMode.CreateNew))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(v));}
 static void CheckRegistration(Dictionary<string,string> entries,string path,string hash){string old;Need(!entries.TryGetValue(path,out old)||old==hash,"REGISTERED_SOURCE_CONFLICT");}
 static void SelfTest(){var d=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);d["a"]="one";CheckRegistration(d,"A","one");CheckRegistration(d,"b","two");bool rejected=false;try{CheckRegistration(d,"a","two");}catch(InvalidOperationException){rejected=true;}Need(rejected&&d.Count==1&&d["a"]=="one","METADATA_SELF_TEST");}
 [CommandMethod("HLCADSOURCEREGISTERV1",CommandFlags.Session)] public void Run(){
  var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nSource registration: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;
  Job job=null;Type adapter=null;bool owned=false,added=false,addedGarden=false;Dictionary<string,string> approved=null;HashSet<string> gardens=null;string path=null;
  try{
   var m=J.Deserialize<Manifest>(File.ReadAllText(a.StringResult.Trim('"')));var p=System.Diagnostics.Process.GetCurrentProcess();
   Need(p.Id==m.host.pid&&p.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(p.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   adapter=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);CadAdapterContractV1.Check(adapter);
   Need(Eq(adapter.Assembly.Location,m.loaded_dll)&&Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Get(adapter,"dir"),m.session_dir),"ADAPTER_IDENTITY");
   Need(!(bool)Get(adapter,"busy")&&!(bool)Get(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");
   Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   var r=J.Deserialize<Request>(File.ReadAllText(m.request));Call(adapter,"CheckPath",r.job_path);Need(r.kind=="source_register"&&Hash(r.job_path)==r.job_sha256,"JOB_IDENTITY");
   job=J.Deserialize<Job>(File.ReadAllText(r.job_path));Call(adapter,"CheckLive",job.input,job.input_sha256);Call(adapter,"CheckPath",job.receipt);Need(!File.Exists(job.receipt),"RECEIPT_EXISTS");
   path=Path.GetFullPath(job.path);Call(adapter,"CheckPath",path);Need(Path.GetExtension(path).Equals(".dwg",StringComparison.OrdinalIgnoreCase)&&Hash(path)==job.expected_sha256,"SOURCE_IDENTITY");
   Need(job.role=="garden"||job.role=="planting"||job.role=="reference","SOURCE_ROLE");
   var doc=Get(adapter,"doc");Need(doc==App.DocumentManager.MdiActiveDocument,"ACTIVE_DOCUMENT_CHANGED");var dirty=App.GetSystemVariable("DBMOD");SelfTest();
   approved=(Dictionary<string,string>)Get(adapter,"approved");gardens=(HashSet<string>)Get(adapter,"gardenPaths");CheckRegistration(approved,path,job.expected_sha256);
   Need(job.role!="planting"||!gardens.Contains(path),"SOURCE_ROLE_CONFLICT");
   adapter.GetField("busy",F).SetValue(null,true);owned=true;
   if(!approved.ContainsKey(path)){approved.Add(path,job.expected_sha256);added=true;}if(job.role=="garden")addedGarden=gardens.Add(path);
   Call(adapter,"CheckLive",job.input,job.input_sha256);Need(doc==App.DocumentManager.MdiActiveDocument&&Equals(dirty,App.GetSystemVariable("DBMOD")),"DOCUMENT_CHANGED");
   Write(job.receipt,new{status="SOURCE_REGISTERED_NO_DRAWING_CHANGE",source_sha256=job.input_sha256,registered_path=path,registered_sha256=job.expected_sha256,role=job.role,pid=p.Id,document_unchanged=true,metadata_self_test="PASS",dwg_written=false});
  }catch(System.Exception e){if(added)approved.Remove(path);if(addedGarden)gardens.Remove(path);if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status="REJECTED_BEFORE_WRITE",source_sha256=job.input_sha256,error=e.ToString(),write_started=false,committed=false,replayed=false,emergency=(string)null});}
  finally{if(owned)adapter.GetField("busy",F).SetValue(null,false);}
 }
}
