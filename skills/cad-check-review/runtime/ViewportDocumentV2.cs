using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Reflection;using System.Security.Cryptography;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.ApplicationServices;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
using Job=BoundCadEditsV6.Job;
public class ViewportDocumentV5 {
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;public Host host;}
 public class Request{public string kind,job_path,job_sha256;}
 public class Result{public string operation,input_snapshot,input_snapshot_sha256;public object changes;public bool reopen_verified,model_unchanged,paper_windows_preserved;}
 public class Diagnostic{public string job,job_sha256,input,input_sha256,source,reference_sha256,output,receipt,operation,compare_source,compare_source_sha256;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=200000000,RecursionLimit=100};
 static readonly BindingFlags BF=BindingFlags.NonPublic|BindingFlags.Static;
 public static void Need(bool v,string why){if(!v)throw new InvalidOperationException(why);}
 public static string Hash(string p){return BoundCadEditsV6.Hash(p);}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 public static void Write(string p,object value){using(var f=new FileStream(p,FileMode.CreateNew,FileAccess.Write,FileShare.Read))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(value));}
 static string Digest(string s){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(System.Text.Encoding.UTF8.GetBytes(s)));}
 static string Model(Database db){var rows=new List<string>();using(var tr=db.TransactionManager.StartTransaction()){
  var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead);
  foreach(ObjectId id in ms){var e=(Entity)tr.GetObject(id,OpenMode.ForRead);rows.Add(e.Handle+"|"+e.GetRXClass().Name+"|"+e.Layer+"|"+J.Serialize(BoundCadEditsV6.Bounds(e)));}
 }return Digest(J.Serialize(rows));}
 static string PaperBounds(Entity e){
  var d=new Dictionary<string,object>{{"color",e.ColorIndex},{"lineweight",(int)e.LineWeight},{"ltscale",e.LinetypeScale}};
  var b=e as BlockReference;if(b!=null)d["transform"]=b.BlockTransform.ToArray();
  var p=e as Polyline;if(p!=null){var points=new List<double[]>();for(int i=0;i<p.NumberOfVertices;i++)points.Add(new[]{p.GetPoint3dAt(i).X,p.GetPoint3dAt(i).Y,p.GetPoint3dAt(i).Z,p.GetBulgeAt(i)});d["vertices"]=points;d["closed"]=p.Closed;}
  var t=e as DBText;if(t!=null){d["text"]=t.TextString;d["position"]=t.Position.ToString();d["height"]=t.Height;}
  var m=e as MText;if(m!=null){d["text"]=m.Contents;d["location"]=m.Location.ToString();d["height"]=m.TextHeight;}
  var l=e as Line;if(l!=null){d["start"]=l.StartPoint.ToString();d["end"]=l.EndPoint.ToString();}
  return J.Serialize(d);
 }
 static string Windows(Database db,Job job,string operation){var rows=new List<string>();using(var tr=db.TransactionManager.StartTransaction()){
  var ld=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);foreach(DBDictionaryEntry item in ld){var layout=(Layout)tr.GetObject(item.Value,OpenMode.ForRead);if(layout.ModelType)continue;var space=(BlockTableRecord)tr.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);
   foreach(ObjectId id in space){var e=(Entity)tr.GetObject(id,OpenMode.ForRead);var vp=e as Viewport;string data=vp==null?PaperBounds(e):J.Serialize(new{center=vp.CenterPoint.ToString(),width=vp.Width,height=vp.Height,locked=vp.Locked,clip=vp.NonRectClipEntityId.IsNull?null:vp.NonRectClipEntityId.Handle.ToString(),clip_on=vp.NonRectClipOn,camera=operation=="viewport_camera"&&job.pairs.Any(p=>p.target.handle.Equals(vp.Handle.ToString(),StringComparison.OrdinalIgnoreCase))?null:new{target=vp.ViewTarget.ToString(),direction=vp.ViewDirection.ToString(),center=vp.ViewCenter.ToString(),scale=vp.CustomScale,twist=vp.TwistAngle},frozen=operation=="viewport_layers"&&job.pairs.Any(p=>p.target.handle.Equals(vp.Handle.ToString(),StringComparison.OrdinalIgnoreCase))?null:vp.GetFrozenLayers().Cast<ObjectId>().Where(x=>!x.IsErased).Select(x=>((LayerTableRecord)tr.GetObject(x,OpenMode.ForRead)).Name).OrderBy(x=>x,StringComparer.Ordinal).ToArray()});rows.Add(layout.LayoutName+"|"+e.Handle+"|"+e.GetRXClass().Name+"|"+e.Layer+"|"+data);}
  }
 }return Digest(J.Serialize(rows));}
 static string Views(Database db,Job job){var rows=new List<object>();using(var tr=db.TransactionManager.StartTransaction()){
  var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);foreach(var pair in job.pairs){var vp=(Viewport)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(pair.target.handle,16)),0),OpenMode.ForRead);var layers=new List<object>();
   if(job.layer_pairs!=null)foreach(var p in job.layer_pairs){var l=(LayerTableRecord)tr.GetObject(lt[p.target],OpenMode.ForRead);var o=l.GetViewportOverrides(vp.ObjectId);layers.Add(new{layer=p.target,off=l.IsOff,frozen=l.IsFrozen,color=o.IsColorOverridden?o.Color.ToString():null,color_override=o.IsColorOverridden,weight=o.IsLineWeightOverridden?(int?)o.LineWeight:null,weight_override=o.IsLineWeightOverridden,transparency=o.IsTransparencyOverridden?(int?)o.Transparency.Alpha:null,transparency_override=o.IsTransparencyOverridden,linetype=o.IsLinetypeOverridden?o.LinetypeObjectId.Handle.ToString():null,linetype_override=o.IsLinetypeOverridden});}
   rows.Add(new{handle=vp.Handle.ToString(),target=vp.ViewTarget.ToString(),direction=vp.ViewDirection.ToString(),center=vp.ViewCenter.ToString(),scale=vp.CustomScale,twist=vp.TwistAngle,frozen=vp.GetFrozenLayers().Cast<ObjectId>().Where(x=>!x.IsErased).Select(x=>((LayerTableRecord)tr.GetObject(x,OpenMode.ForRead)).Name).OrderBy(x=>x,StringComparer.Ordinal).ToArray(),layers=layers});
  }
 }return J.Serialize(rows);}
 static string LayerSource(Database db,Job job){
  var rows=new List<object>();using(var tr=db.TransactionManager.StartTransaction()){
   var owner=BoundCadEditsV6.Space(tr,db,job.source_layout);var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);
   foreach(var pair in job.pairs){var vp=(Viewport)BoundCadEditsV6.Checked(tr,db,pair.source,owner);var frozen=new HashSet<ObjectId>(vp.GetFrozenLayers().Cast<ObjectId>());var layers=new List<object>();
    foreach(var p in job.layer_pairs){Need(lt.Has(p.source),"SOURCE_LAYER_MISSING:"+p.source);var l=(LayerTableRecord)tr.GetObject(lt[p.source],OpenMode.ForRead);var o=l.GetViewportOverrides(vp.ObjectId);layers.Add(new{layer=p.source,frozen=frozen.Contains(l.ObjectId),color=o.IsColorOverridden?o.Color.ToString():null,weight=o.IsLineWeightOverridden?(int?)o.LineWeight:null,transparency=o.IsTransparencyOverridden?(int?)o.Transparency.Alpha:null,linetype=o.IsLinetypeOverridden?((LinetypeTableRecord)tr.GetObject(o.LinetypeObjectId,OpenMode.ForRead)).Name:null,plotstyle=o.IsPlotStyleOverridden?o.PlotStyleName:null});}
    rows.Add(new{handle=vp.Handle.ToString(),layers=layers});
   }
  }return J.Serialize(rows);
 }
 static void CompareLayerSource(Job job,Diagnostic c){
  if(String.IsNullOrEmpty(c.compare_source))return;Need(Hash(c.compare_source)==c.compare_source_sha256,"COMPARISON_SOURCE_CHANGED");string actual,other;
  using(var db=new Database(false,true)){db.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);actual=LayerSource(db,job);}
  using(var db=new Database(false,true)){db.ReadDwgFile(c.compare_source,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);other=LayerSource(db,job);}
  Write(c.output+".source-comparison.json",new{status=actual==other?"RELEVANT_VIEWPORT_LAYER_FIELDS_EQUAL":"SOURCE_FIELDS_DIFFER",source=job.source,source_sha256=job.source_sha256,compare_source=c.compare_source,compare_source_sha256=c.compare_source_sha256,viewports=job.pairs.Length,layers=job.layer_pairs.Length,actual=J.DeserializeObject(actual),other=J.DeserializeObject(other)});Need(actual==other,"SOURCE_FIELDS_DIFFER");
 }
 public static Result Build(Job job,string operation){
  Need(operation=="viewport_camera"||operation=="viewport_layers","VIEWPORT_OPERATION_REQUIRED");Need(Hash(job.input)==job.input_sha256&&Hash(job.source)==job.source_sha256&&!File.Exists(job.output),"INPUT_OUTPUT_IDENTITY");
  var original=App.DocumentManager.MdiActiveDocument;var previous=HostApplicationServices.WorkingDatabase;Document staging=null;var result=new Result{operation=operation};string model,windows,views;
  try{
   ViewportCameraDataV3.Row[] cameras=null;
   if(operation=="viewport_camera")using(var source=new Database(false,true)){source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,null);source.CloseInput(true);HostApplicationServices.WorkingDatabase=source;cameras=ViewportCameraDataV3.Read(source,job);HostApplicationServices.WorkingDatabase=previous;}
   string input=job.output+".staging.dwg";Need(!File.Exists(input),"STAGING_EXISTS");File.Copy(job.input,input,false);
   staging=App.DocumentManager.Open(input,false);App.DocumentManager.MdiActiveDocument=staging;
   using(staging.LockDocument()){
    var dest=staging.Database;HostApplicationServices.WorkingDatabase=dest;model=Model(dest);windows=Windows(dest,job,operation);
    if(operation=="viewport_camera")result.changes=ViewportCameraDataV3.Apply(dest,job,cameras);
    else if(Hash(job.source)==job.input_sha256)result.changes=BoundViewportOpsV5.Apply(dest,dest,job,operation);
    else using(var source=new Database(false,true)){source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,null);source.CloseInput(true);result.changes=BoundViewportOpsV5.Apply(source,dest,job,operation);}
    staging.Editor.Regen();Need(Model(dest)==model&&Windows(dest,job,operation)==windows,"UNRELATED_OBJECT_CHANGED");views=Views(dest,job);dest.SaveAs(job.output,DwgVersion.AC1032);
    if(Model(dest)!=model||Windows(dest,job,operation)!=windows||Views(dest,job)!=views){Write(job.output+".save-diff.json",new{model_equal=Model(dest)==model,paper_equal=Windows(dest,job,operation)==windows,views_before=views,views_after=Views(dest,job)});throw new InvalidOperationException("NATIVE_SAVE_CHANGED");}
   }
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;staging.CloseAndDiscard();staging=null;
   using(var db=new Database(false,true)){db.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;db.ResolveXrefs(false,false);var sameModel=Model(db)==model;var sameWindows=Windows(db,job,operation)==windows;var readViews=Views(db,job);var sameViews=readViews==views;if(!sameModel||!sameWindows||!sameViews){Write(job.output+".validation-diff.json",new{model_equal=sameModel,paper_equal=sameWindows,views_equal=sameViews,views_before=views,views_after=readViews});throw new InvalidOperationException("REOPEN_CHANGED");}HostApplicationServices.WorkingDatabase=previous;}
   Need(Hash(job.input)==job.input_sha256&&Hash(job.source)==job.source_sha256,"INPUT_CHANGED");result.reopen_verified=true;result.model_unchanged=true;result.paper_windows_preserved=true;return result;
  }finally{HostApplicationServices.WorkingDatabase=previous;App.DocumentManager.MdiActiveDocument=original;if(staging!=null)staging.CloseAndDiscard();}
 }

 [CommandMethod("HLCADVIEWPORTDOCUMENTDIAGV5",CommandFlags.Session)]public void Diagnose(){
  var doc=App.DocumentManager.MdiActiveDocument;var a=doc.Editor.GetString(new PromptStringOptions("\nSide diagnostic config: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Diagnostic c=null;string name=doc.Name;object dirty=App.GetSystemVariable("DBMOD");
  Type adapter=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);Need(!(bool)Field(adapter,"busy"),"SESSION_BUSY");Set(adapter,"busy",true);try{c=J.Deserialize<Diagnostic>(File.ReadAllText(a.StringResult.Trim('"')));Need(Hash(c.job)==c.job_sha256,"DIAG_JOB_HASH");var job=J.Deserialize<Job>(File.ReadAllText(c.job));job.input=c.input;job.input_sha256=c.input_sha256;job.source=c.source;job.source_sha256=c.reference_sha256;job.output=c.output;CompareLayerSource(job,c);var result=Build(job,c.operation);Need(doc.Name==name&&App.GetSystemVariable("DBMOD").Equals(dirty),"LIVE_CHANGED");Write(c.receipt,new{status="ISOLATED_PROJECT_NATIVE_VERIFIED",output=c.output,sha256=Hash(c.output),changes=result,live_document_unchanged=true});}
  catch(System.Exception ex){if(c!=null&&!File.Exists(c.receipt))Write(c.receipt,new{status="DIAGNOSTIC_FAILED",error=ex.ToString(),live_document_unchanged=doc.Name==name});}finally{Set(adapter,"busy",false);}
 }
 static object Field(Type t,string n){return t.GetField(n,BF).GetValue(null);}static void Set(Type t,string n,object v){t.GetField(n,BF).SetValue(null,v);}static object Call(Type t,string n,params object[] args){return t.GetMethod(n,BF).Invoke(null,args);}
 [CommandMethod("HLCADVIEWPORTDOCUMENTV7",CommandFlags.Session)] public void Run(){
  var answer=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nExact viewport manifest: "){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  Type adapter=null;Job job=null;bool busy=false,activating=false;
  try{
   var m=J.Deserialize<Manifest>(File.ReadAllText(answer.StringResult.Trim('"')));var proc=System.Diagnostics.Process.GetCurrentProcess();
   Need(proc.Id==m.host.pid&&proc.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(proc.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   adapter=AppDomain.CurrentDomain.GetAssemblies().Select(a=>a.GetType("V736BaseSession",false)).Single(t=>t!=null);
   CadAdapterContractV1.CheckBaseReplace(adapter);
   Need(Eq(adapter.Assembly.Location,m.loaded_dll)&&Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Field(adapter,"dir"),m.session_dir),"ADAPTER_IDENTITY");
   Need(!(bool)Field(adapter,"busy")&&!(bool)Field(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");
   Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   var req=J.Deserialize<Request>(File.ReadAllText(m.request));Need((req.kind=="viewport_camera"||req.kind=="viewport_layers")&&Hash(req.job_path)==req.job_sha256,"VIEWPORT_JOB_REQUIRED");Call(adapter,"CheckPath",req.job_path);
   job=J.Deserialize<Job>(File.ReadAllText(req.job_path));Call(adapter,"CheckLive",job.input,job.input_sha256);Call(adapter,"CheckOutput",job.output,job.receipt);Call(adapter,"CheckPath",job.source);
   var approved=(Dictionary<string,string>)Field(adapter,"approved");string hash;Need(approved.TryGetValue(Path.GetFullPath(job.source),out hash)&&hash==job.source_sha256,"SOURCE_NOT_ALLOWLISTED");
   Set(adapter,"busy",true);busy=true;
   // Preserve even pending view/settings changes automatically, before side-DB
   // work. Exact object assertions still run against this native saved snapshot.
   var buildJob=J.Deserialize<Job>(J.Serialize(job));
   if(Convert.ToInt32(App.GetSystemVariable("DBMOD"))!=0){
    string protection=job.output+".input.dwg";Need(!File.Exists(protection),"INPUT_PROTECTION_EXISTS");
    var live=(Document)Field(adapter,"doc");using(live.LockDocument())live.Database.SaveAs(protection,DwgVersion.AC1032);
    Call(adapter,"VerifyDwg",protection);buildJob.input=protection;buildJob.input_sha256=Hash(protection);approved[Path.GetFullPath(protection)]=buildJob.input_sha256;
   }
   var result=Build(buildJob,req.kind);result.input_snapshot=buildJob.input;result.input_snapshot_sha256=buildJob.input_sha256;Call(adapter,"CheckLive",job.input,job.input_sha256);
   string candidateHash=Hash(job.output);approved[Path.GetFullPath(job.output)]=candidateHash;
   var type=adapter.GetNestedType("Switch",BindingFlags.Public);var sw=Activator.CreateInstance(type);
   foreach(var pair in new Dictionary<string,string>{{"input",job.input},{"input_sha256",job.input_sha256},{"next_path",job.output},{"next_sha256",candidateHash},{"save_path",job.output+".pre_replace.dwg"},{"receipt",job.receipt+".switch.json"}})type.GetField(pair.Key).SetValue(sw,pair.Value);
   activating=true;Call(adapter,"SwitchDocument",sw);
   Write(job.receipt,new{status="SAVED_STILL_OPEN",source_sha256=job.input_sha256,reference_sha256=job.source_sha256,output=job.output,sha256=candidateHash,live_document=((Document)Field(adapter,"doc")).Name,changes=result,pid=proc.Id});
  }catch(System.Exception error){if(error is TargetInvocationException&&error.InnerException!=null)error=error.InnerException;if(activating&&adapter!=null)Set(adapter,"blocked",true);
   if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status="VIEWPORT_SIDE_FAILED",source_sha256=job.input_sha256,active_document_changed=activating,candidate_path=job.output,candidate_exists=File.Exists(job.output),error=error.ToString()});
  }finally{if(busy)Set(adapter,"busy",false);}
 }
}
