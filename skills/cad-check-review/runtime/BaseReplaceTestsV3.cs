using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class BaseReplaceTestsV3 {
 public class Config {public string folder,receipt;}
 static void Need(bool x,string s){BaseReplaceV3.Need(x,s);}
 static string SaveTerrain(string path,double height){using(var db=new Database(true,true)){
  using(var tr=db.TransactionManager.StartTransaction()){var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);var l=new Line(new Point3d(0,0,height),new Point3d(10,10,height));ms.AppendEntity(l);tr.AddNewlyCreatedDBObject(l,true);tr.Commit();}db.SaveAs(path,DwgVersion.AC1032);}return path;}
 static BaseReplaceV3.Target[] Fixture(Database db,bool source,string terrain){
  var result=new List<BaseReplaceV3.Target>();
  using(var tr=db.TransactionManager.StartTransaction()){
   var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForWrite);var layer=new LayerTableRecord{Name="SAME_LAYER",Color=Autodesk.AutoCAD.Colors.Color.FromColorIndex(Autodesk.AutoCAD.Colors.ColorMethod.ByAci,source?(short)2:(short)3)};lt.Add(layer);tr.AddNewlyCreatedDBObject(layer,true);
   var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForWrite);var shared=new BlockTableRecord{Name="SAME_BLOCK"};bt.Add(shared);tr.AddNewlyCreatedDBObject(shared,true);var circle=new Circle(Point3d.Origin,Vector3d.ZAxis,source?9:1);shared.AppendEntity(circle);tr.AddNewlyCreatedDBObject(circle,true);
   var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);var plant=new BlockReference(new Point3d(source?50:5,5,7),shared.ObjectId){LayerId=layer.ObjectId};ms.AppendEntity(plant);tr.AddNewlyCreatedDBObject(plant,true);result.Add(BaseReplaceV3.Identity(plant));
   var old=new BlockTableRecord{Name="OLD_ONLY"};bt.Add(old);tr.AddNewlyCreatedDBObject(old,true);var edge=new Line(Point3d.Origin,new Point3d(3,0,0));old.AppendEntity(edge);tr.AddNewlyCreatedDBObject(edge,true);
   var oldLayer=new LayerTableRecord{Name="UNREFERENCED_AFTER_DELETE"};lt.Add(oldLayer);tr.AddNewlyCreatedDBObject(oldLayer,true);
   var oldRef=new BlockReference(new Point3d(20,10,3),old.ObjectId){LayerId=oldLayer.ObjectId};ms.AppendEntity(oldRef);tr.AddNewlyCreatedDBObject(oldRef,true);result.Add(BaseReplaceV3.Identity(oldRef));
   var layouts=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);
   foreach(DBDictionaryEntry entry in layouts){var lay=(Layout)tr.GetObject(entry.Value,OpenMode.ForRead);if(lay.ModelType)continue;lay.UpgradeOpen();lay.Initialize();
    var ps=(BlockTableRecord)tr.GetObject(lay.BlockTableRecordId,OpenMode.ForWrite);var vp=new Viewport{CenterPoint=new Point3d(50,50,0),Width=30,Height=20,ViewTarget=new Point3d(7,8,0),ViewDirection=Vector3d.ZAxis,ViewHeight=100};ps.AppendEntity(vp);tr.AddNewlyCreatedDBObject(vp,true);vp.FreezeLayersInViewport(new ObjectIdCollection(new[]{oldLayer.ObjectId}).GetEnumerator());
   }
   var gd=(DBDictionary)tr.GetObject(db.GroupDictionaryId,OpenMode.ForWrite);var group=new Group("rock group",true);gd.SetAt("SOURCE_ROCK",group);tr.AddNewlyCreatedDBObject(group,true);group.Append(new ObjectIdCollection(new[]{plant.ObjectId,oldRef.ObjectId}));
   tr.Commit();
  }
  var xref=db.AttachXref(terrain,"SAME_TERRAIN");using(var tr=db.TransactionManager.StartTransaction()){
   var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);var br=new BlockReference(Point3d.Origin,xref);ms.AppendEntity(br);tr.AddNewlyCreatedDBObject(br,true);result.Add(BaseReplaceV3.Identity(br));tr.Commit();
  }
  return result.ToArray();
 }
 [CommandMethod("HLCADBASEREPLACETESTV6",CommandFlags.Session)]public void Run(){
  var doc=App.DocumentManager.MdiActiveDocument;var ans=doc.Editor.GetString(new PromptStringOptions("\nBase test config: "){AllowSpaces=true});if(ans.Status!=PromptStatus.OK)return;
  var j=new JavaScriptSerializer{MaxJsonLength=100000000};Config c=null;var previous=HostApplicationServices.WorkingDatabase;string originalName=doc.Name;
  try{
   c=j.Deserialize<Config>(File.ReadAllText(ans.StringResult.Trim('"')));CadAdapterContractV1.CheckBaseReplace(AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null));Directory.CreateDirectory(c.folder);Need(!File.Exists(c.receipt),"TEST_EXISTS");
   string src=Path.Combine(c.folder,"source.dwg"),dest=Path.Combine(c.folder,"old.dwg"),output=Path.Combine(c.folder,"replacement.dwg");
   var newTerrain=SaveTerrain(Path.Combine(c.folder,"new_terrain.dwg"),42);var oldTerrain=SaveTerrain(Path.Combine(c.folder,"old_terrain.dwg"),2);
   BaseReplaceV3.Target[] s,t;
   using(var a=new Database(true,true)){try{HostApplicationServices.WorkingDatabase=a;s=Fixture(a,true,newTerrain);HostApplicationServices.WorkingDatabase=previous;a.SaveAs(src,DwgVersion.AC1032);}finally{HostApplicationServices.WorkingDatabase=previous;}}
   using(var b=new Database(true,true)){try{HostApplicationServices.WorkingDatabase=b;t=Fixture(b,false,oldTerrain);HostApplicationServices.WorkingDatabase=previous;b.SaveAs(dest,DwgVersion.AC1032);}finally{HostApplicationServices.WorkingDatabase=previous;}}
   var job=new BaseReplaceV3.Job{input=dest,input_sha256=BaseReplaceV3.Hash(dest),source=src,source_sha256=BaseReplaceV3.Hash(src),output=output,source_targets=s,protected_targets=new[]{t[0]},old_targets=new[]{t[1],t[2]},deferred_targets=new BaseReplaceV3.Target[0]};
   BaseReplaceV3.Write(Path.Combine(c.folder,"replacement.params.json"),new{source=job.source,source_targets=job.source_targets,old_targets=job.old_targets,protected_targets=job.protected_targets,deferred_targets=job.deferred_targets});
   // A missing classification must leave originals untouched and create no output.
   job.old_targets=new[]{t[1]};bool rejected=false;try{BaseReplaceV3.Build(job);}catch(InvalidOperationException e){rejected=e.Message.StartsWith("MODEL_CLASSIFICATION_INCOMPLETE");}
   Need(rejected&&!File.Exists(output)&&BaseReplaceV3.Hash(dest)==job.input_sha256,"INCOMPLETE_PLAN_NOT_ROLLED_BACK");job.old_targets=new[]{t[1],t[2]};
   var result=BaseReplaceV3.Build(job);Need(result.reopen_verified&&result.coverage_complete&&result.protected_verified,"BASE_VERIFY_FAILED");
   Need(result.purged.Count>0&&result.entity_map.Count==3&&result.groups.Count==1&&result.xrefs.Count==1,"PURGE_MAP_GROUP_XREF_EVIDENCE");
   using(var db=new Database(false,true)){
    db.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);using(var tr=db.TransactionManager.StartTransaction()){
     var keep=(BlockReference)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(t[0].handle,16)),0),OpenMode.ForRead);
     var imported=(BlockReference)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(result.entity_map.Single(x=>x.source_handle==s[0].handle).target_handle,16)),0),OpenMode.ForRead);
     var a=(BlockTableRecord)tr.GetObject(keep.BlockTableRecord,OpenMode.ForRead);var b=(BlockTableRecord)tr.GetObject(imported.BlockTableRecord,OpenMode.ForRead);
     Need(a.Name=="SAME_BLOCK"&&a.ObjectId!=b.ObjectId,"SAME_NAME_OLD_DEFINITION_REUSED");
     Need(((Circle)tr.GetObject(a.Cast<ObjectId>().Single(),OpenMode.ForRead)).Radius==1&&((Circle)tr.GetObject(b.Cast<ObjectId>().Single(),OpenMode.ForRead)).Radius==9,"BLOCK_CONTENTS_NOT_PRESERVED");
     Need(((LayerTableRecord)tr.GetObject(keep.LayerId,OpenMode.ForRead)).Color.ColorIndex==3&&((LayerTableRecord)tr.GetObject(imported.LayerId,OpenMode.ForRead)).Color.ColorIndex==2,"LAYER_STYLE_REUSED");
    }
   }
   Need(doc.Name==originalName,"LIVE_DOCUMENT_CHANGED");BaseReplaceV3.Write(c.receipt,new{status="ISOLATED_NATIVE_SAVE_REOPEN_VERIFIED",output=output,sha256=BaseReplaceV3.Hash(output),changes=result,tests=new[]{"incomplete classification rejected without output","old erased before native purge","same-name plant block and layer retained","new source definitions independent","all source to target mappings","rock group rebuilt","old terrain replaced and new xref resolved","saved and independently reopened","live document unchanged","purged old frozen layer records reported; paper camera and frame preserved"}});
  }catch(System.Exception e){if(c!=null&&!File.Exists(c.receipt))BaseReplaceV3.Write(c.receipt,new{status="TEST_FAILED",error=e.ToString()});}
  finally{HostApplicationServices.WorkingDatabase=previous;}
 }
}
