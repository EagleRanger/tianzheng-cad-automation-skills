// Translate boundary data, never TransformBy the patterned HATCH: the latter can
// reload a different installed PAT definition and move its line-family bases.
using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.ApplicationServices;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class HatchWorkplaneV2 {
 public class Target{public string handle,type,layer;public double[] bounds;}
 public class Part{public double[][][] loops;}
 public class Job{public string input,input_sha256,template,template_layer,expected_pattern,output,receipt;public int? expected_color;public Target replace_target;public Part[] parts;}
 public class TestConfig{public string source,source_sha256,receipt;public Job job;public int? expected_render_line_count;}
 public class Added{public string handle;public double area,local_area;public double[] offset;public int loops;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=100000000,RecursionLimit=100};
 public static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}
 public static void Write(string p,object o){using(var f=new FileStream(p,FileMode.CreateNew))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(o));}
 public static ObjectId Id(Database d,string h){return d.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0);}
 public static bool Absent(Database d,string handle){try{return Id(d,handle).IsErased;}catch(Autodesk.AutoCAD.Runtime.Exception e){if(e.ErrorStatus.ToString()=="UnknownHandle")return true;throw;}}
 public static string Pattern(Hatch h){return J.Serialize(new{h.PatternName,h.PatternType,h.PatternScale,h.PatternAngle,h.PatternDouble,h.HatchStyle,origin=new[]{h.Origin.X,h.Origin.Y},definitions=Enumerable.Range(0,h.NumberOfPatternDefinitions).Select(i=>{var p=h.GetPatternDefinitionAt(i);return new{p.Angle,p.BaseX,p.BaseY,p.OffsetX,p.OffsetY,dashes=p.GetDashes().Cast<double>().ToArray()};}).ToArray()});}
 static void SetLoops(Hatch h,double[][][] loops,double ox,double oy){
  while(h.NumberOfLoops>0)h.RemoveLoopAt(h.NumberOfLoops-1);
  for(int j=0;j<loops.Length;j++){var loop=loops[j];Need(loop!=null&&loop.Length>=3,"BOUNDARY_TOO_SHORT");int n=loop.Length;if(loop[0][0]==loop[n-1][0]&&loop[0][1]==loop[n-1][1])n--;Need(n>=3,"BOUNDARY_TOO_SHORT");var points=new Point2dCollection();var bulges=new DoubleCollection();
   for(int i=0;i<n;i++){var v=loop[i];Need(v!=null&&v.Length>=2&&v.Length<=3&&v.All(x=>!Double.IsNaN(x)&&!Double.IsInfinity(x)),"FINITE_XY_BULGE_REQUIRED");points.Add(new Point2d(v[0]-ox,v[1]-oy));bulges.Add(v.Length==3?v[2]:0);}
   // Native HATCH polyline loops need the terminal start point explicitly.
   // AutoCAD can report the right area without it while clipping away pattern
   // strokes at the implicit closing segment (especially a closing arc).
   points.Add(points[0]);bulges.Add(0);
   h.AppendLoop(j==0?HatchLoopTypes.External:HatchLoopTypes.Default,points,bulges);
  }
 }
 public static Added[] Apply(Document doc,Job job){
  Need(job.parts!=null&&job.parts.Length>0,"HATCH_PARTS_REQUIRED");var db=doc.Database;var rows=new List<Added>();
  using(var tr=db.TransactionManager.StartTransaction()){
   var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);var source=tr.GetObject(Id(db,job.template),OpenMode.ForRead) as Hatch;
   Need(source!=null&&source.OwnerId==ms.ObjectId&&source.PatternName==job.expected_pattern&&source.Layer==job.template_layer&&(!job.expected_color.HasValue||source.ColorIndex==job.expected_color.Value),"HATCH_TEMPLATE_IDENTITY");
   Need(source.Normal.IsEqualTo(Vector3d.ZAxis)&&source.Elevation==0&&source.HatchStyle==HatchStyle.Normal&&!source.IsSolidFill,"NORMAL_Z0_PATTERN_TEMPLATE_REQUIRED");
   string pattern=Pattern(source);Entity old=null;
   if(job.replace_target!=null){var t=job.replace_target;old=tr.GetObject(Id(db,t.handle),OpenMode.ForRead) as Entity;Need(old is Hatch&&old.OwnerId==ms.ObjectId&&old.GetRXClass().Name==t.type&&old.Layer==t.layer&&t.bounds!=null&&t.bounds.Length==4,"REPLACE_HATCH_IDENTITY");var ex=old.GeometricExtents;var b=new[]{ex.MinPoint.X,ex.MinPoint.Y,ex.MaxPoint.X,ex.MaxPoint.Y};Need(b.Zip(t.bounds,(x,y)=>Math.Abs(x-y)).All(x=>x<=.001),"REPLACE_HATCH_BOUNDS_CHANGED");}
   foreach(var part in job.parts){Need(part.loops!=null&&part.loops.Length>0&&part.loops[0].Length>=3,"CLOSED_LOOPS_REQUIRED");double ox=part.loops[0][0][0],oy=part.loops[0][0][1];
    var h=(Hatch)source.Clone();ms.AppendEntity(h);tr.AddNewlyCreatedDBObject(h,true);h.Associative=false;
    SetLoops(h,part.loops,ox,oy);h.EvaluateHatch(true);double local=h.Area;Need(local>0&&!Double.IsNaN(local),"LOCAL_HATCH_AREA_INVALID");Need(Pattern(h)==pattern,"LOCAL_PATTERN_CHANGED");
    // Reapply the inverse translation to the complete native boundary (bulges
    // and holes included). No setter touches the template's pattern or origin.
    SetLoops(h,part.loops,0,0);h.EvaluateHatch(true);double world=h.Area;Need(Math.Abs(world-local)<=Math.Max(1e-5,local*1e-8),"WORKPLANE_AREA_MISMATCH");Need(Pattern(h)==pattern,"RETURN_PATTERN_CHANGED");
    h.RecordGraphicsModified(true);rows.Add(new Added{handle=h.Handle.ToString(),area=world,local_area=local,offset=new[]{ox,oy},loops=h.NumberOfLoops});
   }
   Need(Pattern(source)==pattern,"SOURCE_PATTERN_CHANGED");if(old!=null){old.UpgradeOpen();old.Erase();}tr.Commit();
  }return rows.ToArray();
 }
 static int RenderLineCount(Hatch h){var parts=new DBObjectCollection();try{h.Explode(parts);return parts.Cast<DBObject>().OfType<Line>().Count();}finally{foreach(DBObject p in parts)p.Dispose();}}
 [CommandMethod("HLCADHATCHWORKPLANETESTV6",CommandFlags.Session)]public void Test(){
  var original=App.DocumentManager.MdiActiveDocument;var previous=HostApplicationServices.WorkingDatabase;var a=original.Editor.GetString(new PromptStringOptions("\nIsolated hatch test: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;TestConfig c=null;Document staging=null;
  try{c=J.Deserialize<TestConfig>(File.ReadAllText(a.StringResult.Trim('"')));var job=c.job;Need(job.input==c.source&&job.input_sha256==c.source_sha256&&NativeGeometryReadV1.Hash(c.source)==c.source_sha256&&!File.Exists(job.output)&&!File.Exists(c.receipt),"TEST_SOURCE_OUTPUT_IDENTITY");string copy=job.output+".staging.dwg";File.Copy(c.source,copy,false);staging=App.DocumentManager.Open(copy,false);App.DocumentManager.MdiActiveDocument=staging;HostApplicationServices.WorkingDatabase=staging.Database;string expected;Added[] created;
   using(staging.LockDocument()){using(var tr=staging.Database.TransactionManager.StartTransaction())expected=Pattern((Hatch)tr.GetObject(Id(staging.Database,job.template),OpenMode.ForRead));created=Apply(staging,job);staging.Editor.Regen();staging.Database.SaveAs(job.output,DwgVersion.AC1032);}
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;staging.CloseAndDiscard();staging=App.DocumentManager.Open(job.output,true);App.DocumentManager.MdiActiveDocument=staging;HostApplicationServices.WorkingDatabase=staging.Database;var geometry=new List<object>();int renderCount=0;
   using(staging.LockDocument())using(var tr=staging.Database.TransactionManager.StartTransaction()){foreach(var row in created){var h=(Hatch)tr.GetObject(Id(staging.Database,row.handle),OpenMode.ForRead);Need(Pattern(h)==expected&&h.NumberOfLoops==row.loops&&Math.Abs(h.Area-row.area)<1e-7,"REOPEN_HATCH_MISMATCH");geometry.Add(NativeGeometryReadV1.Geometry(h));if(c.expected_render_line_count.HasValue)renderCount+=RenderLineCount(h);}if(job.replace_target!=null)Need(Absent(staging.Database,job.replace_target.handle),"OLD_HATCH_RETAINED");}
   Need(!c.expected_render_line_count.HasValue||renderCount==c.expected_render_line_count.Value,"REOPEN_RENDER_LINE_REGRESSION");
   Write(c.receipt,new{status="ISOLATED_NATIVE_HATCH_VERIFIED",source=c.source,source_unchanged=NativeGeometryReadV1.Hash(c.source)==c.source_sha256,output=job.output,sha256=NativeGeometryReadV1.Hash(job.output),created=created,geometry=geometry,native_save_reopen_verified=true,full_pattern_and_origin_unchanged=true,native_render_line_count=c.expected_render_line_count.HasValue?(int?)renderCount:null});
  }catch(System.Exception e){if(c!=null&&!File.Exists(c.receipt))Write(c.receipt,new{status="HATCH_TEST_FAILED",error=e.ToString()});}
  finally{App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;if(staging!=null)staging.CloseAndDiscard();}
 }
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;public Host host;}
 public class Request{public string kind,job_path,job_sha256;}
 static readonly System.Reflection.BindingFlags F=System.Reflection.BindingFlags.Static|System.Reflection.BindingFlags.NonPublic;
 static object Get(Type t,string n){return t.GetField(n,F).GetValue(null);}static object Call(Type t,string n,params object[] a){return t.GetMethod(n,F).Invoke(null,a);}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 public static string Snapshot(Database db,Added[] rows){using(var tr=db.TransactionManager.StartTransaction())return J.Serialize(rows.Select(r=>NativeGeometryReadV1.Geometry((Hatch)tr.GetObject(Id(db,r.handle),OpenMode.ForRead),false)).ToArray());}
 [CommandMethod("HLCADHATCHWORKPLANEV3",CommandFlags.Session)]public void Run(){
  var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nHatch manifest: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Type adapter=null;Job job=null;bool owned=false,committed=false;
  try{var m=J.Deserialize<Manifest>(File.ReadAllText(a.StringResult.Trim('"')));var p=System.Diagnostics.Process.GetCurrentProcess();Need(p.Id==m.host.pid&&p.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(p.MainModule.FileName,m.host.image),"HOST_IDENTITY");adapter=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);CadAdapterContractV1.Check(adapter);Need(Eq(adapter.Assembly.Location,m.loaded_dll)&&NativeGeometryReadV1.Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Get(adapter,"dir"),m.session_dir),"ADAPTER_IDENTITY");Need(!(bool)Get(adapter,"busy")&&!(bool)Get(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&NativeGeometryReadV1.Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");var req=J.Deserialize<Request>(File.ReadAllText(m.request));Need(req.kind=="hatch"&&NativeGeometryReadV1.Hash(req.job_path)==req.job_sha256,"JOB_IDENTITY");Call(adapter,"CheckPath",req.job_path);job=J.Deserialize<Job>(File.ReadAllText(req.job_path));Call(adapter,"CheckLive",job.input,job.input_sha256);Call(adapter,"CheckOutput",job.output,job.receipt);var doc=(Document)Get(adapter,"doc");Need(doc==App.DocumentManager.MdiActiveDocument,"ACTIVE_DOCUMENT_CHANGED");adapter.GetField("busy",F).SetValue(null,true);owned=true;
   using(doc.LockDocument()){var created=Apply(doc,job);committed=true;doc.Editor.Regen();var expected=Snapshot(doc.Database,created);doc.Database.SaveAs(job.output,DwgVersion.AC1032);var previous=HostApplicationServices.WorkingDatabase;
    try{using(var db=new Database(false,true)){db.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;Need(Snapshot(db,created)==expected,"REOPEN_HATCH_GEOMETRY_OR_PATTERN_CHANGED");if(job.replace_target!=null)Need(Absent(db,job.replace_target.handle),"OLD_HATCH_RETAINED");}}finally{HostApplicationServices.WorkingDatabase=previous;}
    string path=Path.GetFullPath(job.output),sha=NativeGeometryReadV1.Hash(path);((Dictionary<string,string>)Get(adapter,"approved"))[path]=sha;adapter.GetField("currentPath",F).SetValue(null,path);adapter.GetField("currentHash",F).SetValue(null,sha);Write(job.receipt,new{status="SAVED_STILL_OPEN",live_document=doc.Name,output=path,sha256=sha,pid=p.Id,changes=new{created=created,native_save_reopen_verified=true,full_pattern_and_origin_unchanged=true,workplane_boundary_inverse_translation=true}});Call(adapter,"State");}
  }catch(System.Exception e){string emergency=null;if(committed&&adapter!=null){adapter.GetField("blocked",F).SetValue(null,true);try{var d=(Document)Get(adapter,"doc");emergency=Path.Combine((string)Get(adapter,"dir"),"hatch_emergency_"+Guid.NewGuid().ToString("N")+".dwg");using(d.LockDocument())d.Database.SaveAs(emergency,DwgVersion.AC1032);}catch{}}
   if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status=committed?"BOUND_MODULE_FAILED":"REJECTED_BEFORE_WRITE",source_sha256=job.input_sha256,write_started=committed,committed=committed,replayed=false,emergency=emergency,error=e.ToString()});
  }finally{if(owned)adapter.GetField("busy",F).SetValue(null,false);}
 }

}
