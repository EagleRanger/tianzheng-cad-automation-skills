using System;using System.IO;using System.Linq;using System.Reflection;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Application;
public class NativePaperTransferTestsV1 {
 public class Config{public string source,source_sha256,output,receipt;}
 static JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=50000000};
 static void Need(bool b,string s){if(!b)throw new InvalidOperationException(s);}
 static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 static double Prop(Entity e,string n){var o=e.AcadObject;return Convert.ToDouble(o.GetType().InvokeMember(n,BindingFlags.GetProperty,null,o,null));}
 static NativePaperPatchV1.Edit Edit(Entity e,string layout,string target,string action){return new NativePaperPatchV1.Edit{handle=e.Handle.ToString(),type=e.GetRXClass().Name,layer=e.Layer,layout=layout,target_layout=target,action=action,offset=new[]{1700.0,-800.0}};}
 static void Add(Transaction tr,BlockTableRecord b,Entity e){b.AppendEntity(e);tr.AddNewlyCreatedDBObject(e,true);}
 [CommandMethod("HLCADPAPERTRANSFERTESTV2",CommandFlags.Session)]public void Run(){
  var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("Test config:"){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;
  var c=J.Deserialize<Config>(File.ReadAllText(a.StringResult.Trim('"')));var prior=App.DocumentManager.MdiActiveDocument;var olddb=HostApplicationServices.WorkingDatabase;Document copy=null,reopened=null;string stage="open";
  try{
   Need(!File.Exists(c.output)&&!File.Exists(c.receipt)&&NativeGeometryReadV1.Hash(c.source)==c.source_sha256,"INPUT_OUTPUT_IDENTITY");
   File.Copy(c.source,c.output+".staging.dwg");copy=App.DocumentManager.Open(c.output+".staging.dwg",false);App.DocumentManager.MdiActiveDocument=copy;
   var moves=new List<NativePaperPatchV1.Edit>();string nativeCoord=null,sourceLayout=null,blockHandle=null;object changes=null,copyChanges=null;string expectedPaper=null,expectedCoord=null,restoredViewport=null;bool negative=false;
   using(copy.LockDocument()){
    var db=copy.Database;HostApplicationServices.WorkingDatabase=db;stage="fixtures";
    var targetId=LayoutManager.Current.CreateLayout("MODULE_TRANSFER_TEST");
    using(var tr=db.TransactionManager.StartTransaction()){
     // One real native viewport from the protected source, without reading its drawing appearance.
     var vp=(Viewport)tr.GetObject(db.GetObjectId(false,new Handle(0x4D83),0),OpenMode.ForRead);
     var owner=(BlockTableRecord)tr.GetObject(vp.OwnerId,OpenMode.ForRead);var sl=(Layout)tr.GetObject(owner.LayoutId,OpenMode.ForRead);sourceLayout=sl.LayoutName;
     var source=(BlockTableRecord)tr.GetObject(sl.BlockTableRecordId,OpenMode.ForWrite);
     // Native viewport restore tested separately; ownership transfer is unsupported by AutoCAD.
     var wanted=new HashSet<string>(new[]{"TDbText","TDbSymbMultiLeader"});
     foreach(ObjectId id in source){var e=tr.GetObject(id,OpenMode.ForRead) as Entity;if(e!=null&&wanted.Remove(e.GetRXClass().Name)){var layer=(LayerTableRecord)tr.GetObject(e.LayerId,OpenMode.ForWrite);layer.IsLocked=false;moves.Add(Edit(e,sourceLayout,"MODULE_TRANSFER_TEST","move"));}}
     var arc=new Arc(new Point3d(100,100,0),50,0,Math.PI);Add(tr,source,arc);moves.Add(Edit(arc,sourceLayout,"MODULE_TRANSFER_TEST","move"));
     var circle=new Circle(new Point3d(200,100,0),Vector3d.ZAxis,10);Add(tr,source,circle);moves.Add(Edit(circle,sourceLayout,"MODULE_TRANSFER_TEST","move"));
     var hatch=new Hatch();Add(tr,source,hatch);hatch.SetHatchPattern(HatchPatternType.PreDefined,"SOLID");hatch.Associative=true;hatch.AppendLoop(HatchLoopTypes.External,new ObjectIdCollection(new[]{circle.ObjectId}));hatch.EvaluateHatch(true);moves.Add(Edit(hatch,sourceLayout,"MODULE_TRANSFER_TEST","move"));
     var bt=(BlockTable)tr.GetObject(db.BlockTableId,OpenMode.ForWrite);var def=new BlockTableRecord{Name="MODULE_FRAME_FIXTURE"};bt.Add(def);tr.AddNewlyCreatedDBObject(def,true);
     Add(tr,def,new Line(Point3d.Origin,new Point3d(100,0,0)));var ad=new AttributeDefinition{Position=new Point3d(10,10,0),Tag="SHEET",TextString="A",Height=5};Add(tr,def,ad);
     var block=new BlockReference(new Point3d(300,100,0),def.ObjectId);Add(tr,source,block);var attr=new AttributeReference();attr.SetAttributeFromBlock(ad,block.BlockTransform);attr.TextString="TEST-01";block.AttributeCollection.AppendAttribute(attr);tr.AddNewlyCreatedDBObject(attr,true);blockHandle=block.Handle.ToString();moves.Add(Edit(block,sourceLayout,"MODULE_TRANSFER_TEST","move"));
     foreach(ObjectId id in (BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead)){var e=tr.GetObject(id,OpenMode.ForRead) as Entity;if(e!=null&&e.GetRXClass().Name=="TDbSymbCoord"){nativeCoord=e.Handle.ToString();break;}}
     tr.Commit();
    }
    LayoutManager.Current.CurrentLayout="MODULE_TRANSFER_TEST";
    stage="hatch_dependency_negative";var hatchOnly=moves.Where(i=>i.type=="AcDbHatch").ToArray();try{NativePaperPatchV1.Apply(db,hatchOnly,()=>{throw new System.Exception("SHOULD_NOT_WRITE");});}catch(InvalidOperationException e){negative=e.Message=="MOVE_ASSOCIATIVE_HATCH_WITH_BOUNDARIES";}Need(negative,"MISSING_HATCH_BOUNDARIES_NOT_REJECTED");
    stage="restore_viewport";using(var src=new Database(false,true)){src.ReadDwgFile(c.source,FileOpenMode.OpenForReadAndAllShare,true,"");src.CloseInput(true);restoredViewport=NativeViewportRestoreV1.Apply(db,src,sourceLayout,"4D83","MODULE_TRANSFER_TEST",new[]{1700.0,-800.0});}
    stage="transfer";changes=NativePaperPatchV1.Apply(db,moves.ToArray(),()=>{});
    stage="copy_frame";var cloneEdit=moves.Single(x=>x.handle==blockHandle);cloneEdit.layout="MODULE_TRANSFER_TEST";cloneEdit.target_layout=null;cloneEdit.action="copy";copyChanges=NativePaperPatchV1.Apply(db,new[]{cloneEdit},()=>{});
    var copied=J.Deserialize<NativePaperPatchV1.CopyResult>(J.Serialize(copyChanges)).copied.Select(x=>x.target).ToArray();var handles=moves.Select(x=>x.handle).Concat(copied).Concat(new[]{restoredViewport}).ToArray();expectedPaper=NativePaperPatchV1.SelectedSnapshot(db,handles);
    stage="model_coord";Need(nativeCoord!=null,"MODEL_NATIVE_COORD_SAMPLE_REQUIRED");NativeCoordCreateV2.Item item;
    using(var tr=db.TransactionManager.StartTransaction()){
     var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(nativeCoord,16)),0),OpenMode.ForRead);var g=new GripDataCollection();e.GetGripPoints(g,1,5,Vector3d.ZAxis,GetGripPointsFlags.GripPointsOnly);Need(g.Count==3,"COORD_GRIPS");
     var t=(g[2].GripPoint-g[1].GripPoint);var u=new Vector3d(-t.Y,t.X,0).GetNormal();if(u.DotProduct(g[1].GripPoint-g[0].GripPoint)<0)u=-u;var bend=g[0].GripPoint+u*((g[1].GripPoint-g[0].GripPoint).Length+10);
     item=new NativeCoordCreateV2.Item{template_handle=nativeCoord,layout="Model",layer=e.Layer,expected=new NativeCoordUpdateV1.Expected{x_value=Prop(e,"XValue"),y_value=Prop(e,"YValue"),rotation=Prop(e,"LayoutRotation"),grips=g.Cast<GripData>().Select(x=>P(x.GripPoint)).ToArray()},grips=new[]{P(g[0].GripPoint),P(bend),P(bend+t)}};
    }
    NativeCoordUpdateV1.Apply(copy,new NativeCoordCreateV2.Job{axis_order="YX",display_only=true,items=new[]{item}},()=>{});expectedCoord=J.Serialize(NativeDetailsReadV2.Read(copy,new[]{nativeCoord}));
    stage="save";db.SaveAs(c.output,DwgVersion.AC1032);
    using(var saved=new Database(false,true)){saved.ReadDwgFile(c.output,FileOpenMode.OpenForReadAndAllShare,true,"");saved.CloseInput(true);var actual=NativePaperPatchV1.SelectedSnapshot(saved,handles);if(!CadValueCompareV1.Json(expectedPaper,actual))File.WriteAllText(c.receipt+".paper_diff.json",J.Serialize(new{expected=J.DeserializeObject(expectedPaper),actual=J.DeserializeObject(actual)}));Need(CadValueCompareV1.Json(expectedPaper,actual),"PAPER_SAVE_REOPEN");}
   }
   stage="coordinate_reopen";reopened=App.DocumentManager.Open(c.output,false);App.DocumentManager.MdiActiveDocument=reopened;using(reopened.LockDocument()){HostApplicationServices.WorkingDatabase=reopened.Database;string actual=J.Serialize(NativeDetailsReadV2.Read(reopened,new[]{nativeCoord}));if(!CadValueCompareV1.Json(expectedCoord,actual))File.WriteAllText(c.receipt+".coord_diff.json",J.Serialize(new{expected=J.DeserializeObject(expectedCoord),actual=J.DeserializeObject(actual)}));Need(CadValueCompareV1.Json(expectedCoord,actual),"COORD_SAVE_REOPEN");}
   Need(NativeGeometryReadV1.Hash(c.source)==c.source_sha256,"SOURCE_CHANGED");File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_NATIVE_VERIFIED",c.output,sha256=NativeGeometryReadV1.Hash(c.output),changes,copyChanges,restoredViewport,model_coord=nativeCoord,association_preflight=negative,native_save_reopen_verified=true,source_unchanged=true,visual_review="execution_review_required"}));
  }catch(System.Exception e){File.WriteAllText(c.receipt,J.Serialize(new{status="TEST_FAILED",stage,error=e.ToString()}));}finally{App.DocumentManager.MdiActiveDocument=prior;HostApplicationServices.WorkingDatabase=olddb;if(reopened!=null)reopened.CloseAndDiscard();if(copy!=null)copy.CloseAndDiscard();}
 }
}
