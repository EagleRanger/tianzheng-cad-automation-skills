using System;using System.Linq;using System.Collections.Generic;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
public static class PolylineGeometryV1 {
 public class Edit {public BoundCadEditsV1.Target target;public bool expected_closed;public double[][] vertices;}
 public class Offset {public BoundCadEditsV1.Target target;public double distance;}
 static void Need(bool ok,string error){if(!ok)throw new InvalidOperationException(error);}
 static bool Finite(double x){return !Double.IsNaN(x)&&!Double.IsInfinity(x);}
 static Polyline Checked(Database db,Transaction tr,BoundCadEditsV1.Target t){
  Need(t!=null&&t.bounds!=null&&t.bounds.Length==4,"EXACT_TARGET_REQUIRED");
  var p=tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(t.handle,16)),0),OpenMode.ForRead) as Polyline;
  Need(p!=null&&p.OwnerId==SymbolUtilityServices.GetBlockModelSpaceId(db)&&p.GetRXClass().Name==t.type&&p.Layer==t.layer,"POLYLINE_TARGET_CHANGED");
  Need(BoundCadEditsV1.Bounds(p).Zip(t.bounds,(a,b)=>Math.Abs(a-b)<=.001).All(x=>x),"TARGET_BOUNDS_CHANGED");return p;
 }
 public static double[][] Vertices(Polyline p){return Enumerable.Range(0,p.NumberOfVertices).Select(i=>new[]{p.GetPoint2dAt(i).X,p.GetPoint2dAt(i).Y,p.GetBulgeAt(i),p.GetStartWidthAt(i),p.GetEndWidthAt(i)}).ToArray();}
 static double[] XYZ(Point3d p){return new[]{p.X,p.Y,p.Z};}
 public static object Snapshot(Curve c){
  var p=c as Polyline;var arc=c as Arc;
  return new {identity=BoundCadEditsV1.Identity(c),start=XYZ(c.StartPoint),end=XYZ(c.EndPoint),closed=c.Closed,
   vertices_ocs=p==null?null:Vertices(p),normal=p==null?null:new[]{p.Normal.X,p.Normal.Y,p.Normal.Z},elevation=p==null?(double?)null:p.Elevation,
   arc_center=arc==null?null:XYZ(arc.Center),arc_radius=arc==null?(double?)null:arc.Radius};
 }
 public static object Replace(Database db,Edit[] edits){
  Need(edits!=null&&edits.Length>0,"POLYLINE_EDITS_REQUIRED");
  Need(edits.All(e=>e!=null&&e.target!=null)&&edits.Select(e=>e.target.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==edits.Length,"DUPLICATE_TARGET");
  using(var tr=db.TransactionManager.StartTransaction()){
   var objects=edits.Select(e=>Checked(db,tr,e.target)).ToArray();
   for(int k=0;k<edits.Length;k++){
    var e=edits[k];var p=objects[k];Need(p.Closed==e.expected_closed,"CLOSED_STATE_CHANGED");
    Need(e.vertices!=null&&e.vertices.Length>=(p.Closed?3:2)&&e.vertices.All(v=>v!=null&&v.Length==5&&v.All(Finite)&&v[3]>=0&&v[4]>=0),"VERTICES_REQUIRE_X_Y_BULGE_STARTWIDTH_ENDWIDTH");
    for(int i=0;i<e.vertices.Length-(p.Closed?0:1);i++){var a=e.vertices[i];var b=e.vertices[(i+1)%e.vertices.Length];Need(a[0]!=b[0]||a[1]!=b[1],"ZERO_LENGTH_SEGMENT");}
   }
   var results=new List<object>();
   for(int k=0;k<edits.Length;k++){
    var p=objects[k];var before=Snapshot(p);var rows=edits[k].vertices;p.UpgradeOpen();
    while(p.NumberOfVertices>rows.Length)p.RemoveVertexAt(p.NumberOfVertices-1);
    for(int i=0;i<rows.Length;i++){var v=rows[i];var xy=new Point2d(v[0],v[1]);if(i==p.NumberOfVertices)p.AddVertexAt(i,xy,v[2],v[3],v[4]);else{p.SetPointAt(i,xy);p.SetBulgeAt(i,v[2]);p.SetStartWidthAt(i,v[3]);p.SetEndWidthAt(i,v[4]);}}
    results.Add(new{before,after=Snapshot(p)});
   }
   tr.Commit();return new{updated=results,coordinate_system="target OCS; normal/elevation unchanged",identity_display_closed_preserved=true};
  }
 }
 public class Create {public BoundCadEditsV1.Target template;public bool closed;public double[][] vertices;}
 public static object CreateCurves(Database db,Create[] rows){
  Need(rows!=null&&rows.Length>0&&rows.All(x=>x!=null),"CREATE_ITEMS_REQUIRED");
  using(var tr=db.TransactionManager.StartTransaction()){
   var sources=rows.Select(x=>Checked(db,tr,x.template)).ToArray();
   foreach(var x in rows){Need(x.vertices!=null&&x.vertices.Length>=(x.closed?3:2)&&x.vertices.All(v=>v!=null&&v.Length==5&&v.All(Finite)&&v[3]>=0&&v[4]>=0),"EXPLICIT_VALID_VERTICES_REQUIRED");for(int i=0;i<x.vertices.Length-(x.closed?0:1);i++){var a=x.vertices[i];var b=x.vertices[(i+1)%x.vertices.Length];Need(a[0]!=b[0]||a[1]!=b[1],"ZERO_LENGTH_SEGMENT");}}
   var ms=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);var added=new List<object>();
   for(int i=0;i<rows.Length;i++){var x=rows[i];var source=sources[i];var p=new Polyline();p.SetPropertiesFrom(source);p.Normal=source.Normal;p.Elevation=source.Elevation;p.Thickness=source.Thickness;p.Plinegen=source.Plinegen;p.Closed=x.closed;for(int k=0;k<x.vertices.Length;k++){var v=x.vertices[k];p.AddVertexAt(k,new Point2d(v[0],v[1]),v[2],v[3],v[4]);}ms.AppendEntity(p);tr.AddNewlyCreatedDBObject(p,true);added.Add(new{template=Snapshot(source),created=Snapshot(p)});}
   tr.Commit();return new{created=added,source_unchanged=true,coordinate_system="template OCS; native normal/elevation inherited; no hidden connecting segment"};
  }
 }
 public static object OffsetCurves(Database db,Offset[] offsets){
  Need(offsets!=null&&offsets.Length>0&&offsets.All(o=>o!=null&&Finite(o.distance)&&o.distance!=0),"FINITE_NONZERO_OFFSET_REQUIRED");
  using(var tr=db.TransactionManager.StartTransaction()){
   var sources=offsets.Select(o=>Checked(db,tr,o.target)).ToArray();
   var model=(BlockTableRecord)tr.GetObject(SymbolUtilityServices.GetBlockModelSpaceId(db),OpenMode.ForWrite);
   var results=new List<object>();
   for(int i=0;i<offsets.Length;i++){
    var source=sources[i];var curves=source.GetOffsetCurves(offsets[i].distance);
    try{
     Need(curves.Count>0,"NATIVE_OFFSET_RETURNED_NO_CURVES");var added=new List<object>();
     foreach(DBObject item in curves){var curve=item as Curve;Need(curve!=null,"OFFSET_RETURNED_NON_CURVE");curve.SetPropertiesFrom(source);model.AppendEntity(curve);tr.AddNewlyCreatedDBObject(curve,true);added.Add(Snapshot(curve));}
     results.Add(new{source=Snapshot(source),signed_distance=offsets[i].distance,direction="native GetOffsetCurves signed distance; inspect returned geometry, not presumed inside/outside",returned_count=curves.Count,returned_objects=added});
    }finally{foreach(DBObject item in curves)item.Dispose();}
   }
   tr.Commit();return new{offsets=results,source_unchanged=true,all_native_results_appended=true};
  }
 }
}
