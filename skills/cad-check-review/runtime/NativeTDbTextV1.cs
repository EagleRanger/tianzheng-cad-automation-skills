// Native TDbText content only. Reuse the existing writer; do not explode or replace.
using System;using System.Linq;using System.Collections.Generic;using System.Reflection;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
public static class NativeTDbTextV1 {
 public static bool Supports(Entity e){return e!=null&&e.GetRXClass().Name=="TDbText";}
 public static bool Only(BoundCadEditsV6.TextEdit[] edits){return edits!=null&&edits.Length>0&&edits.All(e=>e.type=="TDbText");}
 public sealed class Guard:IDisposable {
  readonly Database db;readonly HashSet<string> allowed;readonly HashSet<string> touched=new HashSet<string>();
  public Guard(Database database,BoundCadEditsV6.TextEdit[] edits){db=database;allowed=new HashSet<string>(edits.Select(e=>e.handle),StringComparer.OrdinalIgnoreCase);db.ObjectModified+=Modified;db.ObjectAppended+=Modified;db.ObjectErased+=Erased;}
  void Modified(object sender,ObjectEventArgs a){if((a.DBObject is Entity&&!allowed.Contains(a.DBObject.Handle.ToString()))||a.DBObject is TextStyleTableRecord||a.DBObject is LayerTableRecord)touched.Add(a.DBObject.Handle.ToString());}
  void Erased(object sender,ObjectErasedEventArgs a){if(a.Erased)touched.Add(a.DBObject.Handle.ToString());}
  public void Check(){if(touched.Count>0)throw new InvalidOperationException("TEXT_CHANGED_OTHER_OBJECTS:"+String.Join(",",touched));}
  public void Dispose(){db.ObjectModified-=Modified;db.ObjectAppended-=Modified;db.ObjectErased-=Erased;}
 }
 public static Guard Watch(Database db,BoundCadEditsV6.TextEdit[] edits){return Only(edits)?new Guard(db,edits):null;}
 static object Get(Entity e,string name){var c=e.AcadObject;return c.GetType().InvokeMember(name,BindingFlags.GetProperty,null,c,null);}
 public static string Content(Entity e){foreach(var n in new[]{"Text","TextString"}){try{var s=Get(e,n) as string;if(s!=null)return s;}catch{}}throw new InvalidOperationException("NATIVE_TEXT_CONTENT_UNAVAILABLE");}
 public static Point3d Position(Entity e){var g=new GripDataCollection();e.GetGripPoints(g,1,5,Vector3d.ZAxis,GetGripPointsFlags.GripPointsOnly);if(g.Count==0)throw new InvalidOperationException("NATIVE_TEXT_ANCHOR_UNAVAILABLE");return g[0].GripPoint;}
 public static object Snapshot(Entity e,bool content){
  if(!Supports(e))throw new InvalidOperationException("NATIVE_TDBTEXT_REQUIRED");
  var p=Position(e);var format=new SortedDictionary<string,object>();
  foreach(var key in new[]{"Height","TextHeight","Scale","LayoutRotation","TextStyle","WidthFactor","Rotation","Alignment","ObliqueAngle"}){try{format[key]=Get(e,key);}catch{}}
  if(!format.ContainsKey("TextStyle")||(!format.ContainsKey("Height")&&!format.ContainsKey("TextHeight")))throw new InvalidOperationException("NATIVE_TEXT_FORMAT_UNAVAILABLE");
  return new{type=e.GetRXClass().Name,owner=e.OwnerId.Handle.ToString(),anchor=new[]{p.X,p.Y,p.Z},text=content?Content(e):null,format,layer=e.Layer,color=e.Color.ToString(),linetype=e.Linetype,ltscale=e.LinetypeScale,lineweight=e.LineWeight,visible=e.Visible};
 }
}
