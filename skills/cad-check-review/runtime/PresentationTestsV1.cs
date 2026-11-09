using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Reflection;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class PresentationTestsV1 {
 public class Config {public string folder,receipt,tch_source,tch_sha256,tch_handle,note_text,display_job;public bool note_only;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=20000000};
 static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}
 static string Paper(Database db){using(var t=db.TransactionManager.StartTransaction()){var d=(DBDictionary)t.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);foreach(DBDictionaryEntry r in d){var l=(Layout)t.GetObject(r.Value,OpenMode.ForRead);if(!l.ModelType)return l.LayoutName;}}throw new InvalidOperationException("NO_LAYOUT");}
 static void Trace(Config c,string stage){File.AppendAllText(Path.Combine(c.folder,"stages.txt"),stage+Environment.NewLine);}
 static object TestDisplay(Config c){
  var previous=HostApplicationServices.WorkingDatabase;string output=Path.Combine(c.folder,"display.dwg");var hashes=new List<string>();string[] handles;string snapshot;
  try{
   using(var db=new Database(true,true)){
    HostApplicationServices.WorkingDatabase=db;Trace(c,"fresh database");
    BoundCadEditsV6.Target[] targets;
    using(var tr=db.TransactionManager.StartTransaction()){
     var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);
     var p=new Polyline{Elevation=7,Closed=true,Thickness=.4,ColorIndex=2,LinetypeScale=2};p.AddVertexAt(0,new Point2d(1,2),.25,.4,.9);p.AddVertexAt(1,new Point2d(5,8),-.1,.5,.6);p.AddVertexAt(2,new Point2d(4,2),0,.2,.2);
     var a=new Arc(new Point3d(30,20,6),new Vector3d(0,1,1).GetNormal(),5,.3,4.2){ColorIndex=1,Thickness=.25,LinetypeScale=3};
     var line=new Line(new Point3d(1,2,3),new Point3d(4,5,7)){ColorIndex=4,Thickness=.3};
     var hatch=new Hatch{ColorIndex=5,Elevation=3};
     var keep=new Arc(new Point3d(60,40,2),4,.1,2.3){ColorIndex=6};
     foreach(var e in new Entity[]{p,a,line,hatch,keep}){Trace(c,"append "+e.GetType().Name);ms.AppendEntity(e);tr.AddNewlyCreatedDBObject(e,true);if(e==hatch){hatch.SetHatchPattern(HatchPatternType.PreDefined,"ANSI31");hatch.PatternScale=.4;hatch.PatternAngle=.2;hatch.AppendLoop(HatchLoopTypes.External,new Point2dCollection(new[]{new Point2d(0,0),new Point2d(20,0),new Point2d(20,20),new Point2d(0,20)}),new DoubleCollection(new[]{.1,0.0,0.0,0.0}));hatch.AppendLoop(HatchLoopTypes.Default,new Point2dCollection(new[]{new Point2d(5,5),new Point2d(7,5),new Point2d(7,7),new Point2d(5,7)}),new DoubleCollection(new[]{0.0,0.0,0.0,0.0}));Trace(c,"hatch evaluate");hatch.EvaluateHatch(true);}Trace(c,"geometry "+e.GetType().Name);hashes.Add(EntityDisplayOpsV1.Geometry(e));}
     targets=new[]{BoundCadEditsV6.Identity(p),BoundCadEditsV6.Identity(a),BoundCadEditsV6.Identity(line),BoundCadEditsV6.Identity(hatch)};handles=new[]{p.Handle.ToString(),a.Handle.ToString(),line.Handle.ToString(),hatch.Handle.ToString(),keep.Handle.ToString()};tr.Commit();
    }
    var job=new BoundCadEditsV6.Job{entities=new[]{new BoundCadEditsV6.DisplayEdit{target=targets[0],before_color=2,target_layer="BASE_DISPLAY",color=253},new BoundCadEditsV6.DisplayEdit{target=targets[1],before_color=1,target_layer="BASE_DISPLAY",color=253},new BoundCadEditsV6.DisplayEdit{target=targets[2],before_color=4,target_layer="BASE_DISPLAY",color=253},new BoundCadEditsV6.DisplayEdit{target=targets[3],before_color=5,target_layer="BASE_DISPLAY",color=253}},new_layers=new[]{new BoundCadEditsV6.NewLayer{name="BASE_DISPLAY",color=8}}};
    Trace(c,"apply display");EntityDisplayOpsV1.Apply(db,job);bool stale=false;try{EntityDisplayOpsV1.Apply(db,job);}catch(InvalidOperationException){stale=true;}Need(stale,"STALE_IDENTITY_ACCEPTED");
    BoundCadEditsV6.ApplyLayers(db,new BoundCadEditsV6.Job{layers=new[]{new BoundCadEditsV6.LayerEdit{name="BASE_DISPLAY",before=new BoundCadEditsV6.Flags{on=true,frozen=false,color=8},after=new BoundCadEditsV6.Flags{on=true,frozen=false,color=253}}}});
    Trace(c,"save fixture");snapshot=PresentationVerifyV1.Snapshot(db,job,"entity_display");Trace(c,"snapshot done");db.SaveAs(output,DwgVersion.AC1032);Trace(c,"save done");HostApplicationServices.WorkingDatabase=previous;
   }
   Trace(c,"fixture disposed; reopening");using(var db=new Database(false,true)){HostApplicationServices.WorkingDatabase=db;db.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;
    using(var tr=db.TransactionManager.StartTransaction()){
     for(int i=0;i<handles.Length;i++){var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(handles[i],16)),0),OpenMode.ForRead);Need(EntityDisplayOpsV1.Geometry(e)==hashes[i],"GEOMETRY_NOT_PRESERVED");Need(e.Layer==(i==4?"0":"BASE_DISPLAY")&&e.ColorIndex==(i==4?6:253),"DISPLAY_OR_UNSELECTED_CHANGED");if(i<2)Need(e.LinetypeScale==(i==0?2:3),"LINETYPE_SCALE_CHANGED");}
     var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);var zero=(LayerTableRecord)tr.GetObject(lt["0"],OpenMode.ForRead);var gray=(LayerTableRecord)tr.GetObject(lt["BASE_DISPLAY"],OpenMode.ForRead);Need(zero.Color.ColorIndex==7&&gray.Color.ColorIndex==253&&!gray.IsFrozen&&!gray.IsOff,"LAYER_COLOR_OR_FLAGS_CHANGED");
    }
    HostApplicationServices.WorkingDatabase=previous;
   }
   return new{status="NATIVE_DISPLAY_SAVE_REOPEN_VERIFIED",output=output,sha256=BoundCadEditsV6.Hash(output),exact_arc_and_bulge_width_z_preserved=true,line_xyz_and_hatch_loops_pattern_islands_preserved=true,unselected_and_zero_layer_preserved=true,stale_precondition_rejected=true};
  }finally{HostApplicationServices.WorkingDatabase=previous;}
 }
 static object TestNote(Config c){
  if(String.IsNullOrEmpty(c.tch_source))return new{status="NOT_REQUESTED"};
  Need(BoundCadEditsV6.Hash(c.tch_source)==c.tch_sha256,"SOURCE_CHANGED");var original=App.DocumentManager.MdiActiveDocument;var previous=HostApplicationServices.WorkingDatabase;Autodesk.AutoCAD.ApplicationServices.Document staging=null;string output=Path.Combine(c.folder,"note.dwg"),before,after;
  try{
   string working=Path.Combine(c.folder,"note_working.dwg");File.Copy(c.tch_source,working,false);staging=App.DocumentManager.Open(working,false);App.DocumentManager.MdiActiveDocument=staging;HostApplicationServices.WorkingDatabase=staging.Database;
   using(staging.LockDocument()){
    var db=staging.Database;using(var tr=db.TransactionManager.StartTransaction()){
     var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(c.tch_handle,16)),0),OpenMode.ForWrite);Need(e.GetRXClass().Name=="TDbText","SOURCE_NOT_NATIVE_TEXT");before=J.Serialize(BoundCadEditsV6.TextParts(e));BoundViewportOpsV5.SetNativeText(e,c.note_text);e.RecordGraphicsModified(true);tr.Commit();
    }
    staging.Editor.Regen();App.UpdateScreen();
    using(var tr=db.TransactionManager.StartTransaction()){
     var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(c.tch_handle,16)),0),OpenMode.ForRead);var parts=BoundCadEditsV6.TextParts(e);after=J.Serialize(parts);var text=String.Concat(parts.Select(x=>Convert.ToString(x.GetType().GetProperty("text").GetValue(x,null))));File.WriteAllText(Path.Combine(c.folder,"note-comparison.json"),J.Serialize(new{before=before,after=after,joined=text,expected=c.note_text}),new System.Text.UTF8Encoding(false));Need(text==c.note_text,"NATIVE_TEXT_VISUAL_PARTS_NOT_UPDATED");
    }db.SaveAs(output,DwgVersion.AC1032);
   }
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;staging.CloseAndDiscard();staging=null;
   Trace(c,"fixture disposed; reopening");using(var db=new Database(false,true)){HostApplicationServices.WorkingDatabase=db;db.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;using(var tr=db.TransactionManager.StartTransaction()){var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(c.tch_handle,16)),0),OpenMode.ForRead);Need(e.GetRXClass().Name=="TDbText"&&J.Serialize(BoundCadEditsV6.TextParts(e))==after,"NATIVE_NOTE_REOPEN_CHANGED");}}
   Need(BoundCadEditsV6.Hash(c.tch_source)==c.tch_sha256,"SOURCE_MUTATED");return new{status="NATIVE_TDBTEXT_REWRITE_SAVE_REOPEN_VERIFIED",output=output,sha256=BoundCadEditsV6.Hash(output),native_handle=c.tch_handle,before=before,after=after,source_unchanged=true};
  }finally{App.DocumentManager.MdiActiveDocument=original;if(staging!=null)staging.CloseAndDiscard();HostApplicationServices.WorkingDatabase=previous;}
 }
 static object TestBlockJob(Config c){
  if(String.IsNullOrEmpty(c.display_job))return new{status="NOT_REQUESTED"};
  var job=J.Deserialize<BoundCadEditsV6.Job>(File.ReadAllText(c.display_job));Need(BoundCadEditsV6.Hash(job.input)==job.input_sha256&&!File.Exists(job.output),"TEST_INPUT_OR_OUTPUT_CHANGED");
  var previous=HostApplicationServices.WorkingDatabase;string expected;object changes;var rejected=new List<string>();
  try{
   using(var db=new Database(false,true)){
    db.ReadDwgFile(job.input,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;
    var before=PresentationVerifyV1.Snapshot(db,job,"entity_display");
    foreach(var kind in new[]{"wrong_owner","missing_reference","stale_color"}){
     var bad=J.Deserialize<BoundCadEditsV6.Job>(J.Serialize(job));
     if(kind=="wrong_owner")bad.entities[0].definition=bad.definitions[1].handle;
     else if(kind=="missing_reference")bad.definitions[0].instances=bad.definitions[0].instances.Skip(1).ToArray();
     else bad.entities[0].before_color=42;
     bool stopped=false;try{EntityDisplayOpsV1.Apply(db,bad);}catch(InvalidOperationException){stopped=true;}
     Need(stopped&&PresentationVerifyV1.Snapshot(db,job,"entity_display")==before,"INVALID_JOB_MUTATED:"+kind);rejected.Add(kind);
    }
    changes=EntityDisplayOpsV1.Apply(db,job);expected=PresentationVerifyV1.Snapshot(db,job,"entity_display");db.SaveAs(job.output,DwgVersion.AC1032);
   }
   using(var db=new Database(false,true)){db.ReadDwgFile(job.output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;Need(PresentationVerifyV1.Snapshot(db,job,"entity_display")==expected,"BLOCK_DISPLAY_REOPEN_CHANGED");}
   Need(BoundCadEditsV6.Hash(job.input)==job.input_sha256,"BLOCK_DISPLAY_SOURCE_CHANGED");
   return new{status="BLOCK_CHILD_DISPLAY_SAVE_REOPEN_VERIFIED",source_unchanged=true,output=job.output,sha256=BoundCadEditsV6.Hash(job.output),changes=changes,rejected_before_mutation=rejected,save_reopen_verified=true};
  }finally{HostApplicationServices.WorkingDatabase=previous;}
 }
 [CommandMethod("HLCADPRESENTATIONTESTV2",CommandFlags.Session)]public void Run(){
  var doc=App.DocumentManager.MdiActiveDocument;var a=doc.Editor.GetString(new PromptStringOptions("\nIsolated presentation test: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Config c=null;Type adapter=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).FirstOrDefault(x=>x!=null);var flags=BindingFlags.NonPublic|BindingFlags.Static;bool owned=false;var name=doc.Name;var dirty=App.GetSystemVariable("DBMOD");
  try{c=J.Deserialize<Config>(File.ReadAllText(a.StringResult.Trim('"')));Need(!File.Exists(c.receipt)&&!Directory.Exists(c.folder),"TEST_OUTPUT_EXISTS");if(adapter!=null){Need(!(bool)adapter.GetField("busy",flags).GetValue(null)&&!(bool)adapter.GetField("blocked",flags).GetValue(null),"HOST_BUSY");adapter.GetField("busy",flags).SetValue(null,true);owned=true;}Directory.CreateDirectory(c.folder);
    var display=c.note_only?(object)new{status="INDEPENDENT_CORE_EVIDENCE"}:TestDisplay(c);var note=TestNote(c);var block=TestBlockJob(c);var afterDirty=App.GetSystemVariable("DBMOD");
    File.WriteAllText(Path.Combine(c.folder,"validation_results.json"),J.Serialize(new{display=display,note=note,block_display=block,live_before=name,live_after=doc.Name,dbmod_before=dirty,dbmod_after=afterDirty}),new System.Text.UTF8Encoding(false));
    Need(doc.Name==name&&Equals(dirty,afterDirty),"LIVE_CHANGED");File.WriteAllText(c.receipt,J.Serialize(new{status="PRESENTATION_NATIVE_TESTS_PASSED",display=display,note=note,block_display=block,live_document_unchanged=true}),new System.Text.UTF8Encoding(false));
  }catch(System.Exception e){if(c!=null&&!File.Exists(c.receipt))File.WriteAllText(c.receipt,J.Serialize(new{status="PRESENTATION_NATIVE_TESTS_FAILED",error=e.ToString()}),new System.Text.UTF8Encoding(false));}
  finally{if(owned)adapter.GetField("busy",flags).SetValue(null,false);}
 }
}
