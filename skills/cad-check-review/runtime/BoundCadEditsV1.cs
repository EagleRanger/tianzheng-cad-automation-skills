// Narrow native operations attached to the existing bound session. No new CAD host.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Reflection;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;

public class BoundCadEditsV1 {
 public class Target {public string handle,type,layer;public double[] bounds;}
 public class Flags {public bool on,frozen;}
 public class LayerEdit {public string name;public Flags before,after;}
 public class Pair {public Target source,target;public string[] preserve_target_endpoints;}
 public class Host {public int pid;public long created;public string image;}
 public class Job {
  public string input,input_sha256,output,receipt,source,source_sha256;
  public string source_layout,target_layout,target_layer;
  public Target source_frame;public Target[] source_targets,target_frames;
  public PolylineGeometryV1.Create[] creations;public HatchPatternPatchV1.Edit[] hatches;public PolylineGeometryV1.Edit[] edits;public PolylineGeometryV1.Offset[] offsets;
  public IndexAnchorV1.Edit[] indexes;public Pair[] pairs;public LayerEdit[] layers;public string[] handles;
  public NativeAnnotationUpdateV1.Edit[] annotations;
  public string layout,image;public double x,y,width,height;public double[] bounds;
 }
 public class Request {public string kind,job_path,job_sha256;}
 public class Dispatch {
  public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;
  public Host host;
 }
 public class Repair : Dispatch {public string failure,failure_sha256,repair_receipt;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=50000000,RecursionLimit=100};
 static readonly BindingFlags Private=BindingFlags.Static|BindingFlags.NonPublic;
 public static string Hash(string path){using(var h=SHA256.Create())using(var f=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))return BitConverter.ToString(h.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static void Require(bool ok,string error){if(!ok)throw new InvalidOperationException(error);}
 static void WriteNew(string path,object obj){using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(obj));}
 static ObjectId Id(Database db,string h){return db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0);}
 public static double[] Bounds(Entity e){var x=e.GeometricExtents;return new[]{x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};}
 public static Target Identity(Entity e){return new Target{handle=e.Handle.ToString(),type=e.GetRXClass().Name,layer=e.Layer,bounds=Bounds(e)};}
 public static List<object> TextParts(Entity entity,int depth=0){
  var result=new List<object>();
  var d=entity as DBText;var m=entity as MText;
  if(d!=null)result.Add(new{text=d.TextString,position=new[]{d.Position.X,d.Position.Y,d.Position.Z},height=d.Height,width_factor=d.WidthFactor});
  else if(m!=null)result.Add(new{text=m.Contents,position=new[]{m.Location.X,m.Location.Y,m.Location.Z},height=m.TextHeight,width=m.Width});
  else if(depth<5){
   var parts=new DBObjectCollection();try{entity.Explode(parts);foreach(DBObject part in parts){var e=part as Entity;if(e!=null)result.AddRange(TextParts(e,depth+1));}}
   finally{foreach(DBObject part in parts)part.Dispose();}
  }
  return result;
 }
 public static object ReadPaper(Database source,Job job){
  Require(job.source_layout!="Model"&&job.handles!=null&&job.handles.Length>0,"PAPER_READ_SCOPE_REQUIRED");
  var rows=new List<object>();
  using(var tr=source.TransactionManager.StartTransaction()){
   var owner=Space(tr,source,job.source_layout);
   foreach(var handle in job.handles){
    var e=tr.GetObject(Id(source,handle),OpenMode.ForRead,false) as Entity;
    Require(e!=null&&e.OwnerId==owner,"PAPER_READ_OWNER_CHANGED:"+handle);
    rows.Add(new{identity=Identity(e),text_parts=TextParts(e),native_type=e.GetRXClass().Name});
   }
  }
  return rows;
 }
 static bool Contains(double[] a,double[] b){return b[0]>=a[0]-.001&&b[1]>=a[1]-.001&&b[2]<=a[2]+.001&&b[3]<=a[3]+.001;}
 static Entity Checked(Transaction tr,Database db,Target t,ObjectId owner){
  Require(t!=null&&t.bounds!=null&&t.bounds.Length==4,"EXACT_TARGET_REQUIRED");
  var e=tr.GetObject(Id(db,t.handle),OpenMode.ForRead,false) as Entity;
  Require(e!=null&&e.GetRXClass().Name==t.type&&e.Layer==t.layer&&e.OwnerId==owner,"TARGET_ROLE_CHANGED:"+t.handle);
  var a=Bounds(e);Require(a.Zip(t.bounds,(x,y)=>Math.Abs(x-y)<=.001).All(x=>x),"TARGET_BOUNDS_CHANGED:"+t.handle+":"+e.GetRXClass().Name+":expected="+J.Serialize(t.bounds)+":actual="+J.Serialize(a));return e;
 }
 public static ObjectId Space(Transaction tr,Database db,string layout){
  var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
  Require(dict.Contains(layout),"LAYOUT_NOT_FOUND:"+layout);
  return ((Layout)tr.GetObject(dict.GetAt(layout),OpenMode.ForRead)).BlockTableRecordId;
 }
 public static void ApplyLayers(Database db,Job job){
  Require(job.layers!=null&&job.layers.Length>0&&job.layers.Length<=64,"LAYER_LIST_REQUIRED");
  Require(job.layers.Select(x=>x.name).Distinct(StringComparer.OrdinalIgnoreCase).Count()==job.layers.Length,"DUPLICATE_LAYER");
  using(var tr=db.TransactionManager.StartTransaction()){
   var table=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);
   var checkedRows=new List<LayerTableRecord>();
   foreach(var edit in job.layers){
    Require(edit.before!=null&&edit.after!=null&&table.Has(edit.name),"LAYER_IDENTITY:"+edit.name);
    var layer=(LayerTableRecord)tr.GetObject(table[edit.name],OpenMode.ForRead);
    Require(!layer.IsDependent&&!layer.IsErased,"DEPENDENT_LAYER_NOT_SUPPORTED:"+edit.name);
    Require(!layer.IsOff==edit.before.on&&layer.IsFrozen==edit.before.frozen,"LAYER_STATE_CHANGED:"+edit.name);
    Require(!(edit.after.frozen&&layer.ObjectId==db.Clayer),"CANNOT_FREEZE_CURRENT_LAYER");
    checkedRows.Add(layer);
   }
   for(int i=0;i<job.layers.Length;i++){
    var layer=checkedRows[i];layer.UpgradeOpen();layer.IsOff=!job.layers[i].after.on;layer.IsFrozen=job.layers[i].after.frozen;
   }
   tr.Commit();
  }
 }
 static Polyline CheckedPolyline(Transaction tr,Database db,Target target){
  var model=SymbolUtilityServices.GetBlockModelSpaceId(db);
  var p=Checked(tr,db,target,model) as Polyline;
  Require(p!=null&&p.NumberOfVertices>=2,"ONLY_NATIVE_MODEL_LWPOLYLINE_SUPPORTED");return p;
 }
 public static void ApplyPolylineGeometry(Database source,Database dest,Job job){
  Require(job.pairs!=null&&job.pairs.Length>0,"POLYLINE_PAIRS_REQUIRED");
  Require(job.pairs.Select(x=>x.target.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==job.pairs.Length,"DUPLICATE_POLYLINE_TARGET");
  using(var sr=source.TransactionManager.StartTransaction())using(var tr=dest.TransactionManager.StartTransaction()){
   var inputs=job.pairs.Select(x=>CheckedPolyline(sr,source,x.source)).ToArray();
   var outputs=job.pairs.Select(x=>CheckedPolyline(tr,dest,x.target)).ToArray();
   // A preserved endpoint includes its point, outgoing bulge and widths.
   // Reject ambiguous closed or differently oriented planes before any write.
   var preserved=new Dictionary<int,double[]>[inputs.Length];
   for(int k=0;k<inputs.Length;k++){
    preserved[k]=new Dictionary<int,double[]>();var names=job.pairs[k].preserve_target_endpoints??new string[0];
    Require(names.Distinct().Count()==names.Length&&names.All(n=>n=="start"||n=="end"),"ENDPOINT_NAMES");
    if(names.Length==0)continue;var a=inputs[k];var b=outputs[k];
    Require(!a.Closed&&!b.Closed&&a.Normal.IsEqualTo(b.Normal,new Tolerance(1e-12,1e-12))&&Math.Abs(a.Elevation-b.Elevation)<=1e-9,"PRESERVED_ENDPOINT_REQUIRES_OPEN_SAME_PLANE");
    foreach(var name in names){int oldIndex=name=="start"?0:b.NumberOfVertices-1;int newIndex=name=="start"?0:a.NumberOfVertices-1;var p=b.GetPoint2dAt(oldIndex);preserved[k].Add(newIndex,new[]{p.X,p.Y,b.GetBulgeAt(oldIndex),b.GetStartWidthAt(oldIndex),b.GetEndWidthAt(oldIndex)});}
   }
   for(int k=0;k<inputs.Length;k++){
    var a=inputs[k];var b=outputs[k];b.UpgradeOpen();
    // Entity identity and all display properties stay on b. Only complete geometry changes.
    b.Normal=a.Normal;b.Elevation=a.Elevation;b.Thickness=a.Thickness;b.Closed=a.Closed;b.Plinegen=a.Plinegen;
    while(b.NumberOfVertices>a.NumberOfVertices)b.RemoveVertexAt(b.NumberOfVertices-1);
    for(int i=0;i<a.NumberOfVertices;i++){
     if(i==b.NumberOfVertices)b.AddVertexAt(i,a.GetPoint2dAt(i),a.GetBulgeAt(i),a.GetStartWidthAt(i),a.GetEndWidthAt(i));
     else {b.SetPointAt(i,a.GetPoint2dAt(i));b.SetBulgeAt(i,a.GetBulgeAt(i));b.SetStartWidthAt(i,a.GetStartWidthAt(i));b.SetEndWidthAt(i,a.GetEndWidthAt(i));}
    }
    foreach(var entry in preserved[k]){var v=entry.Value;int i=entry.Key;b.SetPointAt(i,new Point2d(v[0],v[1]));b.SetBulgeAt(i,v[2]);b.SetStartWidthAt(i,v[3]);b.SetEndWidthAt(i,v[4]);}
   }
   tr.Commit();sr.Commit();
  }
 }
 public static object ApplyPaperCopies(Database source,Database dest,Job job,bool geometry=false){var prior=HostApplicationServices.WorkingDatabase;try{return PaperCopies(source,dest,job,geometry);}finally{HostApplicationServices.WorkingDatabase=prior;}}
 static object PaperCopies(Database source,Database dest,Job job,bool geometry){
  HostApplicationServices.WorkingDatabase=source;
  Require(job.source_layout!="Model"&&job.target_layout!="Model","PAPER_LAYOUT_REQUIRED");
  Require(job.source_targets!=null&&job.source_targets.Length>0&&job.target_frames!=null&&job.target_frames.Length>0,"PAPER_COPY_TARGETS_REQUIRED");
  Require(job.source_targets.Select(x=>x.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==job.source_targets.Length,"DUPLICATE_SOURCE_TEXT");
  Require(job.target_frames.Select(x=>x.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==job.target_frames.Length,"DUPLICATE_TARGET_FRAME");
  var added=new List<object>();
  using(var sr=source.TransactionManager.StartTransaction())using(var tr=dest.TransactionManager.StartTransaction()){
   var from=Space(sr,source,job.source_layout);var to=Space(tr,dest,job.target_layout);
   Require(Checked(sr,source,job.source_frame,from) is BlockReference,"SOURCE_FRAME_MUST_BE_BLOCK");
   var ids=new ObjectIdCollection();var sourceLayers=new Dictionary<ObjectId,string>();
   foreach(var id in job.source_targets){
    var e=Checked(sr,source,id,from);Require(e is DBText||e is MText||e.GetRXClass().Name=="TDbText"||(geometry&&(e is Line||e is Polyline||e.GetRXClass().Name=="TDbSymbCoord"||e.GetRXClass().Name=="TDbSymbMultiLeader")),"SUPPORTED_PAPER_ENTITY_REQUIRED");
    Require(Contains(job.source_frame.bounds,Bounds(e)),"NOTE_OUTSIDE_SOURCE_FRAME");ids.Add(e.ObjectId);sourceLayers[e.ObjectId]=e.Layer;
   }
   HostApplicationServices.WorkingDatabase=dest;ObjectId layer=ObjectId.Null;
   if(!String.IsNullOrEmpty(job.target_layer)){
    var lt=(LayerTable)tr.GetObject(dest.LayerTableId,OpenMode.ForRead);Require(lt.Has(job.target_layer),"TARGET_LAYER_MISSING");layer=lt[job.target_layer];
   }
   if(geometry&&String.IsNullOrEmpty(job.target_layer)){
    foreach(var pair in sourceLayers){var lt=(LayerTable)tr.GetObject(dest.LayerTableId,OpenMode.ForRead);if(!lt.Has(pair.Value)){var src=(Entity)sr.GetObject(pair.Key,OpenMode.ForRead);source.WblockCloneObjects(new ObjectIdCollection(new[]{src.LayerId}),dest.LayerTableId,new IdMapping(),DuplicateRecordCloning.Ignore,false);}}
   }
   foreach(var f in job.target_frames){
    Require(Checked(tr,dest,f,to) is BlockReference,"TARGET_FRAME_MUST_BE_BLOCK");
    var a=job.source_frame.bounds;var b=f.bounds;
    Require(Math.Abs((a[2]-a[0])-(b[2]-b[0]))<=.001&&Math.Abs((a[3]-a[1])-(b[3]-b[1]))<=.001,"FRAME_SIZE_MISMATCH_NO_IMPLICIT_SCALE");
    var displacement=new Vector3d(b[0]-a[0],b[1]-a[1],0);
    var map=new IdMapping();source.WblockCloneObjects(ids,to,map,DuplicateRecordCloning.MangleName,false);
    foreach(ObjectId sid in ids){
     Require(map.Contains(sid),"NOTE_CLONE_MISSING");var e=(Entity)tr.GetObject(map[sid].Value,OpenMode.ForWrite);
     e.TransformBy(Matrix3d.Displacement(displacement));if(!layer.IsNull)e.LayerId=layer;else if(geometry)e.LayerId=((LayerTable)tr.GetObject(dest.LayerTableId,OpenMode.ForRead))[sourceLayers[sid]];
     Require(Contains(b,Bounds(e)),"COPIED_NOTE_OUTSIDE_TARGET_FRAME");
     added.Add(new{source_handle=sid.Handle.ToString(),target_handle=e.Handle.ToString(),target_frame=f.handle,bounds=Bounds(e)});
    }
   }
   tr.Commit();sr.Commit();
  }
  return added;
 }
 static object Call(Type type,string name,params object[] args){return type.GetMethod(name,Private).Invoke(null,args);}
 static object Field(Type type,string name){return type.GetField(name,Private).GetValue(null);}
 static void SetField(Type type,string name,object value){type.GetField(name,Private).SetValue(null,value);}
 static Type Adapter(Dispatch m){
  var proc=System.Diagnostics.Process.GetCurrentProcess();
  Require(proc.Id==m.host.pid&&proc.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(proc.MainModule.FileName,m.host.image),"HOST_IDENTITY");
  var adapter=AppDomain.CurrentDomain.GetAssemblies().Select(a=>a.GetType("V736BaseSession",false)).Single(t=>t!=null);
  Require(Eq(adapter.Assembly.Location,m.loaded_dll)&&Hash(m.loaded_dll)==m.loaded_dll_sha256,"LOADED_ADAPTER_IDENTITY");
  Require(Eq((string)Field(adapter,"dir"),m.session_dir),"SESSION_DIR_CHANGED");return adapter;
 }
 static void InspectView(Type adapter,Document doc,Job job){
  Require(!String.IsNullOrEmpty(job.layout)&&job.width>0&&job.height>0,"VIEW_REQUIRED");
  // Validate the requested layout before any layout/view change.
  using(var tr=doc.Database.TransactionManager.StartTransaction()){Space(tr,doc.Database,job.layout);}
  var originalType=adapter.GetNestedType("Inspect",BindingFlags.Public);
  var read=Activator.CreateInstance(originalType);
  foreach(var name in new[]{"input","input_sha256","handles","bounds"})originalType.GetField(name).SetValue(read,typeof(Job).GetField(name).GetValue(job));
  string nativeRead=job.receipt+".model-read.json";Call(adapter,"CheckPath",nativeRead);
  Require(!File.Exists(nativeRead),"VIEW_READ_RECEIPT_EXISTS");originalType.GetField("receipt").SetValue(read,nativeRead);
  Call(adapter,"InspectRegion",read);
  bool paper=job.layout!="Model";doc.Database.TileMode=!paper;LayoutManager.Current.CurrentLayout=job.layout;
  if(paper&&Convert.ToInt32(App.GetSystemVariable("CVPORT"))!=1)doc.Editor.SwitchToPaperSpace();
  Require(!paper||Convert.ToInt32(App.GetSystemVariable("CVPORT"))==1,"PAPERSPACE_NOT_ACTIVE");
  using(var v=doc.Editor.GetCurrentView()){v.Target=Point3d.Origin;v.ViewDirection=Vector3d.ZAxis;v.ViewTwist=0;v.CenterPoint=new Point2d(job.x,job.y);v.Width=job.width;v.Height=job.height;doc.Editor.SetCurrentView(v);}
  doc.Editor.Regen();App.UpdateScreen();
  var result=J.Deserialize<Dictionary<string,object>>(File.ReadAllText(nativeRead));
  result["image"]=job.image;result["layout"]=job.layout;result["actual_layout"]=App.GetSystemVariable("CTAB");result["cvport"]=App.GetSystemVariable("CVPORT");
  result["image_method"]="capture --id required; native preview intentionally omitted";
  WriteNew(job.receipt,result);
 }
 [CommandMethod("HLCADREPAIRLAYOUTV1",CommandFlags.Session)] public void RepairLayout(){
  var opt=new PromptStringOptions("\nExact failed-layout repair manifest: "){AllowSpaces=true};var ans=App.DocumentManager.MdiActiveDocument.Editor.GetString(opt);if(ans.Status!=PromptStatus.OK)return;
  Repair m=null;
  try{
   m=J.Deserialize<Repair>(File.ReadAllText(ans.StringResult.Trim('"')));var a=Adapter(m);
   Require((bool)Field(a,"blocked")&&!(bool)Field(a,"busy"),"EXPECTED_LAYOUT_HOLD");
   Require(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   Require(Eq(m.failure,Path.Combine(m.session_dir,"session_failure.json"))&&Hash(m.failure)==m.failure_sha256,"FAILURE_IDENTITY");
   var req=J.Deserialize<Request>(File.ReadAllText(m.request));Require(req.kind=="inspect"&&Hash(req.job_path)==req.job_sha256,"FAILED_INSPECT_ONLY");
   var job=J.Deserialize<Job>(File.ReadAllText(req.job_path));
   var failure=J.Deserialize<Dictionary<string,object>>(File.ReadAllText(m.failure));
   Require(((string)failure["error"]).StartsWith("System.InvalidOperationException: LAYOUT_INVALID\r\n"),"EXACT_LAYOUT_REJECTION_ONLY");
   Require(job.layout!="Model"&&job.layout!="布局1"&&!String.IsNullOrEmpty(job.image)&&!File.Exists(job.receipt),"EXPECTED_PRE_VIEW_REJECTION");
   Call(a,"CheckLive",job.input,job.input_sha256);
   string emergency=(string)failure["emergency"];Call(a,"CheckPath",emergency);Call(a,"VerifyDwg",emergency);
   string archived=m.failure+".layout_rejection_preserved";Require(!File.Exists(archived)&&!File.Exists(m.repair_receipt),"REPAIR_OUTPUT_EXISTS");
   WriteNew(job.receipt,new{status="RECONCILED_READ_ONLY_REJECTION",source_sha256=job.input_sha256,
    reason="LAYOUT_INVALID_BEFORE_VIEW_CHANGE",inspection_completed=false,replayed=false,preserved_failure=archived,emergency=emergency});
   File.Move(m.failure,archived);SetField(a,"blocked",false);Call(a,"State");
   WriteNew(m.repair_receipt,new{status="EXACT_READ_ONLY_REJECTION_RECONCILED",request=m.request,failed_request_completed=false,emergency=emergency,emergency_sha256=Hash(emergency),cad_entities_modified=false});
  }catch(System.Exception ex){if(m!=null&&!File.Exists(m.repair_receipt))WriteNew(m.repair_receipt,new{status="REPAIR_FAILED",error=ex.ToString()});}
 }
 [CommandMethod("HLCADANNOTATIONAPPLYV17",CommandFlags.Session)] public void Run(){
  var ed=App.DocumentManager.MdiActiveDocument.Editor;
  var opt=new PromptStringOptions("\nBound dispatch file: "){AllowSpaces=true};var answer=ed.GetString(opt);if(answer.Status!=PromptStatus.OK)return;
  Type adapter=null;Job job=null;bool ownsBusy=false,committed=false,writeStarted=false;
  try{
   var m=J.Deserialize<Dispatch>(File.ReadAllText(answer.StringResult.Trim('"')));
   var proc=System.Diagnostics.Process.GetCurrentProcess();
   Require(proc.Id==m.host.pid&&proc.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(proc.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   adapter=AppDomain.CurrentDomain.GetAssemblies().Select(a=>a.GetType("V736BaseSession",false)).Single(t=>t!=null);
   CadAdapterContractV1.Check(adapter);
   Require(Eq(adapter.Assembly.Location,m.loaded_dll)&&Hash(m.loaded_dll)==m.loaded_dll_sha256,"LOADED_ADAPTER_IDENTITY");
   Require(Eq((string)Field(adapter,"dir"),m.session_dir),"SESSION_DIR_CHANGED");
   Require(!(bool)Field(adapter,"busy")&&!(bool)Field(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");
   Require(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   var req=J.Deserialize<Request>(File.ReadAllText(m.request));
   Call(adapter,"CheckPath",req.job_path);Require(Hash(req.job_path)==req.job_sha256,"JOB_IDENTITY");
   job=J.Deserialize<Job>(File.ReadAllText(req.job_path));
   Call(adapter,"CheckLive",job.input,job.input_sha256);
   if(req.kind=="paper_read"||req.kind=="inspect"){Call(adapter,"CheckPath",job.receipt);Require(!File.Exists(job.receipt),"RECEIPT_EXISTS");}
   else Call(adapter,"CheckOutput",job.output,job.receipt);
   var doc=(Document)Field(adapter,"doc");Require(doc==App.DocumentManager.MdiActiveDocument,"ACTIVE_DOCUMENT_CHANGED");
   SetField(adapter,"busy",true);ownsBusy=true;
   object changes=null;
   using(doc.LockDocument()){
    if(req.kind=="inspect"){InspectView(adapter,doc,job);return;}
    if(req.kind=="layer_patch") {writeStarted=true;ApplyLayers(doc.Database,job);changes=new{global_layer_changes=job.layers,per_viewport_freeze_changed=false};}
    else if(req.kind=="index_anchor"){changes=IndexAnchorV1.Apply(doc.Database,job.indexes,()=>writeStarted=true);}
    else if(req.kind=="native_annotation_update"){changes=NativeAnnotationUpdateV1.Apply(doc.Database,job.annotations,()=>writeStarted=true);}
    else if(req.kind=="hatch_pattern"){writeStarted=true;changes=HatchPatternPatchV1.Apply(doc.Database,job.hatches);}
    else if(req.kind=="polyline_edit"){writeStarted=true;changes=PolylineGeometryV1.Replace(doc.Database,job.edits);}
    else if(req.kind=="polyline_create"){writeStarted=true;changes=PolylineGeometryV1.CreateCurves(doc.Database,job.creations);}
    else if(req.kind=="polyline_offset"){writeStarted=true;changes=PolylineGeometryV1.OffsetCurves(doc.Database,job.offsets);}
    else {
     Require(req.kind=="paper_copy"||req.kind=="paper_entities_copy"||req.kind=="polyline_sync"||req.kind=="paper_read","UNSUPPORTED_BOUND_OPERATION");
     Call(adapter,"CheckPath",job.source);var approved=(Dictionary<string,string>)Field(adapter,"approved");string sha;
     Require(approved.TryGetValue(Path.GetFullPath(job.source),out sha)&&sha==job.source_sha256&&Hash(job.source)==sha,"SOURCE_IDENTITY");
     using(var source=new Database(false,true)){
      source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,null);source.CloseInput(true);
      if(req.kind=="paper_read"){
       var rows=ReadPaper(source,job);Call(adapter,"CheckLive",job.input,job.input_sha256);
       WriteNew(job.receipt,new{status="BOUND_PAPER_READ_ONLY",source_sha256=job.input_sha256,reference_sha256=job.source_sha256,entities=rows,pid=proc.Id});return;
      }
      writeStarted=true;
      if(req.kind=="paper_copy"||req.kind=="paper_entities_copy")changes=new{copied_notes=ApplyPaperCopies(source,doc.Database,job,req.kind=="paper_entities_copy"),source=job.source};
      else {ApplyPolylineGeometry(source,doc.Database,job);changes=new{synced=job.pairs,source=job.source,target_handles_and_display_properties_preserved=true};}
     }
    }
    committed=true;doc.Editor.Regen();Call(adapter,"SaveModified",job.output,job.receipt,changes);
   }
  }catch(System.Exception exc){
   var error=exc is TargetInvocationException&&exc.InnerException!=null?exc.InnerException:exc;
   string emergency=null;
   if(writeStarted&&adapter!=null){
    SetField(adapter,"blocked",true);
    try{var d=(Document)Field(adapter,"doc");emergency=Path.Combine((string)Field(adapter,"dir"),"module_emergency_"+Guid.NewGuid().ToString("N")+".dwg");using(d.LockDocument())d.Database.SaveAs(emergency,DwgVersion.AC1032);}catch{emergency=null;}
   }
   if(job!=null&&!String.IsNullOrEmpty(job.receipt)&&!File.Exists(job.receipt))WriteNew(job.receipt,new{status=writeStarted?"BOUND_MODULE_FAILED":"REJECTED_BEFORE_WRITE",source_sha256=job.input_sha256,replayed=false,error=error.ToString(),committed=committed,write_started=writeStarted,emergency=emergency});
   ed.WriteMessage("\nBOUND_MODULE_FAILED: "+error.Message);
  }finally{if(ownsBusy)SetField(adapter,"busy",false);}
 }
}
