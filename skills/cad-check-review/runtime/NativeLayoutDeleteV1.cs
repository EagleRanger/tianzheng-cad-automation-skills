// Delete one explicitly named inactive paper layout using AutoCAD's layout manager.
// Migration acceptance belongs to execution/review; this module protects retained objects.
using System;using System.IO;using System.Linq;using System.Collections.Generic;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.ApplicationServices;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public partial class NativeLayoutOpsV1 {
 static bool PaperName(string s){return !String.IsNullOrWhiteSpace(s)&&!s.Equals("Model",StringComparison.OrdinalIgnoreCase)&&!s.Any(c=>Char.IsControl(c)||"*?\"<>/\\|:;=".Contains(c));}
 static string H(ObjectId id){return id.IsNull?null:id.Handle.ToString();}
 static void CheckDelete(Database db,Job j){
  Need(PaperName(j.layout)&&PaperName(j.replacement_layout)&&!j.layout.Equals(j.replacement_layout,StringComparison.OrdinalIgnoreCase),"EXACT_DISTINCT_PAPER_LAYOUTS_REQUIRED");
  var names=Layouts(db);Need(names.Contains(j.layout)&&names.Contains(j.replacement_layout),"DELETE_OR_REPLACEMENT_LAYOUT_MISSING");
  Need(!LayoutManager.Current.CurrentLayout.Equals(j.layout,StringComparison.OrdinalIgnoreCase),"ACTIVATE_REPLACEMENT_LAYOUT_BEFORE_DELETE");
  using(var tr=db.TransactionManager.StartTransaction()){var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);foreach(var name in new[]{j.layout,j.replacement_layout})Need(!((Layout)tr.GetObject(dict.GetAt(name),OpenMode.ForRead)).ModelType,"MODEL_LAYOUT_PROTECTED");}
 }
 static string RetainedState(Database db,string excluded){
  using(var tr=db.TransactionManager.StartTransaction()){
   var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);var layouts=new List<Layout>();foreach(DBDictionaryEntry e in dict)layouts.Add((Layout)tr.GetObject(e.Value,OpenMode.ForRead));var ls=layouts.Where(l=>!l.LayoutName.Equals(excluded,StringComparison.OrdinalIgnoreCase)).OrderBy(l=>l.TabOrder).ToArray();
   var result=new List<object>();foreach(var l in ls){var b=(BlockTableRecord)tr.GetObject(l.BlockTableRecordId,OpenMode.ForRead);var ids=b.Cast<ObjectId>().Where(id=>!id.IsErased).ToArray();var vv=ids.Where(id=>tr.GetObject(id,OpenMode.ForRead) is Viewport).ToArray();var known=l.GetViewports();var overall=known.Count>0?known[0]:(vv.Length>0?vv[0]:ObjectId.Null);
    result.Add(new{name=l.LayoutName,layout=H(l.ObjectId),owner=H(b.ObjectId),l.ModelType,l.PlotType,l.PlotRotation,l.PlotConfigurationName,l.CanonicalMediaName,l.CurrentStyleSheet,roots=ids.Select(H).OrderBy(h=>h,StringComparer.Ordinal).ToArray(),viewports=vv.Where(id=>id!=overall).Select(id=>new{handle=H(id),state=NativeViewportRestoreV1.State(db,H(id))}).OrderBy(v=>v.handle,StringComparer.Ordinal).ToArray()});
   }return J.Serialize(result);
  }
 }
 static object DeleteLayout(Database db,Job j,Action mutation){
  CheckDelete(db,j);var expected=RetainedState(db,j.layout);var names=Layouts(db);var allowed=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
  using(var tr=db.TransactionManager.StartTransaction()){var dict=(DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead);var l=(Layout)tr.GetObject(dict.GetAt(j.layout),OpenMode.ForRead);var b=(BlockTableRecord)tr.GetObject(l.BlockTableRecordId,OpenMode.ForRead);allowed.Add(H(b.ObjectId));foreach(ObjectId id in b){allowed.Add(H(id));var br=tr.GetObject(id,OpenMode.ForRead) as BlockReference;if(br!=null)foreach(ObjectId at in br.AttributeCollection)allowed.Add(H(at));}}
  var unexpected=new HashSet<string>();ObjectEventHandler changed=(s,a)=>{var e=a.DBObject as Entity;if(e!=null&&!allowed.Contains(H(e.ObjectId))&&!allowed.Contains(H(e.OwnerId)))unexpected.Add(H(e.ObjectId));};ObjectErasedEventHandler erased=(s,a)=>{var e=a.DBObject as Entity;if(e!=null&&!allowed.Contains(H(e.ObjectId))&&!allowed.Contains(H(e.OwnerId)))unexpected.Add(H(e.ObjectId));};
  db.ObjectModified+=changed;db.ObjectAppended+=changed;db.ObjectErased+=erased;
  try{mutation();LayoutManager.Current.DeleteLayout(j.layout);}finally{db.ObjectModified-=changed;db.ObjectAppended-=changed;db.ObjectErased-=erased;}
  Need(unexpected.Count==0,"LAYOUT_DELETE_CHANGED_RETAINED_ENTITIES:"+String.Join(",",unexpected));names.Remove(j.layout);Need(Layouts(db).SetEquals(names),"EXACT_ONE_LAYOUT_REMOVAL_REQUIRED");Need(CadValueCompareV1.Json(expected,RetainedState(db,j.layout)),"RETAINED_LAYOUT_STATE_CHANGED");
  return new{operation="layout_delete",deleted_layout=j.layout,replacement_layout=j.replacement_layout,native_api="LayoutManager.DeleteLayout",retained_model_and_paper_root_handles=true,retained_plot_and_viewport_fields=true,unselected_entity_write_guard=true,purge_performed=false,visual_review="execution_review_required"};
 }
 static void VerifyDeleted(string file,Job j,string expected){using(var saved=new Database(false,true)){saved.ReadDwgFile(file,FileOpenMode.OpenForReadAndAllShare,true,"");saved.CloseInput(true);Need(!Layouts(saved).Contains(j.layout)&&Layouts(saved).Contains(j.replacement_layout),"DELETED_LAYOUT_SAVE_REOPEN_MISMATCH");Need(CadValueCompareV1.Json(expected,RetainedState(saved,j.layout)),"RETAINED_LAYOUT_SAVE_REOPEN_MISMATCH");}}
 [CommandMethod("HLCADLAYOUTDELETETESTV2",CommandFlags.Session)]public void DeleteTest(){
  var original=App.DocumentManager.MdiActiveDocument;var old=HostApplicationServices.WorkingDatabase;var ans=original.Editor.GetString(new PromptStringOptions("Isolated layout deletion:"){AllowSpaces=true});if(ans.Status!=PromptStatus.OK)return;Job j=null;Document d=null;bool started=false;
  try{j=J.Deserialize<Job>(File.ReadAllText(ans.StringResult.Trim('"')));Need(NativeGeometryReadV1.Hash(j.input)==j.input_sha256&&!File.Exists(j.output)&&!File.Exists(j.receipt),"INPUT_OUTPUT_IDENTITY");File.Copy(j.input,j.output+".staging.dwg",false);d=App.DocumentManager.Open(j.output+".staging.dwg",false);App.DocumentManager.MdiActiveDocument=d;HostApplicationServices.WorkingDatabase=d.Database;object changes;string expected;
   using(d.LockDocument()){if(PaperName(j.layout)&&LayoutManager.Current.CurrentLayout.Equals(j.layout,StringComparison.OrdinalIgnoreCase)&&Layouts(d.Database).Contains(j.replacement_layout))LayoutManager.Current.CurrentLayout=j.replacement_layout;changes=DeleteLayout(d.Database,j,()=>started=true);expected=RetainedState(d.Database,j.layout);d.Database.SaveAs(j.output,DwgVersion.AC1032);VerifyDeleted(j.output,j,expected);}
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=old;d.CloseAndDiscard();d=null;d=App.DocumentManager.Open(j.output,true);App.DocumentManager.MdiActiveDocument=d;HostApplicationServices.WorkingDatabase=d.Database;using(d.LockDocument()){Need(!Layouts(d.Database).Contains(j.layout)&&CadValueCompareV1.Json(expected,RetainedState(d.Database,j.layout)),"REAL_REOPEN_LAYOUT_MISMATCH");}
   Write(j.receipt,new{status="ISOLATED_NATIVE_LAYOUT_DELETE_VERIFIED",output=j.output,sha256=NativeGeometryReadV1.Hash(j.output),native_save_reopen_verified=true,source_unchanged=NativeGeometryReadV1.Hash(j.input)==j.input_sha256,changes});
  }catch(System.Exception e){if(j!=null&&!File.Exists(j.receipt))Write(j.receipt,new{status=started?"LAYOUT_DELETE_TEST_FAILED":"REJECTED_BEFORE_WRITE",write_started=started,error=e.ToString()});}finally{App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=old;if(d!=null)d.CloseAndDiscard();}
 }
}
