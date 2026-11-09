// Native title content adapter; no explode-and-replace. Exploded pieces below
// are transient readback used only to protect the native object's formatting.
using System;using System.Linq;using System.Collections.Generic;using System.Reflection;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
public static class NativeTitleTextV1 {
 public static bool Supports(Entity e){return e!=null&&e.GetRXClass().Name=="TDbDrawingName";}
 static void Need(bool v,string s){if(!v)throw new InvalidOperationException(s);}
 public static string Content(Entity e){Need(Supports(e),"NATIVE_DRAWING_TITLE_REQUIRED");var c=e.AcadObject;return Convert.ToString(c.GetType().InvokeMember("NameText",BindingFlags.GetProperty,null,c,null));}
 public static void Set(Entity e,string value){Need(Supports(e),"NATIVE_DRAWING_TITLE_REQUIRED");var c=e.AcadObject;c.GetType().InvokeMember("NameText",BindingFlags.SetProperty,null,c,new object[]{value});e.RecordGraphicsModified(true);}
 static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 public static GripDataCollection Grips(Entity e){var g=new GripDataCollection();e.GetGripPoints(g,1,5,Vector3d.ZAxis,GetGripPointsFlags.GripPointsOnly);Need(g.Count==2,"TITLE_TWO_NATIVE_GRIPS_REQUIRED");return g;}
 public static Point3d Position(Entity e){return Grips(e)[0].GripPoint;}
 static object Property(Entity e,string name){var c=e.AcadObject;return c.GetType().InvokeMember(name,BindingFlags.GetProperty,null,c,null);}
 static void Put(Entity e,string name,object value){var c=e.AcadObject;c.GetType().InvokeMember(name,BindingFlags.SetProperty,null,c,new[]{value});}
 static void Heights(Entity e,List<double> values,int depth){Need(depth<8,"TITLE_TEXT_DEPTH");if(e is DBText){values.Add(((DBText)e).Height);return;}if(e is MText){values.Add(((MText)e).TextHeight);return;}var pieces=new DBObjectCollection();try{e.Explode(pieces);foreach(DBObject p in pieces)if(p is Entity)Heights((Entity)p,values,depth+1);}finally{foreach(DBObject p in pieces)p.Dispose();}}
 public static double[] RenderedHeights(Entity e,int role){var pieces=new DBObjectCollection();try{e.Explode(pieces);Need(pieces.Count>=2,"TITLE_NAME_SCALE_REQUIRED");var values=new List<double>();Heights((Entity)pieces[role],values,0);Need(values.Count>0,"TITLE_TEXT_HEIGHT_MISSING");return values.ToArray();}finally{foreach(DBObject p in pieces)p.Dispose();}}
 public static object StyleSnapshot(Entity e,bool content,string nameStyle,string scaleStyle,string nameHeight,string scaleHeight){
  var props=new SortedDictionary<string,object>();foreach(var key in new[]{"NameText","NameStyle","NameHeight","ScaleText","ScaleStyle","ScaleHeight","SpaceCoef","DimStyle","TextColor","ShowScale","Scale","LayoutRotation","ObjectControl"}){
   if(!content&&(key=="NameText"||(key=="NameStyle"&&nameStyle!=null)||(key=="ScaleStyle"&&scaleStyle!=null)||(key=="NameHeight"&&nameHeight!=null)||(key=="ScaleHeight"&&scaleHeight!=null)))continue;props[key]=Property(e,key);
  }var g=Grips(e);return new{type=e.GetRXClass().Name,owner=e.OwnerId.Handle.ToString(),layer=e.Layer,color=e.Color.ToString(),visible=e.Visible,linetype=e.Linetype,ltscale=e.LinetypeScale,lineweight=e.LineWeight,anchor=P(g[0].GripPoint),scale_grip=content?P(g[1].GripPoint):null,name_render_heights=!content&&(nameHeight!=null||nameStyle!=null)?null:RenderedHeights(e,0),scale_render_heights=!content&&(scaleHeight!=null||scaleStyle!=null)?null:RenderedHeights(e,1),properties=props};
 }
 public static void SetStyles(Entity e,string nameStyle,string scaleStyle,string nameHeight,string scaleHeight,Point3d[] positions){
  Need(Supports(e),"NATIVE_DRAWING_TITLE_REQUIRED");if(nameStyle!=null)Put(e,"NameStyle",nameStyle);if(scaleStyle!=null)Put(e,"ScaleStyle",scaleStyle);if(nameHeight!=null)Put(e,"NameHeight",nameHeight);if(scaleHeight!=null)Put(e,"ScaleHeight",scaleHeight);
  for(int i=0;i<1;i++){var g=Grips(e);var delta=positions[i]-g[i].GripPoint;if(delta.Length>1e-10){var one=new GripDataCollection();one.Add(g[i]);e.MoveGripPointsAt(one,delta,(MoveGripPointsFlags)0);}}
  if(nameStyle!=null)Need(Convert.ToString(Property(e,"NameStyle"))==nameStyle,"TITLE_NAME_STYLE_WRITE_FAILED");if(scaleStyle!=null)Need(Convert.ToString(Property(e,"ScaleStyle"))==scaleStyle,"TITLE_SCALE_STYLE_WRITE_FAILED");if(nameHeight!=null)Need(Math.Abs(Convert.ToDouble(Property(e,"NameHeight"))-Double.Parse(nameHeight,System.Globalization.CultureInfo.InvariantCulture))<=0.050000001,"TITLE_NAME_HEIGHT_WRITE_FAILED");if(scaleHeight!=null)Need(Math.Abs(Convert.ToDouble(Property(e,"ScaleHeight"))-Double.Parse(scaleHeight,System.Globalization.CultureInfo.InvariantCulture))<=0.050000001,"TITLE_SCALE_HEIGHT_WRITE_FAILED");e.RecordGraphicsModified(true);
 }
 static object Piece(Entity e,bool content,int depth){
  var j=new System.Web.Script.Serialization.JavaScriptSerializer();var result=j.DeserializeObject(j.Serialize(NativeDetailsReadV2.Piece(e,depth)));
  if(!content)OmitText(result);return result;
 }
 static void OmitText(object o){var d=o as Dictionary<string,object>;if(d!=null){if(d.ContainsKey("text"))d["text"]=null;foreach(var value in d.Values.ToArray())OmitText(value);}var a=o as object[];if(a!=null)foreach(var value in a)OmitText(value);}

