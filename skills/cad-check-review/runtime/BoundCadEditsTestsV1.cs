using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;

public class BoundCadEditsTestsV1 {
 public class Config {public string folder,receipt,tch_source,tch_sha256;public string[] tch_handles;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=10000000};
 static void Assert(bool yes,string msg){if(!yes)throw new InvalidOperationException(msg);}
 static string Paper(Database db){using(var tr=db.TransactionManager.StartTransaction()){
  var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
  foreach(DBDictionaryEntry item in dict){var l=(Layout)tr.GetObject(item.Value,OpenMode.ForRead);if(l.LayoutName!="Model")return l.LayoutName;}
 }throw new InvalidOperationException("NO_FIXTURE_LAYOUT");}
 static BoundCadEditsV1.Target[] Fixture(Database db,bool source){
  using(var tr=db.TransactionManager.StartTransaction()){
   var layers=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForWrite);
   var row=new LayerTableRecord{Name="KEEP_GRAY",Color=Autodesk.AutoCAD.Colors.Color.FromColorIndex(Autodesk.AutoCAD.Colors.ColorMethod.ByAci,8)};
   layers.Add(row);tr.AddNewlyCreatedDBObject(row,true);
   var grid=new LayerTableRecord{Name="GRID",IsFrozen=true};layers.Add(grid);tr.AddNewlyCreatedDBObject(grid,true);
   var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForWrite);
   var definition=new BlockTableRecord{Name="TEST_FRAME"};bt.Add(definition);tr.AddNewlyCreatedDBObject(definition,true);
   var edge=new Polyline();edge.AddVertexAt(0,new Point2d(0,0),0,0,0);edge.AddVertexAt(1,new Point2d(100,0),0,0,0);edge.AddVertexAt(2,new Point2d(100,100),0,0,0);edge.AddVertexAt(3,new Point2d(0,100),0,0,0);edge.Closed=true;
   definition.AppendEntity(edge);tr.AddNewlyCreatedDBObject(edge,true);
   var paper=(BlockTableRecord)tr.GetObject(BoundCadEditsV1.Space(tr,db,Paper(db)),OpenMode.ForWrite);
   var frame=new BlockReference(new Point3d(source?0:200,source?0:100,0),definition.ObjectId);paper.AppendEntity(frame);tr.AddNewlyCreatedDBObject(frame,true);
   var text=new DBText{TextString=source?"Grid 2m x 2m":"Keep other note",Position=new Point3d(source?5:210,source?8:180,0),Height=2,WidthFactor=.75};paper.AppendEntity(text);tr.AddNewlyCreatedDBObject(text,true);
   var model=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);
   var pl=new Polyline{Layer="KEEP_GRAY",ColorIndex=253,LinetypeScale=2};
   pl.AddVertexAt(0,new Point2d(source?10:1,source?10:1),source?.25:0,source?.3:0,source?.6:0);
   pl.AddVertexAt(1,new Point2d(source?25:4,source?12:1),source?-.1:0,source?.4:0,source?.7:0);
   if(source)pl.AddVertexAt(2,new Point2d(30,20),0,.2,.5);
   pl.Closed=source;pl.Elevation=source?7:0;pl.Thickness=source?.25:0;pl.Plinegen=source;
   model.AppendEntity(pl);tr.AddNewlyCreatedDBObject(pl,true);
   var result=new[]{BoundCadEditsV1.Identity(frame),BoundCadEditsV1.Identity(text),BoundCadEditsV1.Identity(pl)};
   tr.Commit();return result;
  }
 }
 static Polyline Poly(Transaction tr,Database db,string h){return (Polyline)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0),OpenMode.ForRead);}
 static void Verify(Database db,string handle){
  using(var tr=db.TransactionManager.StartTransaction()){
   var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);var l=(LayerTableRecord)tr.GetObject(lt["GRID"],OpenMode.ForRead);
   Assert(!l.IsFrozen&&!l.IsOff,"LAYER_FLAGS_NOT_SAVED");
   var p=Poly(tr,db,handle);Assert(p.NumberOfVertices==3&&p.Closed&&p.Elevation==7&&Math.Abs(p.Thickness-.25)<1e-9&&p.Plinegen,"GEOMETRY_FLAGS_NOT_SAVED");
   Assert(p.Layer=="KEEP_GRAY"&&p.ColorIndex==253&&p.LinetypeScale==2,"TARGET_DISPLAY_PROPERTIES_CHANGED");
   Assert(p.GetPoint2dAt(0).IsEqualTo(new Point2d(10,10))&&Math.Abs(p.GetBulgeAt(0)-.25)<1e-9&&Math.Abs(p.GetStartWidthAt(0)-.3)<1e-9&&Math.Abs(p.GetEndWidthAt(1)-.7)<1e-9,"GEOMETRY_DATA_NOT_SAVED");
   var paper=(BlockTableRecord)tr.GetObject(BoundCadEditsV1.Space(tr,db,Paper(db)),OpenMode.ForRead);
   var texts=paper.Cast<ObjectId>().Select(id=>tr.GetObject(id,OpenMode.ForRead)).OfType<DBText>().ToArray();
   var note=texts.Single(t=>t.TextString=="Grid 2m x 2m");
   Assert(note.Position.IsEqualTo(new Point3d(205,108,0))&&note.Height==2&&note.WidthFactor==.75,"PAPER_NOTE_FORMAT_OR_PLACEMENT_CHANGED");
   Assert(texts.Any(t=>t.TextString=="Keep other note"),"EXISTING_NOTE_LOST");
  }
 }
 static object TestTianzheng(Config c){
  if(String.IsNullOrEmpty(c.tch_source))return new{status="NOT_REQUESTED"};
  Assert(BoundCadEditsV1.Hash(c.tch_source)==c.tch_sha256,"TCH_SOURCE_HASH_CHANGED");
  var output=Path.Combine(c.folder,"tianzheng_clone.dwg");Assert(!File.Exists(output),"TCH_TEST_OUTPUT_EXISTS");
  var before=new List<string>();var cloned=new List<string>();
  using(var source=new Database(false,true))using(var dest=new Database(true,true)){
   source.ReadDwgFile(c.tch_source,FileOpenMode.OpenForReadAndAllShare,true,null);source.CloseInput(true);
   var ids=new ObjectIdCollection();
   using(var sr=source.TransactionManager.StartTransaction())foreach(var h in c.tch_handles){
    var id=source.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0);var e=(Entity)sr.GetObject(id,OpenMode.ForRead);
    Assert(e.GetRXClass().Name=="TDbText","TCH_SOURCE_PROXY_OR_WRONG_TYPE");ids.Add(id);before.Add(J.Serialize(BoundCadEditsV1.TextParts(e)));
   }
   using(var tr=dest.TransactionManager.StartTransaction()){
    var owner=BoundCadEditsV1.Space(tr,dest,Paper(dest));var map=new IdMapping();source.WblockCloneObjects(ids,owner,map,DuplicateRecordCloning.MangleName,false);
    foreach(ObjectId id in ids){var e=(Entity)tr.GetObject(map[id].Value,OpenMode.ForRead);Assert(e.GetRXClass().Name=="TDbText","TCH_CLONE_NOT_NATIVE");cloned.Add(e.Handle.ToString());}
    tr.Commit();
   }
   dest.SaveAs(output,DwgVersion.AC1032);
  }
  var after=new List<string>();
  using(var db=new Database(false,true)){
   db.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);
   using(var tr=db.TransactionManager.StartTransaction())foreach(var h in cloned){var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0),OpenMode.ForRead);Assert(e.GetRXClass().Name=="TDbText","TCH_REOPEN_PROXY");after.Add(J.Serialize(BoundCadEditsV1.TextParts(e)));}
  }
  Assert(before.SequenceEqual(after)&&before.All(x=>x!="[]"),"TCH_CONTENT_CHANGED_OR_UNREADABLE");
  Assert(BoundCadEditsV1.Hash(c.tch_source)==c.tch_sha256,"TCH_SOURCE_MUTATED");
  return new{status="NATIVE_TDBTEXT_CLONE_SAVE_REOPEN_VERIFIED",count=cloned.Count,output=output,source_unchanged=true};
 }
 [CommandMethod("HLCADBOUNDTESTV1",CommandFlags.Session)]public void Run(){
  var doc=App.DocumentManager.MdiActiveDocument;var opt=new PromptStringOptions("\nIsolated module test manifest: "){AllowSpaces=true};var answer=doc.Editor.GetString(opt);if(answer.Status!=PromptStatus.OK)return;
  Config c=null;var working=HostApplicationServices.WorkingDatabase;var name=doc.Name;object dbmod=App.GetSystemVariable("DBMOD"),tab=App.GetSystemVariable("CTAB");
  try{
   c=J.Deserialize<Config>(File.ReadAllText(answer.StringResult.Trim('"')));Assert(!File.Exists(c.receipt),"TEST_RECEIPT_EXISTS");Directory.CreateDirectory(c.folder);
   string sourceFile=Path.Combine(c.folder,"source_fixture.dwg"),output=Path.Combine(c.folder,"result_fixture.dwg");
   Assert(!File.Exists(sourceFile)&&!File.Exists(output),"TEST_OUTPUT_EXISTS");
   BoundCadEditsV1.Target[] s,t;
   using(var source=new Database(true,true))using(var dest=new Database(true,true)){
    HostApplicationServices.WorkingDatabase=source;s=Fixture(source,true);source.SaveAs(sourceFile,DwgVersion.AC1032);
    HostApplicationServices.WorkingDatabase=dest;t=Fixture(dest,false);
    var changes=new[]{new BoundCadEditsV1.LayerEdit{name="GRID",before=new BoundCadEditsV1.Flags{on=true,frozen=true},after=new BoundCadEditsV1.Flags{on=true,frozen=false}}};
    BoundCadEditsV1.ApplyLayers(dest,new BoundCadEditsV1.Job{layers=changes});
    bool failed=false;try{BoundCadEditsV1.ApplyLayers(dest,new BoundCadEditsV1.Job{layers=changes});}catch(InvalidOperationException){failed=true;}Assert(failed,"STALE_LAYER_PRECONDITION_NOT_REJECTED");
    BoundCadEditsV1.ApplyPolylineGeometry(source,dest,new BoundCadEditsV1.Job{pairs=new[]{new BoundCadEditsV1.Pair{source=s[2],target=t[2]}}});
    BoundCadEditsV1.ApplyPaperCopies(source,dest,new BoundCadEditsV1.Job{source_layout=Paper(source),target_layout=Paper(dest),source_frame=s[0],source_targets=new[]{s[1]},target_frames=new[]{t[0]}});
    Verify(dest,t[2].handle);dest.SaveAs(output,DwgVersion.AC1032);
   }
   using(var reopened=new Database(false,true)){reopened.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);reopened.CloseInput(true);HostApplicationServices.WorkingDatabase=reopened;Verify(reopened,t[2].handle);}
   HostApplicationServices.WorkingDatabase=working;var tch=TestTianzheng(c);
   Assert(doc.Name==name&&Equals(App.GetSystemVariable("DBMOD"),dbmod)&&Equals(App.GetSystemVariable("CTAB"),tab),"LIVE_DOCUMENT_CHANGED_BY_TEST");
   File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_NATIVE_SAVE_REOPEN_VERIFIED",fixture_output=output,sha256=BoundCadEditsV1.Hash(output),layer_before_state_checked=true,target_handle_layer_color_linetype_scale_preserved=true,vertices_bulges_widths_elevation_thickness_closed_verified=true,paper_note_format_placement_verified=true,tianzheng=tch,live_document_unchanged=true}),new System.Text.UTF8Encoding(false));
  }catch(System.Exception ex){if(c!=null&&!File.Exists(c.receipt))File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_TEST_FAILED",error=ex.ToString()}),new System.Text.UTF8Encoding(false));doc.Editor.WriteMessage(ex.ToString());}
  finally{HostApplicationServices.WorkingDatabase=working;}
 }
}
