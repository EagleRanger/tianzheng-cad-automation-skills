using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.EditorInput;using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class HatchPatternPatchV1 {
 public class Pattern {public string pattern;public double scale;}
 public class Edit {public string layout;public BoundCadEditsV1.Target target;public Pattern before,after;}
 static JavaScriptSerializer J=new JavaScriptSerializer();
 static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}
 public static string Protected(Hatch h){
  var g=J.Deserialize<Dictionary<string,object>>(J.Serialize(NativeGeometryReadV1.Geometry(h,false)));
  foreach(string name in new[]{"pattern","pattern_type","pattern_scale","pattern_lines"})g.Remove(name);
  return J.Serialize(new{geometry=g,owner=h.OwnerId.Handle.ToString(),handle=h.Handle.ToString(),layer=h.Layer,color=h.Color.ToString(),lt=h.Linetype,lw=(int)h.LineWeight,lts=h.LinetypeScale,transparency=h.Transparency.ToString()});
 }
 public static object Apply(Database db,Edit[] edits){
  Need(edits!=null&&edits.Length>0&&edits.All(e=>e!=null&&e.target!=null)&&edits.Select(e=>e.target.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==edits.Length,"UNIQUE_HATCH_TARGETS_REQUIRED");
  using(var tr=db.TransactionManager.StartTransaction()){
   var hs=new List<Hatch>();
   foreach(var e in edits){
    Need(e.target.bounds!=null&&e.target.bounds.Length==4&&e.before!=null&&e.after!=null&&!String.IsNullOrWhiteSpace(e.after.pattern)&&!e.after.pattern.Equals("SOLID",StringComparison.OrdinalIgnoreCase)&&e.after.scale>0&&!Double.IsInfinity(e.after.scale),"PATTERN_AND_POSITIVE_SCALE_REQUIRED");
    var h=tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(e.target.handle,16)),0),OpenMode.ForRead) as Hatch;
    Need(h!=null&&h.GetRXClass().Name==e.target.type&&h.Layer==e.target.layer&&h.OwnerId==BoundCadEditsV1.Space(tr,db,String.IsNullOrEmpty(e.layout)?"Model":e.layout)&&!h.IsSolidFill,"EXACT_LAYOUT_PATTERN_HATCH_REQUIRED");
    Need(BoundCadEditsV1.Bounds(h).Zip(e.target.bounds,(a,b)=>Math.Abs(a-b)<=.001).All(x=>x)&&h.PatternName==e.before.pattern&&Math.Abs(h.PatternScale-e.before.scale)<=1e-10,"HATCH_BEFORE_CHANGED");hs.Add(h);
   }
   var result=new List<object>();
   for(int i=0;i<edits.Length;i++){
    var h=hs[i];var e=edits[i];string protect=Protected(h);double area=h.Area,angle=h.PatternAngle;var origin=h.Origin;bool doublePattern=h.PatternDouble;var style=h.HatchStyle;
    h.UpgradeOpen();h.SetHatchPattern(HatchPatternType.PreDefined,e.after.pattern);h.PatternScale=e.after.scale;h.PatternAngle=angle;h.Origin=origin;h.PatternDouble=doublePattern;h.HatchStyle=style;h.EvaluateHatch(true);
    Need(h.PatternName.Equals(e.after.pattern,StringComparison.OrdinalIgnoreCase)&&Math.Abs(h.PatternScale-e.after.scale)<=1e-10,"PATTERN_WRITE_MISMATCH");
    Need(Protected(h)==protect&&Math.Abs(h.Area-area)<=Math.Max(1e-8,Math.Abs(area)*1e-9),"HATCH_BOUNDARY_AREA_OR_STYLE_CHANGED");
    result.Add(new{handle=h.Handle.ToString(),before=e.before,after=new{pattern=h.PatternName,scale=h.PatternScale},area=h.Area,loops=h.NumberOfLoops,boundary_and_style_preserved=true});
   }
   tr.Commit();return new{hatches=result};
  }
 }
 public class TestConfig{public string folder,receipt;}
 static Hatch Open(Database db,Transaction tr,string handle){return (Hatch)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0),OpenMode.ForRead);}
 [CommandMethod("HLCADHATCHPATTERNTESTV2",CommandFlags.Session)]public void Test(){
  var original=HostApplicationServices.WorkingDatabase;var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nTest config: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;TestConfig c=null;
  try{c=J.Deserialize<TestConfig>(File.ReadAllText(a.StringResult.Trim('"')));Need(!File.Exists(c.receipt),"RECEIPT_EXISTS");Directory.CreateDirectory(c.folder);var results=new List<object>();
   foreach(string mode in new[]{"sand","scale","paper_sand","paper_wrong_owner","invalid_pattern","wrong_before"}){
    string output=Path.Combine(c.folder,mode+".dwg"),handle,protectedBefore;double area;bool rejected=false;object result=null;
    using(var db=new Database(true,true)){
     HostApplicationServices.WorkingDatabase=db;string layout="Model";if(mode.StartsWith("paper"))using(var ltx=db.TransactionManager.StartTransaction()){foreach(DBDictionaryEntry row in (DBDictionary)ltx.GetObject(db.LayoutDictionaryId,OpenMode.ForRead)){var l=(Layout)ltx.GetObject(row.Value,OpenMode.ForRead);if(!l.ModelType){layout=l.LayoutName;break;}}}
     using(var tr=db.TransactionManager.StartTransaction()){
      var ms=(BlockTableRecord)tr.GetObject(BoundCadEditsV1.Space(tr,db,layout),OpenMode.ForWrite);var h=new Hatch{ColorIndex=3};ms.AppendEntity(h);tr.AddNewlyCreatedDBObject(h,true);h.SetHatchPattern(HatchPatternType.PreDefined,"ANGLE");h.PatternScale=1;h.PatternAngle=.25;
      var points=new Point2dCollection(new[]{new Point2d(0,0),new Point2d(20,0),new Point2d(20,10),new Point2d(0,10),new Point2d(0,0)});h.AppendLoop(HatchLoopTypes.External,points,new DoubleCollection(new[]{0.0,.2,0.0,0.0,0.0}));
      h.AppendLoop(HatchLoopTypes.Default,new Point2dCollection(new[]{new Point2d(2,2),new Point2d(4,2),new Point2d(4,4),new Point2d(2,4),new Point2d(2,2)}),new DoubleCollection(new[]{0.0,0.0,0.0,0.0,0.0}));h.AppendLoop(HatchLoopTypes.Default,new Point2dCollection(new[]{new Point2d(6,2),new Point2d(8,2),new Point2d(8,4),new Point2d(6,4),new Point2d(6,2)}),new DoubleCollection(new[]{0.0,0.0,0.0,0.0,0.0}));h.EvaluateHatch(true);handle=h.Handle.ToString();
      var line=new Line(new Point3d(-3,-2,7),new Point3d(-1,-2,7));ms.AppendEntity(line);tr.AddNewlyCreatedDBObject(line,true);tr.Commit();
     }
     BoundCadEditsV1.Target t;using(var tr=db.TransactionManager.StartTransaction()){var h=Open(db,tr,handle);t=BoundCadEditsV1.Identity(h);protectedBefore=Protected(h);area=h.Area;}
     var edit=new Edit{layout=mode=="paper_wrong_owner"?"Model":layout,target=t,before=new Pattern{pattern=mode=="wrong_before"?"WRONG":"ANGLE",scale=1},after=new Pattern{pattern=mode=="invalid_pattern"?"MISSING_PATTERN_123":mode=="scale"?"ANGLE":"AR-SAND",scale=2.5}};
     try{result=Apply(db,new[]{edit});}catch(System.Exception){rejected=true;if(mode=="sand"||mode=="scale"||mode=="paper_sand")throw;}
     Need(rejected==(mode=="invalid_pattern"||mode=="wrong_before"||mode=="paper_wrong_owner"),"REJECTION_MISMATCH");
     using(var tr=db.TransactionManager.StartTransaction()){
      var h=Open(db,tr,handle);Need(Protected(h)==protectedBefore&&Math.Abs(h.Area-area)<1e-8,"PROTECTION_FAILED");Need(h.PatternName==(rejected?"ANGLE":edit.after.pattern)&&h.PatternScale==(rejected?1:2.5),"ACTUAL_PATTERN_SCALE");
      var ms=(BlockTableRecord)tr.GetObject(BoundCadEditsV1.Space(tr,db,layout),OpenMode.ForRead);Need(ms.Cast<ObjectId>().Count(id=>!(tr.GetObject(id,OpenMode.ForRead) is Viewport))==2,"OBJECT_COUNT_CHANGED");var l=ms.Cast<ObjectId>().Select(id=>tr.GetObject(id,OpenMode.ForRead)).OfType<Line>().Single();Need(l.StartPoint==new Point3d(-3,-2,7)&&l.EndPoint==new Point3d(-1,-2,7),"NON_TARGET_CHANGED");
     }
     db.SaveAs(output,DwgVersion.AC1032);
    }
    using(var db=new Database(false,true)){db.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;using(var tr=db.TransactionManager.StartTransaction()){var h=Open(db,tr,handle);Need(Protected(h)==protectedBefore&&Math.Abs(h.Area-area)<1e-8,"REOPEN_PROTECTION_FAILED");Need(h.PatternScale==(rejected?1:2.5),"REOPEN_SCALE_CHANGED");}}
    HostApplicationServices.WorkingDatabase=original;results.Add(new{mode,output,rejected,result});
   }
   File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_HATCH_PATTERN_SAVE_REOPEN_VERIFIED",cases=results}));
  }catch(System.Exception ex){if(c!=null&&!File.Exists(c.receipt))File.WriteAllText(c.receipt,J.Serialize(new{status="FAIL",error=ex.ToString()}));}finally{HostApplicationServices.WorkingDatabase=original;}
 }
}
