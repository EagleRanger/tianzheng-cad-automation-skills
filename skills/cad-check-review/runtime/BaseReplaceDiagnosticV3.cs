using System;using System.IO;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class BaseReplaceDiagnosticV3 {
 public class Config {public string job,job_sha256,input,input_sha256,output,receipt;}
 [CommandMethod("HLCADBASEREPLACEDIAGV3",CommandFlags.Session)]public void Run(){
  var doc=App.DocumentManager.MdiActiveDocument;var answer=doc.Editor.GetString(new PromptStringOptions("\nSide database diagnostic config: "){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  var j=new JavaScriptSerializer{MaxJsonLength=200000000};Config c=null;var originalName=doc.Name;var dbmod=App.GetSystemVariable("DBMOD");var originalTab=App.GetSystemVariable("CTAB");
  try{
   c=j.Deserialize<Config>(File.ReadAllText(answer.StringResult.Trim('"')));BaseReplaceV3.Need(BaseReplaceV3.Hash(c.job)==c.job_sha256&&!File.Exists(c.receipt)&&!File.Exists(c.output),"DIAGNOSTIC_IDENTITY");
   var job=j.Deserialize<BaseReplaceV3.Job>(File.ReadAllText(c.job));job.input=c.input;job.input_sha256=c.input_sha256;job.output=c.output;
   var result=BaseReplaceV3.Build(job);
   BaseReplaceV3.Need(doc.Name==originalName&&App.GetSystemVariable("DBMOD").Equals(dbmod)&&App.GetSystemVariable("CTAB").Equals(originalTab),"LIVE_DOCUMENT_CHANGED");
   BaseReplaceV3.Write(c.receipt,new{status="ISOLATED_PROJECT_NATIVE_VERIFIED",output=c.output,sha256=BaseReplaceV3.Hash(c.output),changes=result,live_document_unchanged=true});
  }catch(System.Exception ex){if(c!=null&&!File.Exists(c.receipt))BaseReplaceV3.Write(c.receipt,new{status="DIAGNOSTIC_FAILED",output=c.output,output_exists=File.Exists(c.output),error=ex.ToString(),live_document_unchanged=doc.Name==originalName&&App.GetSystemVariable("DBMOD").Equals(dbmod)});}
 }
}
