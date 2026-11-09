// Table legend only: add a closed native outline to a single rectangular hatch.
using System;using System.Linq;using System.Collections.Generic;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.ApplicationServices;
public partial class NativeTablePatchV1 {
 static double[] OutlineRectangle(Hatch h){
  const double tol=1e-7;Need(!h.Associative&&h.Normal.IsEqualTo(Vector3d.ZAxis)&&Math.Abs(h.Elevation)<1e-10&&h.NumberOfLoops==1,"OUTLINE_SINGLE_Z0_NONASSOCIATIVE_HATCH_REQUIRED");
  var loop=h.GetLoopAt(0);var points=new List<Point2d>();
  if(loop.IsPolyline){var vv=loop.Polyline.Cast<BulgeVertex>().ToArray();Need(vv.All(v=>Math.Abs(v.Bulge)<1e-12),"OUTLINE_STRAIGHT_RECTANGLE_REQUIRED");points.AddRange(vv.Select(v=>v.Vertex));if(points.Count==5&&points[0].GetDistanceTo(points[4])<tol)points.RemoveAt(4);}
  else{var edges=loop.Curves.Cast<Curve2d>().ToArray();Need(edges.Length==4&&edges.All(e=>e is LineSegment2d),"OUTLINE_FOUR_LINE_EDGES_REQUIRED");var lines=edges.Cast<LineSegment2d>().ToArray();for(int n=0;n<4;n++){Need(lines[n].EndPoint.GetDistanceTo(lines[(n+1)%4].StartPoint)<tol,"OUTLINE_OPEN_EDGE_LOOP");points.Add(lines[n].StartPoint);}}
  Need(points.Count==4,"OUTLINE_FOUR_CORNERS_REQUIRED");double x0=points.Min(p=>p.X),y0=points.Min(p=>p.Y),x1=points.Max(p=>p.X),y1=points.Max(p=>p.Y);Need(x1-x0>tol&&y1-y0>tol,"OUTLINE_NONZERO_RECTANGLE_REQUIRED");var corners=new HashSet<int>();
  for(int n=0;n<4;n++){var p=points[n];var q=points[(n+1)%4];bool left=Math.Abs(p.X-x0)<tol,right=Math.Abs(p.X-x1)<tol,bottom=Math.Abs(p.Y-y0)<tol,top=Math.Abs(p.Y-y1)<tol;Need((left||right)&&(bottom||top)&&corners.Add((right?1:0)+(top?2:0)),"OUTLINE_AXIS_ALIGNED_RECTANGLE_REQUIRED");Need((Math.Abs(p.X-q.X)<tol) != (Math.Abs(p.Y-q.Y)<tol),"OUTLINE_AXIS_ALIGNED_EDGES_REQUIRED");}return new[]{x0,y0,x1,y1};
 }
 static void CheckOutline(Transaction tr,BlockTableRecord b,Hatch h,LegendHatch x){
  Need(x.rectangle==null&&!x.reload_pattern&&!x.pattern_scale.HasValue,"OUTLINE_ONLY_LEGEND_REQUIRED");var ids=b.Cast<ObjectId>().Where(id=>!id.IsErased).ToArray();Need(ids.Length==1&&ids[0]==h.ObjectId,"OUTLINE_REQUIRES_HATCH_ONLY_BLOCK");var layer=(LayerTableRecord)tr.GetObject(h.LayerId,OpenMode.ForRead);Need(!layer.IsLocked&&!layer.IsDependent,"OUTLINE_LAYER_LOCKED_OR_DEPENDENT");OutlineRectangle(h);
 }
 static object ApplyOutlines(Document doc,Job job,Action mutation){
  Need(job.tables.All(i=>i.cells.Length==0&&i.delete_tail==null&&i.delete_rows==null&&i.legend_hatches.Length>0&&i.legend_hatches.All(x=>x.outline)),"OUTLINE_BATCH_SEPARATE_REQUIRED");
  var edits=job.tables.SelectMany(i=>i.legend_hatches).ToArray();Need(edits.Select(x=>x.block.ToUpperInvariant()).Distinct().Count()==edits.Length,"UNIQUE_OUTLINE_BLOCKS_REQUIRED");var db=doc.Database;var tableIds=new HashSet<string>(job.tables.Select(i=>i.handle),StringComparer.OrdinalIgnoreCase);var created=new HashSet<string>();var cacheOwners=new HashSet<string>();var touched=new Dictionary<string,string>();var results=new List<object>();
  ObjectEventHandler changed=(sender,a)=>{var e=a.DBObject as Entity;if(e!=null&&!tableIds.Contains(H(e.ObjectId)))touched[H(e.ObjectId)]=H(e.OwnerId);};ObjectErasedEventHandler erased=(sender,a)=>{var e=a.DBObject as Entity;if(e!=null&&!tableIds.Contains(H(e.ObjectId)))touched[H(e.ObjectId)]=H(e.OwnerId);};
  using(var tr=db.TransactionManager.StartTransaction()){
   foreach(var i in job.tables){var t=Open(db,tr,i.handle,OpenMode.ForRead);Check(t,i);CheckLegends(db,tr,t,i);cacheOwners.Add(H(t.BlockTableRecord));}
   string before=J.Serialize(job.tables.Select(i=>FullState(db,tr,i,false)).ToArray());db.ObjectModified+=changed;db.ObjectAppended+=changed;db.ObjectErased+=erased;
   try{mutation();foreach(var x in edits){var h=(Hatch)tr.GetObject(Id(db,x.handle),OpenMode.ForRead);var b=(BlockTableRecord)tr.GetObject(h.OwnerId,OpenMode.ForWrite);var q=OutlineRectangle(h);var line=new Polyline(4);line.SetPropertiesFrom(h);line.Normal=Vector3d.ZAxis;line.Elevation=0;line.AddVertexAt(0,new Point2d(q[0],q[1]),0,0,0);line.AddVertexAt(1,new Point2d(q[2],q[1]),0,0,0);line.AddVertexAt(2,new Point2d(q[2],q[3]),0,0,0);line.AddVertexAt(3,new Point2d(q[0],q[3]),0,0,0);line.Closed=true;b.AppendEntity(line);tr.AddNewlyCreatedDBObject(line,true);created.Add(H(line.ObjectId));Need(line.OwnerId==h.OwnerId&&line.NumberOfVertices==4&&line.Closed&&Math.Abs(line.Area-(q[2]-q[0])*(q[3]-q[1]))<1e-7,"OUTLINE_NATIVE_READBACK");results.Add(new{block=x.block,hatch=x.handle,created=H(line.ObjectId),rectangle=q,layer=line.Layer,color=line.Color.ToString(),style_source="original_hatch"});}
    foreach(var i in job.tables){var t=Open(db,tr,i.handle,OpenMode.ForWrite);t.GenerateLayout();t.RecomputeTableBlock(true);cacheOwners.Add(H(t.BlockTableRecord));t.RecordGraphicsModified(true);}
    string after=J.Serialize(job.tables.Select(i=>FullState(db,tr,i,false,created)).ToArray());Need(CadValueCompareV1.Json(before,after),"OUTLINE_CHANGED_EXISTING_TABLE_OR_LEGEND");Need(touched.All(kv=>created.Contains(kv.Key)||cacheOwners.Contains(kv.Value)),"OUTLINE_UNSELECTED_ENTITY_CHANGED");tr.Commit();Need(touched.All(kv=>created.Contains(kv.Key)||cacheOwners.Contains(kv.Value)),"OUTLINE_UNSELECTED_ENTITY_CHANGED_ON_COMMIT");
   }finally{db.ObjectModified-=changed;db.ObjectAppended-=changed;db.ObjectErased-=erased;}
  }
  doc.Editor.Regen();return new{operation="table_legend_outline",outlines=results,existing_hatches_and_patterns_preserved=true,table_cells_styles_and_explicit_scales_preserved=true,unselected_entity_write_guard=true,graphics_cache_refreshed=true};
 }
}
