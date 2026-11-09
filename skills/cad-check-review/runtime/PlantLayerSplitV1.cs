// Isolate selected static plant-symbol definitions by role. Other users keep originals.
using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Reflection;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class PlantLayerSplitV4 {
 public class Target{public string handle,type,layer;public double[] bounds;}
 public class Role{public string layer;public short color;public Target[] targets;}
 public class Job{public string input,input_sha256,output,receipt;public Role[] roles;}
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;public Host host;}
 public class Request{public string kind,job_path,job_sha256;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=100000000,RecursionLimit=100};
 static readonly BindingFlags F=BindingFlags.Static|BindingFlags.NonPublic;
 static void Need(bool b,string s){if(!b)throw new InvalidOperationException(s);}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static ObjectId Id(Database db,string h){return db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0);}
 static object Get(Type t,string n){return t.GetField(n,F).GetValue(null);}static object Call(Type t,string n,params object[] a){return t.GetMethod(n,F).Invoke(null,a);}
 static void Write(string p,object o){using(var f=new FileStream(p,FileMode.CreateNew))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(o));}
 static object Geometry(Entity e){
  if(e is MText){var t=(MText)e;return new{kind="MTEXT",text=t.Contents,location=t.Location.ToString(),height=t.TextHeight,width=t.Width,rotation=t.Rotation,normal=t.Normal.ToString(),style=t.TextStyleId.Handle.ToString()};}
  if(e is DBText){var t=(DBText)e;return new{kind="TEXT",text=t.TextString,position=t.Position.ToString(),align=t.AlignmentPoint.ToString(),height=t.Height,width=t.WidthFactor,rotation=t.Rotation,normal=t.Normal.ToString(),style=t.TextStyleId.Handle.ToString()};}
  return NativeGeometryReadV1.Geometry(e,false);
 }
 static object Child(Entity e,bool display){return new{type=e.GetRXClass().Name,geometry=Geometry(e),display=display?(object)new{layer=e.Layer,color=e.Color.ToString(),visible=e.Visible,linetype=e.LinetypeId.Handle.ToString(),scale=e.LinetypeScale,weight=e.LineWeight}:null};}
 static string Definition(Transaction tr,BlockTableRecord def,bool display){return J.Serialize(new{origin=def.Origin.ToString(),units=def.Units,entities=def.Cast<ObjectId>().Select(id=>Child((Entity)tr.GetObject(id,OpenMode.ForRead),display)).ToArray()});}
 static string State(Database db,Job job,string[] originalDefs){
  using(var tr=db.TransactionManager.StartTransaction()){
   var rows=new List<object>();foreach(var r in job.roles)foreach(var t in r.targets){var e=(Entity)tr.GetObject(Id(db,t.handle),OpenMode.ForRead);var b=e as BlockReference;rows.Add(new{handle=t.handle,layer=e.Layer,color=e.Color.ToString(),instance=b==null?Geometry(e):(object)new{matrix=b.BlockTransform.ToArray(),definition=b.BlockTableRecord.Handle.ToString(),contents=J.DeserializeObject(Definition(tr,(BlockTableRecord)tr.GetObject(b.BlockTableRecord,OpenMode.ForRead),true))}});}
   var defs=new List<object>();foreach(string h in originalDefs){var d=(BlockTableRecord)tr.GetObject(Id(db,h),OpenMode.ForRead);defs.Add(new{handle=h,contents=J.DeserializeObject(Definition(tr,d,true)),references=d.GetBlockReferenceIds(true,true).Cast<ObjectId>().Where(id=>!id.IsErased).Select(id=>id.Handle.ToString()).OrderBy(x=>x).ToArray()});}
   return J.Serialize(new{selected=rows,original_definitions=defs});
  }
 }
 static string ColorState(Transaction tr,Entity e){
  var rootLayer=(LayerTableRecord)tr.GetObject(e.LayerId,OpenMode.ForRead);var root=e.Color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByLayer?rootLayer.Color:e.Color;
  var b=e as BlockReference;if(b==null)return root.ToString();var colors=new List<string>();var d=(BlockTableRecord)tr.GetObject(b.BlockTableRecord,OpenMode.ForRead);
  foreach(ObjectId id in d){var c=(Entity)tr.GetObject(id,OpenMode.ForRead);var l=(LayerTableRecord)tr.GetObject(c.LayerId,OpenMode.ForRead);var color=c.Color;if(color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByLayer)color=l.Name=="0"?rootLayer.Color:l.Color;else if(color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByBlock)color=root;colors.Add(color.ToString());}
  return J.Serialize(colors);
 }
 static void CheckColorOverrides(Database db,Transaction tr,IEnumerable<Entity> entities){
  var ids=new HashSet<ObjectId>();foreach(var e in entities){if(e.Color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByLayer)ids.Add(e.LayerId);var b=e as BlockReference;if(b==null)continue;var d=(BlockTableRecord)tr.GetObject(b.BlockTableRecord,OpenMode.ForRead);foreach(ObjectId id in d){var c=(Entity)tr.GetObject(id,OpenMode.ForRead);var l=(LayerTableRecord)tr.GetObject(c.LayerId,OpenMode.ForRead);if(l.IsPlottable&&l.Name!="Defpoints"&&c.Color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByLayer)ids.Add(l.Name=="0"?e.LayerId:c.LayerId);}}
  var ld=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);var conflicts=new List<string>();foreach(DBDictionaryEntry item in ld){var layout=(Layout)tr.GetObject(item.Value,OpenMode.ForRead);if(layout.ModelType)continue;var space=(BlockTableRecord)tr.GetObject(layout.BlockTableRecordId,OpenMode.ForRead);foreach(ObjectId id in space){var vp=tr.GetObject(id,OpenMode.ForRead) as Viewport;if(vp==null||vp.Number==1)continue;foreach(var lid in ids){var l=(LayerTableRecord)tr.GetObject(lid,OpenMode.ForRead);var o=l.GetViewportOverrides(vp.ObjectId);if(o.IsColorOverridden&&o.Color.ToString()!=l.Color.ToString())conflicts.Add(vp.Handle+":"+l.Name);}}}
  Need(conflicts.Count==0,"COLOR_VIEWPORT_OVERRIDE_NEEDS_PRESERVING:"+String.Join(",",conflicts.Take(20)));
 }
 public static string[] Apply(Database db,Job job,Action onMutation){
  Need(job.roles!=null&&job.roles.Length>0,"ROLES_REQUIRED");var all=job.roles.SelectMany(r=>r.targets).ToArray();Need(all.Length>0&&all.Select(t=>t.handle.ToUpperInvariant()).Distinct().Count()==all.Length,"DUPLICATE_ROLE_TARGET");
  using(var tr=db.TransactionManager.StartTransaction()){
   var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForRead);var model=SymbolUtilityServices.GetBlockModelSpaceId(db);
   var defs=new Dictionary<ObjectId,string>();var entities=new Dictionary<string,Entity>(StringComparer.OrdinalIgnoreCase);var transforms=new Dictionary<string,string>();
   foreach(var r in job.roles){Need(!String.IsNullOrWhiteSpace(r.layer)&&r.layer!="0"&&r.layer!="Defpoints"&&r.color>=1&&r.color<=255&&r.targets.Length>0,"ROLE_LAYER_REQUIRED");if(lt.Has(r.layer)){var l=(LayerTableRecord)tr.GetObject(lt[r.layer],OpenMode.ForRead);Need(!l.IsDependent&&!l.IsLocked,"ROLE_LAYER_UNAVAILABLE");}
    foreach(var t in r.targets){var e=(Entity)tr.GetObject(Id(db,t.handle),OpenMode.ForRead);Need(e.GetRXClass().Name==t.type&&e.Layer==t.layer&&e.OwnerId==model,"TARGET_IDENTITY:"+t.handle);var x=e.GeometricExtents;var bounds=new[]{x.MinPoint.X,x.MinPoint.Y,x.MaxPoint.X,x.MaxPoint.Y};Need(t.bounds!=null&&t.bounds.Length==4&&bounds.Zip(t.bounds,(actual,wanted)=>Math.Abs(actual-wanted)<=.001).All(z=>z),"TARGET_BOUNDS:"+t.handle);
     var b=e as BlockReference;if(b!=null){Need(!b.IsDynamicBlock&&b.AttributeCollection.Count==0,"DYNAMIC_OR_ATTRIBUTE_BLOCK_REQUIRES_SEPARATE_ADAPTER");var d=(BlockTableRecord)tr.GetObject(b.BlockTableRecord,OpenMode.ForRead);Need(!d.IsFromExternalReference&&!d.IsLayout&&d.Annotative!=AnnotativeStates.True,"UNSUPPORTED_SYMBOL_DEFINITION");foreach(ObjectId id in d)Need(!(tr.GetObject(id,OpenMode.ForRead) is BlockReference),"NESTED_SYMBOL_REQUIRES_SEPARATE_ADAPTER");if(!defs.ContainsKey(d.ObjectId))defs.Add(d.ObjectId,Definition(tr,d,true));transforms[t.handle]=J.Serialize(b.BlockTransform.ToArray());}
     else Need(e is Circle,"ROLE_INSTANCE_MUST_BE_BLOCK_OR_CIRCLE");entities.Add(t.handle,e);
    }
   }
   // No caller-supplied non-target list: the actual database determines all other users.
   var selected=new HashSet<ObjectId>(entities.Values.Select(e=>e.ObjectId));var untouched=defs.Keys.SelectMany(id=>((BlockTableRecord)tr.GetObject(id,OpenMode.ForRead)).GetBlockReferenceIds(true,true).Cast<ObjectId>()).Where(id=>!selected.Contains(id)&&!id.IsErased).Distinct().ToDictionary(id=>id,id=>((BlockReference)tr.GetObject(id,OpenMode.ForRead)).BlockTableRecord);
   CheckColorOverrides(db,tr,entities.Values);var colors=entities.ToDictionary(k=>k.Key,k=>ColorState(tr,k.Value));
   onMutation();lt.UpgradeOpen();bt.UpgradeOpen();
   foreach(var r in job.roles){if(!lt.Has(r.layer)){var l=new LayerTableRecord{Name=r.layer,Color=Autodesk.AutoCAD.Colors.Color.FromColorIndex(Autodesk.AutoCAD.Colors.ColorMethod.ByAci,r.color)};lt.Add(l);tr.AddNewlyCreatedDBObject(l,true);}
    var copies=new Dictionary<string,ObjectId>();foreach(var target in r.targets){var e=entities[target.handle];var originalLayer=(LayerTableRecord)tr.GetObject(e.LayerId,OpenMode.ForRead);var b=e as BlockReference;string copyKey=b==null?null:b.BlockTableRecord.Handle+"/"+e.LayerId.Handle;
     if(b!=null){ObjectId copyId;if(!copies.TryGetValue(copyKey,out copyId)){var old=(BlockTableRecord)tr.GetObject(b.BlockTableRecord,OpenMode.ForRead);var copy=new BlockTableRecord{Name="HLROLE_"+old.Handle+"_"+Guid.NewGuid().ToString("N").Substring(0,12),Origin=old.Origin,Units=old.Units,Explodable=old.Explodable,BlockScaling=old.BlockScaling,Comments=old.Comments};bt.Add(copy);tr.AddNewlyCreatedDBObject(copy,true);
       foreach(ObjectId id in old){var child=(Entity)tr.GetObject(id,OpenMode.ForRead);var clone=(Entity)child.Clone();copy.AppendEntity(clone);tr.AddNewlyCreatedDBObject(clone,true);var layer=(LayerTableRecord)tr.GetObject(child.LayerId,OpenMode.ForRead);if(layer.IsPlottable&&!layer.Name.Equals("Defpoints",StringComparison.OrdinalIgnoreCase)){if(clone.Color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByLayer)clone.Color=layer.Name=="0"?originalLayer.Color:layer.Color;clone.LayerId=lt["0"];}}
       Need(Definition(tr,old,false)==Definition(tr,copy,false),"CLONE_GEOMETRY_CHANGED");copyId=copy.ObjectId;copies.Add(copyKey,copyId);}
      b.UpgradeOpen();b.BlockTableRecord=copyId;Need(J.Serialize(b.BlockTransform.ToArray())==transforms[target.handle],"INSTANCE_TRANSFORM_CHANGED");
     }else e.UpgradeOpen();if(e.Color.ColorMethod==Autodesk.AutoCAD.Colors.ColorMethod.ByLayer)e.Color=originalLayer.Color;e.LayerId=lt[r.layer];Need(ColorState(tr,e)==colors[target.handle],"EFFECTIVE_COLOR_CHANGED:"+target.handle);
    }
   }
   foreach(var d in defs)Need(Definition(tr,(BlockTableRecord)tr.GetObject(d.Key,OpenMode.ForRead),true)==d.Value,"ORIGINAL_DEFINITION_CHANGED");foreach(var e in untouched)Need(((BlockReference)tr.GetObject(e.Key,OpenMode.ForRead)).BlockTableRecord==e.Value,"UNSELECTED_REFERENCE_CHANGED");
   tr.Commit();return defs.Keys.Select(id=>id.Handle.ToString()).ToArray();
  }
 }
 [CommandMethod("HLCADPLANTLAYERSPLITTESTV4",CommandFlags.Session)]public void Test(){
  var original=App.DocumentManager.MdiActiveDocument;var previous=HostApplicationServices.WorkingDatabase;var a=original.Editor.GetString(new PromptStringOptions("\nIsolated plant role job: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Job job=null;Document staging=null;
  try{job=J.Deserialize<Job>(File.ReadAllText(a.StringResult.Trim('"')));Need(NativeGeometryReadV1.Hash(job.input)==job.input_sha256&&!File.Exists(job.output)&&!File.Exists(job.receipt),"TEST_INPUT_OUTPUT");string copy=job.output+".staging.dwg";File.Copy(job.input,copy,false);staging=App.DocumentManager.Open(copy,false);App.DocumentManager.MdiActiveDocument=staging;HostApplicationServices.WorkingDatabase=staging.Database;string expected;string[] defs;
   using(staging.LockDocument()){defs=Apply(staging.Database,job,()=>{});expected=State(staging.Database,job,defs);staging.Database.SaveAs(job.output,DwgVersion.AC1032);}
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;staging.CloseAndDiscard();staging=null;
   string after;using(var db=new Database(false,true)){db.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;after=State(db,job,defs);HostApplicationServices.WorkingDatabase=previous;}
   if(!CadValueCompareV1.Json(after,expected))Write(job.output+".diff.json",new{expected=J.DeserializeObject(expected),actual=J.DeserializeObject(after)});Need(CadValueCompareV1.Json(after,expected),"ROLE_SPLIT_REOPEN_CHANGED");Write(job.receipt,new{status="ISOLATED_PLANT_LAYERS_VERIFIED",output=job.output,sha256=NativeGeometryReadV1.Hash(job.output),effective_colors_preserved=true,color_viewport_overrides_checked=true,native_save_reopen_verified=true,source_unchanged=NativeGeometryReadV1.Hash(job.input)==job.input_sha256});
  }catch(System.Exception ex){if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status="ISOLATED_PLANT_LAYERS_FAILED",error=ex.ToString()});}
  finally{App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;if(staging!=null)staging.CloseAndDiscard();}
 }
 [CommandMethod("HLCADPLANTLAYERSPLITV4",CommandFlags.Session)]public void Run(){
  var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nPlant layer job: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Type adapter=null;Job job=null;bool owned=false,started=false,committed=false;
  try{var m=J.Deserialize<Manifest>(File.ReadAllText(a.StringResult.Trim('"')));var p=System.Diagnostics.Process.GetCurrentProcess();Need(p.Id==m.host.pid&&p.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(p.MainModule.FileName,m.host.image),"HOST_IDENTITY");adapter=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);CadAdapterContractV1.Check(adapter);Need(Eq(adapter.Assembly.Location,m.loaded_dll)&&NativeGeometryReadV1.Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Get(adapter,"dir"),m.session_dir),"ADAPTER_IDENTITY");Need(!(bool)Get(adapter,"busy")&&!(bool)Get(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");Need(NativeGeometryReadV1.Hash(m.request)==m.request_sha256,"REQUEST_CHANGED");var req=J.Deserialize<Request>(File.ReadAllText(m.request));Need(req.kind=="plant_layers"&&NativeGeometryReadV1.Hash(req.job_path)==req.job_sha256,"JOB_IDENTITY");Call(adapter,"CheckPath",req.job_path);job=J.Deserialize<Job>(File.ReadAllText(req.job_path));Call(adapter,"CheckLive",job.input,job.input_sha256);Call(adapter,"CheckOutput",job.output,job.receipt);
   var doc=(Document)Get(adapter,"doc");Need(doc==App.DocumentManager.MdiActiveDocument,"ACTIVE_DOCUMENT_CHANGED");adapter.GetField("busy",F).SetValue(null,true);owned=true;
   using(doc.LockDocument()){var defs=Apply(doc.Database,job,()=>started=true);committed=true;doc.Editor.Regen();string expected=State(doc.Database,job,defs);doc.Database.SaveAs(job.output,DwgVersion.AC1032);var previous=HostApplicationServices.WorkingDatabase;try{using(var db=new Database(false,true)){db.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;Need(CadValueCompareV1.Json(State(db,job,defs),expected),"ROLE_SPLIT_REOPEN_CHANGED");HostApplicationServices.WorkingDatabase=previous;}}finally{HostApplicationServices.WorkingDatabase=previous;}
    string path=Path.GetFullPath(job.output),sha=NativeGeometryReadV1.Hash(path);((Dictionary<string,string>)Get(adapter,"approved"))[path]=sha;adapter.GetField("currentPath",F).SetValue(null,path);adapter.GetField("currentHash",F).SetValue(null,sha);Write(job.receipt,new{status="SAVED_STILL_OPEN",output=path,sha256=sha,pid=p.Id,changes=new{roles=job.roles.Select(r=>new{layer=r.layer,count=r.targets.Length}).ToArray(),original_definitions=defs,original_and_unselected_preserved=true,instance_transforms_preserved=true,nonplot_children_preserved=true,effective_colors_preserved=true,color_viewport_overrides_checked=true,native_save_reopen_verified=true}});Call(adapter,"State");}
  }catch(System.Exception ex){string emergency=null;if(started&&adapter!=null){adapter.GetField("blocked",F).SetValue(null,true);try{var d=(Document)Get(adapter,"doc");emergency=Path.Combine((string)Get(adapter,"dir"),"plant_split_emergency_"+Guid.NewGuid().ToString("N")+".dwg");using(d.LockDocument())d.Database.SaveAs(emergency,DwgVersion.AC1032);}catch{}}
   if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status=started?"BOUND_MODULE_FAILED":"REJECTED_BEFORE_WRITE",source_sha256=job.input_sha256,write_started=started,committed=committed,replayed=false,emergency=emergency,error=ex.ToString()});
  }finally{if(owned)adapter.GetField("busy",F).SetValue(null,false);}
 }
}
