// Read-only exact LINE/ARC boolean split. Reuses the native Region method in
// V745NativeBooleanRead, without its sliver deletion or largest-loop assumption.
using System;using System.IO;using System.Linq;using System.Collections.Generic;using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;using Autodesk.AutoCAD.DatabaseServices;using Autodesk.AutoCAD.Geometry;using Autodesk.AutoCAD.EditorInput;
using App=Autodesk.AutoCAD.ApplicationServices.Core.Application;
public class NativeHatchSplitV1 {
 public class Boundary{public string handle;public int[] loops;}
 public class Item{public string handle;public string[] clips,hold_reasons;}
 public class Request{public string input,input_sha256,clips_input,clips_sha256,receipt;public Boundary[] boundaries;public Item[] items;}
 public class Part{public double[][][] loops;}
 class Seg{public Point2d a,b;public double bulge;}
 class Ring:IDisposable{public List<Seg> edges;public Region region;public double area;public int parent=-1,depth;public void Dispose(){region.Dispose();}}
 static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=100000000,RecursionLimit=100};
 const double Join=1e-7,AreaAbsolute=1e-6;
 static void Need(bool b,string s){if(!b)throw new InvalidOperationException(s);}
 static double ATol(double a){return Math.Max(AreaAbsolute,a*1e-9);}
 static double Area(Region r){return r==null||r.IsNull?0:r.Area;}
 static ObjectId Id(Database db,string h){return db.GetObjectId(false,new Handle(Convert.ToInt64(h,16)),0);}
 static Database Open(string p){var d=new Database(false,true);d.ReadDwgFile(p,FileOpenMode.OpenForReadAndAllShare,true,null);d.CloseInput(true);return d;}
 static double Mod(double x){return (x%(2*Math.PI)+2*Math.PI)%(2*Math.PI);}
 static Seg Reverse(Seg s){return new Seg{a=s.b,b=s.a,bulge=-s.bulge};}
 static Point2d P(Point2d p,Vector3d off){return new Point2d(p.X-off.X,p.Y-off.Y);}
 static List<Seg> ReadLoop(HatchLoop l,Vector3d off){
  var es=new List<Seg>();
  if(l.IsPolyline){var v=l.Polyline.Cast<BulgeVertex>().ToArray();int n=v.Length;if(n>1&&v[0].Vertex==v[n-1].Vertex)n--;
   for(int k=0;k<n;k++)es.Add(new Seg{a=P(v[k].Vertex,off),b=P(v[(k+1)%n].Vertex,off),bulge=v[k].Bulge});
  }else foreach(Curve2d c in l.Curves){var line=c as LineSegment2d;if(line!=null){es.Add(new Seg{a=P(line.StartPoint,off),b=P(line.EndPoint,off)});continue;}
   var arc=c as CircularArc2d;var ellipse=c as EllipticalArc2d;
   Need(arc!=null||ellipse!=null,"UNSUPPORTED_NATIVE_CURVE:"+c.GetType().Name);
   // ACIS can store a true circle as an ellipse. Accept exact equal radii only;
   // unequal ellipses must never be approximated by circular bulges.
   if(ellipse!=null)Need(ellipse.MajorRadius==ellipse.MinorRadius&&ellipse.MajorRadius>0,"NONCIRCULAR_NATIVE_ELLIPSE");
   Point2d a=P(c.StartPoint,off),b=P(c.EndPoint,off),center=P(arc!=null?arc.Center:ellipse.Center,off);double t0=Math.Atan2(a.Y-center.Y,a.X-center.X),t1=Math.Atan2(b.Y-center.Y,b.X-center.X);double sign=(arc!=null?arc.IsClockWise:ellipse.IsClockWise)?-1:1,sw=sign>0?Mod(t1-t0):-Mod(t0-t1);
   Need(a.GetDistanceTo(b)>Join,"FULL_CIRCLE_REQUIRES_NATIVE_CIRCLE_PATH");es.Add(new Seg{a=a,b=b,bulge=Math.Tan(sw/4)});
  }
  Need(es.Count>=2,"LOOP_TOO_SHORT");for(int i=0;i<es.Count;i++)Need(es[i].b.GetDistanceTo(es[(i+1)%es.Count].a)<=Join,"NATIVE_JOIN_GAP:"+es[i].b.GetDistanceTo(es[(i+1)%es.Count].a).ToString("R"));return es;
 }
 static Polyline Poly(List<Seg> es){var p=new Polyline();p.Elevation=0;p.Normal=Vector3d.ZAxis;foreach(var s in es){Need(s.a.GetDistanceTo(s.b)>1e-10,"ZERO_LENGTH_NATIVE_SEGMENT");p.AddVertexAt(p.NumberOfVertices,s.a,s.bulge,0,0);}p.Closed=true;return p;}
 static Ring MakeRing(List<Seg> es){var curves=new DBObjectCollection();try{foreach(var e in es){if(e.bulge==0){curves.Add(new Line(new Point3d(e.a.X,e.a.Y,0),new Point3d(e.b.X,e.b.Y,0)));continue;}double b=e.bulge,dx=e.b.X-e.a.X,dy=e.b.Y-e.a.Y;var c=new Point3d((e.a.X+e.b.X)/2-dy*(1-b*b)/(4*b),(e.a.Y+e.b.Y)/2+dx*(1-b*b)/(4*b),0);Point2d a=b>0?e.a:e.b,z=b>0?e.b:e.a;double t0=Math.Atan2(a.Y-c.Y,a.X-c.X),sw=4*Math.Atan(Math.Abs(b));curves.Add(new Arc(c,Vector3d.ZAxis,new Point2d(c.X,c.Y).GetDistanceTo(a),t0,t0+sw));}
  var rs=Region.CreateFromCurves(curves);if(rs.Count!=1){foreach(DBObject x in rs)x.Dispose();throw new InvalidOperationException("NON_SIMPLE_OR_OPEN_LOOP:"+rs.Count);}var r=(Region)rs[0];return new Ring{edges=es,region=r,area=r.Area};}finally{foreach(DBObject x in curves)x.Dispose();}}
 static double IntersectionArea(Region a,Region b){using(var x=(Region)a.Clone())using(var y=(Region)b.Clone()){x.BooleanOperation(BooleanOperationType.BoolIntersect,y);return Area(x);}}
 static void Nest(List<Ring> rings){for(int i=0;i<rings.Count;i++){double pa=Double.PositiveInfinity;for(int j=0;j<rings.Count;j++){if(i==j)continue;double overlap=IntersectionArea(rings[i].region,rings[j].region),tol=ATol(Math.Min(rings[i].area,rings[j].area));if(overlap<=tol)continue;Need(!(Math.Abs(overlap-rings[i].area)<=tol&&Math.Abs(overlap-rings[j].area)<=tol),"DUPLICATE_OR_UNRESOLVED_COINCIDENT_LOOPS");
    if(Math.Abs(overlap-rings[i].area)<=tol&&rings[j].area>rings[i].area+tol){if(rings[j].area<pa){rings[i].parent=j;pa=rings[j].area;}}
    else if(Math.Abs(overlap-rings[j].area)>tol)throw new InvalidOperationException("INTERSECTING_OR_DUPLICATE_LOOPS");}
   }for(int i=0;i<rings.Count;i++){int p=rings[i].parent,d=0;while(p>=0){Need(++d<=rings.Count,"NESTING_CYCLE");p=rings[p].parent;}rings[i].depth=d;}}
 static Region Body(List<Ring> rings){Need(rings.Count>0,"NO_PHYSICAL_LOOPS");Nest(rings);Region result=null;try{foreach(int i in Enumerable.Range(0,rings.Count).OrderBy(i=>rings[i].depth)){
    if(result==null){Need(rings[i].depth==0,"FIRST_LOOP_IS_HOLE");result=(Region)rings[i].region.Clone();}
    else using(var q=(Region)rings[i].region.Clone())result.BooleanOperation(rings[i].depth%2==0?BooleanOperationType.BoolUnite:BooleanOperationType.BoolSubtract,q);
   }return result;}catch{if(result!=null)result.Dispose();throw;}}
 static List<Ring> ReadRings(Hatch h,int[] indices,Vector3d off,bool clip){Need(h.Normal.IsEqualTo(Vector3d.ZAxis)&&h.HatchStyle==HatchStyle.Normal,"NORMAL_HORIZONTAL_HATCH_REQUIRED");if(!clip)Need(h.Elevation==0,"SOURCE_HATCH_NOT_Z0");var rings=new List<Ring>();try{
   int[] ids=indices??Enumerable.Range(0,h.NumberOfLoops).ToArray();Need(ids.Length>0&&ids.Distinct().Count()==ids.Length,"LOOP_INDICES_REQUIRED");
   foreach(int k in ids){Need(k>=0&&k<h.NumberOfLoops,"LOOP_INDEX_RANGE");var l=h.GetLoopAt(k);Need((((int)l.LoopType)&8)==0,"TEXTBOX_LOOP_REQUIRES_EXPLICIT_PHYSICAL_SELECTION");var es=ReadLoop(l,off);rings.Add(MakeRing(es));}return rings;
  }catch{foreach(var r in rings)r.Dispose();throw;}}

 static void Collect(Region region,List<Seg> es,int depth){Need(depth<12,"REGION_EXPLODE_DEPTH");var parts=new DBObjectCollection();region.Explode(parts);foreach(DBObject obj in parts)using(obj){var sub=obj as Region;if(sub!=null){Collect(sub,es,depth+1);continue;}var line=obj as Line;if(line!=null){es.Add(new Seg{a=new Point2d(line.StartPoint.X,line.StartPoint.Y),b=new Point2d(line.EndPoint.X,line.EndPoint.Y)});continue;}var arc=obj as Arc;if(arc!=null){double sw=Mod(arc.EndAngle-arc.StartAngle)*(arc.Normal.Z<0?-1:1);es.Add(new Seg{a=new Point2d(arc.StartPoint.X,arc.StartPoint.Y),b=new Point2d(arc.EndPoint.X,arc.EndPoint.Y),bulge=Math.Tan(sw/4)});continue;}var ellipse=obj as Ellipse;if(ellipse!=null){Need(ellipse.RadiusRatio==1.0,"NONCIRCULAR_BOOLEAN_ELLIPSE:"+ellipse.RadiusRatio.ToString("R"));double sw=(ellipse.EndParam-ellipse.StartParam)*(ellipse.Normal.Z<0?-1:1);Need(Math.Abs(sw)<2*Math.PI-1e-10,"FULL_CIRCULAR_ELLIPSE_OUTPUT");es.Add(new Seg{a=new Point2d(ellipse.StartPoint.X,ellipse.StartPoint.Y),b=new Point2d(ellipse.EndPoint.X,ellipse.EndPoint.Y),bulge=Math.Tan(sw/4)});continue;}throw new InvalidOperationException("UNSUPPORTED_BOOLEAN_EDGE:"+obj.GetRXClass().Name);}}
 static List<Ring> Extract(Region region){var rings=new List<Ring>();if(Area(region)==0)return rings;var es=new List<Seg>();Collect(region,es,0);try{while(es.Count>0){var first=es[0];es.RemoveAt(0);var chain=new List<Seg>{first};Point2d end=first.b;
    while(end.GetDistanceTo(first.a)>Join){var hits=new List<int>();for(int i=0;i<es.Count;i++)if(end.GetDistanceTo(es[i].a)<=Join||end.GetDistanceTo(es[i].b)<=Join)hits.Add(i);Need(hits.Count==1,"AMBIGUOUS_OR_OPEN_BOOLEAN_JOIN:"+hits.Count);var next=es[hits[0]];es.RemoveAt(hits[0]);if(end.GetDistanceTo(next.a)>Join)next=Reverse(next);chain.Add(next);end=next.b;}
    rings.Add(MakeRing(chain)); // Keep every nonzero component, including slivers.
   }Nest(rings);return rings;}catch{foreach(var r in rings)r.Dispose();throw;}}
 static List<Seg> AtLeastThree(List<Seg> es){if(es.Count>=3)return es;var result=new List<Seg>();bool split=false;foreach(var s in es){if(!split&&Math.Abs(s.bulge)>1e-12){split=true;double b=s.bulge,dx=s.b.X-s.a.X,dy=s.b.Y-s.a.Y;var c=new Point2d((s.a.X+s.b.X)/2-dy*(1-b*b)/(4*b),(s.a.Y+s.b.Y)/2+dx*(1-b*b)/(4*b));double t=Math.Atan2(s.a.Y-c.Y,s.a.X-c.X)+2*Math.Atan(b),rad=c.GetDistanceTo(s.a);var mid=new Point2d(c.X+rad*Math.Cos(t),c.Y+rad*Math.Sin(t));double half=Math.Tan(Math.Atan(b)/2);result.Add(new Seg{a=s.a,b=mid,bulge=half});result.Add(new Seg{a=mid,b=s.b,bulge=half});}else result.Add(s);}Need(result.Count>=3,"UNREPRESENTABLE_TWO_EDGE_LOOP");return result;}
 static double[][] Vertices(List<Seg> edges,Vector3d off){return AtLeastThree(edges).Select(e=>new[]{e.a.X+off.X,e.a.Y+off.Y,e.bulge}).ToArray();}
 static Part[] Parts(List<Ring> rings,Vector3d off){var parts=new List<Part>();for(int i=0;i<rings.Count;i++)if(rings[i].depth%2==0){var loops=new List<double[][]>{Vertices(rings[i].edges,off)};for(int j=0;j<rings.Count;j++)if(rings[j].parent==i&&rings[j].depth%2==1)loops.Add(Vertices(rings[j].edges,off));parts.Add(new Part{loops=loops.ToArray()});}return parts.ToArray();}
 static Region PartBody(Part[] ps,Vector3d off){Region result=null;foreach(var p in ps){var rings=new List<Ring>();try{foreach(var vs in p.loops){var es=new List<Seg>();for(int i=0;i<vs.Length;i++)es.Add(new Seg{a=new Point2d(vs[i][0]-off.X,vs[i][1]-off.Y),b=new Point2d(vs[(i+1)%vs.Length][0]-off.X,vs[(i+1)%vs.Length][1]-off.Y),bulge=vs[i][2]});rings.Add(MakeRing(es));}using(var b=Body(rings)){if(result==null)result=(Region)b.Clone();else using(var q=(Region)b.Clone())result.BooleanOperation(BooleanOperationType.BoolUnite,q);}}finally{foreach(var x in rings)x.Dispose();}}return result;}
 static double DifferenceArea(Region a,Region b){if(Area(a)==0)return 0;if(Area(b)==0)return Area(a);using(var x=(Region)a.Clone())using(var y=(Region)b.Clone()){x.BooleanOperation(BooleanOperationType.BoolSubtract,y);return Area(x);}}
 static object Split(Hatch h,Item item,Dictionary<string,Region> clips,Dictionary<string,string> clipErrors,Vector3d off){
  Need(h.PatternName=="GRASS"&&!h.IsSolidFill,"GRASS_TEMPLATE_REQUIRED");if(item.hold_reasons!=null&&item.hold_reasons.Length>0)throw new InvalidOperationException("CALLER_HELD:"+String.Join(",",item.hold_reasons));Need(item.clips!=null&&item.clips.Length>0,"CLIP_SELECTION_REQUIRED");foreach(var k in item.clips)Need(clips.ContainsKey(k),"CLIP_UNAVAILABLE:"+k+":"+(clipErrors.ContainsKey(k)?clipErrors[k]:"not requested"));
  var sourceRings=ReadRings(h,null,off,false);try{using(var source=Body(sourceRings))using(var cutter=(Region)clips[item.clips[0]].Clone()){
   for(int i=1;i<item.clips.Length;i++)using(var q=(Region)clips[item.clips[i]].Clone())cutter.BooleanOperation(BooleanOperationType.BoolUnite,q);
   double sourceArea=Area(source);double? stored=null;try{stored=h.Area;}catch{}if(stored.HasValue)Need(Math.Abs(stored.Value-sourceArea)<=ATol(sourceArea),"SOURCE_NATIVE_AREA_MISMATCH:"+(stored.Value-sourceArea).ToString("R"));
   using(var inside=(Region)source.Clone())using(var outside=(Region)source.Clone()){
    using(var q=(Region)cutter.Clone())inside.BooleanOperation(BooleanOperationType.BoolIntersect,q);using(var q=(Region)cutter.Clone())outside.BooleanOperation(BooleanOperationType.BoolSubtract,q);
    double ai=Area(inside),ao=Area(outside),overlap=ai==0||ao==0?0:IntersectionArea(inside,outside);Need(Math.Abs(ai+ao-sourceArea)<=ATol(sourceArea)&&overlap<=ATol(sourceArea),"BOOLEAN_AREA_CONSERVATION_FAILED");
    var ri=Extract(inside);var ro=Extract(outside);try{var pi=Parts(ri,off);var po=Parts(ro,off);using(var back=PartBody(pi.Concat(po).ToArray(),off)){
      double lost=DifferenceArea(source,back),extra=DifferenceArea(back,source);Need(lost<=ATol(sourceArea)&&extra<=ATol(sourceArea),"BULGE_ROUNDTRIP_SYMMETRIC_DIFFERENCE");
      var ex=h.GeometricExtents;return new{handle=item.handle,status="EXACT_NATIVE_SPLIT",source_area=sourceArea,stored_hatch_area=stored,inside_area=ai,outside_area=ao,overlap_area=overlap,lost_area=lost,extra_area=extra,area_tolerance=ATol(sourceArea),inside=pi,outside=po,inside_arc_segments=ri.Sum(r=>r.edges.Count(e=>Math.Abs(e.bulge)>1e-12)),outside_arc_segments=ro.Sum(r=>r.edges.Count(e=>Math.Abs(e.bulge)>1e-12)),source_geometry=NativeGeometryReadV1.Geometry(h,false),parameters=new{template=item.handle,template_layer=h.Layer,expected_pattern=h.PatternName,expected_color=h.ColorIndex,replace_target=new{handle=item.handle,type=h.GetRXClass().Name,layer=h.Layer,bounds=new[]{ex.MinPoint.X,ex.MinPoint.Y,ex.MaxPoint.X,ex.MaxPoint.Y}},parts=pi.Concat(po).ToArray()},inside_part_count=pi.Length,outside_part_count=po.Length};
     }}finally{foreach(var r in ri)r.Dispose();foreach(var r in ro)r.Dispose();}
   }
  }}finally{foreach(var r in sourceRings)r.Dispose();}
 }
 [CommandMethod("HLCADHATCHSPLITREADV1",CommandFlags.Session)]public void Run(){var a=App.DocumentManager.MdiActiveDocument.Editor.GetString(new PromptStringOptions("\nExact hatch split request: "){AllowSpaces=true});if(a.Status!=PromptStatus.OK)return;Request q=null;Database old=HostApplicationServices.WorkingDatabase;var clips=new Dictionary<string,Region>();var errors=new Dictionary<string,string>();try{
   q=J.Deserialize<Request>(File.ReadAllText(a.StringResult.Trim('"')));Need(!File.Exists(q.receipt),"OUTPUT_EXISTS");Need(NativeGeometryReadV1.Hash(q.input)==q.input_sha256&&NativeGeometryReadV1.Hash(q.clips_input)==q.clips_sha256,"INPUT_HASH_CHANGED");Need(q.items.Length>0&&q.boundaries.Length>0,"ITEMS_BOUNDARIES_REQUIRED");
   using(var db=Open(q.input))using(var cb=Open(q.clips_input))using(var tr=db.TransactionManager.StartTransaction())using(var ct=cb.TransactionManager.StartTransaction()){
    HostApplicationServices.WorkingDatabase=db;var first=(Hatch)tr.GetObject(Id(db,q.items[0].handle),OpenMode.ForRead);var ex=first.GeometricExtents;var off=new Vector3d(ex.MinPoint.X,ex.MinPoint.Y,0);
    foreach(var b in q.boundaries){List<Ring> rings=null;try{HostApplicationServices.WorkingDatabase=cb;var h=ct.GetObject(Id(cb,b.handle),OpenMode.ForRead) as Hatch;Need(h!=null,"CLIP_NOT_HATCH");rings=ReadRings(h,b.loops,off,true);clips[b.handle]=Body(rings);}catch(System.Exception e){errors[b.handle]=e.Message;}finally{if(rings!=null)foreach(var r in rings)r.Dispose();}}
    HostApplicationServices.WorkingDatabase=db;var rows=new List<object>();foreach(var item in q.items)try{var h=tr.GetObject(Id(db,item.handle),OpenMode.ForRead) as Hatch;Need(h!=null,"TARGET_NOT_HATCH");rows.Add(Split(h,item,clips,errors,off));}catch(System.Exception e){rows.Add(new{handle=item.handle,status="EXCEPTION_NO_PARAMETERS",error=e.Message,detail=e.StackTrace});}
    Need(NativeGeometryReadV1.Hash(q.input)==q.input_sha256&&NativeGeometryReadV1.Hash(q.clips_input)==q.clips_sha256,"SOURCE_CHANGED_DURING_READ");File.WriteAllText(q.receipt,J.Serialize(new{status="READ_ONLY_EXACT_NATIVE_SPLIT",input=q.input,input_sha256=q.input_sha256,clips_input=q.clips_input,clips_sha256=q.clips_sha256,source_unchanged=true,approximation=false,slivers_dropped=false,join_tolerance=Join,offset=new[]{off.X,off.Y},clip_exceptions=errors,rows=rows}),new System.Text.UTF8Encoding(false));
   }
  }catch(System.Exception e){if(q!=null&&!File.Exists(q.receipt))File.WriteAllText(q.receipt,J.Serialize(new{status="NATIVE_SPLIT_FAILED",error=e.ToString()}));}finally{HostApplicationServices.WorkingDatabase=old;foreach(var x in clips.Values)x.Dispose();}}
}
