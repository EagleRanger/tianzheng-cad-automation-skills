// One fixed operation: exact old-base removal, native purge, isolated clone,
// relationship mapping, save/reopen verification, then activate the candidate.
// Engineering classification is supplied by the writer/reviewer, never inferred here.
using System;using System.IO;using System.Linq;using System.Collections.Generic;
using System.Reflection;using System.Security.Cryptography;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;

public class BaseReplaceV3 {
 public class Target {public string handle,type,layer;public double[] bounds;}
 public class GroupSpec {public string name;public string[] handles;}
 public class Job {public string input,input_sha256,source,source_sha256,output,receipt;public Target[] source_targets,old_targets,protected_targets,deferred_targets;public GroupSpec[] source_groups;}
 public class Host {public int pid;public long created;public string image;}
 public class Manifest {public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;public Host host;}
 public class Request {public string kind,job_path,job_sha256;}
 public class MapRow {public string source_handle,target_handle,type,source_layer,target_layer;public double[] bounds3d;public string geometry;}
 public class SymbolRow {public string source_handle,target_handle,type,source_name,target_name;public bool cloned;}
 public class GroupRow {public string name,source_name;public string[] source_handles,target_handles;}
 public class XrefSource {public string source_handle,path,sha256;}
 public class Result {
  public string operation="base_replace";
  public bool protected_verified,classification_complete,coverage_complete,reopen_verified,viewport_layer_sync_required;
  public Target[] deferred_targets;
  public string[] removed;public List<MapRow> entity_map=new List<MapRow>();
  public List<SymbolRow> symbol_map=new List<SymbolRow>();public List<GroupRow> groups=new List<GroupRow>();
  public List<object> purged=new List<object>();public List<object> xrefs=new List<object>();
  public List<XrefSource> xref_sources=new List<XrefSource>();
  public Dictionary<string,string> protected_signatures=new Dictionary<string,string>();
  public Dictionary<string,string[]> viewport_frozen_before,viewport_frozen_after;
  public string paper_signature;public string[] steps={"validate","delete_old","purge_unused","clone_source","rebuild_groups","save_reopen"};
  public string input_snapshot,input_snapshot_sha256;
 }
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=200000000,RecursionLimit=100};
 static readonly BindingFlags BF=BindingFlags.NonPublic|BindingFlags.Static;
 public static void Need(bool yes,string reason){if(!yes)throw new InvalidOperationException(reason);}
 public static string Hash(string path){using(var h=SHA256.Create())using(var f=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))return BitConverter.ToString(h.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static ObjectId Id(Database db,string handle){return db.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0);}
 public static void Write(string path,object value){using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(value));}
 static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 public static double[] Extents(Entity e){var x=e.GeometricExtents;return new[]{x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};}
 static double[] Extents3(Entity e){var x=e.GeometricExtents;return new[]{x.MinPoint.X,x.MinPoint.Y,x.MinPoint.Z,x.MaxPoint.X,x.MaxPoint.Y,x.MaxPoint.Z};}
 public static Target Identity(Entity e){return new Target{handle=e.Handle.ToString(),type=e.GetRXClass().Name,layer=e.Layer,bounds=Extents(e)};}
 static Entity Checked(Database db,Transaction tr,Target t){
  Need(t!=null&&t.bounds!=null&&t.bounds.Length==4,"EXACT_IDENTITY_REQUIRED");
  var e=tr.GetObject(Id(db,t.handle),OpenMode.ForRead,false) as Entity;
  Need(e!=null&&e.OwnerId==SymbolUtilityServices.GetBlockModelSpaceId(db)&&e.GetRXClass().Name==t.type&&e.Layer==t.layer,"IDENTITY_CHANGED:"+t.handle);
  Need(Extents(e).Zip(t.bounds,(a,b)=>Math.Abs(a-b)<=.001).All(x=>x),"BOUNDS_CHANGED:"+t.handle);
  return e; // A real [0,0,0,0] bound is valid and is checked as reported.
 }
 public static string Geometry(Entity e){
  var d=new Dictionary<string,object>{{"type",e.GetRXClass().Name},{"bounds",Extents3(e)},{"color",e.ColorIndex},{"lineweight",(int)e.LineWeight},{"ltscale",e.LinetypeScale}};
  var p=e as Polyline;if(p!=null){var a=new List<double[]>();for(int i=0;i<p.NumberOfVertices;i++)a.Add(new[]{p.GetPoint3dAt(i).X,p.GetPoint3dAt(i).Y,p.GetPoint3dAt(i).Z,p.GetBulgeAt(i),p.GetStartWidthAt(i),p.GetEndWidthAt(i)});d["vertices"]=a;d["closed"]=p.Closed;}
  var l=e as Line;if(l!=null){d["start"]=P(l.StartPoint);d["end"]=P(l.EndPoint);}
  var c=e as Circle;if(c!=null){d["center"]=P(c.Center);d["radius"]=c.Radius;}
  var a1=e as Arc;if(a1!=null){d["center"]=P(a1.Center);d["radius"]=a1.Radius;d["angles"]=new[]{a1.StartAngle,a1.EndAngle};}
  var b=e as BlockReference;if(b!=null)d["transform"]=b.BlockTransform.ToArray();
  var t=e as DBText;if(t!=null){d["text"]=t.TextString;d["position"]=P(t.Position);d["height"]=t.Height;d["width"]=t.WidthFactor;}
  var m=e as MText;if(m!=null){d["text"]=m.Contents;d["position"]=P(m.Location);d["height"]=m.TextHeight;d["width"]=m.Width;}
  var h=e as Hatch;if(h!=null){d["pattern"]=h.PatternName;d["loops"]=h.NumberOfLoops;d["scale"]=h.PatternScale;d["angle"]=h.PatternAngle;}
  return J.Serialize(d);
 }
 static string Protected(Entity e){return e.Handle+"|"+e.Layer+"|"+e.LayerId.Handle+"|"+e.LinetypeId.Handle+"|"+Geometry(e);}
 public static Dictionary<string,string[]> Frozen(Database db){
  var result=new Dictionary<string,string[]>();using(var tr=db.TransactionManager.StartTransaction()){
   var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
   foreach(DBDictionaryEntry item in dict){var lay=(Layout)tr.GetObject(item.Value,OpenMode.ForRead);if(lay.ModelType)continue;
    var block=(BlockTableRecord)tr.GetObject(lay.BlockTableRecordId,OpenMode.ForRead);
    foreach(ObjectId id in block){var vp=tr.GetObject(id,OpenMode.ForRead) as Viewport;if(vp!=null)result[vp.Handle.ToString()]=vp.GetFrozenLayers().Cast<ObjectId>().Where(x=>!x.IsErased).Select(x=>((LayerTableRecord)tr.GetObject(x,OpenMode.ForRead)).Name).OrderBy(x=>x,StringComparer.Ordinal).ToArray();}
   }
  }return result;
 }
 static string PaperGeometry(Entity e){
  // Extents are derived display caches. Preserve native defining data instead.
  var values=J.Deserialize<Dictionary<string,object>>(Geometry(e));values.Remove("bounds");return J.Serialize(values);
 }
 public static string Paper(Database db){
  var rows=new List<string>();using(var tr=db.TransactionManager.StartTransaction()){
   var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
   foreach(DBDictionaryEntry item in dict){var lay=(Layout)tr.GetObject(item.Value,OpenMode.ForRead);if(lay.ModelType)continue;
    var b=(BlockTableRecord)tr.GetObject(lay.BlockTableRecordId,OpenMode.ForRead);
    foreach(ObjectId id in b){var e=(Entity)tr.GetObject(id,OpenMode.ForRead);string s=lay.LayoutName+"|"+e.Handle+"|"+e.Layer+"|"+e.GetRXClass().Name;
     var vp=e as Viewport;if(vp!=null)s+="|"+J.Serialize(new{center=P(vp.CenterPoint),width=vp.Width,height=vp.Height,target=P(vp.ViewTarget),direction=new[]{vp.ViewDirection.X,vp.ViewDirection.Y,vp.ViewDirection.Z},viewcenter=new[]{vp.ViewCenter.X,vp.ViewCenter.Y},twist=vp.TwistAngle,scale=vp.CustomScale,clip=vp.NonRectClipEntityId.IsNull?null:vp.NonRectClipEntityId.Handle.ToString()});
     else {try{s+="|"+PaperGeometry(e);}catch{s+="|NO_EXTENTS";}}
     rows.Add(s);
    }
   }
  }rows.Sort(StringComparer.Ordinal);return J.Serialize(rows);
 }
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
 static List<GroupSpec> Groups(Database db,HashSet<string> selected,GroupSpec[] explicitGroups){
  var result=new List<GroupSpec>();using(var tr=db.TransactionManager.StartTransaction()){
   var dict=(DBDictionary)tr.GetObject(db.GroupDictionaryId,OpenMode.ForRead);
   foreach(DBDictionaryEntry entry in dict){var g=(Group)tr.GetObject(entry.Value,OpenMode.ForRead);var members=g.GetAllEntityIds().Where(x=>!x.IsErased).Select(x=>x.Handle.ToString()).ToArray();
    if(members.Length>0&&members.All(selected.Contains))result.Add(new GroupSpec{name=entry.Key,handles=members});
   }
  }
  if(explicitGroups!=null)foreach(var g in explicitGroups){Need(g.handles!=null&&g.handles.Length>0&&g.handles.All(selected.Contains),"GROUP_MEMBER_NOT_COPIED:"+g.name);if(!result.Any(x=>new HashSet<string>(x.handles).SetEquals(g.handles)))result.Add(g);}
  return result;
 }
 public static Result Apply(Database source,Database dest,Job job){
  Need(job.source_targets!=null&&job.source_targets.Length>0&&job.old_targets!=null&&job.protected_targets!=null&&job.deferred_targets!=null,"CLASSIFICATION_AND_DEFERRED_SCOPE_REQUIRED");
  var result=new Result();result.paper_signature=Paper(dest);result.viewport_frozen_before=Frozen(dest);
  var old=new HashSet<string>(job.old_targets.Select(x=>x.handle.ToUpperInvariant()));var kept=new HashSet<string>(job.protected_targets.Select(x=>x.handle.ToUpperInvariant()));
  Need(old.Count==job.old_targets.Length&&kept.Count==job.protected_targets.Length&&!old.Overlaps(kept),"OLD_PROTECTED_COLLISION");
  Need(job.deferred_targets.All(x=>kept.Contains(x.handle.ToUpperInvariant())),"DEFERRED_MUST_BE_PROTECTED");result.deferred_targets=job.deferred_targets;
  var sourceHandles=new HashSet<string>(job.source_targets.Select(x=>x.handle.ToUpperInvariant()),StringComparer.OrdinalIgnoreCase);Need(sourceHandles.Count==job.source_targets.Length,"SOURCE_DUPLICATE");
  var groups=Groups(source,sourceHandles,job.source_groups);var oldXrefs=new HashSet<ObjectId>();
  var sourceGeometry=new Dictionary<ObjectId,string>();var sourceLayer=new Dictionary<ObjectId,string>();
  using(var sr=source.TransactionManager.StartTransaction())using(var tr=dest.TransactionManager.StartTransaction()){
   var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(dest),OpenMode.ForRead);
   var actual=new HashSet<string>(ms.Cast<ObjectId>().Where(x=>!x.IsErased).Select(x=>x.Handle.ToString()));var declared=new HashSet<string>(old);declared.UnionWith(kept);
   Need(actual.SetEquals(declared),"MODEL_CLASSIFICATION_INCOMPLETE:"+String.Join(",",actual.Except(declared).Take(20)));
   foreach(var target in job.protected_targets){var e=Checked(dest,tr,target);result.protected_signatures[e.Handle.ToString()]=Protected(e);}
   foreach(var target in job.deferred_targets)Checked(dest,tr,target);
   foreach(var target in job.old_targets){var e=Checked(dest,tr,target);var br=e as BlockReference;if(br!=null){var b=(BlockTableRecord)tr.GetObject(br.BlockTableRecord,OpenMode.ForRead);if(b.IsFromExternalReference)oldXrefs.Add(b.ObjectId);}}
   foreach(var target in job.source_targets){var e=Checked(source,sr,target);sourceGeometry[e.ObjectId]=Geometry(e);sourceLayer[e.ObjectId]=e.Layer;
    var br=e as BlockReference;if(br!=null){var block=(BlockTableRecord)sr.GetObject(br.BlockTableRecord,OpenMode.ForRead);if(block.IsFromExternalReference){
     string path=Path.GetFullPath(Path.Combine(Path.GetDirectoryName(job.source),block.PathName));Need(File.Exists(path)&&block.XrefStatus==XrefStatus.Resolved,"SOURCE_XREF_MISSING_OR_UNRESOLVED");
     result.xref_sources.Add(new XrefSource{source_handle=e.Handle.ToString(),path=path,sha256=Hash(path)});
    }}
   }
   // Only explicit old entities are erased. Retained planting and paper objects
   // are never selected by a name prefix or area bounding box.
   foreach(var target in job.old_targets)Checked(dest,tr,target).UpgradeOpen();
   foreach(var target in job.old_targets)((Entity)tr.GetObject(Id(dest,target.handle),OpenMode.ForWrite)).Erase();
   var gd=(DBDictionary)tr.GetObject(dest.GroupDictionaryId,OpenMode.ForWrite);
   var groupEntries=new List<DBDictionaryEntry>();foreach(DBDictionaryEntry entry in gd)groupEntries.Add(entry);
   foreach(var entry in groupEntries){
    var g=(Group)tr.GetObject(entry.Value,OpenMode.ForWrite);var members=g.GetAllEntityIds();
    if(members.Length==0||members.All(x=>x.IsErased)){gd.Remove(entry.Key);g.Erase();}
   }
   tr.Commit();sr.Commit();
  }
  // Side-database only: if any later step fails the candidate is discarded,
  // and the active production document remains byte-for-byte at its checkpoint.
  foreach(var id in oldXrefs){using(var tr=dest.TransactionManager.StartTransaction()){
   var b=(BlockTableRecord)tr.GetObject(id,OpenMode.ForRead);Need(!b.GetBlockReferenceIds(true,false).Cast<ObjectId>().Any(x=>!x.IsErased),"OLD_XREF_STILL_REFERENCED");tr.Commit();}dest.DetachXref(id);}
  result.purged=Purge(dest);
  using(var sr=source.TransactionManager.StartTransaction())using(var tr=dest.TransactionManager.StartTransaction()){
   var ids=new ObjectIdCollection(sourceGeometry.Keys.ToArray());var map=new IdMapping();
   source.WblockCloneObjects(ids,SymbolUtilityServices.GetBlockModelSpaceId(dest),map,DuplicateRecordCloning.MangleName,false);
   foreach(IdPair pair in map){if(pair.Value.IsNull)continue;var a=sr.GetObject(pair.Key,OpenMode.ForRead) as SymbolTableRecord;var b=tr.GetObject(pair.Value,OpenMode.ForRead) as SymbolTableRecord;
    if(a!=null&&b!=null)result.symbol_map.Add(new SymbolRow{source_handle=a.Handle.ToString(),target_handle=b.Handle.ToString(),type=a.GetRXClass().Name,source_name=a.Name,target_name=b.Name,cloned=pair.IsCloned});
   }
   foreach(ObjectId sid in ids){Need(map.Contains(sid)&&map[sid].IsCloned,"SOURCE_NOT_CLONED:"+sid.Handle);var e=(Entity)tr.GetObject(map[sid].Value,OpenMode.ForRead);
    // Newly cloned xrefs have no extents until ResolveXrefs. Keep expected source
    // geometry here, then read and compare actual target geometry after resolve.
    result.entity_map.Add(new MapRow{source_handle=sid.Handle.ToString(),target_handle=e.Handle.ToString(),type=e.GetRXClass().Name,source_layer=sourceLayer[sid],target_layer=e.Layer,geometry=sourceGeometry[sid]});
   }
   var groupDict=(DBDictionary)tr.GetObject(dest.GroupDictionaryId,OpenMode.ForWrite);
   int index=0;foreach(var spec in groups){string name="CAD_BASE_"+(++index).ToString("D3");while(groupDict.Contains(name))name+="_";
    var group=new Group(spec.name,true);groupDict.SetAt(name,group);tr.AddNewlyCreatedDBObject(group,true);
    var members=spec.handles.Select(h=>map[Id(source,h)].Value).ToArray();group.Append(new ObjectIdCollection(members));
    result.groups.Add(new GroupRow{name=name,source_name=spec.name,source_handles=spec.handles,target_handles=members.Select(x=>x.Handle.ToString()).ToArray()});
   }
   foreach(var target in job.protected_targets){var e=Checked(dest,tr,target);Need(Protected(e)==result.protected_signatures[e.Handle.ToString()],"PROTECTED_CHANGED:"+e.Handle);}
   tr.Commit();sr.Commit();
  }
  dest.ResolveXrefs(false,false);
  using(var tr=dest.TransactionManager.StartTransaction())foreach(var row in result.entity_map){var e=(Entity)tr.GetObject(Id(dest,row.target_handle),OpenMode.ForRead);Need(Geometry(e)==row.geometry,"CLONED_GEOMETRY_OR_Z_CHANGED:"+row.source_handle);row.bounds3d=Extents3(e);}
  result.removed=old.ToArray();result.protected_verified=true;result.classification_complete=true;result.coverage_complete=job.deferred_targets.Length==0;
  result.viewport_frozen_after=Frozen(dest);result.viewport_layer_sync_required=result.symbol_map.Any(x=>x.type=="AcDbLayerTableRecord")||J.Serialize(result.viewport_frozen_before)!=J.Serialize(result.viewport_frozen_after);
  var afterPaper=Paper(dest);if(afterPaper!=result.paper_signature){Write(job.output+".paper-diff.json",new{before=result.paper_signature,after=afterPaper});throw new InvalidOperationException("PAPER_OR_VIEWPORT_CHANGED");}return result;
 }
 public static void Verify(Database reopened,Result result){
  using(var tr=reopened.TransactionManager.StartTransaction()){
   foreach(var row in result.entity_map){var e=(Entity)tr.GetObject(Id(reopened,row.target_handle),OpenMode.ForRead);Need(e.Layer==row.target_layer&&Geometry(e)==row.geometry,"REOPEN_CLONE_CHANGED:"+row.target_handle);}
   foreach(var pair in result.protected_signatures){var e=(Entity)tr.GetObject(Id(reopened,pair.Key),OpenMode.ForRead);Need(Protected(e)==pair.Value,"REOPEN_PROTECTED_CHANGED:"+pair.Key);}
   foreach(var h in result.removed){ObjectId id;bool found=reopened.TryGetObjectId(new Handle(Convert.ToInt64(h,16)),out id);Need(!found||id.IsErased,"OLD_ENTITY_REMAINS:"+h);}
   var expected=new HashSet<string>(result.entity_map.Select(x=>x.target_handle));expected.UnionWith(result.protected_signatures.Keys);
   var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(reopened),OpenMode.ForRead);
   Need(expected.SetEquals(ms.Cast<ObjectId>().Where(x=>!x.IsErased).Select(x=>x.Handle.ToString())),"UNPLANNED_MODEL_ENTITY_AFTER_CLONE");
   var gd=(DBDictionary)tr.GetObject(reopened.GroupDictionaryId,OpenMode.ForRead);
   foreach(var row in result.groups){Need(gd.Contains(row.name),"REOPEN_GROUP_MISSING");var g=(Group)tr.GetObject(gd.GetAt(row.name),OpenMode.ForRead);Need(new HashSet<string>(g.GetAllEntityIds().Where(x=>!x.IsErased).Select(x=>x.Handle.ToString())).SetEquals(row.target_handles),"REOPEN_GROUP_MEMBERS_CHANGED");}
  }
  var reopenedPaper=Paper(reopened);if(reopenedPaper!=result.paper_signature)throw new InvalidOperationException("REOPEN_PAPER_CHANGED expected="+result.paper_signature+" actual="+reopenedPaper);result.reopen_verified=true;
 }
 static void VerifyXrefs(Database reopened,Job job,Result result){
  // Source identity, bounds, transform and reference hash were captured before
  // cloning. Verify the reopened target against that immutable observation;
  // loading the source again shares native xref display caches unnecessarily.
  if(result.xref_sources.Count==0)return;reopened.ResolveXrefs(false,false);
  using(var tr=reopened.TransactionManager.StartTransaction())foreach(var item in result.xref_sources){var row=result.entity_map.Single(x=>String.Equals(x.source_handle,item.source_handle,StringComparison.OrdinalIgnoreCase));var br=(BlockReference)tr.GetObject(Id(reopened,row.target_handle),OpenMode.ForRead);var b=(BlockTableRecord)tr.GetObject(br.BlockTableRecord,OpenMode.ForRead);
   string path=Path.GetFullPath(Path.Combine(Path.GetDirectoryName(job.output),b.PathName));Need(b.IsFromExternalReference&&b.XrefStatus==XrefStatus.Resolved&&Eq(path,item.path)&&Hash(path)==item.sha256,"CLONED_XREF_NOT_RESOLVED_FROM_SOURCE");
   result.xrefs.Add(new{source_handle=item.source_handle,target_handle=row.target_handle,path=path,sha256=item.sha256,status=b.XrefStatus.ToString()});
  }
 }
 public static Result Build(Job job){
  Need(Hash(job.input)==job.input_sha256&&Hash(job.source)==job.source_sha256&&!File.Exists(job.output),"INPUT_OR_OUTPUT_IDENTITY");
  Result result;var previous=HostApplicationServices.WorkingDatabase;
  try{
   using(var source=new Database(false,true))using(var dest=new Database(false,true)){
    source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,null);source.CloseInput(true);source.ResolveXrefs(false,false);
    dest.ReadDwgFile(job.input,FileOpenMode.OpenForReadAndAllShare,true,null);dest.CloseInput(true);dest.ResolveXrefs(false,false);
    HostApplicationServices.WorkingDatabase=dest;result=Apply(source,dest,job);HostApplicationServices.WorkingDatabase=previous;dest.SaveAs(job.output,DwgVersion.AC1032);
   }
   using(var reopened=new Database(false,true)){
    reopened.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,null);reopened.CloseInput(true);HostApplicationServices.WorkingDatabase=reopened;
    VerifyXrefs(reopened,job,result);Verify(reopened,result);HostApplicationServices.WorkingDatabase=previous;
   }
   Need(Hash(job.input)==job.input_sha256&&Hash(job.source)==job.source_sha256,"ORIGINAL_CHANGED");return result;
  }finally{HostApplicationServices.WorkingDatabase=previous;}
 }
 static object Field(Type t,string n){return t.GetField(n,BF).GetValue(null);}static void Set(Type t,string n,object v){t.GetField(n,BF).SetValue(null,v);}static object Call(Type t,string n,params object[] args){return t.GetMethod(n,BF).Invoke(null,args);}
 [CommandMethod("HLCADBASEREPLACEV6",CommandFlags.Session)] public void Run(){
  var answer=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nExact base replacement manifest: "){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  Type adapter=null;Job job=null;bool busy=false,activating=false;
  try{
   var m=J.Deserialize<Manifest>(File.ReadAllText(answer.StringResult.Trim('"')));var proc=System.Diagnostics.Process.GetCurrentProcess();
   Need(proc.Id==m.host.pid&&proc.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(proc.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   adapter=AppDomain.CurrentDomain.GetAssemblies().Select(a=>a.GetType("V736BaseSession",false)).Single(t=>t!=null);CadAdapterContractV1.CheckBaseReplace(adapter);
   Need(Eq(adapter.Assembly.Location,m.loaded_dll)&&Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Field(adapter,"dir"),m.session_dir),"ADAPTER_IDENTITY");
   Need(!(bool)Field(adapter,"busy")&&!(bool)Field(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");
   Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   var req=J.Deserialize<Request>(File.ReadAllText(m.request));Need(req.kind=="base_replace"&&Hash(req.job_path)==req.job_sha256,"BASE_REPLACE_JOB_REQUIRED");Call(adapter,"CheckPath",req.job_path);
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
   var result=Build(buildJob);result.input_snapshot=buildJob.input;result.input_snapshot_sha256=buildJob.input_sha256;Call(adapter,"CheckLive",job.input,job.input_sha256);
   string candidateHash=Hash(job.output);approved[Path.GetFullPath(job.output)]=candidateHash;
   var type=adapter.GetNestedType("Switch",BindingFlags.Public);var sw=Activator.CreateInstance(type);
   foreach(var pair in new Dictionary<string,string>{{"input",job.input},{"input_sha256",job.input_sha256},{"next_path",job.output},{"next_sha256",candidateHash},{"save_path",job.output+".pre_replace.dwg"},{"receipt",job.receipt+".switch.json"}})type.GetField(pair.Key).SetValue(sw,pair.Value);
   activating=true;Call(adapter,"SwitchDocument",sw);
   Write(job.receipt,new{status="SAVED_STILL_OPEN",source_sha256=job.input_sha256,reference_sha256=job.source_sha256,output=job.output,sha256=candidateHash,live_document=((Document)Field(adapter,"doc")).Name,changes=result,pid=proc.Id});
  }catch(System.Exception error){if(error is TargetInvocationException&&error.InnerException!=null)error=error.InnerException;if(activating&&adapter!=null)Set(adapter,"blocked",true);
   if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status="BASE_REPLACE_FAILED",source_sha256=job.input_sha256,active_document_changed=activating,candidate_path=job.output,candidate_exists=File.Exists(job.output),error=error.ToString()});
  }finally{if(busy)Set(adapter,"busy",false);}
 }
}