 static void NormalizeDerived(object o,double angle){var d=o as Dictionary<string,object>;if(d!=null){foreach(var key in d.Keys.ToArray()){if(key=="position"||key=="ocs"||key=="wcs"){var p=d[key] as object[];if(p!=null&&p.Length>=2)d[key]=new[]{-Math.Sin(angle)*Convert.ToDouble(p[0])+Math.Cos(angle)*Convert.ToDouble(p[1]),p.Length>2?Convert.ToDouble(p[2]):0};}else NormalizeDerived(d[key],angle);}}var a=o as object[];if(a!=null)foreach(var v in a)NormalizeDerived(v,angle);}
 // A Chinese/ASCII/Chinese title produces A,B,A drawing fragments. Text edits
 // may split runs; protect the set of identical rendered style profiles, not run count.
 static void DedupDerivedRuns(object o){var d=o as Dictionary<string,object>;if(d!=null){foreach(var k in d.Keys.ToArray()){DedupDerivedRuns(d[k]);if(k=="pieces"){var a=d[k] as object[];if(a!=null){var unique=new List<object>();var j=new System.Web.Script.Serialization.JavaScriptSerializer();foreach(var row in a)if(!unique.Any(x=>CadValueCompareV1.Json(j.Serialize(x),j.Serialize(row))))unique.Add(row);d[k]=unique.ToArray();}}}}var arr=o as object[];if(arr!=null)foreach(var x in arr)DedupDerivedRuns(x);}
 static double Angle(object o){var d=o as Dictionary<string,object>;if(d!=null){if(d.ContainsKey("rotation"))return Convert.ToDouble(d["rotation"]);foreach(var v in d.Values){try{return Angle(v);}catch(InvalidOperationException){}}}var a=o as object[];if(a!=null)foreach(var v in a){try{return Angle(v);}catch(InvalidOperationException){}}throw new InvalidOperationException("TITLE_TEXT_ROTATION_MISSING");}
 public static object Snapshot(Entity e,bool content){
  Need(Supports(e),"NATIVE_DRAWING_TITLE_REQUIRED");var g=Grips(e);var objects=new DBObjectCollection();try{e.Explode(objects);Need(objects.Count==3,"TITLE_NAME_SCALE_UNDERLINE_REQUIRED");var name=Piece((Entity)objects[0],content,0);var scale=Piece((Entity)objects[1],true,0);var line=Piece((Entity)objects[2],true,0);double angle=Angle(name);var pl=objects[2] as Polyline;Need(pl!=null&&pl.NumberOfVertices==2,"TITLE_NATIVE_UNDERLINE_REQUIRED");double gap=g[1].GripPoint.GetAsVector().DotProduct(new Vector3d(Math.Cos(angle),Math.Sin(angle),0))-pl.GetPoint3dAt(1).GetAsVector().DotProduct(new Vector3d(Math.Cos(angle),Math.Sin(angle),0));
   if(!content){NormalizeDerived(name,angle);DedupDerivedRuns(name);NormalizeDerived(scale,angle);NormalizeDerived(line,angle);}
   return new{type=e.GetRXClass().Name,owner=e.OwnerId.Handle.ToString(),layer=e.Layer,color=e.Color.ToString(),visible=e.Visible,linetype=e.Linetype,ltscale=e.LinetypeScale,lineweight=e.LineWeight,anchor=P(g[0].GripPoint),scale_grip=content?P(g[1].GripPoint):new[]{-Math.Sin(angle)*g[1].GripPoint.X+Math.Cos(angle)*g[1].GripPoint.Y,g[1].GripPoint.Z},name,scale,underline=line,scale_gap=gap};
  }finally{foreach(DBObject o in objects)o.Dispose();}
 }
}
