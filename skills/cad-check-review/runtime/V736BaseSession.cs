// Narrow, task-specific private CAD session. Compile preparation only until the
// prior owned session has been protected and has exited normally.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;

public class V736BaseSession {
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=250000000,RecursionLimit=200};
 static string dir, queue, livePath, currentPath, currentHash, terrain, terrainHash;
 static Document doc; static bool busy, blocked; static Inspect pendingView;
 static readonly Dictionary<string,string> approved=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
 static readonly HashSet<string> gardenPaths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
 public class Config {public string garden,garden_sha256,planting,planting_sha256,terrain,terrain_sha256,font_map,initial_role;public Dictionary<string,string> references;}
 public class Request {public string kind,job_path,job_sha256;}
 public class Inspect {public string input,input_sha256,receipt,image,layout;public double x,y,width,height;public string[] handles;public double[] bounds;}
 public class Switch {public string input,input_sha256,save_path,next_path,next_sha256,receipt;}
 public class CloseJob {public string input,input_sha256,recovery_dir,receipt;}
 public class PageMapJob {public string input,input_sha256,layout,title_contains,frame_block_prefix,grid_block_name,receipt;}
 public class Target {public string handle,type,layer;public double[] bounds;}
public class CopyTransformPair {public Target source_grid,source_frame,target_frame;}
public class CopyTransformJob {public string input,input_sha256,layout,frame_block_prefix,grid_block_name,output,receipt;public CopyTransformPair[] pairs;}
 public class HatchPart {public double[][][] loops;}
 public class HatchJob {public string input,input_sha256,template,template_layer,expected_pattern,output,receipt;public int? expected_color;public Target replace_target;public HatchPart[] parts;}
 public class EraseJob {public string input,input_sha256,output,receipt;public Target[] targets;}
 public class TransferJob {public string input,input_sha256,source,source_sha256,output,receipt;public Target[] old_targets,source_targets;}
 static Config config;
 static string Hash(string path){using(var h=SHA256.Create())using(var f=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))return BitConverter.ToString(h.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static void Write(string path,object value){if(File.Exists(path))throw new InvalidOperationException("OUTPUT_EXISTS:"+path);File.WriteAllText(path,J.Serialize(value),new System.Text.UTF8Encoding(false));}
 static void CheckPath(string path){if(!Eq(Path.GetDirectoryName(Path.GetFullPath(path)),dir))throw new InvalidOperationException("PATH_OUTSIDE_SESSION:"+path);}
 static void CheckLive(string path,string hash){
  if(doc==null||!Eq(doc.Name,livePath)||!Eq(path,currentPath)||hash!=currentHash||Hash(path)!=hash)throw new InvalidOperationException("LIVE_DOCUMENT_IDENTITY");
  if(Hash(terrain)!=terrainHash)throw new InvalidOperationException("TERRAIN_IDENTITY");
 }
 static void State(){File.WriteAllText(Path.Combine(dir,"session_status.json"),J.Serialize(new{status="READY_SAME_DOCUMENT",live_document=doc.Name,last_saved=currentPath,last_sha256=currentHash,pid=System.Diagnostics.Process.GetCurrentProcess().Id,layout=App.GetSystemVariable("CTAB"),cvport=App.GetSystemVariable("CVPORT"),terrain=terrain,terrain_sha256=terrainHash}),new System.Text.UTF8Encoding(false));}
 static void VerifyDwg(string path){using(var d=new Database(false,true)){d.ReadDwgFile(path,FileOpenMode.OpenForReadAndAllShare,true,null);d.CloseInput(true);}}
 static void ProtectInitial(){
  var all=App.DocumentManager.Cast<Document>().ToArray();
  if(all.Length!=1||!String.Equals(Path.GetFileName(all[0].Name),"Drawing1.dwg",StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("INITIAL_DOCUMENT_NOT_UNIQUE");
  var target=Path.Combine(dir,"initial_Drawing1_protected.dwg");if(File.Exists(target))throw new InvalidOperationException("INITIAL_PROTECTION_EXISTS");
  using(all[0].LockDocument()){all[0].Database.SaveAs(target,DwgVersion.AC1032);} string hash=Hash(target);VerifyDwg(target);if(Hash(target)!=hash)throw new InvalidOperationException("INITIAL_PROTECTION_CHANGED");
  Write(Path.Combine(dir,"initial_document_protection.json"),new{status="PROTECTED_AND_READ_BACK",document=all[0].Name,snapshot=target,sha256=hash,pid=System.Diagnostics.Process.GetCurrentProcess().Id});
 }
 static string TianzhengSys(){
   string value=Environment.GetEnvironmentVariable("HL_TIANZHENG_SYS");
   if(String.IsNullOrEmpty(value)||!Directory.Exists(value))throw new InvalidOperationException("TIANZHENG_ENVIRONMENT_MISSING");
   return Path.GetFullPath(value);
  }
  static void ResolveTerrain(Document target){
  using(target.LockDocument()){
   target.Database.ResolveXrefs(false,false);
   object acad=Autodesk.AutoCAD.ApplicationServices.Application.AcadApplication;
   foreach(string name in new[]{"tch_utility.arx","tch_pipewire.arx","tch_pipebase.arx","tch_initstart.arx","tch_common.arx","tch3_kernal.arx"})acad.GetType().InvokeMember("LoadArx",System.Reflection.BindingFlags.InvokeMethod,null,acad,new object[]{Path.Combine(TianzhengSys(),name)});
   using(var tr=target.Database.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(target.Database.BlockTableId,OpenMode.ForRead);bool found=false;
    foreach(ObjectId id in bt){var b=(BlockTableRecord)tr.GetObject(id,OpenMode.ForRead);if(!b.IsFromExternalReference||b.XrefStatus!=XrefStatus.Resolved)continue;string full=Path.GetFullPath(Path.Combine(Path.GetDirectoryName(target.Name),b.PathName));if(Eq(full,terrain))found=true;}
    if(!found)throw new InvalidOperationException("TERRAIN_NOT_RESOLVED:"+terrain);tr.Commit();
   }
  }
 }
 static void CloseSafely(CloseJob job){
  CheckLive(job.input,job.input_sha256);CheckPath(job.recovery_dir);CheckPath(job.receipt);if(File.Exists(job.receipt))throw new InvalidOperationException("CLOSE_RECEIPT_EXISTS");
  blocked=true;
  if(!SafeCadSessionLifecycleV42.ProtectCloseAndQuit(doc.Name,currentPath,currentHash,job.recovery_dir,job.receipt))throw new InvalidOperationException("LIFECYCLE_PROTECTION_FAILED");
 }
 static void SwitchDocument(Switch job){
  CheckLive(job.input,job.input_sha256);CheckPath(job.save_path);CheckPath(job.next_path);CheckPath(job.receipt);
  if(File.Exists(job.save_path)||File.Exists(job.receipt))throw new InvalidOperationException("SWITCH_OUTPUT_EXISTS");
  string expected;if(!approved.TryGetValue(Path.GetFullPath(job.next_path),out expected)||expected!=job.next_sha256||Hash(job.next_path)!=job.next_sha256)throw new InvalidOperationException("NEXT_DOCUMENT_NOT_ALLOWLISTED");
  using(doc.LockDocument()){doc.Database.SaveAs(job.save_path,DwgVersion.AC1032);}string savedHash=Hash(job.save_path);VerifyDwg(job.save_path);if(Hash(job.save_path)!=savedHash)throw new InvalidOperationException("SAVE_CHANGED");
  approved[Path.GetFullPath(job.save_path)]=savedHash;if(gardenPaths.Contains(currentPath))gardenPaths.Add(Path.GetFullPath(job.save_path));Write(job.receipt,new{status="CURRENT_SAVED_BEFORE_SWITCH",source=doc.Name,saved=job.save_path,sha256=savedHash,next=job.next_path,pid=System.Diagnostics.Process.GetCurrentProcess().Id});
  doc.CloseAndDiscard();doc=null;doc=App.DocumentManager.Open(job.next_path,false);App.DocumentManager.MdiActiveDocument=doc;HostApplicationServices.WorkingDatabase=doc.Database;
  livePath=Path.GetFullPath(job.next_path);currentPath=livePath;currentHash=job.next_sha256;ResolveTerrain(doc);State();
 }
 static ObjectId Id(Database db,string h){return db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0);}
 static Entity Checked(Transaction tr,Database db,Target target,OpenMode mode){
  if(target==null||String.IsNullOrEmpty(target.handle)||String.IsNullOrEmpty(target.type)||String.IsNullOrEmpty(target.layer)||target.bounds==null||target.bounds.Length!=4)throw new InvalidOperationException("TARGET_IDENTITY_REQUIRED");
  var e=tr.GetObject(Id(db,target.handle),mode) as Entity;if(e==null||e.GetRXClass().Name!=target.type||e.Layer!=target.layer)throw new InvalidOperationException("TARGET_TYPE_OR_LAYER:"+target.handle);
  var x=e.GeometricExtents;double[] actual={x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};for(int i=0;i<4;i++)if(Math.Abs(actual[i]-target.bounds[i])>.001)throw new InvalidOperationException("TARGET_BOUNDS_CHANGED:"+target.handle);return e;
 }
 static void CheckOutput(string output,string receipt){CheckPath(output);CheckPath(receipt);if(File.Exists(output)||File.Exists(receipt))throw new InvalidOperationException("OUTPUT_EXISTS");}
 static void SaveModified(string output,string receipt,object changes){doc.Database.SaveAs(output,DwgVersion.AC1032);string hash=Hash(output);approved[Path.GetFullPath(output)]=hash;if(gardenPaths.Contains(currentPath))gardenPaths.Add(Path.GetFullPath(output));currentPath=Path.GetFullPath(output);currentHash=hash;Write(receipt,new{status="SAVED_STILL_OPEN",live_document=doc.Name,output=currentPath,sha256=hash,changes=changes,pid=System.Diagnostics.Process.GetCurrentProcess().Id});State();}
 static void EraseExact(EraseJob job){
  CheckLive(job.input,job.input_sha256);CheckOutput(job.output,job.receipt);if(job.targets==null||job.targets.Length==0||job.targets.Select(x=>x.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=job.targets.Length)throw new InvalidOperationException("ERASE_TARGETS_INVALID");
  using(doc.LockDocument()){using(var tr=doc.Database.TransactionManager.StartTransaction()){foreach(var item in job.targets)Checked(tr,doc.Database,item,OpenMode.ForWrite).Erase();tr.Commit();}SaveModified(job.output,job.receipt,new{erased=job.targets.Select(x=>x.handle).ToArray()});}
 }
 static void HatchWorkplane(HatchJob job){
  CheckLive(job.input,job.input_sha256);CheckOutput(job.output,job.receipt);if(job.parts==null||job.parts.Length==0||String.IsNullOrEmpty(job.template_layer))throw new InvalidOperationException("HATCH_PLAN_INVALID");var added=new List<object>();
  using(doc.LockDocument()){using(var tr=doc.Database.TransactionManager.StartTransaction()){
   var db=doc.Database;var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);var template=(Hatch)tr.GetObject(Id(db,job.template),OpenMode.ForRead);
   if(String.IsNullOrEmpty(job.expected_pattern)||!String.Equals(template.PatternName,job.expected_pattern,StringComparison.OrdinalIgnoreCase)||template.Layer!=job.template_layer||(job.expected_color.HasValue&&template.ColorIndex!=job.expected_color.Value))throw new InvalidOperationException("HATCH_TEMPLATE_IDENTITY");
   if(job.replace_target!=null)Checked(tr,db,job.replace_target,OpenMode.ForRead);
   foreach(var part in job.parts){var loops=part.loops;if(loops==null||loops.Length==0||loops[0].Length<3)throw new InvalidOperationException("CLOSED_LOOPS_REQUIRED");double ox=loops[0][0][0],oy=loops[0][0][1];var offset=new Vector3d(ox,oy,0);var boundaries=new List<ObjectId>();
    foreach(var loop in loops){if(loop.Length<3)throw new InvalidOperationException("BOUNDARY_TOO_SHORT");var boundary=new Polyline();boundary.Normal=Vector3d.ZAxis;boundary.Elevation=0;boundary.Layer=template.Layer;int n=loop.Length;if(loop[0][0]==loop[n-1][0]&&loop[0][1]==loop[n-1][1])n--;for(int i=0;i<n;i++){var v=loop[i];boundary.AddVertexAt(i,new Point2d(v[0]-ox,v[1]-oy),v.Length>2?v[2]:0,0,0);}boundary.Closed=true;ms.AppendEntity(boundary);tr.AddNewlyCreatedDBObject(boundary,true);boundaries.Add(boundary.ObjectId);}
    var target=(Hatch)template.Clone();ms.AppendEntity(target);tr.AddNewlyCreatedDBObject(target,true);target.Associative=false;while(target.NumberOfLoops>0)target.RemoveLoopAt(target.NumberOfLoops-1);target.Normal=Vector3d.ZAxis;target.Elevation=0;target.HatchStyle=HatchStyle.Normal;target.Origin=new Point2d(template.Origin.X-ox,template.Origin.Y-oy);
    for(int i=0;i<boundaries.Count;i++)target.AppendLoop(i==0?HatchLoopTypes.External:HatchLoopTypes.Default,new ObjectIdCollection(new[]{boundaries[i]}));target.EvaluateHatch(true);target.TransformBy(Matrix3d.Displacement(offset));target.EvaluateHatch(true);double area=target.Area;if(Double.IsNaN(area)||area<=0)throw new InvalidOperationException("HATCH_AREA_INVALID");foreach(var id in boundaries)((Entity)tr.GetObject(id,OpenMode.ForWrite)).Erase();added.Add(new{handle=target.Handle.ToString(),area=area,workplane_z=0,offset=new[]{ox,oy}});
   }if(job.replace_target!=null)Checked(tr,db,job.replace_target,OpenMode.ForWrite).Erase();tr.Commit();}SaveModified(job.output,job.receipt,new{new_hatches=added,removed=job.replace_target==null?null:job.replace_target.handle});}
 }
 static void TransferExact(TransferJob job){
  CheckLive(job.input,job.input_sha256);CheckOutput(job.output,job.receipt);CheckPath(job.source);string expected;if(!approved.TryGetValue(Path.GetFullPath(job.source),out expected)||expected!=job.source_sha256||Hash(job.source)!=job.source_sha256)throw new InvalidOperationException("SOURCE_NOT_ALLOWLISTED");if(job.old_targets==null||job.source_targets==null||job.source_targets.Length==0)throw new InvalidOperationException("TRANSFER_PLAN_INVALID");
  using(doc.LockDocument()){using(var source=new Database(false,true)){source.ReadDwgFile(job.source,FileOpenMode.OpenForReadAndAllShare,true,null);source.CloseInput(true);var ids=new ObjectIdCollection();using(var sr=source.TransactionManager.StartTransaction()){foreach(var target in job.source_targets){var ent=Checked(sr,source,target,OpenMode.ForRead);ids.Add(ent.ObjectId);}sr.Commit();}
   using(var tr=doc.Database.TransactionManager.StartTransaction()){var bt=(BlockTable)tr.GetObject(doc.Database.BlockTableId,OpenMode.ForRead);var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);foreach(var old in job.old_targets)Checked(tr,doc.Database,old,OpenMode.ForWrite).Erase();var map=new IdMapping();source.WblockCloneObjects(ids,ms.ObjectId,map,DuplicateRecordCloning.Ignore,false);tr.Commit();}
  }SaveModified(job.output,job.receipt,new{removed=job.old_targets.Select(x=>x.handle).ToArray(),source=job.source,copied=job.source_targets.Select(x=>x.handle).ToArray()});}
 }
 static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 static string TextOf(Entity e){var d=e as DBText;return d!=null?d.TextString:(e as MText)!=null?((MText)e).Contents:null;}
 static Dictionary<string,object> Describe(Entity e,Transaction t){var row=new Dictionary<string,object>{{"handle",e.Handle.ToString()},{"type",e.GetRXClass().Name},{"dxf",e.GetRXClass().DxfName},{"layer",e.Layer},{"color",e.ColorIndex}};try{var x=e.GeometricExtents;row["bounds"]=new[]{x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};row["center"]=new[]{(x.MinPoint.X+x.MaxPoint.X)/2.0,(x.MinPoint.Y+x.MaxPoint.Y)/2.0};}catch{}string text=TextOf(e);if(text!=null){row["text"]=text;var p=(e as DBText)!=null?((DBText)e).Position:((MText)e).Location;row["position"]=new[]{p.X,p.Y,p.Z};}var br=e as BlockReference;if(br!=null){row["block"]=((BlockTableRecord)t.GetObject(br.BlockTableRecord,OpenMode.ForRead)).Name;row["insert"]=new[]{br.Position.X,br.Position.Y,br.Position.Z};row["rotation"]=br.Rotation;}var vp=e as Viewport;if(vp!=null){row["viewportNumber"]=vp.Number;row["viewportCenter"]=new[]{vp.CenterPoint.X,vp.CenterPoint.Y};row["viewportSize"]=new[]{vp.Width,vp.Height};row["viewCenter"]=new[]{vp.ViewCenter.X,vp.ViewCenter.Y};row["viewHeight"]=vp.ViewHeight;row["viewTarget"]=new[]{vp.ViewTarget.X,vp.ViewTarget.Y,vp.ViewTarget.Z};row["twistAngle"]=vp.TwistAngle;row["customScale"]=vp.CustomScale;}return row;}
 static void PageMap(PageMapJob job){
  CheckLive(job.input,job.input_sha256);CheckPath(job.receipt);if(File.Exists(job.receipt))throw new InvalidOperationException("RECEIPT_EXISTS");
  if(String.IsNullOrEmpty(job.layout)||String.IsNullOrEmpty(job.title_contains)||String.IsNullOrEmpty(job.frame_block_prefix)||String.IsNullOrEmpty(job.grid_block_name))throw new InvalidOperationException("PAGE_MAP_PLAN_INVALID");
  var rows=new List<object>();var entities=new List<Entity>();string matchedLayout=null;
  using(doc.LockDocument()){
   using(var tr=doc.Database.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(doc.Database.BlockTableId,OpenMode.ForRead);ObjectId spaceId=ObjectId.Null;
    foreach(ObjectId bid in bt){var btr=(BlockTableRecord)tr.GetObject(bid,OpenMode.ForRead);if(!btr.IsLayout)continue;var layout=(Layout)tr.GetObject(btr.LayoutId,OpenMode.ForRead);if(layout.LayoutName!=job.layout)continue;spaceId=bid;matchedLayout=layout.LayoutName;break;}
    if(spaceId.IsNull)throw new InvalidOperationException("LAYOUT_NOT_FOUND:"+job.layout);
    var space=(BlockTableRecord)tr.GetObject(spaceId,OpenMode.ForWrite);
    foreach(ObjectId id in space){var e=tr.GetObject(id,OpenMode.ForRead,false) as Entity;if(e==null||e.IsErased)continue;entities.Add(e);rows.Add(Describe(e,tr));}
    var titles=entities.Where(x=>TextOf(x)!=null&&TextOf(x).Contains(job.title_contains)).ToArray();
    var frames=entities.OfType<BlockReference>().Where(x=>((BlockTableRecord)tr.GetObject(x.BlockTableRecord,OpenMode.ForRead)).Name.StartsWith(job.frame_block_prefix,StringComparison.OrdinalIgnoreCase)).ToArray();
    var grids=entities.OfType<BlockReference>().Where(x=>String.Equals(((BlockTableRecord)tr.GetObject(x.BlockTableRecord,OpenMode.ForRead)).Name,job.grid_block_name,StringComparison.OrdinalIgnoreCase)).ToArray();
    var viewports=entities.OfType<Viewport>().ToArray();
    string afterHash=Hash(currentPath);if(afterHash!=currentHash)throw new InvalidOperationException("PAGE_MAP_SOURCE_CHANGED");
    Write(job.receipt,new{status="PAGE_MAP_READ_ONLY",document=doc.Name,source_sha256=currentHash,source_sha256_after=afterHash,layout=matchedLayout,titleContains=job.title_contains,frameBlockPrefix=job.frame_block_prefix,gridBlockName=job.grid_block_name,paperSpaceEntityCount=entities.Count,titleCount=titles.Length,viewportCount=viewports.Length,frameCount=frames.Length,gridCount=grids.Length,titles=titles.Select(x=>Describe(x,tr)).ToArray(),viewports=viewports.Select(x=>Describe(x,tr)).ToArray(),frames=frames.Select(x=>Describe(x,tr)).ToArray(),grids=grids.Select(x=>Describe(x,tr)).ToArray(),entities=rows,pid=System.Diagnostics.Process.GetCurrentProcess().Id});
    tr.Commit();
   }
  }
 }
 static string BlockName(Transaction tr,Entity e){
  var br=e as BlockReference;if(br==null)return null;
  return ((BlockTableRecord)tr.GetObject(br.BlockTableRecord,OpenMode.ForRead)).Name;
 }
 static bool Contains(double[] outer,double[] inner){
  return inner[0]>=outer[0]-0.001&&inner[1]>=outer[1]-0.001&&inner[2]<=outer[2]+0.001&&inner[3]<=outer[3]+0.001;
 }
 static void CopyTransform(CopyTransformJob job){
  CheckLive(job.input,job.input_sha256);CheckOutput(job.output,job.receipt);
  if(String.IsNullOrEmpty(job.layout)||String.IsNullOrEmpty(job.frame_block_prefix)||String.IsNullOrEmpty(job.grid_block_name)||job.pairs==null||job.pairs.Length==0)throw new InvalidOperationException("COPY_TRANSFORM_PLAN_INVALID");
  var handles=job.pairs.SelectMany(x=>new[]{x.source_grid,x.source_frame,x.target_frame}).ToArray();
  if(handles.Any(x=>x==null||String.IsNullOrEmpty(x.handle))||handles.Select(x=>x.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()!=handles.Length)throw new InvalidOperationException("COPY_TRANSFORM_TARGETS_INVALID");
  var added=new List<object>();
  using(doc.LockDocument()){
   using(var tr=doc.Database.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(doc.Database.BlockTableId,OpenMode.ForRead);ObjectId spaceId=ObjectId.Null;
    foreach(ObjectId bid in bt){var btr=(BlockTableRecord)tr.GetObject(bid,OpenMode.ForRead);if(!btr.IsLayout)continue;var layout=(Layout)tr.GetObject(btr.LayoutId,OpenMode.ForRead);if(layout.LayoutName!=job.layout)continue;spaceId=bid;break;}
    if(spaceId.IsNull)throw new InvalidOperationException("LAYOUT_NOT_FOUND:"+job.layout);
    var space=(BlockTableRecord)tr.GetObject(spaceId,OpenMode.ForWrite);
    var plans=new List<object>();
    foreach(var pair in job.pairs){
     var grid=Checked(tr,doc.Database,pair.source_grid,OpenMode.ForRead) as BlockReference;
     var sourceFrame=Checked(tr,doc.Database,pair.source_frame,OpenMode.ForRead) as BlockReference;
     var targetFrame=Checked(tr,doc.Database,pair.target_frame,OpenMode.ForRead) as BlockReference;
     if(grid==null||sourceFrame==null||targetFrame==null)throw new InvalidOperationException("COPY_TRANSFORM_NOT_BLOCK:"+pair.source_grid.handle);
     if(!String.Equals(BlockName(tr,grid),job.grid_block_name,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("COPY_SOURCE_BLOCK_CHANGED:"+pair.source_grid.handle);
     if(!BlockName(tr,sourceFrame).StartsWith(job.frame_block_prefix,StringComparison.OrdinalIgnoreCase)||!BlockName(tr,targetFrame).StartsWith(job.frame_block_prefix,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("COPY_FRAME_BLOCK_CHANGED");
     if(!spaceId.Equals(grid.OwnerId)||!spaceId.Equals(sourceFrame.OwnerId)||!spaceId.Equals(targetFrame.OwnerId))throw new InvalidOperationException("COPY_SPACE_CHANGED");
     if(!Contains(pair.source_frame.bounds,pair.source_grid.bounds))throw new InvalidOperationException("COPY_SOURCE_OUTSIDE_FRAME:"+pair.source_grid.handle);
     var g=pair.source_grid.bounds;var f=pair.source_frame.bounds;var t=pair.target_frame.bounds;
     var displacement=new Vector3d(t[0]-f[0],t[1]-f[1],0);
     if(Math.Abs(displacement.X)>0.001)throw new InvalidOperationException("COPY_DISPLACEMENT_NOT_VERTICAL:"+pair.source_grid.handle);
     var expected=new[]{g[0]+displacement.X,g[1]+displacement.Y,g[2]+displacement.X,g[3]+displacement.Y};
     if(!Contains(pair.target_frame.bounds,expected))throw new InvalidOperationException("COPY_TARGET_OUTSIDE_FRAME:"+pair.source_grid.handle);
     var occupied=false;
     foreach(ObjectId id in space){var e=tr.GetObject(id,OpenMode.ForRead,false) as BlockReference;if(e==null||e.IsErased)continue;if(!String.Equals(BlockName(tr,e),job.grid_block_name,StringComparison.OrdinalIgnoreCase))continue;try{var x=e.GeometricExtents;var b=new[]{x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};if(b[0]<t[2]&&b[2]>t[0]&&b[1]<t[3]&&b[3]>t[1])occupied=true;}catch{}}
     if(occupied)throw new InvalidOperationException("COPY_TARGET_ALREADY_HAS_GRID:"+pair.target_frame.handle);
     plans.Add(new{grid=grid,sourceFrame=sourceFrame,targetFrame=targetFrame,displacement=displacement,expected=expected});
    }
    foreach(dynamic plan in plans){
     var grid=(BlockReference)plan.grid;var expected=(double[])plan.expected;var displacement=(Vector3d)plan.displacement;
     var copy=(BlockReference)grid.Clone();var copyId=space.AppendEntity(copy);tr.AddNewlyCreatedDBObject(copy,true);copy.TransformBy(Matrix3d.Displacement(displacement));
     var x=copy.GeometricExtents;var actual=new[]{x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};
     for(int i=0;i<4;i++)if(Math.Abs(actual[i]-expected[i])>0.001)throw new InvalidOperationException("COPY_BOUNDS_CHANGED:"+copy.Handle.ToString());
     if(!String.Equals(copy.Layer,grid.Layer,StringComparison.OrdinalIgnoreCase)||!String.Equals(BlockName(tr,copy),job.grid_block_name,StringComparison.OrdinalIgnoreCase)||!spaceId.Equals(copy.OwnerId))throw new InvalidOperationException("COPY_IDENTITY_CHANGED:"+copy.Handle.ToString());
     added.Add(new{source_handle=grid.Handle.ToString(),handle=copy.Handle.ToString(),displacement=new[]{displacement.X,displacement.Y,displacement.Z},bounds=actual,block=job.grid_block_name,layer=copy.Layer});
    }
    tr.Commit();
   }
  }
  SaveModified(job.output,job.receipt,new{copied_grids=added});
 }
 static void InspectRegion(Inspect job){
  CheckLive(job.input,job.input_sha256);CheckPath(job.receipt);if(File.Exists(job.receipt))throw new InvalidOperationException("RECEIPT_EXISTS");
  if((job.handles==null||job.handles.Length==0)&&(job.bounds==null||job.bounds.Length!=4))throw new InvalidOperationException("SCOPED_INSPECTION_REQUIRED");
  var rows=new List<object>();
  using(doc.LockDocument()){
   using(var tr=doc.Database.TransactionManager.StartTransaction()){
    var bt=(BlockTable)tr.GetObject(doc.Database.BlockTableId,OpenMode.ForRead);var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    IEnumerable<ObjectId> scoped=(job.bounds==null&&job.handles!=null)?job.handles.Select(h=>Id(doc.Database,h)):ms.Cast<ObjectId>();foreach(ObjectId id in scoped){var e=tr.GetObject(id,OpenMode.ForRead) as Entity;if(e==null||e.OwnerId!=ms.ObjectId)continue;bool selected=job.handles!=null&&job.handles.Contains(e.Handle.ToString(),StringComparer.OrdinalIgnoreCase);Extents3d ex=new Extents3d();bool hasExt=false;try{ex=e.GeometricExtents;hasExt=true;}catch{}
     if(job.bounds!=null&&job.bounds.Length==4&&hasExt)selected|=ex.MinPoint.X<=job.bounds[2]&&ex.MaxPoint.X>=job.bounds[0]&&ex.MinPoint.Y<=job.bounds[3]&&ex.MaxPoint.Y>=job.bounds[1];if(!selected)continue;
     var row=new Dictionary<string,object>{{"handle",e.Handle.ToString()},{"type",e.GetRXClass().Name},{"dxf",e.GetRXClass().DxfName},{"layer",e.Layer},{"color",e.ColorIndex}};
     if(hasExt)row["bounds"]=new[]{ex.MinPoint.X,ex.MinPoint.Y,ex.MaxPoint.X,ex.MaxPoint.Y};var pl=e as Polyline;if(pl!=null){var pts=new List<double[]>();for(int i=0;i<pl.NumberOfVertices;i++){var p=pl.GetPoint2dAt(i);pts.Add(new[]{p.X,p.Y,pl.GetBulgeAt(i)});}row["vertices"]=pts;row["closed"]=pl.Closed;row["elevation"]=pl.Elevation;}
     var b=e as BlockReference;if(b!=null){row["block"]=((BlockTableRecord)tr.GetObject(b.BlockTableRecord,OpenMode.ForRead)).Name;row["position"]=P(b.Position);row["rotation"]=b.Rotation;}
     var h=e as Hatch;if(h!=null){row["pattern"]=h.PatternName;row["loops"]=h.NumberOfLoops;try{row["area"]=h.Area;}catch{}}
     rows.Add(row);
    }tr.Commit();
   }
   if(!String.IsNullOrEmpty(job.image)){
    CheckPath(job.image);if(File.Exists(job.image)||job.width<=0||job.height<=0)throw new InvalidOperationException("IMAGE_TARGET");
    ViewStage(job,"ACTIVATE_LAYOUT");
    bool paper=job.layout!="Model";if(doc.Database.TileMode==paper)doc.Database.TileMode=!paper;
    if(LayoutManager.Current.CurrentLayout!=job.layout)LayoutManager.Current.CurrentLayout=job.layout;
    ViewStage(job,"ACTIVATE_PAPERSPACE");
    if(paper&&Convert.ToInt32(App.GetSystemVariable("CVPORT"))!=1)doc.Editor.SwitchToPaperSpace();
    if(paper&&Convert.ToInt32(App.GetSystemVariable("CVPORT"))!=1)throw new InvalidOperationException("PAPERSPACE_NOT_ACTIVE");
    ViewStage(job,"NATIVE_ZOOM");
    // Execute the native view operation in document command context, never
    // SetCurrentView/Regen in Application.Idle after an MDI document swap.
    using(var view=doc.Editor.GetCurrentView()){
     if(!paper&&(Math.Abs(view.ViewTwist)>1e-10||(view.ViewDirection.GetNormal()-Vector3d.ZAxis).Length>1e-10))doc.Editor.Command("_.PLAN","_W");
     double aspect=view.Width/view.Height;double height=Math.Max(job.height,job.width/aspect);
     doc.Editor.Command("_.ZOOM","_C",new Point3d(job.x,job.y,0),height);
    }
    ViewStage(job,"NATIVE_VIEW_POSITIONED");
   }
  }
  Write(job.receipt,new{status="SCOPED_READ_ONLY_INSPECTION",document=doc.Name,source_sha256=currentHash,image=job.image,layout=job.layout,actual_layout=App.GetSystemVariable("CTAB"),cvport=App.GetSystemVariable("CVPORT"),entities=rows,pid=System.Diagnostics.Process.GetCurrentProcess().Id});
 }
 static void ViewStage(Inspect job,string stage){File.WriteAllText(job.receipt+".progress.json",J.Serialize(new{stage=stage,pid=System.Diagnostics.Process.GetCurrentProcess().Id,input=job.input,source_sha256=job.input_sha256}),new System.Text.UTF8Encoding(false));}
 [CommandMethod("HL736INSPECT",CommandFlags.Modal)] public void InspectCommand(){
  if(pendingView==null||busy||blocked)return;busy=true;var job=pendingView;pendingView=null;
  try{ViewStage(job,"DOCUMENT_COMMAND_STARTED");InspectRegion(job);}
  catch(System.Exception ex){blocked=true;File.WriteAllText(Path.Combine(dir,"session_failure.json"),J.Serialize(new{status="HOLD",error=ex.ToString(),emergency=(string)null,live=doc==null?null:doc.Name,pid=System.Diagnostics.Process.GetCurrentProcess().Id,view_read_only=true}),new System.Text.UTF8Encoding(false));}
  finally{busy=false;}
 }
 static void Pump(object sender,EventArgs args){
  if(busy||blocked||pendingView!=null||!File.Exists(queue))return;busy=true;
  try{string accepted=Path.Combine(dir,"request_"+Guid.NewGuid().ToString("N")+".json");File.Move(queue,accepted);var request=J.Deserialize<Request>(File.ReadAllText(accepted));CheckPath(request.job_path);if(Hash(request.job_path)!=request.job_sha256)throw new InvalidOperationException("JOB_IDENTITY");string data=File.ReadAllText(request.job_path);if(request.kind=="inspect"){var inspect=J.Deserialize<Inspect>(data);if(String.IsNullOrEmpty(inspect.image))InspectRegion(inspect);else{pendingView=inspect;ViewStage(inspect,"QUEUED_DOCUMENT_COMMAND");doc.SendStringToExecute("HL736INSPECT\n",true,false,false);}}else if(request.kind=="page_map")PageMap(J.Deserialize<PageMapJob>(data));else if(request.kind=="switch")SwitchDocument(J.Deserialize<Switch>(data));else if(request.kind=="erase")EraseExact(J.Deserialize<EraseJob>(data));else if(request.kind=="hatch")HatchWorkplane(J.Deserialize<HatchJob>(data));else if(request.kind=="transfer")TransferExact(J.Deserialize<TransferJob>(data));else if(request.kind=="copy_transform")CopyTransform(J.Deserialize<CopyTransformJob>(data));else if(request.kind=="close")CloseSafely(J.Deserialize<CloseJob>(data));else throw new InvalidOperationException("JOB_KIND");}
  catch(System.Exception ex){blocked=true;string emergency=null;try{if(doc!=null){emergency=Path.Combine(dir,"emergency_"+Guid.NewGuid().ToString("N")+".dwg");using(doc.LockDocument())doc.Database.SaveAs(emergency,DwgVersion.AC1032);}}catch{emergency=null;}File.WriteAllText(Path.Combine(dir,"session_failure.json"),J.Serialize(new{status="HOLD",error=ex.ToString(),emergency=emergency,live=doc==null?null:doc.Name,pid=System.Diagnostics.Process.GetCurrentProcess().Id}),new System.Text.UTF8Encoding(false));}finally{busy=false;}
 }
 [CommandMethod("HL736BASE",CommandFlags.Session)] public void Start(){
  string file=Environment.GetEnvironmentVariable("HL_BASE_JOB"), expected=Environment.GetEnvironmentVariable("HL_BASE_JOB_SHA256");if(String.IsNullOrEmpty(file)||Hash(file)!=expected)throw new InvalidOperationException("BOOT_IDENTITY");config=J.Deserialize<Config>(File.ReadAllText(file));dir=Path.GetDirectoryName(Path.GetFullPath(file));queue=Path.Combine(dir,"request.json");
  CheckPath(config.garden);CheckPath(config.planting);CheckPath(config.terrain);terrain=Path.GetFullPath(config.terrain);terrainHash=config.terrain_sha256;if(File.Exists(queue)||Hash(config.garden)!=config.garden_sha256||Hash(config.planting)!=config.planting_sha256||Hash(terrain)!=terrainHash)throw new InvalidOperationException("BOOT_FILES");approved[Path.GetFullPath(config.garden)]=config.garden_sha256;approved[Path.GetFullPath(config.planting)]=config.planting_sha256;gardenPaths.Add(Path.GetFullPath(config.garden));
  if(config.references!=null)foreach(var entry in config.references){CheckPath(entry.Key);if(Hash(entry.Key)!=entry.Value)throw new InvalidOperationException("RECOVERY_REFERENCE_IDENTITY");approved[Path.GetFullPath(entry.Key)]=entry.Value;}
  if(config.initial_role!=null&&config.initial_role!="garden"&&config.initial_role!="planting")throw new InvalidOperationException("INITIAL_ROLE_INVALID");
  string initial=config.initial_role=="planting"?config.planting:config.garden;string initialHash=config.initial_role=="planting"?config.planting_sha256:config.garden_sha256;
  object oldFont=App.GetSystemVariable("FONTMAP"),oldProxy=App.GetSystemVariable("PROXYNOTICE");try{if(!String.IsNullOrWhiteSpace(config.font_map))App.SetSystemVariable("FONTMAP",config.font_map);App.SetSystemVariable("PROXYNOTICE",0);ProtectInitial();doc=App.DocumentManager.Open(initial,false);App.DocumentManager.MdiActiveDocument=doc;livePath=Path.GetFullPath(initial);currentPath=livePath;currentHash=initialHash;ResolveTerrain(doc);}finally{App.SetSystemVariable("FONTMAP",oldFont);App.SetSystemVariable("FILEDIA",1);App.SetSystemVariable("CMDDIA",1);App.SetSystemVariable("PROXYNOTICE",oldProxy);}
  State();App.Idle+=Pump;
 }
}
