// Reuse V703 NativeDetails: native grips + COM values, no mutation or save.
using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Reflection;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;using Autodesk.AutoCAD.ApplicationServices;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class NativeDetailsReadV2 {
 public class Host{public int pid;public long created;public string image;}
 public class Manifest{public string request,request_sha256,loaded_dll,loaded_dll_sha256,session_dir;public Host host;}
 public class Request{public string kind,job_path,job_sha256;}
 public class Job{public string input,input_sha256,receipt;public string[] handles,layers;}
 public class TestJob{public string source,source_sha256,receipt,kind;public string[] handles,layers;}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=50000000};
 static readonly BindingFlags F=BindingFlags.NonPublic|BindingFlags.Static;
 static void Need(bool b,string s){if(!b)throw new InvalidOperationException(s);}
 static bool Eq(string a,string b){return String.Equals(Path.GetFullPath(a),Path.GetFullPath(b),StringComparison.OrdinalIgnoreCase);}
 static object Get(Type t,string n){return t.GetField(n,F).GetValue(null);}static object Call(Type t,string n,params object[] a){return t.GetMethod(n,F).Invoke(null,a);}
 static double[] P(Point3d p){return new[]{p.X,p.Y,p.Z};}
 static void Write(string path,object o){using(var f=new FileStream(path,FileMode.CreateNew))using(var w=new StreamWriter(f,new System.Text.UTF8Encoding(false)))w.Write(J.Serialize(o));}
 static object Font(ObjectId id){
  try{if(id.IsNull||!id.IsValid||id.IsErased||id.Database==null)return new{status="UNKNOWN",reason="TEXT_STYLE_ID_UNAVAILABLE"};
   using(var tr=id.Database.TransactionManager.StartOpenCloseTransaction()){var s=tr.GetObject(id,OpenMode.ForRead) as TextStyleTableRecord;if(s==null)return new{status="UNKNOWN",reason="TEXT_STYLE_RECORD_UNAVAILABLE"};return new{status="READ",handle=s.Handle.ToString(),name=s.Name,font_file=s.FileName,big_font_file=s.BigFontFileName};}
  }catch(System.Exception ex){return new{status="UNKNOWN",reason=ex.Message};}
 }
 public static object Piece(Entity e,int depth){
  if(e is DBText){var p=(DBText)e;return new{type=e.GetRXClass().Name,text=p.TextString,position=P(p.Position),height=p.Height,width_factor=p.WidthFactor,rotation=p.Rotation,text_style=Font(p.TextStyleId),explode_depth=depth};}
  if(e is MText){var p=(MText)e;return new{type=e.GetRXClass().Name,text=p.Contents,position=P(p.Location),height=p.TextHeight,width=p.Width,rotation=p.Rotation,text_style=Font(p.TextStyleId),explode_depth=depth};}
  try{return new{type=e.GetRXClass().Name,geometry=NativeGeometryReadV1.Geometry(e,false)};}
  catch(NotSupportedException){
   if(depth>=5)return new{type=e.GetRXClass().Name,status="UNEXPANDED"};
   var os=new DBObjectCollection();var rows=new List<object>();try{e.Explode(os);foreach(DBObject o in os){var child=o as Entity;if(child!=null)rows.Add(Piece(child,depth+1));}}finally{foreach(DBObject o in os)o.Dispose();}
   return new{type=e.GetRXClass().Name,pieces=rows};
  }
 }
 public static object ReadViewports(Database db,string[] handles,string[] names){
  Need(handles!=null&&handles.Length>0&&names!=null&&names.Length>0,"VIEWPORT_HANDLES_AND_LAYERS_REQUIRED");var rows=new List<object>();var missing=new List<string>();
  using(var tr=db.TransactionManager.StartTransaction()){
   var lt=(LayerTable)tr.GetObject(db.LayerTableId,OpenMode.ForRead);foreach(var name in names)if(!lt.Has(name))missing.Add(name);
   foreach(var handle in handles){var vp=tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0),OpenMode.ForRead) as Viewport;Need(vp!=null,"VIEWPORT_REQUIRED:"+handle);var frozen=new HashSet<ObjectId>(vp.GetFrozenLayers().Cast<ObjectId>());var layers=new List<object>();
    foreach(var name in names){if(!lt.Has(name))continue;var l=(LayerTableRecord)tr.GetObject(lt[name],OpenMode.ForRead);var o=l.GetViewportOverrides(vp.ObjectId);layers.Add(new{name,global_on=!l.IsOff,global_frozen=l.IsFrozen,plottable=l.IsPlottable,global_color=l.Color.ToString(),global_color_index=l.Color.ColorIndex,global_color_method=l.Color.ColorMethod.ToString(),vp_frozen=frozen.Contains(l.ObjectId),color_overridden=o.IsColorOverridden,color=o.IsColorOverridden?o.Color.ToString():null,color_index=o.IsColorOverridden?(int?)o.Color.ColorIndex:null,weight_overridden=o.IsLineWeightOverridden,weight=o.IsLineWeightOverridden?(int?)o.LineWeight:null,linetype_overridden=o.IsLinetypeOverridden,linetype=o.IsLinetypeOverridden?((LinetypeTableRecord)tr.GetObject(o.LinetypeObjectId,OpenMode.ForRead)).Name:null,plotstyle_overridden=o.IsPlotStyleOverridden,plotstyle=o.IsPlotStyleOverridden?o.PlotStyleName:null,transparency_overridden=o.IsTransparencyOverridden,transparency=o.IsTransparencyOverridden?(int?)o.Transparency.Alpha:null});}
    rows.Add(new{handle=vp.Handle.ToString(),on=vp.On,number=vp.Number,layers=layers});
   }
  }return new{viewports=rows,missing_layers=missing};
 }
 static object RenderedTableSamples(Table table,Dictionary<string,string> wanted){var found=new Dictionary<string,object>();var errors=new List<string>();Action<Entity,int> scan=null;scan=(entity,depth)=>{if(entity is DBText||entity is MText){string text=entity is DBText?((DBText)entity).TextString:((MText)entity).Text;foreach(var w in wanted)if(!found.ContainsKey(w.Key)&&text==w.Value)found[w.Key]=Piece(entity,depth);return;}if(depth>=3||(!(entity is Table)&&!(entity is BlockReference)))return;var pieces=new DBObjectCollection();try{entity.Explode(pieces);foreach(DBObject o in pieces){var e=o as Entity;if(e!=null)scan(e,depth+1);}}catch(System.Exception ex){errors.Add(ex.GetType().Name+":"+ex.Message);}finally{foreach(DBObject o in pieces)o.Dispose();}};using(var detached=(Table)table.Clone())scan(detached,0);return new{method="detached_clone_explode_only",requested=wanted,matched=found,unmatched=wanted.Keys.Where(k=>!found.ContainsKey(k)).ToArray(),errors=errors};}
 static object SavedRenderedTableSamples(string source,string handle,Dictionary<string,string> wanted){if(String.IsNullOrEmpty(source))return new{status="SAVED_SOURCE_REQUIRED"};string hash=NativeGeometryReadV1.Hash(source);object result;using(var side=new Database(false,true)){side.ReadDwgFile(source,FileOpenMode.OpenForReadAndAllShare,true,"");side.CloseInput(true);using(var tr=side.TransactionManager.StartTransaction()){var t=tr.GetObject(side.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0),OpenMode.ForRead) as Table;Need(t!=null,"SAVED_TABLE_REQUIRED");result=RenderedTableSamples(t,wanted);}}Need(NativeGeometryReadV1.Hash(source)==hash,"RENDER_READ_CHANGED_SAVED_FILE");return new{source=source,source_sha256=hash,isolated_database=true,samples=result};}
 static string StyleKey(ObjectId id,SortedDictionary<string,object> styles){if(id.IsNull||!id.IsValid||id.IsErased)return null;string key=id.Handle.ToString();if(!styles.ContainsKey(key))styles[key]=Font(id);return key;}
 public static object ReadTables(Database db,string[] handles,string savedSource=null){
  Need(handles!=null&&handles.Length>0,"TABLE_HANDLES_REQUIRED");var rows=new List<object>();using(var tr=db.TransactionManager.StartTransaction())foreach(string h in handles){
   var t=tr.GetObject(db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0),OpenMode.ForRead) as Table;Need(t!=null,"ACDBTABLE_REQUIRED:"+h);var cells=new List<object>();var styles=new SortedDictionary<string,object>();var ts=t.TableStyle.IsNull?null:tr.GetObject(t.TableStyle,OpenMode.ForRead) as TableStyle;var named=new SortedDictionary<string,object>();var rowStyles=new SortedDictionary<string,object>();var representatives=new Dictionary<string,string>();bool unresolved=false;object legendSample=null;
   for(int i=0;i<t.Rows.Count;i++)for(int k=0;k<t.Columns.Count;k++){
    var cell=t.Cells[i,k];if(legendSample==null&&!cell.BlockTableRecordId.IsNull){var legend=(BlockTableRecord)tr.GetObject(cell.BlockTableRecordId,OpenMode.ForRead);legendSample=new{row=i,column=k,type="Block",handle=legend.Handle.ToString(),name=legend.Name};}string cellName=cell.Style;var rowType=t.RowType(i);if(!representatives.ContainsKey(rowType.ToString())&&!String.IsNullOrEmpty(cell.TextString))representatives[rowType.ToString()]=cell.TextString;ObjectId namedId=ObjectId.Null,rowId=ObjectId.Null;double? namedHeight=null,rowHeight=null;
    if(ts!=null){if(!String.IsNullOrEmpty(cellName)){namedId=ts.TextStyle(cellName);namedHeight=ts.TextHeight(cellName);named[cellName]=new{style=StyleKey(namedId,styles),height=namedHeight};}rowId=ts.TextStyle(rowType);rowHeight=ts.TextHeight(rowType);rowStyles[rowType.ToString()]=new{style=StyleKey(rowId,styles),height=rowHeight};}
    string cellStyle=StyleKey(cell.TextStyleId??ObjectId.Null,styles),nativeCellStyle=StyleKey(t.TextStyle(i,k),styles),namedStyle=StyleKey(namedId,styles),rowStyle=StyleKey(rowId,styles);var contents=new List<object>();int index=0;
    foreach(CellContent content in cell.Contents){string style=StyleKey(content.TextStyleId,styles),nativeStyle=StyleKey(t.GetTextStyleId(i,k,index),styles);string effective=style??cellStyle??nativeStyle??nativeCellStyle??namedStyle??rowStyle;if(effective==null)unresolved=true;string source=style!=null?"content_getter":cellStyle!=null?"cell_getter":nativeStyle!=null?"table_content_getter":nativeCellStyle!=null?"table_cell_getter":namedStyle!=null?"table_style_named_cell":rowStyle!=null?"table_style_row_type":"unresolved";contents.Add(new{index=index,type=content.ContentTypes.ToString(),style=style,height=content.TextHeight,overrides=content.Overrides.ToString(),native_style=nativeStyle,native_height=t.GetTextHeight(i,k,index),effective_style=effective,effective_style_source=source,effective_height=t.GetTextHeight(i,k,index),effective_height_source="table_content_getter"});index++;}
    cells.Add(new{row=i,column=k,text=cell.TextString,block=cell.BlockTableRecordId.IsNull?null:cell.BlockTableRecordId.Handle.ToString(),content_count=cell.Contents.Count,contents=contents,cell_style_name=cellName,row_type=rowType.ToString(),cell_style=cellStyle,cell_height=cell.TextHeight,native_cell_style=nativeCellStyle,native_cell_height=t.TextHeight(i,k)});
   }
   rows.Add(new{handle=t.Handle.ToString(),type=t.GetRXClass().Name,layer=t.Layer,row_count=t.Rows.Count,column_count=t.Columns.Count,cells=cells,text_styles=styles,legend_sample=legendSample,rendered_samples=unresolved?SavedRenderedTableSamples(savedSource,h,representatives):null,table_style=new{handle=t.TableStyle.IsNull?null:t.TableStyle.Handle.ToString(),name=t.TableStyleName,named_cell_styles=named,row_types=rowStyles}});
  }return rows;
 }
 public static object Read(Document doc,string[] handles){
  Need(handles!=null&&handles.Length>0&&handles.Distinct(StringComparer.OrdinalIgnoreCase).Count()==handles.Length,"EXACT_HANDLES_REQUIRED");var rows=new List<object>();
  using(var tr=doc.Database.TransactionManager.StartTransaction())foreach(var handle in handles){
   var e=(Entity)tr.GetObject(doc.Database.GetObjectId(false,new Handle(Convert.ToInt64(handle,16)),0),OpenMode.ForRead);
   Need(e.GetRXClass().Name.StartsWith("TDb"),"NATIVE_TIANZHENG_OBJECT_REQUIRED:"+handle);
   var grips=new GripDataCollection();e.GetGripPoints(grips,1,5,Vector3d.ZAxis,GetGripPointsFlags.GripPointsOnly);
   var props=new Dictionary<string,object>();var missing=new List<string>();object co=e.AcadObject;
   foreach(string key in new[]{"XValue","YValue","Text","TextString","Scale","LayoutRotation","TextStyle","TextHeight","UpText","DownText","Height"})try{props[key]=co.GetType().InvokeMember(key,BindingFlags.GetProperty,null,co,null);}catch{missing.Add(key);}
   rows.Add(new{handle,type=e.GetRXClass().Name,layer=e.Layer,color=e.ColorIndex,properties=props,unavailable_properties=missing,grips=grips.Cast<GripData>().Select(g=>P(g.GripPoint)).ToArray(),display=Piece(e,0)});
  }return rows;
 }
 [CommandMethod("HLCADNATIVEDETAILSTESTV7",CommandFlags.Session)]public void Test(){
  var original=App.DocumentManager.MdiActiveDocument;var previous=HostApplicationServices.WorkingDatabase;
  var answer=original.Editor.GetString(new PromptStringOptions("\nIsolated native read: "){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  TestJob j=null;Document copy=null;try{
   j=J.Deserialize<TestJob>(File.ReadAllText(answer.StringResult.Trim('"')));Need(NativeGeometryReadV1.Hash(j.source)==j.source_sha256&&!File.Exists(j.receipt),"TEST_SOURCE_OR_RECEIPT");
   copy=App.DocumentManager.Open(j.source,true);App.DocumentManager.MdiActiveDocument=copy;HostApplicationServices.WorkingDatabase=copy.Database;
   var before=App.GetSystemVariable("DBMOD");object rows;using(copy.LockDocument())rows=j.kind=="table_read"?ReadTables(copy.Database,j.handles,j.source):j.kind=="viewport_details"?ReadViewports(copy.Database,j.handles,j.layers):Read(copy,j.handles);Need(Equals(before,App.GetSystemVariable("DBMOD")),"READ_CHANGED_DOCUMENT");
   App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;copy.CloseAndDiscard();copy=null;
   Need(NativeGeometryReadV1.Hash(j.source)==j.source_sha256,"SOURCE_CHANGED");Write(j.receipt,new{status="ISOLATED_NATIVE_DETAILS_VERIFIED",source_sha256=j.source_sha256,source_unchanged=true,read_only=true,entities=rows});
  }catch(System.Exception e){if(j!=null&&!File.Exists(j.receipt))Write(j.receipt,new{status="NATIVE_DETAILS_TEST_FAILED",error=e.ToString()});}
  finally{App.DocumentManager.MdiActiveDocument=original;HostApplicationServices.WorkingDatabase=previous;if(copy!=null)copy.CloseAndDiscard();}
 }
 [CommandMethod("HLCADNATIVEDETAILSREADV7",CommandFlags.Session)]public void Run(){
  var answer=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nNative details request: "){AllowSpaces=true});if(answer.Status!=PromptStatus.OK)return;
  Type adapter=null;Job job=null;bool owned=false;
  try{
   var m=J.Deserialize<Manifest>(File.ReadAllText(answer.StringResult.Trim('"')));var p=System.Diagnostics.Process.GetCurrentProcess();
   Need(p.Id==m.host.pid&&p.StartTime.ToUniversalTime().ToFileTimeUtc()==m.host.created&&Eq(p.MainModule.FileName,m.host.image),"HOST_IDENTITY");
   adapter=AppDomain.CurrentDomain.GetAssemblies().Select(x=>x.GetType("V736BaseSession",false)).Single(x=>x!=null);CadAdapterContractV1.Check(adapter);
   Need(Eq(adapter.Assembly.Location,m.loaded_dll)&&NativeGeometryReadV1.Hash(m.loaded_dll)==m.loaded_dll_sha256&&Eq((string)Get(adapter,"dir"),m.session_dir),"ADAPTER_IDENTITY");
   Need(!(bool)Get(adapter,"busy")&&!(bool)Get(adapter,"blocked")&&!File.Exists(Path.Combine(m.session_dir,"request.json")),"SESSION_BUSY");
   Need(Eq(Path.GetDirectoryName(m.request),m.session_dir)&&NativeGeometryReadV1.Hash(m.request)==m.request_sha256,"REQUEST_IDENTITY");
   var req=J.Deserialize<Request>(File.ReadAllText(m.request));Call(adapter,"CheckPath",req.job_path);Need((req.kind=="native_details"||req.kind=="viewport_details"||req.kind=="table_read")&&NativeGeometryReadV1.Hash(req.job_path)==req.job_sha256,"JOB_IDENTITY");
   job=J.Deserialize<Job>(File.ReadAllText(req.job_path));Call(adapter,"CheckLive",job.input,job.input_sha256);Call(adapter,"CheckPath",job.receipt);Need(!File.Exists(job.receipt),"RECEIPT_EXISTS");
   var doc=(Document)Get(adapter,"doc");Need(doc==App.DocumentManager.MdiActiveDocument,"ACTIVE_DOCUMENT_CHANGED");var dirty=App.GetSystemVariable("DBMOD");
   adapter.GetField("busy",F).SetValue(null,true);owned=true;object result;using(doc.LockDocument())result=req.kind=="table_read"?ReadTables(doc.Database,job.handles,job.input):req.kind=="viewport_details"?ReadViewports(doc.Database,job.handles,job.layers):Read(doc,job.handles);
   Need(Equals(dirty,App.GetSystemVariable("DBMOD")),"READ_CHANGED_DOCUMENT");Call(adapter,"CheckLive",job.input,job.input_sha256);
   Write(job.receipt,new{status="BOUND_NATIVE_DETAILS_READ",source_sha256=job.input_sha256,entities=result,pid=p.Id,read_only=true,source_unchanged=true});
  }catch(System.Exception ex){if(job!=null&&!File.Exists(job.receipt))Write(job.receipt,new{status="REJECTED_BEFORE_WRITE",source_sha256=job.input_sha256,error=ex.ToString(),write_started=false,committed=false,replayed=false,emergency=(string)null});}
  finally{if(owned)adapter.GetField("busy",F).SetValue(null,false);}
 }
}
