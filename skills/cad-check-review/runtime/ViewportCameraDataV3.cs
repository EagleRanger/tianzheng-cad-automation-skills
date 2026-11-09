using System;using System.Linq;using System.Collections.Generic;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
// Detached camera values. Offset is WCS XY, never DCS ViewCenter.
public static class ViewportCameraDataV3 {
 public class Row{public string source,target;public Point3d view_target;public Vector3d direction;public Point2d center;public double scale,twist;public double[] world_offset;}
 static void Need(bool v,string message){if(!v)throw new InvalidOperationException(message);}
 static bool Finite(double x){return !Double.IsNaN(x)&&!Double.IsInfinity(x);}
 public static Row[] Read(Database db,BoundCadEditsV6.Job job){using(var tr=db.TransactionManager.StartTransaction()){
  var owner=BoundCadEditsV6.Space(tr,db,job.source_layout);return job.pairs.Select(pair=>{
   var v=BoundCadEditsV6.Checked(tr,db,pair.source,owner) as Viewport;
   Need(v!=null&&v.Number!=1&&!v.PerspectiveOn,"ORTHOGRAPHIC_FLOATING_VIEWPORT_REQUIRED");
   var offset=pair.world_offset??new double[]{0,0,0};Need(offset.Length==3&&offset.All(Finite)&&offset[2]==0,"PLAN_WORLD_OFFSET_REQUIRED");
   if(pair.world_offset!=null)Need(v.ViewDirection.GetNormal().IsEqualTo(Vector3d.ZAxis,new Tolerance(1e-9,1e-9)),"PLAN_CAMERA_REQUIRED");
   double scale=pair.custom_scale??v.CustomScale;Need(Finite(scale)&&scale>0,"POSITIVE_CAMERA_SCALE_REQUIRED");
   return new Row{source=pair.source.handle,target=pair.target.handle,view_target=v.ViewTarget+new Vector3d(offset[0],offset[1],0),direction=v.ViewDirection,center=v.ViewCenter,scale=scale,twist=v.TwistAngle,world_offset=offset};
  }).ToArray();
 }}
 public static object Apply(Database db,BoundCadEditsV6.Job job,Row[] rows){var changes=new List<object>();using(var tr=db.TransactionManager.StartTransaction()){
  var owner=BoundCadEditsV6.Space(tr,db,job.target_layout);
  var views=job.pairs.Select(p=>BoundCadEditsV6.Checked(tr,db,p.target,owner) as Viewport).ToArray();
  Need(views.All(v=>v!=null&&v.Number!=1),"FLOATING_TARGET_VIEWPORT_REQUIRED");
  for(int i=0;i<views.Length;i++){
   var pair=job.pairs[i];var row=rows.Single(x=>x.target==pair.target.handle&&x.source==pair.source.handle);var v=views[i];
   v.UpgradeOpen();bool locked=v.Locked;v.Locked=false;v.PerspectiveOn=false;
   v.ViewDirection=row.direction;v.ViewTarget=row.view_target;v.TwistAngle=row.twist;v.ViewCenter=row.center;
   v.ViewHeight=v.Height/row.scale;v.CustomScale=row.scale;v.Locked=locked;
   Need(Math.Abs(v.CustomScale-row.scale)<1e-9&&Math.Abs(v.ViewHeight-v.Height/row.scale)<1e-7,"CAMERA_SCALE_MISMATCH");
   changes.Add(new{source=row.source,target=row.target,view_target=new[]{v.ViewTarget.X,v.ViewTarget.Y,v.ViewTarget.Z},world_offset=row.world_offset,center=new[]{v.ViewCenter.X,v.ViewCenter.Y},scale=v.CustomScale,view_height=v.ViewHeight,twist=v.TwistAngle});
  }tr.Commit();}return changes;
 }
}
