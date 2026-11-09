// Narrow post-base operations; source/target pairing remains engineering input.
using System;using System.Linq;using System.Collections.Generic;using System.Reflection;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
public static class BoundViewportOpsV5 {
 static void Need(bool ok,string why){if(!ok)throw new InvalidOperationException(why);}
 static object Get(object obj,string name){return obj.GetType().InvokeMember(name,BindingFlags.GetProperty,null,obj,null);}
 static void Put(object obj,string name,object value){obj.GetType().InvokeMember(name,BindingFlags.SetProperty,null,obj,new[]{value});}
 public static void SetNativeText(Entity e,string text){
  Need(!String.IsNullOrEmpty(text)&&!text.Any(c=>Char.IsControl(c)),"SINGLE_PLAIN_NOTE_REQUIRED");
  if(e is DBText){((DBText)e).TextString=text;return;}
  if(e is MText){((MText)e).Contents=text;return;}
  Need(e.GetRXClass().Name=="TDbText","NATIVE_TEXT_TYPE_REQUIRED");
  object obj=e.AcadObject;string property=null;
  foreach(string name in new[]{"Text","TextString"}){try{if(Get(obj,name) is string){property=name;break;}}catch{}}
  Need(property!=null,"TCH_WRITABLE_TEXT_PROPERTY_NOT_FOUND");Put(obj,property,text);
  Need(Convert.ToString(Get(obj,property))==text,"NATIVE_TEXT_WRITE_NOT_PERSISTED");
 }
 static string Window(Viewport v){return String.Join("|",new[]{v.CenterPoint.ToString(),v.Width.ToString("R"),v.Height.ToString("R"),v.NonRectClipEntityId.ToString(),v.NonRectClipOn.ToString(),v.Locked.ToString()});}
 static string[] Frozen(Viewport v){return v.GetFrozenLayers().Cast<ObjectId>().Where(id=>!id.IsErased).Select(id=>id.Handle.ToString()).OrderBy(x=>x,StringComparer.Ordinal).ToArray();}
 static object Camera(Viewport v){return new{target=new[]{v.ViewTarget.X,v.ViewTarget.Y,v.ViewTarget.Z},direction=new[]{v.ViewDirection.X,v.ViewDirection.Y,v.ViewDirection.Z},center=new[]{v.ViewCenter.X,v.ViewCenter.Y},scale=v.CustomScale,twist=v.TwistAngle};}
 public static object Apply(Database source,Database dest,BoundCadEditsV6.Job job,string kind){
  Need(job.pairs!=null&&job.pairs.Length>0&&job.source_layout!="Model"&&job.target_layout!="Model","VIEWPORT_PAIRS_REQUIRED");
  Need(job.pairs.Select(p=>p.target.handle.ToUpperInvariant()).Distinct().Count()==job.pairs.Length,"DUPLICATE_TARGET_VIEWPORT");
  var rows=new List<object>();
  using(var sr=source.TransactionManager.StartTransaction())using(var tr=dest.TransactionManager.StartTransaction()){
   var so=BoundCadEditsV6.Space(sr,source,job.source_layout);var to=BoundCadEditsV6.Space(tr,dest,job.target_layout);
   var sourceLayers=(LayerTable)sr.GetObject(source.LayerTableId,OpenMode.ForRead);var targetLayers=(LayerTable)tr.GetObject(dest.LayerTableId,OpenMode.ForRead);
   if(kind=="viewport_layers"){
    Need(job.layer_pairs!=null&&job.layer_pairs.Length>0&&job.protected_layers!=null,"LAYER_MAPPING_AND_PROTECTION_REQUIRED");
    Need(job.layer_pairs.Select(p=>p.target.ToUpperInvariant()).Distinct().Count()==job.layer_pairs.Length,"DUPLICATE_TARGET_LAYER");
    Need(!job.layer_pairs.Any(p=>job.protected_layers.Contains(p.target,StringComparer.OrdinalIgnoreCase)),"PROTECTED_PLANT_LAYER_SELECTED");
   }
   foreach(var pair in job.pairs){
    var a=BoundCadEditsV6.Checked(sr,source,pair.source,so) as Viewport;var b=BoundCadEditsV6.Checked(tr,dest,pair.target,to) as Viewport;
    Need(a!=null&&b!=null,"NATIVE_VIEWPORT_REQUIRED");string window=Window(b);string[] frozen=Frozen(b);var before=Camera(b);b.UpgradeOpen();
    if(kind=="viewport_camera"){
     bool locked=b.Locked;b.Locked=false;b.ViewDirection=a.ViewDirection;b.ViewTarget=a.ViewTarget;b.TwistAngle=a.TwistAngle;b.ViewCenter=a.ViewCenter;b.CustomScale=a.CustomScale;b.Locked=locked;
     Need(Frozen(b).SequenceEqual(frozen),"CAMERA_CHANGED_LAYER_FREEZE");
    }else {
     var sourceFrozen=new HashSet<ObjectId>(a.GetFrozenLayers().Cast<ObjectId>());
     foreach(var layer in job.layer_pairs){
      Need(sourceLayers.Has(layer.source)&&targetLayers.Has(layer.target),"LAYER_MAPPING_NOT_FOUND:"+layer.source+"->"+layer.target);
      var sl=(LayerTableRecord)sr.GetObject(sourceLayers[layer.source],OpenMode.ForRead);var tl=(LayerTableRecord)tr.GetObject(targetLayers[layer.target],OpenMode.ForWrite);
      bool off=tl.IsOff,globallyFrozen=tl.IsFrozen;var ids=new ObjectIdCollection(new[]{tl.ObjectId});
      if(layer.frozen??sourceFrozen.Contains(sl.ObjectId))b.FreezeLayersInViewport(ids.GetEnumerator());else b.ThawLayersInViewport(ids.GetEnumerator());
      var from=sl.GetViewportOverrides(a.ObjectId);var into=tl.GetViewportOverrides(b.ObjectId);into.RemoveOverrides();
      if(layer.color.HasValue){Need(layer.color.Value>=0&&layer.color.Value<=256,"INVALID_VIEWPORT_COLOR");into.Color=Autodesk.AutoCAD.Colors.Color.FromColorIndex(Autodesk.AutoCAD.Colors.ColorMethod.ByAci,layer.color.Value);}else if(from.IsColorOverridden)into.Color=from.Color;
      if(from.IsLineWeightOverridden)into.LineWeight=from.LineWeight;
      if(from.IsTransparencyOverridden)into.Transparency=from.Transparency;
      if(from.IsLinetypeOverridden){
       var map=new IdMapping();source.WblockCloneObjects(new ObjectIdCollection(new[]{from.LinetypeObjectId}),dest.LinetypeTableId,map,DuplicateRecordCloning.MangleName,false);Need(map.Contains(from.LinetypeObjectId),"OVERRIDE_LINETYPE_CLONE_MISSING");into.LinetypeObjectId=map[from.LinetypeObjectId].Value;
      }
      Need(!from.IsPlotStyleOverridden,"NAMED_PLOT_STYLE_OVERRIDE_REQUIRES_EXPLICIT_MAPPING");
      Need(off==tl.IsOff&&globallyFrozen==tl.IsFrozen,"VIEWPORT_CHANGED_GLOBAL_LAYER_STATE");
     }
    }
    Need(Window(b)==window,"VIEWPORT_PAPER_WINDOW_OR_LOCK_CHANGED");rows.Add(new{source=pair.source.handle,target=pair.target.handle,before=before,after=Camera(b),frozen_before=frozen,frozen_after=Frozen(b),paper_window_preserved=true});
   }
   tr.Commit();sr.Commit();
  }return new{operation=kind,viewports=rows};
 }
}
