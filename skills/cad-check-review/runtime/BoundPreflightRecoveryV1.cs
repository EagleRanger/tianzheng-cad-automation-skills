// Reconcile one proven pre-clone rejection from the original module. Never replay it.
using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class BoundPreflightRecoveryV1 {
 const string OriginalModule="9796207639d7744af79e4dc92748ca23da352aae77bb241e2ebee82bc0182f71";
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=50000000};
 static readonly BindingFlags F=BindingFlags.Static|BindingFlags.NonPublic;
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public string request,request_sha256,failed_module,failed_module_sha256,loaded_dll,loaded_dll_sha256,session_dir,failure,failure_sha256,resolution;public Host host;}
 public class Request{public string kind,job_path,job_sha256;}
 public class Target{public string handle,type;}
 public class Job{public string input,input_sha256,output,receipt,source,source_sha256;public Target[] source_targets;}
 static string Hash(string p){using(var h=SHA256.Create())using(var s=File.Open(p,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))return BitConverter.ToString(h.ComputeHash(s)).Replace("-","").ToLowerInvariant();}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static void Need(bool x,string s){if(!x)throw new InvalidOperationException(s);}
 static object Get(Type a,string n){return a.GetField(n,F).GetValue(null);}
 static object Call(Type a,string n,params object[] args){return a.GetMethod(n,F).Invoke(null,args);}
 static void Write(string p,object o){using(var s=new FileStream(p,FileMode.CreateNew))using(var w=new StreamWriter(s,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(o));}
 [CommandMethod("HLCADPREFLIGHTRECOVERV1",CommandFlags.Session)] public void Run(){
  var answer=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nRecovery manifest: "){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  Manifest m=null;
  try{
   m=J.Deserialize<Manifest>(File.ReadAllText(answer.StringResult.Trim('"')));
   var p=System.Diagnostics.Process.GetCurrentProcess();Need(p.Id==m.host.pid&&p.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(p.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   var a=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);
   Need(Eq(a.Assembly.Location,m.loaded_dll)&&Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Get(a,"dir"),m.session_dir),"ADAPTER_IDENTITY");
   Need(m.failed_module_sha256==OriginalModule&&Hash(m.failed_module)==OriginalModule,"UNPROVEN_FAILURE_STAGE");
   Need((bool)Get(a,"blocked")&&!(bool)Get(a,"busy")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"EXPECTED_IDLE_HOLD");
   Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   var req=J.Deserialize<Request>(File.ReadAllText(m.request));Need(req.kind=="paper_copy"&&Hash(req.job_path)==req.job_sha256,"EXPECTED_PAPER_COPY");
   var job=J.Deserialize<Job>(File.ReadAllText(req.job_path));
   Need(Eq(job.receipt,m.failure)&&Hash(m.failure)==m.failure_sha256&&Eq(m.resolution,m.failure+".resolution.json")&&!File.Exists(m.resolution),"FAILURE_IDENTITY");
   var failure=J.Deserialize<Dictionary<string,object>>(File.ReadAllText(m.failure));string error=(string)failure["error"];
   Need((string)failure["status"]=="BOUND_MODULE_FAILED"&&!(bool)failure["committed"]&&!File.Exists(job.output),"NO_SAVED_COPY_EXPECTED");
   Need(job.source_targets.Length==1&&job.source_targets[0].type=="TDbText"&&error.StartsWith("System.InvalidOperationException: TARGET_BOUNDS_CHANGED:"+job.source_targets[0].handle+"\r\n")&&error.Contains("BoundCadEditsV1.Checked(")&&error.Contains("BoundCadEditsV1.ApplyPaperCopies("),"NOT_PROVEN_PRE_CLONE_REJECTION");
   Call(a,"CheckLive",job.input,job.input_sha256);Need(Hash(job.source)==job.source_sha256,"SOURCE_CHANGED");
   var doc=(Document)Get(a,"doc");Need(doc==App.DocumentManager.MdiActiveDocument&&doc.Database.TransactionManager.NumberOfActiveTransactions==0,"DOCUMENT_NOT_IDLE");
   string emergency=(string)failure["emergency"];Call(a,"CheckPath",emergency);Call(a,"VerifyDwg",emergency);
   a.GetField("blocked",F).SetValue(null,false);Call(a,"State");
   Write(m.resolution,new{status="REJECTED_BEFORE_CLONE_RECOVERED",request=m.request,request_sha256=m.request_sha256,job_sha256=req.job_sha256,failure_sha256=m.failure_sha256,source_sha256=job.input_sha256,reference_sha256=job.source_sha256,failed_module_sha256=OriginalModule,stage="source_identity_before_any_clone",completed=false,replayed=false,cad_entities_modified=false,emergency=emergency,emergency_sha256=Hash(emergency),pid=p.Id,created=m.host.created,live_document=doc.Name});
  }catch(System.Exception ex){if(m!=null&&!File.Exists(m.resolution))Write(m.resolution,new{status="RECOVERY_FAILED",error=ex.ToString()});}
 }
}
