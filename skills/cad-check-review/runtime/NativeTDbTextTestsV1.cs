using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.ApplicationServices;using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.EditorInput;using App=Autodesk.AutoCAD.ApplicationServices.Application;
public class NativeTDbTextTestsV1 {
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=50000000};
 public class Config{public string source,source_sha256,output,receipt;}
 static void Need(bool b,string s){if(!b)throw new InvalidOperationException(s);}
 [CommandMethod("HLCADNATIVETDBTEXTTESTV4",CommandFlags.Session)]public void Run(){
  var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nTest config: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;
  var c=J.Deserialize<Config>(File.ReadAllText(a.StringResult.Trim('"')));var prior=HostApplicationServices.WorkingDatabase;var originalDoc=App.DocumentManager.MdiActiveDocument;Autodesk.AutoCAD.ApplicationServices.Document copy=null;
  try{Need(!File.Exists(c.output)&&!File.Exists(c.receipt)&&NativeGeometryReadV1.Hash(c.source)==c.source_sha256,"TEST_INPUT_OUTPUT_IDENTITY");string expected;string layout=null;var edits=new List<BoundCadEditsV6.TextEdit>();bool rejected=false;
   File.Copy(c.source,c.output+".staging.dwg",false);copy=App.DocumentManager.Open(c.output+".staging.dwg",false);App.DocumentManager.MdiActiveDocument=copy;using(copy.LockDocument()){var db=copy.Database;HostApplicationServices.WorkingDatabase=db;
    using(var tr=db.TransactionManager.StartTransaction()){
     foreach(DBDictionaryEntry de in (DBDictionary)tr.GetObject(db.LayoutDictionaryId,OpenMode.ForRead)){var l=(Layout)tr.GetObject(de.Value,OpenMode.ForRead);if(l.ModelType)continue;
      foreach(ObjectId id in (BlockTableRecord)tr.GetObject(l.BlockTableRecordId,OpenMode.ForRead)){var e=tr.GetObject(id,OpenMode.ForRead) as Entity;if(!NativeTDbTextV1.Supports(e))continue;var p=NativeTDbTextV1.Position(e);var text=NativeTDbTextV1.Content(e);edits.Add(new BoundCadEditsV6.TextEdit{handle=e.Handle.ToString(),type="TDbText",layer=e.Layer,position=new[]{p.X,p.Y,p.Z},before=text,after=edits.Count==0?"种植（1/8）":edits.Count==1?"7/8":"生态修复种植平面布置图"});if(edits.Count==3)break;}
      if(edits.Count>0){layout=l.LayoutName;break;}
     }tr.Commit();}
    Need(edits.Count==3,"THREE_NATIVE_TEXT_SAMPLES_REQUIRED");var job=new BoundCadEditsV6.Job{layout=layout,texts=edits.ToArray()};string original=PresentationPatchV1.Snapshot(db,job,false);string old=edits[2].before;edits[2].before="deliberately stale";
    try{PresentationPatchV1.Apply(db,job,"text_patch",()=>{throw new InvalidOperationException("UNEXPECTED_WRITE");});}catch(InvalidOperationException e){rejected=e.Message=="TEXT_CONTENT_CHANGED";}edits[2].before=old;Need(rejected&&CadValueCompareV1.Json(original,PresentationPatchV1.Snapshot(db,job,false)),"STALE_CONTENT_NOT_ATOMIC");
    PresentationPatchV1.Apply(db,job,"text_patch",()=>{});expected=PresentationPatchV1.Snapshot(db,job,false);db.SaveAs(c.output,DwgVersion.AC1032);
   }
   using(var saved=new Database(false,true)){saved.ReadDwgFile(c.output,FileOpenMode.OpenForReadAndAllShare,true,"");saved.CloseInput(true);HostApplicationServices.WorkingDatabase=saved;var actual=PresentationPatchV1.Snapshot(saved,new BoundCadEditsV6.Job{layout=layout,texts=edits.ToArray()},false);if(!CadValueCompareV1.Json(expected,actual))File.WriteAllText(c.receipt+".diff.json",J.Serialize(new{expected=J.DeserializeObject(expected),actual=J.DeserializeObject(actual)}));Need(CadValueCompareV1.Json(expected,actual),"NATIVE_TEXT_SAVE_REOPEN_MISMATCH");}
   Need(NativeGeometryReadV1.Hash(c.source)==c.source_sha256,"TEST_SOURCE_CHANGED");File.WriteAllText(c.receipt,J.Serialize(new{status="ISOLATED_NATIVE_TDBTEXT_VERIFIED",c.output,sha256=NativeGeometryReadV1.Hash(c.output),layout,texts=edits,native_type_anchor_format_preserved=true,stale_text_rejected_before_write=rejected,native_save_reopen_verified=true,source_unchanged=true}));
  }catch(System.Exception e){File.WriteAllText(c.receipt,J.Serialize(new{status="NATIVE_TDBTEXT_TEST_FAILED",error=e.ToString()}));}finally{App.DocumentManager.MdiActiveDocument=originalDoc;HostApplicationServices.WorkingDatabase=prior;if(copy!=null)copy.CloseAndDiscard();}
 }
}
