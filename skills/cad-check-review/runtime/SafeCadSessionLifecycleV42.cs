// Future private-desktop jobs only. Must be called from a Session command.
// Do not activate until a separate, isolated save/reopen/exit trial has passed.
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;

public static class SafeCadSessionLifecycleV42 {
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=10000000};
 static string Hash(string path){using(var h=System.Security.Cryptography.SHA256.Create())using(var f=File.Open(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))return BitConverter.ToString(h.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
 static void Receipt(string path,object data){File.WriteAllText(path,J.Serialize(data),new System.Text.UTF8Encoding(false));}
 // Close nothing unless every open document belongs to this new private process,
 // every document has a unique protected snapshot, and every snapshot reopens.
 public static bool ProtectCloseAndQuit(string expectedInput,string resultPath,string resultHash,string recoveryDirectory,string receiptPath) {
  var rows=new List<Dictionary<string,object>>();var docs=App.DocumentManager.Cast<Document>().ToArray();
  try {
   if(docs.Length<1||docs.Length>2)throw new InvalidOperationException("UNEXPECTED_DOCUMENT_COUNT");
   string expected=Path.GetFullPath(expectedInput);
   if(docs.Count(d=>String.Equals(Path.GetFullPath(d.Name),expected,StringComparison.OrdinalIgnoreCase))!=1)throw new InvalidOperationException("EXPECTED_INPUT_NOT_UNIQUE");
   foreach(var d in docs)if(!String.Equals(Path.GetFullPath(d.Name),expected,StringComparison.OrdinalIgnoreCase)&&!String.Equals(Path.GetFileName(d.Name),"Drawing1.dwg",StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("UNEXPECTED_DOCUMENT:"+d.Name);
   if(!String.IsNullOrEmpty(resultPath)){
    if(!File.Exists(resultPath)||Hash(resultPath)!=resultHash)throw new InvalidOperationException("RESULT_HASH_MISMATCH");
    using(var checkResult=new Database(false,true)){checkResult.ReadDwgFile(resultPath,FileOpenMode.OpenForReadAndAllShare,true,null);checkResult.CloseInput(true);}
    if(Hash(resultPath)!=resultHash)throw new InvalidOperationException("RESULT_HASH_CHANGED_ON_REOPEN");
   }
   Directory.CreateDirectory(recoveryDirectory);
   foreach(var d in docs){
    App.DocumentManager.MdiActiveDocument=d;var row=new Dictionary<string,object>{{"document",d.Name},{"dbmod_before",App.GetSystemVariable("DBMOD")}};rows.Add(row);
    string snapshot=Path.Combine(recoveryDirectory,"protected_"+Guid.NewGuid().ToString("N")+".dwg");
    if(File.Exists(snapshot))throw new InvalidOperationException("RECOVERY_ALREADY_EXISTS");
    using(d.LockDocument()){d.Database.SaveAs(snapshot,DwgVersion.AC1032);}
    string hash=Hash(snapshot);int roots=0;
    using(var check=new Database(false,true)){check.ReadDwgFile(snapshot,FileOpenMode.OpenForReadAndAllShare,true,null);check.CloseInput(true);using(var tr=check.TransactionManager.StartTransaction()){var bt=(BlockTable)tr.GetObject(check.BlockTableId,OpenMode.ForRead);var ms=(BlockTableRecord)tr.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);foreach(ObjectId id in ms)roots++;tr.Commit();}}
    if(Hash(snapshot)!=hash)throw new InvalidOperationException("RECOVERY_HASH_CHANGED");
    row["snapshot"]=snapshot;row["sha256"]=hash;row["model_roots"]=roots;row["separate_database_reopen_same_process"]=true;
   }
   Receipt(receiptPath,new{status="ALL_DOCUMENTS_PROTECTED_REOPENED_BEFORE_CLOSE",pid=System.Diagnostics.Process.GetCurrentProcess().Id,documents=rows,result=resultPath,result_hash=resultHash});
   EventHandler deferred=null; int busyEvents=0;
   deferred=(sender,args)=>{
    try {
     if(Convert.ToInt32(App.GetSystemVariable("CMDACTIVE"))!=0){busyEvents++;return;}
     App.Idle-=deferred;
     var live=App.DocumentManager.Cast<Document>().ToArray();
     if(live.Length!=docs.Length||docs.Any(d=>!live.Contains(d)))throw new InvalidOperationException("DOCUMENT_SET_CHANGED_AFTER_PROTECTION");
     foreach(var row in rows)if(Hash((string)row["snapshot"])!=(string)row["sha256"])throw new InvalidOperationException("SNAPSHOT_CHANGED_AFTER_PROTECTION");
     if(!String.IsNullOrEmpty(resultPath)&&Hash(resultPath)!=resultHash)throw new InvalidOperationException("RESULT_CHANGED_AFTER_PROTECTION");
     for(int i=0;i<docs.Length;i++){
      rows[i]["close_attempted"]=true;Receipt(receiptPath,new{status="CLOSE_ATTEMPT",pid=System.Diagnostics.Process.GetCurrentProcess().Id,documents=rows,busy_idle_events=busyEvents,result=resultPath,result_hash=resultHash});
      docs[i].CloseAndDiscard();rows[i]["closed"]=true;
     }
     if(App.DocumentManager.Cast<Document>().Any())throw new InvalidOperationException("DOCUMENTS_REMAIN_AFTER_CLOSE");
     Receipt(receiptPath,new{status="DOCUMENTS_CLOSED_AWAITING_ORDINARY_WINDOW_CLOSE",pid=System.Diagnostics.Process.GetCurrentProcess().Id,documents=rows,busy_idle_events=busyEvents,result=resultPath,result_hash=resultHash});
    }catch(System.Exception ex){App.Idle-=deferred;Receipt(receiptPath,new{status="HOLD_DEFERRED_CLOSE_FAILED",pid=System.Diagnostics.Process.GetCurrentProcess().Id,error=ex.ToString(),documents=rows,busy_idle_events=busyEvents,result=resultPath,result_hash=resultHash});}
   };
   App.Idle+=deferred;
   Receipt(receiptPath,new{status="DOCUMENTS_PROTECTED_DEFERRED_IDLE_REGISTERED",pid=System.Diagnostics.Process.GetCurrentProcess().Id,documents=rows,result=resultPath,result_hash=resultHash});
   return true;
  } catch(System.Exception e) {
   Receipt(receiptPath,new{status="HOLD_NO_QUIT_PROTECTION_OR_CLOSE_INCOMPLETE",pid=System.Diagnostics.Process.GetCurrentProcess().Id,error=e.ToString(),documents=rows,result=resultPath,result_hash=resultHash});return false;
  }
 }
}
