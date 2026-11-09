// Fixed wrappers around AutoCAD's own -LAYOUT Template and -PURGE.
// Narrow rectangular 2D viewport restore; no engineering selection or coordinate inference.
using System;using System.IO;using System.Linq;using System.Reflection;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.EditorInput;using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public partial class NativeLayoutOpsV1 {
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public Host host;public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;}
 public class Request{public string kind,job_path,job_sha256;}
 public class Job{public string input,input_sha256,output,receipt,source,source_sha256,source_layout,target_layout,source_handle,layout,replacement_layout;public double[] offset;}
 static readonly BindingFlags F=BindingFlags.Static|BindingFlags.NonPublic;static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=100000000};
 static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static object Get(Type a,string n){return a.GetField(n,F).GetValue(null);}static object Call(Type a,string n,params object[] x){return a.GetMethod(n,F).Invoke(null,x);}static void Set(Type a,string n,object x){a.GetField(n,F).SetValue(null,x);}
 static void Write(string p,object o){using(var f=new FileStream(p,FileMode.CreateNew))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(o));}
 static HashSet<string> Layouts(Database db){var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);using(var tr=db.TransactionManager.StartTransaction()){var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);foreach(DBDictionaryEntry entry in dict)names.Add(entry.Key);}return names;}
 static HashSet<string> ModelRoots(Database db){using(var tr=db.TransactionManager.StartTransaction())return new HashSet<string>(((BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead)).Cast<ObjectId>().Where(x=>!x.IsErased).Select(x=>x.Handle.ToString()));}
 static void Stage(Job j,string s){File.WriteAllText(j.receipt+".stage.json",J.Serialize(new{stage=s,at=DateTime.UtcNow}));}
 static List<object> Purge(Database db){
  var result=new List<object>();
  for(int pass=0;pass<64;pass++){
   var ids=new ObjectIdCollection();using(var tr=db.TransactionManager.StartTransaction()){
    foreach(var tid in new[]{db.BlockTableId,db.LayerTableId,db.LinetypeTableId,db.TextStyleTableId,db.DimStyleTableId,db.RegAppTableId})
     foreach(ObjectId id in (SymbolTable)tr.GetObject(tid,OpenMode.ForRead))if(!id.IsErased)ids.Add(id);
    db.Purge(ids);if(ids.Count==0){tr.Commit();return result;}
    foreach(ObjectId id in ids){var o=(SymbolTableRecord)tr.GetObject(id,OpenMode.ForWrite);result.Add(new{handle=o.Handle.ToString(),type=o.GetRXClass().Name,name=o.Name});o.Erase();}tr.Commit();
   }
  }throw new InvalidOperationException("PURGE_DID_NOT_CONVERGE");
 }

 // Modal (document-context) command is required for Editor.Command.
 [CommandMethod("HLCADNATIVELAYOUTV6",CommandFlags.Modal)]public void Run(){
  var answer=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("Layout operation:"){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  Type a=null;Job job=null;bool owned=false,started=false;string stage="bind";
  try{
   var m=J.Deserialize<Manifest>(File.ReadAllText(answer.StringResult.Trim('"')));var p=System.Diagnostics.Process.GetCurrentProcess();Need(p.Id==m.host.pid&&p.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(p.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   a=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);CadAdapterContractV1.Check(a);Need(Eq(a.Assembly.Location,m.loaded_dll)&&NativeGeometryReadV1.Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Get(a,"dir"),m.session_dir),"ADAPTER_IDENTITY");Need(!(bool)Get(a,"busy")&&!(bool)Get(a,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");
   Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&NativeGeometryReadV1.Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");var req=J.Deserialize<Request>(File.ReadAllText(m.request));Need((req.kind=="layout_import"||req.kind=="purge_unused"||req.kind=="viewport_restore"||req.kind=="layout_delete")&&NativeGeometryReadV1.Hash(req.job_path)==req.job_sha256,"JOB_IDENTITY");Call(a,"CheckPath",req.job_path);job=J.Deserialize<Job>(File.ReadAllText(req.job_path));Call(a,"CheckLive",job.input,job.input_sha256);Call(a,"CheckOutput",job.output,job.receipt);
   var doc=(Document)Get(a,"doc");Need(doc==App.DocumentManager.MdiActiveDocument,"ACTIVE_DOCUMENT_CHANGED");var db=doc.Database;var before=Layouts(db);var model=ModelRoots(db);
   if(req.kind=="layout_import"||req.kind=="viewport_restore"){
    Call(a,"CheckPath",job.source);string hash;Need(((Dictionary<string,string>)Get(a,"approved")).TryGetValue(Path.GetFullPath(job.source),out hash)&&hash==job.source_sha256&&NativeGeometryReadV1.Hash(job.source)==hash,"SOURCE_NOT_ALLOWLISTED");Need(job.target_layout!="Model"&&job.source_layout!="Model"&&(req.kind=="layout_import"?!before.Contains(job.target_layout):before.Contains(job.target_layout)),"EXACT_TARGET_PAPER_LAYOUT_REQUIRED");
    using(var source=new Database(false,true)){source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,"");source.CloseInput(true);Need(Layouts(source).Contains(job.source_layout),"SOURCE_LAYOUT_MISSING");}
   }
   if(req.kind=="layout_delete")CheckDelete(db,job);
   Set(a,"busy",true);owned=true;started=true;HostApplicationServices.WorkingDatabase=db;string restored=null;object deleted=null;
   if(req.kind=="layout_delete"){stage="native_layout_delete";Stage(job,stage);deleted=DeleteLayout(db,job,()=>{});
   }else if(req.kind=="purge_unused"){
    stage="native_purge";Stage(job,stage);Purge(db);Need(Layouts(db).SetEquals(before),"LAYOUTS_CHANGED");
   }else if(req.kind=="viewport_restore"){
    stage="restore_viewport";Stage(job,stage);LayoutManager.Current.CurrentLayout=job.target_layout;using(var source=new Database(false,true)){source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,"");source.CloseInput(true);restored=NativeViewportRestoreV1.Apply(db,source,job.source_layout,job.source_handle,job.target_layout,job.offset);}
   }else{
    stage="native_layout_template";Stage(job,stage);doc.Editor.Command("_.-LAYOUT","_Template",job.source,job.source_layout);var added=Layouts(db).Except(before,StringComparer.OrdinalIgnoreCase).ToArray();Need(added.Length==1,"ONE_IMPORTED_LAYOUT_REQUIRED");
    if(!String.Equals(added[0],job.target_layout,StringComparison.OrdinalIgnoreCase))doc.Editor.Command("_.-LAYOUT","_Rename",added[0],job.target_layout);
    Need(Layouts(db).SetEquals(before.Concat(new[]{job.target_layout})),"LAYOUT_IMPORT_RESULT");LayoutManager.Current.CurrentLayout=job.target_layout;
   }
   Need(ModelRoots(db).SetEquals(model),"MODEL_ROOTS_CHANGED");stage="save";Stage(job,stage);if(deleted!=null){string expected=RetainedState(db,job.layout);db.SaveAs(job.output,DwgVersion.AC1032);VerifyDeleted(job.output,job,expected);string path=Path.GetFullPath(job.output),hash=NativeGeometryReadV1.Hash(path);((Dictionary<string,string>)Get(a,"approved"))[path]=hash;var gardens=(HashSet<string>)Get(a,"gardenPaths");if(gardens.Contains((string)Get(a,"currentPath")))gardens.Add(path);Set(a,"currentPath",path);Set(a,"currentHash",hash);Write(job.receipt,new{status="SAVED_STILL_OPEN",output=path,sha256=hash,pid=p.Id,native_save_reopen_verified=true,changes=deleted});Call(a,"State");}else if(restored==null)Call(a,"SaveModified",job.output,job.receipt,new{operation=req.kind,source_layout=job.source_layout,target_layout=job.target_layout,native_command=true,model_roots_preserved=true,visual_review="execution_review_required"});else{string expected=J.Serialize(NativeViewportRestoreV1.State(db,restored));db.SaveAs(job.output,DwgVersion.AC1032);using(var saved=new Database(false,true)){saved.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,"");saved.CloseInput(true);Need(CadValueCompareV1.Json(expected,J.Serialize(NativeViewportRestoreV1.State(saved,restored))),"VIEWPORT_SAVE_REOPEN_MISMATCH");}string path=Path.GetFullPath(job.output),hash=NativeGeometryReadV1.Hash(path);((Dictionary<string,string>)Get(a,"approved"))[path]=hash;var gardens=(HashSet<string>)Get(a,"gardenPaths");if(gardens.Contains((string)Get(a,"currentPath")))gardens.Add(path);Set(a,"currentPath",path);Set(a,"currentHash",hash);Write(job.receipt,new{status="SAVED_STILL_OPEN",output=path,sha256=hash,pid=p.Id,changes=new{operation=req.kind,created=restored,source=job.source,source_handle=job.source_handle,job.target_layout,job.offset,native_save_reopen_verified=true,model_roots_preserved=true,state=J.DeserializeObject(expected),visual_review="execution_review_required"}});Call(a,"State");}
  }catch(System.Exception e){if(a!=null&&started)Set(a,"blocked",true);if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status=started?"BOUND_MODULE_FAILED":"REJECTED_BEFORE_WRITE",source_sha256=job.input_sha256,write_started=started,committed=started,stage=stage,error=e.ToString(),replayed=false});}finally{if(owned)Set(a,"busy",false);}
 }
}
