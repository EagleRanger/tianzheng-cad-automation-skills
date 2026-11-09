using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class PolylineGeometryTestsV1 {
 public class Config {public string folder,receipt;}
 static JavaScriptSerializer J=new JavaScriptSerializer();
 static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}
 static Polyline Open(Database db,Transaction tr,string h){return (Polyline)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0),OpenMode.ForRead);}
 static string Records(Database db){using(var tr=db.TransactionManager.StartTransaction()){
  var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead);
  return J.Serialize(ms.Cast<ObjectId>().Select(id=>{var e=(Entity)tr.GetObject(id,OpenMode.ForRead);var p=e as Polyline;var l=e as Line;return new{handle=e.Handle.ToString(),layer=e.Layer,color=e.ColorIndex,scale=e.LinetypeScale,rows=p==null?null:PolylineGeometryV1.Vertices(p),closed=p!=null&&p.Closed,normal=p==null?null:new[]{p.Normal.X,p.Normal.Y,p.Normal.Z},elevation=p==null?0:p.Elevation,thickness=p==null?0:p.Thickness,line_start=l==null?null:new[]{l.StartPoint.X,l.StartPoint.Y,l.StartPoint.Z}};}).ToArray());
 }}
 static BoundCadEditsV1.Target Make(Database db,bool closed,bool arc){using(var tr=db.TransactionManager.StartTransaction()){
  var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);
  var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForWrite);var layer=new LayerTableRecord{Name="TEST_GEOMETRY"};lt.Add(layer);tr.AddNewlyCreatedDBObject(layer,true);
  var p=new Polyline{LayerId=layer.ObjectId,Elevation=4,Thickness=.25,ColorIndex=3,LinetypeScale=2,Closed=closed};
  p.AddVertexAt(0,new Point2d(0,0),arc?.414213562373095:0,.2,.3);p.AddVertexAt(1,new Point2d(10,0),0,.3,.4);
  if(closed){p.AddVertexAt(2,new Point2d(10,10),0,.4,.5);p.AddVertexAt(3,new Point2d(0,10),0,.5,.2);}
  ms.AppendEntity(p);tr.AddNewlyCreatedDBObject(p,true);var line=new Line(new Point3d(-5,-7,9),new Point3d(-2,-1,9));ms.AppendEntity(line);tr.AddNewlyCreatedDBObject(line,true);var t=BoundCadEditsV1.Identity(p);tr.Commit();return t;
 }}
 static int Count(Database db){using(var tr=db.TransactionManager.StartTransaction())return ((BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead)).Cast<ObjectId>().Count();}
 [CommandMethod("HLCADPOLYGEOMETRYTESTV2",CommandFlags.Session)]public void Run(){
  var doc=App.DocumentManager.MdiActiveDocument;var ans=doc.Editor.GetString(new PromptStringOptions("\nTest config: "){AllowSpaces=true});if(ans.Status!=PromptStatus.OK)return;Config c=null;var original=HostApplicationServices.WorkingDatabase;var dirty=App.GetSystemVariable("DBMOD");
  try{c=J.Deserialize<Config>(File.ReadAllText(ans.StringResult.Trim('"')));Need(!File.Exists(c.receipt),"RECEIPT_EXISTS");Directory.CreateDirectory(c.folder);var results=new List<object>();
   foreach(string mode in new[]{"create_two","create_closed","create_reject","edit_open","edit_closed","closed_reject","identity_reject","width_reject","nan_reject","zero_segment_reject","batch_rollback","offset_both","offset_arc","offset_closed","offset_zero_reject"}){
    string output=Path.Combine(c.folder,mode+".dwg"),expected;object receipt=null;
    using(var db=new Database(true,true)){
     HostApplicationServices.WorkingDatabase=db;bool closed=mode=="edit_closed"||mode=="offset_closed";var target=Make(db,closed,mode=="offset_arc");string before=Records(db);
     bool reject=mode.EndsWith("reject")||mode=="batch_rollback",failed=false;
     try{
      if(mode.StartsWith("create")){
       var vertices=new[]{new[]{0.0,0,.414213562373095,.2,.3},new[]{3.0,4,0,.3,.2},new[]{6.0,5,0,.2,.2}};
       var x=new PolylineGeometryV1.Create{template=target,closed=mode=="create_closed",vertices=vertices};var copies=new[]{x};
       if(mode=="create_two")copies=new[]{x,new PolylineGeometryV1.Create{template=target,closed=false,vertices=new[]{new[]{20.0,0,0,.1,.1},new[]{30.0,0,0,.1,.1}}}};
       if(mode=="create_reject")copies=new[]{x,new PolylineGeometryV1.Create{template=target,closed=false,vertices=new[]{new[]{0.0,0,0,.1,.1},new[]{0.0,0,0,.1,.1}}}};
       receipt=PolylineGeometryV1.CreateCurves(db,copies);
       using(var tr=db.TransactionManager.StartTransaction()){var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead);var all=ms.Cast<ObjectId>().Select(id=>tr.GetObject(id,OpenMode.ForRead)).OfType<Polyline>().ToArray();Need(all.Length==copies.Length+1,"CREATE_COUNT");for(int i=0;i<copies.Length;i++){var q=all[i+1];Need(J.Serialize(PolylineGeometryV1.Vertices(q))==J.Serialize(copies[i].vertices)&&q.Closed==copies[i].closed&&q.Elevation==4&&q.Thickness==.25&&q.ColorIndex==3&&q.Layer=="TEST_GEOMETRY","CREATE_VALUES");}var source=all[0];Need(source.NumberOfVertices==2&&source.GetPoint2dAt(1)==new Point2d(10,0)&&source.GetBulgeAt(0)==0,"CREATE_SOURCE_CHANGED");}
      }else if(mode.StartsWith("offset")){
       var offsets=new[]{new PolylineGeometryV1.Offset{target=target,distance=mode=="offset_zero_reject"?0:1}};
       if(mode=="offset_both")offsets=new[]{new PolylineGeometryV1.Offset{target=target,distance=2},new PolylineGeometryV1.Offset{target=target,distance=-2}};
       receipt=PolylineGeometryV1.OffsetCurves(db,offsets);
       using(var tr=db.TransactionManager.StartTransaction()){
        var source=Open(db,tr,target.handle);Need(source.Elevation==4&&source.Thickness==.25&&source.Layer=="TEST_GEOMETRY"&&source.NumberOfVertices==(closed?4:2),"SOURCE_CHANGED");
        var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead);var added=ms.Cast<ObjectId>().Select(id=>tr.GetObject(id,OpenMode.ForRead)).OfType<Polyline>().Where(p=>p.Handle.ToString()!=target.handle).ToArray();Need(added.Length==offsets.Length,"ALL_RETURNS_COUNT");
        for(int i=0;i<offsets.Length;i++){
         var native=source.GetOffsetCurves(offsets[i].distance);try{Need(native.Count==1,"TEST_FIXTURE_EXPECTATION");var want=(Polyline)native[0];Need(J.Serialize(PolylineGeometryV1.Vertices(want))==J.Serialize(PolylineGeometryV1.Vertices(added[i])),"NATIVE_GEOMETRY_WIDTHS_CHANGED");}finally{foreach(DBObject obj in native)obj.Dispose();}
         Need(added[i].Layer==source.Layer&&added[i].ColorIndex==3&&added[i].LinetypeScale==2&&added[i].Elevation==4&&added[i].Closed==closed,"OFFSET_PROPERTIES_CHANGED");
        }
        if(mode=="offset_both")Need(Math.Abs(added[0].GetPoint2dAt(0).Y)==2&&added[0].GetPoint2dAt(0).Y==-added[1].GetPoint2dAt(0).Y,"SIGNED_DIRECTION_FAILED");
       }
      }else{
       var rows=new[]{new[]{0.0,0,.1,.2,.3},new[]{5.0,2,.2,.3,.4},new[]{10.0,0,0,.4,.5}};
       var edit=new PolylineGeometryV1.Edit{target=target,expected_closed=mode=="closed_reject"?!closed:closed,vertices=rows};
       if(mode=="identity_reject")target.layer="wrong";if(mode=="width_reject")rows[1][3]=-1;if(mode=="nan_reject")rows[1][0]=Double.NaN;if(mode=="zero_segment_reject")rows[1]=rows[0];
       var edits=new[]{edit};if(mode=="batch_rollback")edits=new[]{edit,new PolylineGeometryV1.Edit{target=new BoundCadEditsV1.Target{handle="FFFFFFFF",type="AcDbPolyline",layer="TEST_GEOMETRY",bounds=new[]{0.0,0,10,10}},vertices=rows}};
       receipt=PolylineGeometryV1.Replace(db,edits);
       using(var tr=db.TransactionManager.StartTransaction()){var p=Open(db,tr,target.handle);Need(J.Serialize(PolylineGeometryV1.Vertices(p))==J.Serialize(rows),"EXPLICIT_ROWS_MISMATCH");Need(p.Closed==closed&&p.Elevation==4&&p.Thickness==.25&&p.Layer=="TEST_GEOMETRY"&&p.ColorIndex==3&&p.LinetypeScale==2,"TARGET_PROPERTIES_CHANGED");}
      }
     }catch(System.Exception){failed=true;if(!reject)throw;}
     Need(failed==reject,"EXPECTED_REJECTION:"+mode);if(reject)Need(Records(db)==before,"FAILURE_NOT_ATOMIC");
     using(var tr=db.TransactionManager.StartTransaction()){var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForRead);var l=ms.Cast<ObjectId>().Select(id=>tr.GetObject(id,OpenMode.ForRead)).OfType<Line>().Single();Need(l.StartPoint==new Point3d(-5,-7,9)&&l.EndPoint==new Point3d(-2,-1,9),"NON_TARGET_CHANGED");}
     if((!mode.StartsWith("offset")&&!mode.StartsWith("create"))||reject)Need(Count(db)==2,"OBJECT_SET_CHANGED");expected=Records(db);db.SaveAs(output,DwgVersion.AC1032);
    }
    using(var db=new Database(false,true)){db.ReadDwgFile(output,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);HostApplicationServices.WorkingDatabase=db;Need(Records(db)==expected,"SAVE_REOPEN_CHANGED");}
    HostApplicationServices.WorkingDatabase=original;results.Add(new{mode,output,saved_reopened=true,changes=receipt});
   }
   Need(App.DocumentManager.MdiActiveDocument==doc&&Equals(dirty,App.GetSystemVariable("DBMOD")),"HOST_DOCUMENT_CHANGED");File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_GEOMETRY_SAVE_REOPEN_VERIFIED",cases=results,engineering_review=false}));
  }catch(System.Exception ex){if(c!=null&&!File.Exists(c.receipt))File.WriteAllText(c.receipt,J.Serialize(new{status="FAIL",error=ex.ToString()}));}finally{HostApplicationServices.WorkingDatabase=original;}
 }
}
