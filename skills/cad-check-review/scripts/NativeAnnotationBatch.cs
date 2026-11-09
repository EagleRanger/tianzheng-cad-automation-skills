using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Diagnostics;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using Autodesk.AutoCAD.Runtime;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.EditorInput;
using App = Autodesk.AutoCAD.ApplicationServices.Core.Application;

// Data-driven extension of the tested V3822 / V3837 / V3306 grip recipes.
// Scope: simple single-source leaders only. Other topologies are PENDING.
public class NativeAnnotationBatch
{
    const string Version = "20261105.1";
    static string S(Dictionary<string, object> a, string k) { return a.ContainsKey(k) ? Convert.ToString(a[k]) : ""; }
    static double D(Dictionary<string, object> a, string k) { double n = Convert.ToDouble(a[k]); if (double.IsNaN(n) || double.IsInfinity(n)) throw new System.Exception("NONFINITE_INPUT"); return n; }
    static Dictionary<string, object> Dict(object v) { return (Dictionary<string, object>)v; }
    static ObjectId Id(Database db, string h) { return db.GetObjectId(false, new Handle(Convert.ToInt64(h, 16)), 0); }
    static double[] P(Point3d p) { return new[] { p.X, p.Y, p.Z }; }
    static Point3d Point(object v) { var a = (object[])v; var p = new Point3d(Convert.ToDouble(a[0]), Convert.ToDouble(a[1]), a.Length > 2 ? Convert.ToDouble(a[2]) : 0); foreach (double n in P(p)) if (double.IsNaN(n) || double.IsInfinity(n)) throw new System.Exception("NONFINITE_POINT"); return p; }
    static void GuardViewport(Viewport v)
    {
        if (v.CustomScale <= 0 || v.PerspectiveOn || (v.ViewDirection.GetNormal() - Vector3d.ZAxis).Length > 1e-8)
            throw new System.Exception("PENDING_NONPLAN_VIEWPORT");
    }
    static Point3d[] Grips(Entity e) { var g = new Point3dCollection(); e.GetGripPoints(g, new IntegerCollection(), new IntegerCollection()); return g.Cast<Point3d>().ToArray(); }
    static object Get(Entity e, string n) { var o = e.AcadObject; return o.GetType().InvokeMember(n, BindingFlags.GetProperty, null, o, null); }
    static void Set(Entity e, string n, object value) { var o = e.AcadObject; o.GetType().InvokeMember(n, BindingFlags.SetProperty, null, o, new[] { value }); }
    static Point3d Map(Viewport v, Point3d p)
    {
        double x = p.X - v.ViewTarget.X, y = p.Y - v.ViewTarget.Y, c = Math.Cos(v.TwistAngle), s = Math.Sin(v.TwistAngle);
        return new Point3d(v.CenterPoint.X + v.CustomScale * (c * x - s * y - v.ViewCenter.X), v.CenterPoint.Y + v.CustomScale * (s * x + c * y - v.ViewCenter.Y), 0);
    }
    static Point3d Unmap(Viewport v, Point3d p)
    {
        double x = (p.X - v.CenterPoint.X) / v.CustomScale + v.ViewCenter.X, y = (p.Y - v.CenterPoint.Y) / v.CustomScale + v.ViewCenter.Y;
        double c = Math.Cos(v.TwistAngle), s = Math.Sin(v.TwistAngle);
        return new Point3d(v.ViewTarget.X + c * x + s * y, v.ViewTarget.Y - s * x + c * y, 0);
    }
    static Dictionary<string, object> Props(Entity e)
    {
        var r = new Dictionary<string, object>();
        foreach (string n in new[] { "UpText", "DownText", "DrawingLabel", "IndexLabel", "XValue", "YValue", "Height", "LayoutRotation" })
            try { r[n] = Get(e, n); } catch { }
        return r;
    }
    class Geometry
    {
        public List<Point3d[]> lines = new List<Point3d[]>();
        public List<object> texts = new List<object>();
        public List<double> textRotations = new List<double>();
        public bool complete = true;
    }
    static void Expand(Entity e, Geometry result, int depth)
    {
        var line = e as Line;
        if (line != null) { result.lines.Add(new[] { line.StartPoint, line.EndPoint }); return; }
        var text = e as DBText;
        if (text != null) { result.texts.Add(new { text = text.TextString, position = P(text.Position), height = text.Height, rotation = text.Rotation }); result.textRotations.Add(text.Rotation); return; }
        var poly = e as Polyline;
        if (poly != null)
        {
            int n = poly.NumberOfVertices;
            for (int i = 0; i < (poly.Closed ? n : n - 1); i++)
                if (Math.Abs(poly.GetBulgeAt(i)) < 1e-10) result.lines.Add(new[] { poly.GetPoint3dAt(i), poly.GetPoint3dAt((i + 1) % n) });
                else result.complete = false;
            return;
        }
        if (e is Circle || e is Arc || e is Solid) return;
        if (depth >= 5) { result.complete = false; return; }
        var children = new DBObjectCollection();
        try { e.Explode(children); foreach (DBObject o in children) { var child = o as Entity; if (child != null) Expand(child, result, depth + 1); } }
        catch { result.complete = false; }
        finally { foreach (DBObject o in children) o.Dispose(); }
    }
    static string Profile(Entity e, Point3d[] g, Viewport v)
    {
        string rx = e.GetRXClass().Name;
        if (rx == "TDbSymbCoord" && g.Length == 3 && e.OwnerId == SymbolUtilityServices.GetBlockModelSpaceId(e.Database)) return "coord3-model";
        if (rx == "TDbSymbMultiLeader" && g.Length == 4 && e.OwnerId == v.OwnerId) return "leader4-paper";
        if (rx == "TDbSymbIndexPointer" && (g.Length == 6 || g.Length == 7) && e.OwnerId == v.OwnerId) return "index-paper";
        throw new System.Exception("PENDING_UNSUPPORTED_TOPOLOGY");
    }
    static int[] Roles(string profile) { return profile == "coord3-model" ? new[] { 0, 1, 2 } : profile == "leader4-paper" ? new[] { 2, 0, 1 } : new[] { 2, 1, 0 }; }
    // Grips alone are not proof. Match both rays to actual exploded native segments.
    static object Joint(Entity e, Point3d[] g, string profile, Viewport v, bool requirePass)
    {
        var roles = Roles(profile); var p = g[roles[0]]; var elbow = g[roles[1]]; var bearing = g[roles[2]];
        var geom = new Geometry(); Expand(e, geom, 0);
        var rays = new List<Point3d>();
        foreach (var segment in geom.lines)
        {
            if (segment[0].DistanceTo(elbow) < 1e-5 && segment[1].DistanceTo(elbow) > 1e-5) rays.Add(segment[1]);
            else if (segment[1].DistanceTo(elbow) < 1e-5 && segment[0].DistanceTo(elbow) > 1e-5) rays.Add(segment[0]);
        }
        Func<Point3d, Point3d, bool> sameRay = (a, b) => {
            var x = a - elbow; var y = b - elbow;
            return x.Length > 1e-8 && y.Length > 1e-8 && x.DotProduct(y) > 0 && x.CrossProduct(y).Length / (x.Length * y.Length) < 1e-7;
        };
        var leaders = rays.Where(x => sameRay(x, p)).ToArray();
        var bars = rays.Where(x => sameRay(x, bearing)).ToArray();
        if (!geom.complete || leaders.Length == 0 || bars.Length == 0 || rays.Any(x => !sameRay(x, p) && !sameRay(x, bearing)))
            throw new System.Exception("PENDING_NATIVE_JOINT_ROLE_OR_EXTRA_BRANCH");
        // Extra branches at this joint are not covered by the simple-source adapter.
        if (profile == "index-paper" && g.Length == 7)
        {
            int bends = geom.lines.Count(x => x.Any(z => z.DistanceTo(elbow) < 1e-5));
            if (bends > 2) throw new System.Exception("PENDING_MULTIBRANCH_INDEX");
        }
        double angle = LeaderJointMath.Angle(P(leaders[0]), P(elbow), P(bars[0]));
        var pe = profile == "coord3-model" ? Map(v, elbow) : elbow;
        var pb = profile == "coord3-model" ? Map(v, bearing) : bearing;
        bool horizontal = Math.Abs(pe.Y - pb.Y) < 1e-5;
        bool textDirection = profile != "coord3-model" || geom.textRotations.Count == 2 && geom.textRotations.All(r => Math.Abs(Math.Atan2(Math.Sin(r + v.TwistAngle), Math.Cos(r + v.TwistAngle))) < 1e-6);
        bool pass = LeaderJointMath.Accept(angle) && horizontal && textDirection;
        if (requirePass && !pass) throw new System.Exception("POST_REAL_JOINT_" + angle.ToString("F6"));
        return new { status = pass ? "PASS" : "FAIL", angle_degrees = angle, horizontal, text_direction = textDirection, native_segments_verified = true, anchor = P(p), elbow = P(elbow), bearing = P(bearing), profile };
    }
    static void Move(Entity e, int i, Point3d target) { var g = Grips(e); e.MoveGripPointsAt(new IntegerCollection(new[] { i }), target - g[i]); }
    static string StableProps(Dictionary<string, object> a)
    {
        return new JavaScriptSerializer().Serialize(a.Where(x => x.Key != "LayoutRotation").OrderBy(x => x.Key).ToDictionary(x => x.Key, x => x.Value));
    }
    static void GuardExpected(Entity e, Dictionary<string, object> action, Point3d[] grips)
    {
        if (e.GetRXClass().Name != S(action, "rxclass") || e.Layer != S(action, "layer")) throw new System.Exception("BASELINE_CLASS_LAYER_CHANGED");
        var expected = (object[])action["expected_grips"];
        if (expected.Length != grips.Length) throw new System.Exception("BASELINE_GRIPS_CHANGED");
        for (int i = 0; i < grips.Length; i++) if (grips[i].DistanceTo(Point(expected[i])) > 1e-5) throw new System.Exception("BASELINE_GEOMETRY_CHANGED");
        var props = Dict(action["expected_properties"]);
        foreach (var item in props) if (Convert.ToString(Get(e, item.Key), System.Globalization.CultureInfo.InvariantCulture) != Convert.ToString(item.Value, System.Globalization.CultureInfo.InvariantCulture)) throw new System.Exception("BASELINE_PROPERTY_" + item.Key);
    }
    static Point3d QualifiedTarget(Entity e, Viewport v, Point3d oldWorld, Dictionary<string, object> action, Transaction tr)
    {
        var source = Dict(action["source"]);
        if (S(source, "state") != "active" || S(source, "feature_id") == "" || S(source, "evidence") == "") throw new System.Exception("PENDING_SOURCE_NOT_QUALIFIED");
        var c = tr.GetObject(Id(e.Database, S(source, "handle")), OpenMode.ForRead) as Curve;
        if (c == null || c.Layer != S(source, "layer") || c.OwnerId != SymbolUtilityServices.GetBlockModelSpaceId(e.Database)) throw new System.Exception("PENDING_SOURCE_CLASS_LAYER_OWNER");
        var target = action.ContainsKey("target_world") ? Point(action["target_world"]) : oldWorld;
        double tolerance = D(source, "tolerance");
        if (tolerance < 0 || tolerance > .1) throw new System.Exception("SOURCE_TOLERANCE");
        if (c.GetClosestPointTo(target, false).DistanceTo(target) > tolerance) throw new System.Exception("PENDING_TARGET_NOT_ON_SAME_FEATURE");
        if (target.DistanceTo(oldWorld) > D(action, "max_anchor_move") + 1e-6) throw new System.Exception("ANCHOR_MOVE_LIMIT");
        if (target.DistanceTo(oldWorld) > 1e-6 && S(source, "policy") != "relocate_same_feature") throw new System.Exception("ANCHOR_MOVE_NOT_AUTHORIZED");
        return target;
    }
    static object Inspect(Entity e, Viewport v)
    {
        var g = Grips(e); var geom = new Geometry(); Expand(e, geom, 0);
        string profile = "unknown"; object joint = null;
        try { profile = Profile(e, g, v); joint = Joint(e, g, profile, v, false); }
        catch (System.Exception ex) { joint = new { status = "PENDING", reason = ex.Message }; }
        return new { handle = e.Handle.ToString(), rxclass = e.GetRXClass().Name, layer = e.Layer, owner = e.OwnerId.Handle.ToString(), grips = g.Select(P).ToArray(), properties = Props(e), profile, joint, lines = geom.lines.Select(x => x.Select(P).ToArray()).ToArray(), texts = geom.texts, expanded_complete = geom.complete,
            viewport = new { handle = v.Handle.ToString(), center = P(v.CenterPoint), target = P(v.ViewTarget), view_center = new[] { v.ViewCenter.X, v.ViewCenter.Y }, scale = v.CustomScale, twist = v.TwistAngle, owner = v.OwnerId.Handle.ToString() } };
    }
    [CommandMethod("CXANNOTATIONBATCH", CommandFlags.Session)]
    public void Run()
    {
        var timer = Stopwatch.StartNew(); var js = new JavaScriptSerializer { MaxJsonLength = 16000000 };
        string output = null, jobId = null; bool receiptOwned = false;
        try
        {
            var doc = App.DocumentManager.MdiActiveDocument;
            var option = new PromptStringOptions("\nJob JSON path: ") { AllowSpaces = true };
            var request = doc.Editor.GetString(option);
            if (request.Status != PromptStatus.OK) return;
            string input = request.StringResult.Trim().Trim('"');
            var job = Dict(js.DeserializeObject(File.ReadAllText(input)));
            jobId = S(job, "job_id");
            if (jobId.Length == 0 || jobId.Length > 50 || jobId.Any(c => !char.IsLetterOrDigit(c) && c != '_')) throw new System.Exception("JOB_ID");
            output = Path.Combine(Path.GetDirectoryName(input), jobId + ".result.json");
            if (File.Exists(output) || File.Exists(output + ".started")) { doc.Editor.WriteMessage("\nDUPLICATE_JOB_NO_REPLAY"); return; }
            using (var marker = new FileStream(output + ".started", FileMode.CreateNew)) { }
            receiptOwned = true;
            if (!string.Equals(doc.Name, S(job, "document"), StringComparison.OrdinalIgnoreCase) || Process.GetCurrentProcess().Id != Convert.ToInt32(job["host_pid"])) throw new System.Exception("EXACT_HOST_DOCUMENT");
            string mode = S(job, "mode");
            if (mode != "inspect" && mode != "probe" && mode != "apply") throw new System.Exception("MODE");
            var rows = new List<object>(); int failed = 0, pending = 0, passed = 0, changed = 0;
            using (doc.LockDocument())
            {
                foreach (object raw in (object[])job["actions"])
                {
                    var a = Dict(raw); string handle = S(a, "handle"); var tick = Stopwatch.StartNew();
                    Point3d[] rollbackGrips = null; Dictionary<string, object> rollbackProps = null; ObjectId entityId = ObjectId.Null;
                    try
                    {
                        using (var tr = doc.Database.TransactionManager.StartTransaction())
                        {
                            entityId = Id(doc.Database, handle);
                            var e = (Entity)tr.GetObject(entityId, OpenMode.ForRead);
                            var v = (Viewport)tr.GetObject(Id(doc.Database, S(a, "viewport")), OpenMode.ForRead);
                            GuardViewport(v);
                            if (mode == "inspect") { rows.Add(new { status = "INSPECTED", handle, native = Inspect(e, v), elapsed_ms = tick.Elapsed.TotalMilliseconds }); passed++; continue; }
                            var g = Grips(e); GuardExpected(e, a, g);
                            rollbackGrips = g; rollbackProps = Props(e);
                            var source = Dict(a["source"]);
                            if (S(source, "state") != "active" && S(source, "state") != "cancelled") throw new System.Exception("PENDING_SOURCE_NOT_QUALIFIED");
                            if (S(source, "state") == "cancelled")
                            {
                                if (S(a, "operation") != "delete_cancelled" || S(source, "evidence") == "" || S(source, "feature_id") == "") throw new System.Exception("PENDING_CANCELLED_DELETE_INSTRUCTION");
                                e.UpgradeOpen(); e.Erase();
                                if (mode == "apply") { tr.Commit(); changed++; }
                                rows.Add(new { status = mode == "probe" ? "PROBE_PASS_DELETE_ROLLED_BACK" : "DELETED", handle, source = source, elapsed_ms = tick.Elapsed.TotalMilliseconds }); passed++;
                            }
                            else
                            {
                                string profile = Profile(e, g, v);
                                if (profile != S(a, "profile")) throw new System.Exception("PENDING_PROFILE_MISMATCH");
                                // Before geometry can be acute; native role/branch coverage must still be known.
                                Joint(e, g, profile, v, false);
                                var roles = Roles(profile);
                                var oldWorld = profile == "coord3-model" ? g[roles[0]] : Unmap(v, g[roles[0]]);
                                var target = QualifiedTarget(e, v, oldWorld, a, tr);
                                if (profile == "coord3-model" && target.DistanceTo(oldWorld) > 1e-6) throw new System.Exception("PENDING_COORDINATE_VALUE_CHANGE_SEPARATE_RECIPE");
                                var tip = Map(v, target); var elbow = Point(a["elbow_paper"]); var bearing = Point(a["bearing_paper"]);
                                double wanted = LeaderJointMath.Angle(P(tip), P(elbow), P(bearing));
                                if (!LeaderJointMath.Accept(wanted) || Math.Abs(bearing.Y - elbow.Y) > 1e-6) throw new System.Exception("PLANNED_ACUTE_DEGENERATE_OR_NONHORIZONTAL");
                                if (elbow.DistanceTo(tip) > D(a, "max_leader_paper") || Math.Abs(bearing.X - elbow.X) > D(a, "max_bearing_paper")) throw new System.Exception("PLAN_DISPLACEMENT_LIMIT");
                                e.UpgradeOpen();
                                if (profile == "coord3-model")
                                {
                                    double rotation = (-v.TwistAngle * 180 / Math.PI) % 360; if (rotation < 0) rotation += 360;
                                    Set(e, "LayoutRotation", rotation); Move(e, roles[1], Unmap(v, elbow)); Move(e, roles[2], Unmap(v, bearing));
                                }
                                else
                                {
                                    e.TransformBy(Matrix3d.Displacement(elbow - g[roles[1]]));
                                    Move(e, roles[0], tip); Move(e, roles[2], bearing);
                                }
                                var after = Grips(e);
                                var nativeTip = profile == "coord3-model" ? target : tip;
                                var nativeElbow = profile == "coord3-model" ? Unmap(v, elbow) : elbow;
                                var nativeBearing = profile == "coord3-model" ? Unmap(v, bearing) : bearing;
                                if (after.Length != g.Length || after[roles[0]].DistanceTo(nativeTip) > 1e-5 || after[roles[1]].DistanceTo(nativeElbow) > 1e-5 || after[roles[2]].DistanceTo(nativeBearing) > 1e-5 || StableProps(Props(e)) != StableProps(rollbackProps)) throw new System.Exception("POST_NATIVE_GEOMETRY_OR_CONTENT");
                                var joint = Joint(e, after, profile, v, true); e.RecordGraphicsModified(true);
                                if (mode == "apply") { tr.Commit(); changed++; }
                                rows.Add(new { status = mode == "probe" ? "PROBE_PASS_ROLLED_BACK" : "APPLIED", handle, source = source, before = g.Select(P).ToArray(), after = after.Select(P).ToArray(), joint, elapsed_ms = tick.Elapsed.TotalMilliseconds }); passed++;
                            }
                        }
                    }
                    catch (System.Exception ex)
                    {
                        bool isPending = ex.Message.StartsWith("PENDING_"); if (isPending) pending++; else failed++;
                        rows.Add(new { status = isPending ? "PENDING" : "FAILED", handle, reason = ex.Message, elapsed_ms = tick.Elapsed.TotalMilliseconds });
                    }
                    if (mode == "probe" && rollbackGrips != null)
                    {
                        using (var tr = doc.Database.TransactionManager.StartTransaction())
                        {
                            var e = (Entity)tr.GetObject(entityId, OpenMode.ForRead); var actual = Grips(e);
                            if (actual.Length != rollbackGrips.Length || actual.Where((p, i) => p.DistanceTo(rollbackGrips[i]) > 1e-6).Any() || js.Serialize(Props(e)) != js.Serialize(rollbackProps)) throw new System.Exception("PROBE_ROLLBACK_MISMATCH");
                        }
                    }
                }
                if (changed > 0) doc.Editor.Regen();
            }
            string status = failed > 0 || pending > 0 ? "PARTIAL" : mode == "probe" ? "PROBE_PASS" : mode == "inspect" ? "INSPECTED" : "PASS";
            File.WriteAllText(output, js.Serialize(new { status, job_id = jobId, module_version = Version, document = doc.Name, host_pid = Process.GetCurrentProcess().Id, mode, passed, failed, pending, changed, rows, elapsed_ms = timer.Elapsed.TotalMilliseconds, finished_utc = DateTime.UtcNow.ToString("o") }), new System.Text.UTF8Encoding(false));
        }
        catch (System.Exception ex)
        {
            if (receiptOwned && output != null) File.WriteAllText(output, js.Serialize(new { status = "FAIL", job_id = jobId, module_version = Version, error = ex.ToString(), elapsed_ms = timer.Elapsed.TotalMilliseconds }), new System.Text.UTF8Encoding(false));
            else App.DocumentManager.MdiActiveDocument.Editor.WriteMessage("\n" + ex.Message);
        }
    }
}
