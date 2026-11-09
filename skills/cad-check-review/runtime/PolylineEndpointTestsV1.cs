using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class PolylineEndpointTestsV1 {
 public class Config{public string folder,receipt;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer();
 static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}
 static Polyline Open(Database db,Transaction tr,string h,OpenMode mode){return (Polyline)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0),mode);}
 static double[][] Rows(Polyline p){return Enumerable.Range(0,p.NumberOfVertices).Select(i=>new[]{p.GetPoint2dAt(i).X,p.GetPoint2dAt(i).Y,p.GetBulgeAt(i),p.GetStartWidthAt(i),p.GetEndWidthAt(i)}).ToArray();}
 static BoundCadEditsV1.Target Make(Database db,bool source){using(var tr=db.TransactionManager.StartTransaction()){
  var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);var p=new Polyline{Elevation=3,ColorIndex=source?2:253,LinetypeScale=source?1:2,Thickness=.25};
  int count=source?4:3;for(int i=0;i<count;i++)p.AddVertexAt(i,new Point2d((source?10:100)+i*8,(source?20:200)+i*4),i==count-1?0:.05*(i+1),.1*(i+1),.2*(i+1));ms.AppendEntity(p);tr.AddNewlyCreatedDBObject(p,true);
  // Unselected real object used to catch collateral changes.
  var line=new Line(new Point3d(-5,-6,7),new Point3d(-2,-1,7));ms.AppendEntity(line);tr.AddNewlyCreatedDBObject(line,true);var result=BoundCadEditsV1.Identity(p);tr.Commit();return result;
 }}
 static void Verify(Database db,string handle,double[][] expected){using(var tr=db.TransactionManager.StartTransaction()){
  var p=Open(db,tr,handle,OpenMode.ForRead);Need(J.Serialize(Rows(p))==J.Serialize(expected),"VERTEX_DATA_MISMATCH");Need(p.ColorIndex==253&&p.LinetypeScale==2&&p.Elevation==3&&p.Thickness==.25&&!p.Closed,"PROPERTIES_CHANGED");
  var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead);Need(ms.Cast<ObjectId>().Count()==2,"OBJECT_SET_CHANGED");var line=ms.Cast<ObjectId>().Select(id=>tr.GetObject(id,OpenMode.ForRead)).OfType<Line>().Single();Need(line.StartPoint==new Point3d(-5,-6,7)&&line.EndPoint==new Point3d(-2,-1,7),"UNSELECTED_CHANGED");
 }}
 [CommandMethod("HLCADPOLYENDPOINTTESTV1",CommandFlags.Session)]public void Run(){
  var doc=App.DocumentManager.MdiActiveDocument;var a=doc.Editor.GetString(new PromptStringOptions("\nTest config: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Config c=null;var work=HostApplicationServices.WorkingDatabase;var dirty=App.GetSystemVariable("DBMOD");
  try{c=J.Deserialize<Config>(File.ReadAllText(a.StringResult.Trim('"')));Need(!File.Exists(c.receipt),"RECEIPT_EXISTS");Directory.CreateDirectory(c.folder);var results=new List<object>();
   foreach(string mode in new[]{"none","start","end","both","plane_reject","closed_reject","name_reject"}){
    string output=Path.Combine(c.folder,mode+".dwg");Need(!File.Exists(output),"OUTPUT_EXISTS");string target;double[][] expected;
    using(var source=new Database(true,true))using(var dest=new Database(true,true)){
     HostApplicationServices.WorkingDatabase=source;var s=Make(source,true);HostApplicationServices.WorkingDatabase=dest;var t=Make(dest,false);target=t.handle;
     double[][] old;using(var tr=dest.TransactionManager.StartTransaction())old=Rows(Open(dest,tr,target,OpenMode.ForRead));using(var tr=source.TransactionManager.StartTransaction()){var p=Open(source,tr,s.handle,OpenMode.ForRead);expected=Rows(p);}
     string sourceBefore=J.Serialize(expected);var ends=mode=="none"?null:mode=="both"?new[]{"start","end"}:mode.EndsWith("reject")?new[]{mode=="name_reject"?"middle":"end"}:new[]{mode};
     if(mode=="plane_reject"||mode=="closed_reject")using(var tr=source.TransactionManager.StartTransaction()){var p=Open(source,tr,s.handle,OpenMode.ForWrite);if(mode=="plane_reject")p.Elevation=9;else p.Closed=true;tr.Commit();}
     bool rejected=false;try{BoundCadEditsV1.ApplyPolylineGeometry(source,dest,new BoundCadEditsV1.Job{pairs=new[]{new BoundCadEditsV1.Pair{source=s,target=t,preserve_target_endpoints=ends}}});}catch(InvalidOperationException){rejected=true;}
     Need(rejected==mode.EndsWith("reject"),"REJECTION_RESULT:"+mode);
     if(rejected)expected=old;else{if(ends!=null&&ends.Contains("start"))expected[0]=old[0];if(ends!=null&&ends.Contains("end"))expected[expected.Length-1]=old[old.Length-1];}
     Verify(dest,target,expected);using(var tr=source.TransactionManager.StartTransaction())Need(J.Serialize(Rows(Open(source,tr,s.handle,OpenMode.ForRead)))==sourceBefore,"SOURCE_VERTICES_CHANGED");dest.SaveAs(output,DwgVersion.AC1032);
    }
    using(var reopened=new Database(false,true)){reopened.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);reopened.CloseInput(true);HostApplicationServices.WorkingDatabase=reopened;Verify(reopened,target,expected);}
    HostApplicationServices.WorkingDatabase=work;results.Add(new{mode,output,saved_reopened=true});
   }
   Need(App.DocumentManager.MdiActiveDocument==doc&&Equals(dirty,App.GetSystemVariable("DBMOD")),"ACTIVE_DOCUMENT_CHANGED");File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_ENDPOINT_SAVE_REOPEN_VERIFIED",cases=results,source_vertices_unchanged=true,target_handle_display_unchanged=true,unselected_object_unchanged=true,active_document_unchanged=true}));
  }catch(System.Exception e){if(c!=null&&!File.Exists(c.receipt))File.WriteAllText(c.receipt,J.Serialize(new{status="FAIL",error=e.ToString()}));}finally{HostApplicationServices.WorkingDatabase=work;}
 }
}
