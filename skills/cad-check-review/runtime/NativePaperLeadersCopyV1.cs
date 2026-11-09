// Narrow reuse of native cross-database cloning: intact Tianzheng multi-leaders only.
using System;using System.IO;using System.Linq;using System.Collections.Generic;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.ApplicationServices;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public partial class NativePaperRootsCopyV1 {
 static void CheckLeaderJob(Job j){
  Need(j.source_targets!=null&&j.source_targets.Length>0&&j.source_targets.All(t=>t.type=="TDbSymbMultiLeader"),"EXACT_NATIVE_MULTILEADERS_ONLY");
  Need(j.offset!=null&&j.offset.Length==2&&j.offset.All(v=>!Double.IsNaN(v)&&!Double.IsInfinity(v)),"FINITE_PAPER_OFFSET_REQUIRED");
  Need(j.frozen_layer_pairs==null&&j.targets==null&&j.layout==null,"LEADER_COPY_ONLY_FIELDS");
 }
 static object ShiftLeaderExpected(object shape,double[] offset){
  var s=J.Deserialize<Dictionary<string,object>>(J.Serialize(shape));Need((string)s["type"]=="TDbSymbMultiLeader","EXACT_NATIVE_MULTILEADER_REQUIRED");var g=(Dictionary<string,object>)s["geometry"];var props=(Dictionary<string,object>)g["properties"];Need(props.ContainsKey("UpText")&&props.ContainsKey("DownText")&&props.ContainsKey("Height")&&props.ContainsKey("Scale")&&props.ContainsKey("LayoutRotation"),"NATIVE_LEADER_PROPERTIES_UNAVAILABLE");
  var points=((System.Collections.IEnumerable)g["grips"]).Cast<object>().ToArray();Need(points.Length>=3,"NATIVE_LEADER_GRIPS_REQUIRED");g["grips"]=points.Select(p=>{var a=((System.Collections.IEnumerable)p).Cast<object>().Select(Convert.ToDouble).ToArray();Need(a.Length==3,"THREE_DIMENSIONAL_GRIP_REQUIRED");return new[]{a[0]+offset[0],a[1]+offset[1],a[2]};}).ToArray();return s;
 }
 static void VerifyLeaderResult(Database db,Job j,Result result){
  using(var tr=db.TransactionManager.StartTransaction()){var paper=Space(db,tr,j.target_layout);foreach(var row in result.roots){var e=(Entity)tr.GetObject(Id(db,row.target_handle),OpenMode.ForRead);Need(e.OwnerId==paper&&e.GetRXClass().Name=="TDbSymbMultiLeader"&&CadValueCompareV1.Json(J.Serialize(row.shape),J.Serialize(Shape(e,tr))),"REAL_REOPEN_LEADER_MISMATCH:"+row.target_handle);}}
 }
 [CommandMethod("HLCADPAPERLEADERSTESTV1",CommandFlags.Session)]public void LeadersTest(){
  var original=App.DocumentManager.MdiActiveDocument;var old=HostApplicationServices.WorkingDatabase;var ans=original.Editor.GetString(new PromptStringOptions("Isolated paper leader copy:"){AllowSpaces=true});if(ans.Status!=PromptStatus.OK)return;Job j=null;Document d=null;bool started=false,committed=false;
  try{j=J.Deserialize<Job>(File.ReadAllText(ans.StringResult.Trim('"')));CheckLeaderJob(j);Need(NativeGeometryReadV1.Hash(j.input)==j.input_sha256&&!File.Exists(j.output)&&!File.Exists(j.receipt),"INPUT_OUTPUT_IDENTITY");File.Copy(j.input,j.output+".staging.dwg",false);d=App.DocumentManager.Open(j.output+".staging.dwg",false);App.DocumentManager.MdiActiveDocument=d;HostApplicationServices.WorkingDatabase=d.Database;Result result;
   using(d.LockDocument()){result=Copy(d.Database,j,()=>started=true,()=>committed=true);d.Editor.Regen();VerifyLeaderResult(d.Database,j,result);}
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=old;d.CloseAndDiscard();d=null;d=App.DocumentManager.Open(j.output,true);App.DocumentManager.MdiActiveDocument=d;HostApplicationServices.WorkingDatabase=d.Database;using(d.LockDocument()){VerifyLeaderResult(d.Database,j,result);}
   Write(j.receipt,new{status="ISOLATED_NATIVE_PAPER_LEADERS_VERIFIED",output=j.output,sha256=NativeGeometryReadV1.Hash(j.output),source_unchanged=NativeGeometryReadV1.Hash(j.input)==j.input_sha256&&NativeGeometryReadV1.Hash(j.source)==j.source_sha256,native_save_reopen_verified=true,changes=result,offset=j.offset,visual_review="execution_review_required"});
  }catch(System.Exception e){if(j!=null&&!File.Exists(j.receipt))Write(j.receipt,new{status=started?"PAPER_LEADER_TEST_FAILED":"REJECTED_BEFORE_WRITE",write_started=started,committed,error=e.ToString()});}finally{App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=old;if(d!=null)d.CloseAndDiscard();}
 }
}
