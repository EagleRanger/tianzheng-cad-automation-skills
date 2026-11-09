using System;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;
using Job=BoundCadEditsV6.Job;
public static class EntityDisplayOpsV1 {
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=20000000};
 static void Need(bool yes,string error){if(!yes)throw new InvalidOperationException(error);}
 static double[] V(Vector3d p){return new[]{p.X,p.Y,p.Z};}static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 public static string Geometry(Entity e){
  var br=e as BlockReference;if(br!=null){Need(!br.IsDynamicBlock,"DISPLAY_DYNAMIC_CHILD_UNSUPPORTED");using(var tr=br.Database.TransactionManager.StartOpenCloseTransaction())return J.Serialize(new{kind="block_reference",definition=br.BlockTableRecord.Handle.ToString(),matrix=br.BlockTransform.ToArray(),attributes=br.AttributeCollection.Cast<ObjectId>().Select(id=>{var t=(AttributeReference)tr.GetObject(id,OpenMode.ForRead);return new{handle=t.Handle.ToString(),text=t.TextString,position=P(t.Position),height=t.Height,width=t.WidthFactor,rotation=t.Rotation,style=t.TextStyleId.Handle.ToString()};}).ToArray()});}
  var p=e as Polyline;if(p!=null){var rows=new List<object>();for(int i=0;i<p.NumberOfVertices;i++)rows.Add(new{point=P(p.GetPoint3dAt(i)),bulge=p.GetBulgeAt(i),start_width=p.GetStartWidthAt(i),end_width=p.GetEndWidthAt(i)});return J.Serialize(new{kind="polyline",vertices=rows,closed=p.Closed,elevation=p.Elevation,normal=V(p.Normal),thickness=p.Thickness,plinegen=p.Plinegen});}
  var a=e as Arc;if(a!=null)return J.Serialize(new{kind="arc",center=P(a.Center),normal=V(a.Normal),radius=a.Radius,start=a.StartAngle,end=a.EndAngle,thickness=a.Thickness});
  if(e is Line || e is Hatch)return J.Serialize(NativeGeometryReadV1.Geometry(e,false));
  throw new InvalidOperationException("DISPLAY_NATIVE_TYPE_UNSUPPORTED");
 }
 static ObjectId Id(Database db,string handle){return db.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0);}
 static BlockTableRecord Definition(Transaction tr,Database db,BoundCadEditsV6.DisplayDefinition d){
  var b=tr.GetObject(Id(db,d.handle),OpenMode.ForRead) as BlockTableRecord;
  Need(b!=null&&b.Name==d.name&&!b.IsLayout&&!b.IsFromExternalReference&&!b.IsFromOverlayReference&&!b.IsDependent&&!b.IsDynamicBlock,"DISPLAY_DEFINITION_CHANGED_OR_UNSUPPORTED:"+d.handle);
  var refs=b.GetBlockReferenceIds(false,true).Cast<ObjectId>().Select(id=>(BlockReference)tr.GetObject(id,OpenMode.ForRead)).ToArray();
  Need(d.instances!=null&&d.instances.Length>0&&d.instances.Distinct(StringComparer.OrdinalIgnoreCase).Count()==d.instances.Length,"EXACT_DEFINITION_INSTANCES_REQUIRED");
  Need(refs.Select(e=>e.Handle.ToString()).OrderBy(x=>x,StringComparer.OrdinalIgnoreCase).SequenceEqual(d.instances.OrderBy(x=>x,StringComparer.OrdinalIgnoreCase),StringComparer.OrdinalIgnoreCase),"DISPLAY_DEFINITION_REFERENCES_CHANGED:"+d.handle);
  Need(d.space==null||d.space=="model"||d.space=="paper","DISPLAY_REFERENCE_SPACE");
  Need(refs.All(e=>!e.IsDynamicBlock&&(d.space=="paper"?((BlockTableRecord)tr.GetObject(e.OwnerId,OpenMode.ForRead)).IsLayout&&e.OwnerId!=SymbolUtilityServices.GetBlockModelSpaceId(db):e.OwnerId==SymbolUtilityServices.GetBlockModelSpaceId(db))),"DISPLAY_DEFINITION_REFERENCE_SPACE_OR_DYNAMIC");return b;
 }
 static object StableEntity(Entity e,bool omitDisplay,bool omitScale=false){
  object shape=null;if(e is Polyline||e is Line||e is Arc||e is Hatch)shape=Geometry(e);else if(e is BlockReference)shape=Geometry(e);else if(e is MText){var t=(MText)e;shape=new{text=t.Contents,location=P(t.Location),height=t.TextHeight,width=t.Width,rotation=t.Rotation,style=t.TextStyleId.Handle.ToString()};}else if(e is DBText){var t=(DBText)e;shape=new{text=t.TextString,position=P(t.Position),height=t.Height,width=t.WidthFactor,rotation=t.Rotation,style=t.TextStyleId.Handle.ToString()};}else shape=BoundCadEditsV6.Bounds(e);
  return new{handle=e.Handle.ToString(),type=e.GetRXClass().Name,owner=e.OwnerId.Handle.ToString(),shape=shape,
   layer=omitDisplay?null:e.Layer,color=omitDisplay?null:e.Color.ToString(),linetype=e.Linetype,scale=omitScale?(double?)null:e.LinetypeScale,lineweight=e.LineWeight,visible=e.Visible,transparency=e.Transparency.ToString()};
 }
 public static string DefinitionSnapshot(Database db,Job job,bool omitSelectedDisplay){
  var rows=new List<object>();var selected=new HashSet<string>(job.entities.Select(x=>x.target.handle),StringComparer.OrdinalIgnoreCase);
  using(var tr=db.TransactionManager.StartTransaction())foreach(var d in job.definitions??new BoundCadEditsV6.DisplayDefinition[0]){
   var b=Definition(tr,db,d);var children=b.Cast<ObjectId>().Select(id=>(Entity)tr.GetObject(id,OpenMode.ForRead)).OrderBy(e=>e.Handle.ToString(),StringComparer.OrdinalIgnoreCase).Select(e=>StableEntity(e,omitSelectedDisplay&&selected.Contains(e.Handle.ToString()),omitSelectedDisplay&&job.entities.Any(x=>x.linetype_scale.HasValue&&String.Equals(x.target.handle,e.Handle.ToString(),StringComparison.OrdinalIgnoreCase)))).ToArray();
   var refs=b.GetBlockReferenceIds(false,true).Cast<ObjectId>().Select(id=>(Entity)tr.GetObject(id,OpenMode.ForRead)).OrderBy(e=>e.Handle.ToString(),StringComparer.OrdinalIgnoreCase).Select(e=>StableEntity(e,false)).ToArray();
   rows.Add(new{handle=b.Handle.ToString(),name=b.Name,origin=P(b.Origin),children=children,instances=refs});
  }return J.Serialize(rows);
 }
 public static object Apply(Database db,Job job,Action onMutation=null){
  Need(job.entities!=null&&job.entities.Length>0,"ENTITY_DISPLAY_REQUIRED");
  Need(job.entities.Select(x=>x.target.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==job.entities.Length,"DUPLICATE_DISPLAY_TARGET");
  var definitions=job.definitions??new BoundCadEditsV6.DisplayDefinition[0];
  Need(definitions.Select(d=>d.handle).Distinct(StringComparer.OrdinalIgnoreCase).Count()==definitions.Length,"DUPLICATE_DISPLAY_DEFINITION");
  Need(definitions.All(d=>job.entities.Any(e=>String.Equals(e.definition,d.handle,StringComparison.OrdinalIgnoreCase))),"UNUSED_DISPLAY_DEFINITION");
  var protectedBefore=DefinitionSnapshot(db,job,true);
  using(var tr=db.TransactionManager.StartTransaction()){
   var table=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);var owner=SymbolUtilityServices.GetBlockModelSpaceId(db);
   var owners=definitions.ToDictionary(d=>d.handle,d=>Definition(tr,db,d).ObjectId,StringComparer.OrdinalIgnoreCase);
   var rows=job.entities.Select(x=>{Need(String.IsNullOrEmpty(x.definition)||owners.ContainsKey(x.definition),"DISPLAY_DEFINITION_NOT_DECLARED");return BoundCadEditsV6.Checked(tr,db,x.target,String.IsNullOrEmpty(x.definition)?owner:owners[x.definition]);}).ToArray();var before=rows.Select(Geometry).ToArray();
   for(int i=0;i<rows.Length;i++)Need(rows[i].ColorIndex==job.entities[i].before_color&&job.entities[i].color>=0&&job.entities[i].color<=256&&!String.IsNullOrWhiteSpace(job.entities[i].target_layer),"DISPLAY_PRECONDITION_CHANGED");
   for(int i=0;i<rows.Length;i++){var edit=job.entities[i];Need(edit.before_linetype_scale.HasValue==edit.linetype_scale.HasValue,"LINETYPE_SCALE_BEFORE_AFTER_REQUIRED");if(edit.linetype_scale.HasValue)Need(edit.linetype_scale.Value>0&&!Double.IsInfinity(edit.linetype_scale.Value)&&!Double.IsNaN(edit.linetype_scale.Value)&&edit.before_linetype_scale.Value>0&&!Double.IsInfinity(edit.before_linetype_scale.Value)&&!Double.IsNaN(edit.before_linetype_scale.Value)&&Math.Abs(rows[i].LinetypeScale-edit.before_linetype_scale.Value)<1e-10,"LINETYPE_SCALE_PRECONDITION_OR_VALUE");}
   var protectedRows=rows.Select((e,i)=>J.Serialize(StableEntity(e,true,job.entities[i].linetype_scale.HasValue))).ToArray();var beforeScales=rows.Select(e=>e.LinetypeScale).ToArray();
   var newLayers=job.new_layers??new BoundCadEditsV6.NewLayer[0];Need(newLayers.Select(x=>x.name).Distinct(StringComparer.OrdinalIgnoreCase).Count()==newLayers.Length,"DUPLICATE_NEW_LAYER");
   foreach(var l in newLayers)Need(!table.Has(l.name)&&l.name!="0"&&l.color>=1&&l.color<=255&&job.entities.Any(x=>x.target_layer.Equals(l.name,StringComparison.OrdinalIgnoreCase)),"NEW_LAYER_SCOPE_OR_EXISTS");
   foreach(var edit in job.entities)Need(table.Has(edit.target_layer)||newLayers.Any(l=>l.name.Equals(edit.target_layer,StringComparison.OrdinalIgnoreCase)),"DISPLAY_TARGET_LAYER_MISSING");
   if(onMutation!=null)onMutation();
   if(newLayers.Length>0)table.UpgradeOpen();foreach(var l in newLayers){var layer=new LayerTableRecord{Name=l.name,Color=Autodesk.AutoCAD.Colors.Color.FromColorIndex(Autodesk.AutoCAD.Colors.ColorMethod.ByAci,l.color)};table.Add(layer);tr.AddNewlyCreatedDBObject(layer,true);}
   for(int i=0;i<rows.Length;i++){
    var row=rows[i];var layer=(LayerTableRecord)tr.GetObject(table[job.entities[i].target_layer],OpenMode.ForRead);Need(!layer.IsDependent&&!layer.IsLocked,"DISPLAY_TARGET_LAYER_DEPENDENT_OR_LOCKED");
    row.UpgradeOpen();row.LayerId=layer.ObjectId;row.ColorIndex=job.entities[i].color;if(job.entities[i].linetype_scale.HasValue)row.LinetypeScale=job.entities[i].linetype_scale.Value;Need(J.Serialize(StableEntity(row,true,job.entities[i].linetype_scale.HasValue))==protectedRows[i],"GEOMETRY_OR_PROTECTED_PROPERTY_CHANGED_BY_DISPLAY_EDIT");Need(Math.Abs(row.LinetypeScale-(job.entities[i].linetype_scale??beforeScales[i]))<1e-10,"LINETYPE_SCALE_WRITE_MISMATCH");
   }
   Need(DefinitionSnapshot(db,job,true)==protectedBefore,"DISPLAY_UNSELECTED_CHILD_OR_INSTANCE_CHANGED");
   var result=rows.Select((e,i)=>new{handle=e.Handle.ToString(),definition=job.entities[i].definition,geometry=before[i],before_layer=job.entities[i].target.layer,before_color=job.entities[i].before_color,layer=e.Layer,color=e.ColorIndex,before_linetype_scale=beforeScales[i],linetype_scale=e.LinetypeScale}).ToArray();tr.Commit();return new{entities=result,new_layers=newLayers,geometry_unchanged=true,definition_instances_and_other_children_unchanged=true};
  }
 }
}
public static class PresentationVerifyV1 {
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=50000000};
 public static string Snapshot(Database db,Job job,string kind){
  if(kind=="paper_transform")return PaperTransformOpsV1.Snapshot(db,job);
  if(kind=="viewport_freeze"||kind=="text_patch")return PresentationPatchV1.Snapshot(db,job,false);
  var rows=new List<object>();using(var tr=db.TransactionManager.StartTransaction()){
   if(kind=="entity_display")foreach(var edit in job.entities){var e=(Entity)tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(edit.target.handle,16)),0),OpenMode.ForRead);rows.Add(new{handle=e.Handle.ToString(),geometry=EntityDisplayOpsV1.Geometry(e),layer=e.Layer,color=e.ColorIndex,ltscale=e.LinetypeScale,lineweight=e.LineWeight});}
   else if(kind=="layer_patch"){var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);foreach(var edit in job.layers){var l=(LayerTableRecord)tr.GetObject(lt[edit.name],OpenMode.ForRead);rows.Add(new{name=l.Name,on=!l.IsOff,frozen=l.IsFrozen,color=l.Color.ToString()});}}
   else if(kind=="paper_note"){var space=(BlockTableRecord)tr.GetObject(BoundCadEditsV6.Space(tr,db,job.target_layout),OpenMode.ForRead);foreach(ObjectId id in space){var e=(Entity)tr.GetObject(id,OpenMode.ForRead);if(e is DBText||e is MText||e.GetRXClass().Name=="TDbText")rows.Add(new{handle=e.Handle.ToString(),kind=e.GetRXClass().Name,layer=e.Layer,text=BoundCadEditsV6.TextParts(e)});}}
   else throw new InvalidOperationException("VERIFY_KIND_UNSUPPORTED");
  }if(kind=="entity_display")rows.Add(new{definitions=EntityDisplayOpsV1.DefinitionSnapshot(db,job,false)});return J.Serialize(rows);
 }
}
