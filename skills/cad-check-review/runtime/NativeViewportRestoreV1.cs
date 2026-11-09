// Restore a rectangular 2D viewport from a protected DWG, using native fields.
using System;using System.Linq;using System.Collections.Generic;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
public static class NativeViewportRestoreV1 {
 static void Need(bool b,string m){if(!b)throw new InvalidOperationException(m);}
 static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 static ObjectId Space(Database db,Transaction tr,string name){var d=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);Need(d.Contains(name),"LAYOUT_MISSING");var l=(Layout)tr.GetObject(d.GetAt(name),OpenMode.ForRead);Need(!l.ModelType,"PAPER_LAYOUT_ONLY");return l.BlockTableRecordId;}
 public static object State(Database db,string handle){using(var tr=db.TransactionManager.StartTransaction()){var v=(Viewport)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0),OpenMode.ForRead);return new{type=v.GetRXClass().Name,owner=v.OwnerId.Handle.ToString(),center=P(v.CenterPoint),v.Width,v.Height,target=P(v.ViewTarget),direction=P(Point3d.Origin+v.ViewDirection),view=new[]{v.ViewCenter.X,v.ViewCenter.Y},v.CustomScale,v.ViewHeight,v.TwistAngle,v.Locked,layer=v.Layer,color=v.Color.ToString(),v.Linetype,v.LineWeight,clipped=v.NonRectClipOn,frozen=v.GetFrozenLayers().Cast<ObjectId>().Select(id=>((LayerTableRecord)tr.GetObject(id,OpenMode.ForRead)).Name).OrderBy(x=>x).ToArray()};}}
 public static string Apply(Database dest,Database source,string sourceLayout,string sourceHandle,string targetLayout,double[] offset){
  Need(offset!=null&&offset.Length==2&&offset.All(x=>!Double.IsNaN(x)&&!Double.IsInfinity(x)),"FINITE_PAPER_OFFSET_REQUIRED");
  using(var sr=source.TransactionManager.StartTransaction())using(var tr=dest.TransactionManager.StartTransaction()){
   var from=Space(source,sr,sourceLayout);var to=(BlockTableRecord)tr.GetObject(Space(dest,tr,targetLayout),OpenMode.ForWrite);var v=sr.GetObject(source.GetObjectId(false,new Handle(Convert.ToInt64(sourceHandle,16)),0),OpenMode.ForRead) as Viewport;
   Need(v!=null&&v.OwnerId==from&&((Layout)sr.GetObject(((BlockTableRecord)sr.GetObject(from,OpenMode.ForRead)).LayoutId,OpenMode.ForRead)).GetViewports()[0]!=v.ObjectId&&!v.PerspectiveOn&&!v.NonRectClipOn&&v.NonRectClipEntityId.IsNull&&v.ViewDirection.GetNormal().IsEqualTo(Vector3d.ZAxis,new Tolerance(1e-9,1e-9)),"RECTANGULAR_2D_SOURCE_VIEWPORT_REQUIRED");
   var layers=(LayerTable)tr.GetObject(dest.LayerTableId,OpenMode.ForRead);Need(layers.Has(v.Layer),"TARGET_VIEWPORT_LAYER_MISSING");
   var n=new Viewport();n.SetDatabaseDefaults(dest);to.AppendEntity(n);tr.AddNewlyCreatedDBObject(n,true);n.LayerId=layers[v.Layer];n.Color=v.Color;n.LineWeight=v.LineWeight;n.LinetypeScale=v.LinetypeScale;
   var lt=(LinetypeTable)tr.GetObject(dest.LinetypeTableId,OpenMode.ForRead);Need(lt.Has(v.Linetype),"TARGET_VIEWPORT_LINETYPE_MISSING");n.LinetypeId=lt[v.Linetype];n.Visible=v.Visible;
   n.CenterPoint=v.CenterPoint+new Vector3d(offset[0],offset[1],0);n.Width=v.Width;n.Height=v.Height;n.ViewDirection=v.ViewDirection;n.ViewTarget=v.ViewTarget;n.TwistAngle=v.TwistAngle;n.ViewCenter=v.ViewCenter;n.ViewHeight=v.ViewHeight;n.CustomScale=v.CustomScale;
   var freeze=new ObjectIdCollection();foreach(ObjectId id in v.GetFrozenLayers()){var l=(LayerTableRecord)sr.GetObject(id,OpenMode.ForRead);if(layers.Has(l.Name))freeze.Add(layers[l.Name]);}if(freeze.Count>0)n.FreezeLayersInViewport(freeze.GetEnumerator());n.On=true;n.Locked=v.Locked;
   Need(n.On&&n.ViewTarget.IsEqualTo(v.ViewTarget)&&n.ViewCenter.IsEqualTo(v.ViewCenter)&&Math.Abs(n.CustomScale-v.CustomScale)<1e-9&&Math.Abs(n.TwistAngle-v.TwistAngle)<1e-9,"RESTORED_VIEWPORT_READBACK_FAILED");string handle=n.Handle.ToString();tr.Commit();return handle;
  }
 }
}
