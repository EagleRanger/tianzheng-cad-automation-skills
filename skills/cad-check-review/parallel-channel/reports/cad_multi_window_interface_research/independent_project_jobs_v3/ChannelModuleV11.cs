using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;
using App=Autodesk.AutoCAD.ApplicationServices.Application;

using CadFixedResearchV3;
namespace CadChannelV11 {
 public sealed class ResearchModule : IExtensionApplication {
  static Boot boot; static string dir; static Request pending; static string pendingHash;
  static Document target; static bool blocked,busy; static DateTimeOffset runtimeExpiry; static readonly Dictionary<string,int> next=new Dictionary<string,int>();
  static string bootIdentityPath,bootIdentityHash; static bool bootAccepted;
  static string handlerStarted;static Stopwatch bodyClock;
  static readonly List<object> writeWindows=new List<object>();static string writeFirstUtc,writeLastUtc;
  static object verifiedCheckpoint;
  static int pendingBefore=-1;
  static readonly Dictionary<string,int> preparedDbmod=new Dictionary<string,int>(StringComparer.OrdinalIgnoreCase);
  static void BootNotice(string name,object value){try{Protocol.NewJson(Leaf(name+"_"+Guid.NewGuid().ToString("N")+".json"),value);}catch{blocked=true;}}
  static readonly Process process=Process.GetCurrentProcess(); static long hwnd;
  static string Leaf(string name){return Path.Combine(dir,name);}
  static string Root(string relative){return Path.Combine(boot.root,relative.Replace('/',Path.DirectorySeparatorChar));}
  static void Event(string name){
   Protocol.Require(pending!=null,"EVENT_WITHOUT_TASK");
   File.AppendAllText(Leaf(pending.id+".events.jsonl"),Protocol.Json.Serialize(new {event_name=name,utc=DateTimeOffset.UtcNow.ToString("o"),run_id=pending.run_id,owner=pending.owner,case_id=pending.case_id,operation_id=pending.id,nonce=pending.nonce,source_thread_id=pending.source_thread_id,request_id=pending.request_id,operation=pending.operation,task_sha256=pendingHash})+"\n",new UTF8Encoding(false));
  }
  public void Initialize(){} public void Terminate(){App.Idle-=Pump;}
  [CommandMethod("CXRESEARCHBOOTV3",CommandFlags.Session)] public void Start(){
   string path=Environment.GetEnvironmentVariable("CX_RESEARCH_BOOT_V3");
   if(String.IsNullOrEmpty(path))throw new InvalidOperationException("BOOT_ENV_REQUIRED");
   // Identity-bound reentry never overwrites first evidence or queues work.
   string full=Path.GetFullPath(path),expected=Environment.GetEnvironmentVariable("CX_RESEARCH_BOOT_SHA256_V3");
   if(boot!=null){
    try{Protocol.Require(bootAccepted&&Protocol.Equal(full,bootIdentityPath)&&expected==bootIdentityHash&&Protocol.Hash(full)==bootIdentityHash,"BOOT_REENTRY_IDENTITY");BootNotice("boot_reentry",new {event_name="REENTRY_IGNORED",run_id=boot.run_id,owner=boot.owner,utc=DateTimeOffset.UtcNow.ToString("o")});}
    catch(System.Exception ex){blocked=true;BootNotice("boot_reentry_error",new {status="BLOCKED_NO_REPLAY",error=ex.Message,utc=DateTimeOffset.UtcNow.ToString("o")});}
    return;
   }
   dir=Path.GetDirectoryName(full);
   try{
    Protocol.Require(!File.Exists(Leaf("boot_entry.json")),"BOOT_MARKER_EXISTS_NO_REPLAY");
    Protocol.Require(Protocol.Hash(full)==expected,"BOOT_HASH");
    Protocol.NewJson(Leaf("boot_entry.json"),new {event_name="BOOT_ENTRY",utc=DateTimeOffset.UtcNow.ToString("o")});
    bootIdentityPath=full;bootIdentityHash=expected;
    boot=Protocol.Read<Boot>(path);ChannelProtocol.ValidateBoot(boot,path,Protocol.Hash(Assembly.GetExecutingAssembly().Location));bootAccepted=true;
    // Reuse mature ResolveTerrain's fixed Tianzheng module admission only;
    // no terrain, xref, engineering boot or production document is fabricated.
    object acad=App.AcadApplication;
    for(int i=1;i<boot.machine_arx.Length;i++){
     var arx=boot.machine_arx[i];Protocol.NewJson(Leaf("arx_"+i+"_enter.json"),new {path=arx.path,sha256=arx.sha256,utc=DateTimeOffset.UtcNow.ToString("o")});
     acad.GetType().InvokeMember("LoadArx",BindingFlags.InvokeMethod,null,acad,new object[]{arx.path});
     Protocol.NewJson(Leaf("arx_"+i+"_return.json"),new {path=arx.path,utc=DateTimeOffset.UtcNow.ToString("o")});
    }
    runtimeExpiry=DateTimeOffset.UtcNow.AddSeconds(420);hwnd=App.MainWindow.Handle.ToInt64();Protocol.Require(hwnd!=0,"NATIVE_HWND");
    foreach(var c in boot.cases)next.Add(c.id,0);
    Protocol.NewJson(Leaf("native_ready.json"),new {status="READY_NATIVE_QUEUE",run_id=boot.run_id,owner=boot.owner,pid=process.Id,created=process.StartTime.ToFileTimeUtc(),image=process.MainModule.FileName,hwnd=hwnd,module_sha256=boot.module_sha256,utc=DateTimeOffset.UtcNow.ToString("o")});
    App.Idle+=Pump;
   }catch(System.Exception ex){blocked=true;BootNotice("boot_failed",new {status="BOOT_FAILED_NO_REPLAY",error=ex.ToString(),utc=DateTimeOffset.UtcNow.ToString("o")});}
  }
  static void Pump(object sender,EventArgs args){
   if(blocked||busy||boot==null)return;
   if(DateTimeOffset.UtcNow>=Protocol.Expiry(boot.expires_utc)||DateTimeOffset.UtcNow>=runtimeExpiry){App.Idle-=Pump;return;}
   string queue=Leaf("request.json");if(!File.Exists(queue))return;
   busy=true;
   try{
    var reference=Protocol.Read<FileRef>(queue);Protocol.Inside(Path.Combine(dir,"tasks"),reference.path);Protocol.CheckFile(reference);
    var t=Protocol.Read<Request>(reference.path);Protocol.Token(t.id);
    ChannelProtocol.ValidateRequest(boot,t,process.Id,process.StartTime.ToFileTimeUtc(),hwnd,next[t.case_id]+1);
    Protocol.Require(t.case_id==boot.cases[0].id,"CASE_SEQUENCE");
    // A durable, non-overwriting claim precedes the only internal dispatch.
    Protocol.NewJson(Leaf(t.id+".claim.json"),new {task_path=reference.path,task_sha256=reference.sha256,run_id=boot.run_id,owner=boot.owner,operation_id=t.id,utc=DateTimeOffset.UtcNow.ToString("o")});
    File.Move(queue,Leaf(t.id+".accepted.json"));pending=t;pendingHash=reference.sha256;pendingBefore=-1;handlerStarted=null;bodyClock=null;writeWindows.Clear();writeFirstUtc=null;writeLastUtc=null;verifiedCheckpoint=null;Event("TASK_ACCEPTED");
    var c=boot.cases[0];
    if(t.stage=="DISCOVER"){
     if(target==null){Protocol.CheckFile(new FileRef{path=c.work,sha256=c.sha256});target=App.DocumentManager.Open(c.work,false);}App.DocumentManager.MdiActiveDocument=target;
    }
    Protocol.Require(target!=null&&Protocol.Equal(target.Name,c.work),"TARGET_DOCUMENT");
    // Same document-context mechanism as the mature resident module. No external COM sender.
    // The fixed native command runs inside this exact document. The external
    // source submits only a hash-bound request file, never command text.
    target.SendStringToExecute("CXRESEARCHSTEPV3\n",true,false,false);
   }catch(System.Exception ex){
    blocked=true;Protocol.NewJson(Leaf("intake_failed_"+Guid.NewGuid().ToString("N")+".json"),new {status="INTAKE_STOPPED_NO_RESEND",error=ex.ToString(),pending=pending==null?null:pending.id});busy=false;
   }
  }
  static void Bind(){
   Protocol.Require(DateTimeOffset.UtcNow<runtimeExpiry,"NATIVE_RUNTIME_EXPIRED");
   ChannelProtocol.ValidateRequest(boot,pending,process.Id,process.StartTime.ToFileTimeUtc(),hwnd,next[pending.case_id]+1);
   Protocol.Require(Protocol.Hash(Path.Combine(dir,"tasks",pending.id+".task.json"))==pendingHash,"TASK_CHANGED");
   Protocol.Require(App.MainWindow.Handle.ToInt64()==hwnd&&App.DocumentManager.MdiActiveDocument==target&&Protocol.Equal(target.Name,pending.document),"ACTUAL_NATIVE_DOCUMENT");
   foreach(var f in boot.dependencies)Protocol.CheckFile(f);
   Protocol.CheckFile(new FileRef{path=boot.source,sha256=boot.source_sha256});Event("IDENTITY_BOUND");
   if(pending.stage=="DISCOVER"){
    int tile=Convert.ToInt32(App.GetSystemVariable("TILEMODE")),dbmod=Convert.ToInt32(App.GetSystemVariable("DBMOD")),count=Count(target.Database);
    // Fresh Tianzheng opens may already be dirty (run112: DBMOD=1).
    // Preserve that observed baseline; never clear DBMOD to manufacture cleanliness.
    Protocol.NewJson(Leaf(pending.id+".space_preparation_before.json"),new {tilemode=tile,dbmod=dbmod,model_count=count,utc=DateTimeOffset.UtcNow.ToString("o")});
    if(tile!=1)App.SetSystemVariable("TILEMODE",1);
    Protocol.Require(Convert.ToInt32(App.GetSystemVariable("TILEMODE"))==1&&Count(target.Database)==count,"MODEL_PREPARATION_CHANGED_CONTENT");
    preparedDbmod[pending.document]=Convert.ToInt32(App.GetSystemVariable("DBMOD"));
    Protocol.NewJson(Leaf(pending.id+".space_preparation.json"),new {tilemode_before=tile,tilemode_after=1,dbmod_before=dbmod,dbmod_after=preparedDbmod[pending.document],model_count_before=count,model_count_after=count,preparation="EXISTING_DISCOVER_MODELSPACE_SETUP",utc=DateTimeOffset.UtcNow.ToString("o")});
   }
   Protocol.Require(Convert.ToInt32(App.GetSystemVariable("TILEMODE"))==1,"MODELSPACE_REQUIRED_AFTER_PREPARATION");
  }
  static int Count(Database database){using(var t=database.TransactionManager.StartOpenCloseTransaction()){var bt=(BlockTable)t.GetObject(database.BlockTableId,OpenMode.ForRead);return ((BlockTableRecord)t.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead)).Cast<ObjectId>().Count();}}
  static string LayerName(){return "CX_AB_WRITE_"+boot.run_id+"_"+boot.owner;}
  static string[] Snapshot(Database db,string layer){
   var rows=new List<string>();var indices=new HashSet<int>();double x=boot.owner=="A"?10000.0:20000.0;
   using(var tx=db.TransactionManager.StartOpenCloseTransaction()){
    var bt=(BlockTable)tx.GetObject(db.BlockTableId,OpenMode.ForRead);
    var model=(BlockTableRecord)tx.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForRead);
    foreach(ObjectId id in model){
     var entity=(Entity)tx.GetObject(id,OpenMode.ForRead);if(!String.Equals(entity.Layer,layer,StringComparison.OrdinalIgnoreCase))continue;
     var line=entity as Line;Protocol.Require(line!=null,"WRITE_NATIVE_LINE_CLASS");
     var a=line.StartPoint;var b=line.EndPoint;int index=(int)a.Y;
     Protocol.Require(index>=0&&index<1024&&a.X==x&&a.Y==index&&a.Z==0&&b.X==x+10&&b.Y==index&&b.Z==0&&indices.Add(index),"WRITE_NATIVE_LINE_GEOMETRY");
     rows.Add(index.ToString("D4",CultureInfo.InvariantCulture)+"|"+line.Handle.ToString());
    }
   }
   Protocol.Require(rows.Count==1024&&indices.Count==1024,"WRITE_EXACT_ENTITY_SET");
   rows.Sort(StringComparer.Ordinal);return rows.ToArray();
  }
  static object WriteAndSave(int before){
   var c=boot.cases[0];string layer=LayerName();string other=boot.owner=="A"?"B":"A";
   Protocol.Require(!File.Exists(c.checkpoint)&&Protocol.Equal(target.Name,pending.document),"WRITE_EXACT_NEW_CHECKPOINT");
   using(var tx=target.Database.TransactionManager.StartOpenCloseTransaction()){
    var layers=(LayerTable)tx.GetObject(target.Database.LayerTableId,OpenMode.ForRead);
    Protocol.Require(!layers.Has(layer),"WRITE_TEST_LAYER_ALREADY_EXISTS");
   }
   string otherReady=Path.Combine(boot.root,"runs",boot.run_id,"hosts",other,"write_ready.json");
   Protocol.Inside(boot.root,otherReady);
   Protocol.NewJson(Leaf("write_ready.json"),new {run_id=boot.run_id,owner=boot.owner,source_thread_id=pending.source_thread_id,request_id=pending.request_id,pid=process.Id,created=process.StartTime.ToFileTimeUtc(),utc=DateTimeOffset.UtcNow.ToString("o")});
   Event("WAIT_OTHER_NATIVE_READY");var barrier=Stopwatch.StartNew();
   while(!File.Exists(otherReady)&&barrier.Elapsed.TotalSeconds<25)Thread.Sleep(10);
   Protocol.Require(File.Exists(otherReady),"OTHER_NATIVE_READY_TIMEOUT_NO_WRITE");
   var otherEvidence=Protocol.Json.DeserializeObject(File.ReadAllText(otherReady)) as Dictionary<string,object>;
   Protocol.Require(otherEvidence!=null&&(string)otherEvidence["run_id"]==boot.run_id&&(string)otherEvidence["owner"]==other&&(string)otherEvidence["source_thread_id"]==(other=="A"?ChannelProtocol.Source:ChannelProtocol.Executor)&&(string)otherEvidence["request_id"]=="AB_"+other+"_SEQUENCE_1","OTHER_NATIVE_READY_ROUTE");
   Protocol.Require(Protocol.Hash(Path.Combine(dir,"tasks",pending.id+".task.json"))==pendingHash&&App.DocumentManager.MdiActiveDocument==target,"WRITE_STILL_EXACT_TASK_DOCUMENT");
   Event("NATIVE_WRITE_BEGIN");int n=0;double x=boot.owner=="A"?10000.0:20000.0;
   for(int batch=0;batch<64;batch++){
    string started=DateTimeOffset.UtcNow.ToString("o");
    using(var tx=target.Database.TransactionManager.StartTransaction()){
     var layers=(LayerTable)tx.GetObject(target.Database.LayerTableId,OpenMode.ForRead);ObjectId layerId;
     if(batch==0){layers.UpgradeOpen();var record=new LayerTableRecord{Name=layer};layerId=layers.Add(record);tx.AddNewlyCreatedDBObject(record,true);}
     else {Protocol.Require(layers.Has(layer),"WRITE_LAYER_LOST");layerId=layers[layer];}
     var bt=(BlockTable)tx.GetObject(target.Database.BlockTableId,OpenMode.ForRead);
     var model=(BlockTableRecord)tx.GetObject(bt[BlockTableRecord.ModelSpace],OpenMode.ForWrite);
     for(int j=0;j<16;j++){
      int index=batch*16+j;var line=new Line(new Point3d(x,index,0),new Point3d(x+10,index,0));line.LayerId=layerId;
      model.AppendEntity(line);tx.AddNewlyCreatedDBObject(line,true);n++;
     }
     tx.Commit();
    }
    string ended=DateTimeOffset.UtcNow.ToString("o");if(batch==0)writeFirstUtc=started;writeLastUtc=ended;
    writeWindows.Add(new {batch=batch+1,start_utc=started,end_utc=ended});
   }
   Protocol.Require(n==1024&&Count(target.Database)==before+1024,"WRITE_EXACT_MODEL_DELTA");
   var live=Snapshot(target.Database,layer);Event("NATIVE_WRITE_END");
   Protocol.Require(!File.Exists(c.checkpoint),"WRITE_CHECKPOINT_EXISTS");
   target.Database.SaveAs(c.checkpoint,DwgVersion.AC1032);
   string sha=Protocol.Hash(c.checkpoint);string[] saved;
   using(var db=new Database(false,true)){db.ReadDwgFile(c.checkpoint,FileOpenMode.OpenForReadAndAllShare,true,null);db.CloseInput(true);Protocol.Require(Count(db)==before+1024,"WRITE_SAVED_MODEL_DELTA");saved=Snapshot(db,layer);}
   Protocol.Require(live.SequenceEqual(saved)&&Protocol.Hash(c.checkpoint)==sha,"WRITE_INDEPENDENT_READBACK");
   Protocol.CheckFile(new FileRef{path=boot.source,sha256=boot.source_sha256});
   // The open work DWG is held by this CAD process; verify its unchanged disk
   // hash after the owned host exits, rather than attempting a second open now.
   verifiedCheckpoint=new {path=c.checkpoint,sha256=sha,readback="INDEPENDENT_DATABASE_EXACT_1024_NATIVE_LINES_AND_HANDLES",entity_count=1024,layer=layer};
   Event("SAVE_REOPEN_VERIFIED");
   return verifiedCheckpoint;
  }
  static void Settle(int before,int after,object saved,System.Exception failure){
   string status=failure==null?"COMPLETED":"HANDLER_ERROR";
   if(failure!=null){blocked=true;try{Event("ERROR");}catch{}}
   else next[pending.case_id]++;
   Protocol.NewJson(Leaf(pending.id+".result.json"),new {status=status,error=failure==null?null:failure.ToString(),run_id=boot.run_id,owner=boot.owner,case_id=pending.case_id,operation_id=pending.id,request_id=pending.request_id,source_thread_id=pending.source_thread_id,operation=pending.operation,sequence=pending.sequence,nonce=pending.nonce,task_sha256=pendingHash,pid=process.Id,created=process.StartTime.ToFileTimeUtc(),hwnd=hwnd,document=pending.document,actual_document_after_save=target==null?null:target.Name,before=before,after=after,handler_started_utc=handlerStarted,write_first_utc=writeFirstUtc,write_last_utc=writeLastUtc,write_batches=writeWindows.ToArray(),checkpoint=saved,write_entity_count=before>=0&&after>=before?after-before:0,elapsed_handler_ms=bodyClock==null?0:bodyClock.ElapsedMilliseconds,utc=DateTimeOffset.UtcNow.ToString("o")});
   pending=null;pendingHash=null;pendingBefore=-1;busy=false;App.Idle-=Pump;
  }
  [CommandMethod("CXRESEARCHSTEPV3",CommandFlags.Modal)] public void Step(){
   if(pending==null||blocked)return;
   Event("ENTRY");int before=-1;
   try{
    Bind();before=Count(target.Database);pendingBefore=before;
    Protocol.Require(before>0&&preparedDbmod.ContainsKey(pending.document)&&Convert.ToInt32(App.GetSystemVariable("DBMOD"))==preparedDbmod[pending.document],"WRITE_MODEL_PREPARATION");
    bodyClock=Stopwatch.StartNew();handlerStarted=DateTimeOffset.UtcNow.ToString("o");
    Protocol.NewJson(Leaf(pending.id+".handler_started.json"),new {request_id=pending.request_id,source_thread_id=pending.source_thread_id,owner=boot.owner,utc=handlerStarted});
    Event("BODY_ENTRY");object saved=WriteAndSave(before);int after=Count(target.Database);
    Protocol.Require(after==before+1024,"WRITE_POST_SAVE_MODEL_DELTA");Event("BODY_EXIT");Settle(before,after,saved,null);
   }catch(System.Exception ex){int observed=-1;try{if(target!=null)observed=Count(target.Database);}catch{}Settle(before,observed,verifiedCheckpoint,ex);}
  }
 }
}


