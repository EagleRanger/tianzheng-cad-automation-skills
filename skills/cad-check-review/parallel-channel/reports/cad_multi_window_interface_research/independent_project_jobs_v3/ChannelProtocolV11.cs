using System;
using System.Collections.Generic;
using System.Linq;
using System.IO;
using CadFixedResearchV3;
namespace CadChannelV11 {
 public sealed class Boot {
  public int schema_version; public string validation_mode,run_id,owner,source_thread_id,root,session_dir,module_sha256,expires_utc,source,source_sha256,machine_sys;
  public CaseInput[] cases; public FileRef[] dependencies,machine_arx; public string[] operations;
 }
 public sealed class Request {
  public int schema_version,sequence,pid; public long created,hwnd;
  public string request_id,nonce,source_thread_id,run_id,owner,document,operation,expires_utc;
  public string id {get{return request_id;}} public string case_id {get{return "AB";}} public string stage {get{return "DISCOVER";}}
 }
 public static class ChannelProtocol {
  public const string Mode="PARALLEL_NATIVE_WRITE_ONLY";
  public const string Source="RECEIVER_SOURCE_A";
  public const string Executor="RECEIVER_SOURCE_B";
  public static void ValidateBoot(Boot b,string path,string selfHash){
   Protocol.Require(b.schema_version==10&&b.validation_mode==Mode&&b.source_thread_id==(b.owner=="A"?Source:Executor)&&b.module_sha256==selfHash,"CHANNEL_BOOT_IDENTITY");
   Protocol.Token(b.run_id);Protocol.Fresh(b.expires_utc);Protocol.Inside(b.root,b.session_dir);
   Protocol.Require(Protocol.Equal(Path.GetDirectoryName(path),b.session_dir)&&(b.owner=="A"||b.owner=="B"),"CHANNEL_BOOT_OWNER");
   Protocol.Require(b.cases!=null&&b.cases.Length==1&&b.cases[0].id=="AB","CHANNEL_AB_ONLY");
   Protocol.Require(b.operations!=null&&b.operations.Length==1&&b.operations[0]=="KNOWN_WRITE_BATCH","CHANNEL_FIXED_OPERATIONS");
   var c=b.cases[0];Protocol.Inside(b.session_dir,c.work);Protocol.Require(!Protocol.Equal(c.work,b.source)&&c.sha256==b.source_sha256,"CHANNEL_COPY_ONLY");
   Protocol.Inside(b.session_dir,c.checkpoint);Protocol.Require(!Protocol.Equal(c.checkpoint,c.work)&&!File.Exists(c.checkpoint),"CHANNEL_UNIQUE_CHECKPOINT");
   Protocol.CheckFile(new FileRef{path=b.source,sha256=b.source_sha256});Protocol.CheckFile(new FileRef{path=c.work,sha256=c.sha256});
   Protocol.Require(b.dependencies!=null&&b.dependencies.Length>=6,"CHANNEL_DEPENDENCIES");
   foreach(var f in b.dependencies){Protocol.Inside(b.root,f.path);Protocol.CheckFile(f);}
   string[] names={"tch_kernal.arx","tch_utility.arx","tch_pipewire.arx","tch_pipebase.arx","tch_initstart.arx","tch_common.arx","tch3_kernal.arx"};
   Protocol.Require(b.machine_arx!=null&&b.machine_arx.Length==7,"CHANNEL_TIANZHENG");
   for(int i=0;i<7;i++){var f=b.machine_arx[i];Protocol.Require(Protocol.Equal(f.path,Path.Combine(b.machine_sys,names[i])),"CHANNEL_ARX_PATH");Protocol.CheckFile(f);}
  }
  public static void ValidateRequest(Boot b,Request r,int pid,long created,long hwnd,int sequence){
   Protocol.Require(r.schema_version==10&&r.run_id==b.run_id&&r.owner==b.owner&&r.source_thread_id==b.source_thread_id,"CHANNEL_REQUEST_ROUTE");
   Protocol.Token(r.request_id);Protocol.Token(r.nonce);Protocol.Fresh(b.expires_utc);Protocol.Fresh(r.expires_utc);
   Protocol.Require(Protocol.Expiry(r.expires_utc)<=Protocol.Expiry(b.expires_utc),"CHANNEL_REQUEST_DEADLINE");
   Protocol.Require(r.sequence==sequence&&sequence==1&&r.operation==b.operations[0],"CHANNEL_REQUEST_SEQUENCE");
   Protocol.Require(r.pid==pid&&r.created==created&&r.hwnd==hwnd&&hwnd!=0&&Protocol.Equal(r.document,b.cases[0].work),"CHANNEL_REQUEST_EXACT_OWNER");
  }
 }
}

