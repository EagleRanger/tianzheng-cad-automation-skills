using System;
using System.Globalization;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexTzGripProbe
{
    public static class Commands
    {
        private static string Ask(Editor ed, string label)
        {
            var opts = new PromptStringOptions("\n" + label + ":") { AllowSpaces = true };
            var result = ed.GetString(opts);
            if (result.Status != PromptStatus.OK) throw new Autodesk.AutoCAD.Runtime.Exception(ErrorStatus.UserBreak);
            return result.StringResult.Trim();
        }

        private static ObjectId Resolve(Database db, string handleText)
        {
            long value;
            if (!long.TryParse(handleText, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value))
                throw new InvalidOperationException("INVALID_HANDLE");
            return db.GetObjectId(false, new Handle(value), 0);
        }

        private static GripDataCollection ReadAdvanced(Entity entity)
        {
            var grips = new GripDataCollection();
            entity.GetGripPoints(grips, 1.0, 5, Vector3d.ZAxis, GetGripPointsFlags.GripPointsOnly);
            return grips;
        }

        private static string Tooltip(GripData grip)
        {
            try { return grip.GetTooltip() ?? string.Empty; }
            catch { return string.Empty; }
        }

        private static void AppendEntityState(StringBuilder text, string stage, Entity entity)
        {
            text.AppendLine("STATE\t" + stage + "\t" + entity.Handle + "\t" + entity.GetType().FullName + "\t" + entity.GetRXClass().Name);

            var points = new Point3dCollection();
            var osnap = new IntegerCollection();
            var geometry = new IntegerCollection();
            try
            {
                entity.GetGripPoints(points, osnap, geometry);
                text.AppendLine("LEGACY_COUNT\t" + stage + "\t" + points.Count.ToString(CultureInfo.InvariantCulture));
                for (int i = 0; i < points.Count; i++)
                {
                    Point3d p = points[i];
                    text.AppendLine(string.Format(CultureInfo.InvariantCulture, "LEGACY\t{0}\t{1}\t{2:R}\t{3:R}\t{4:R}", stage, i, p.X, p.Y, p.Z));
                }
            }
            catch (System.Exception ex)
            {
                text.AppendLine("LEGACY_ERROR\t" + stage + "\t" + ex.GetType().Name + "\t" + ex.Message.Replace('\t', ' '));
            }

            try
            {
                GripDataCollection grips = ReadAdvanced(entity);
                text.AppendLine("ADVANCED_COUNT\t" + stage + "\t" + grips.Count.ToString(CultureInfo.InvariantCulture));
                for (int i = 0; i < grips.Count; i++)
                {
                    GripData g = grips[i];
                    Point3d p = g.GripPoint;
                    string tip = Tooltip(g).Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
                    text.AppendLine(string.Format(CultureInfo.InvariantCulture, "ADVANCED\t{0}\t{1}\t{2:R}\t{3:R}\t{4:R}\t{5}", stage, i, p.X, p.Y, p.Z, tip));
                }
            }
            catch (System.Exception ex)
            {
                text.AppendLine("ADVANCED_ERROR\t" + stage + "\t" + ex.GetType().Name + "\t" + ex.Message.Replace('\t', ' '));
            }
        }

        private sealed class BatchMoveSpec
        {
            public string HandleText;
            public string Mode;
            public double TargetOffset;
        }

        private sealed class NativeDimEndpointRepairSpec
        {
            public string HandleText;
            public Point3d EndpointA;
            public Point3d EndpointB;
        }

        private static List<NativeDimEndpointRepairSpec> ReadNativeDimEndpointRepairPlan(string planPath)
        {
            var result = new List<NativeDimEndpointRepairSpec>();
            foreach (string raw in File.ReadAllLines(planPath, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal)) continue;
                string[] parts = line.Split('\t');
                if (parts.Length < 5) throw new InvalidOperationException("ENDPOINT_REPAIR_PLAN_COLUMN_COUNT");
                if (parts[0].Equals("HANDLE", StringComparison.OrdinalIgnoreCase)) continue;
                double ax, ay, bx, by;
                if (!double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out ax)
                    || !double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out ay)
                    || !double.TryParse(parts[3], NumberStyles.Float, CultureInfo.InvariantCulture, out bx)
                    || !double.TryParse(parts[4], NumberStyles.Float, CultureInfo.InvariantCulture, out by))
                    throw new InvalidOperationException("ENDPOINT_REPAIR_PLAN_COORD_INVALID");
                result.Add(new NativeDimEndpointRepairSpec {
                    HandleText = parts[0].Trim().ToUpperInvariant(),
                    EndpointA = new Point3d(ax, ay, 0.0),
                    EndpointB = new Point3d(bx, by, 0.0)
                });
            }
            if (result.Count == 0) throw new InvalidOperationException("ENDPOINT_REPAIR_PLAN_EMPTY");
            return result;
        }

        private static List<BatchMoveSpec> ReadBatchMovePlan(string planPath)
        {
            var result = new List<BatchMoveSpec>();
            foreach (string raw in File.ReadAllLines(planPath, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal)) continue;
                string[] parts = line.Split('\t');
                if (parts.Length < 3) throw new InvalidOperationException("PLAN_COLUMN_COUNT");
                if (parts[0].Equals("HANDLE", StringComparison.OrdinalIgnoreCase)) continue;
                string mode = parts[1].Trim().ToUpperInvariant();
                if (mode != "FLIP" && mode != "KEEP") throw new InvalidOperationException("PLAN_MODE_INVALID:" + mode);
                double targetOffset;
                if (!double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out targetOffset) || targetOffset <= 0.0)
                    throw new InvalidOperationException("PLAN_OFFSET_INVALID:" + parts[2]);
                result.Add(new BatchMoveSpec {
                    HandleText = parts[0].Trim().ToUpperInvariant(),
                    Mode = mode,
                    TargetOffset = targetOffset
                });
            }
            if (result.Count == 0) throw new InvalidOperationException("PLAN_EMPTY");
            return result;
        }

        private static Point3d Mid(Point3d a, Point3d b)
        {
            return new Point3d((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5, (a.Z + b.Z) * 0.5);
        }

        [CommandMethod("CXGRIPAUDIT", CommandFlags.Session)]
        public static void GripAudit()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string handleText = Ask(ed, "HANDLE");
            string reportPath = Ask(ed, "REPORT_PATH");
            var text = new StringBuilder();
            text.AppendLine("STATUS\tBEGIN");
            try
            {
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    Entity entity = (Entity)tr.GetObject(Resolve(db, handleText), OpenMode.ForRead);
                    AppendEntityState(text, "BEFORE", entity);
                    tr.Commit();
                }
                text.AppendLine("STATUS\tPASS");
            }
            catch (System.Exception ex)
            {
                text.AppendLine("STATUS\tFAIL\t" + ex.GetType().FullName + "\t" + ex.Message.Replace('\t', ' '));
            }
            File.WriteAllText(reportPath, text.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXGRIPAUDIT_DONE");
        }

        private static bool IsTargetNativeAnnotation(Entity entity)
        {
            string typeName = entity.GetType().FullName ?? string.Empty;
            string rxName = entity.GetRXClass().Name ?? string.Empty;
            string identity = typeName + "|" + rxName;
            return identity.IndexOf("TDbRadiusDim", StringComparison.OrdinalIgnoreCase) >= 0
                || identity.IndexOf("TDbDimension2", StringComparison.OrdinalIgnoreCase) >= 0
                || identity.IndexOf("TDbSymbCoord", StringComparison.OrdinalIgnoreCase) >= 0
                || identity.IndexOf("TDbSymbIndexPointer", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static string CleanCell(string value)
        {
            return (value ?? string.Empty).Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
        }

        private static void CollectExplodedText(DBObject source, int depth, List<Tuple<string, Extents3d?>> output)
        {
            if (source == null || depth > 4) return;
            DBText dbText = source as DBText;
            if (dbText != null)
            {
                Extents3d? ext = null;
                try { ext = dbText.GeometricExtents; } catch { }
                output.Add(Tuple.Create(CleanCell(dbText.TextString), ext));
                return;
            }
            MText mText = source as MText;
            if (mText != null)
            {
                Extents3d? ext = null;
                try { ext = mText.GeometricExtents; } catch { }
                output.Add(Tuple.Create(CleanCell(mText.Contents), ext));
                return;
            }
            Entity entity = source as Entity;
            if (entity == null) return;
            var children = new DBObjectCollection();
            try
            {
                entity.Explode(children);
                foreach (DBObject child in children)
                {
                    try { CollectExplodedText(child, depth + 1, output); }
                    finally { child.Dispose(); }
                }
            }
            catch { }
        }

        [CommandMethod("CXNATIVEANNOTEXTAUDIT", CommandFlags.Session)]
        public static void NativeAnnotationTextAudit()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string reportPath = Ask(ed, "REPORT_PATH");
            var text = new StringBuilder();
            text.AppendLine("HANDLE\tRXCLASS\tLAYER\tTEXT_INDEX\tTEXT\tMIN_X\tMIN_Y\tMAX_X\tMAX_Y\tSEMANTIC\tSTATUS");
            int objects = 0, extracted = 0, failed = 0;
            try
            {
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    BlockTable table = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    BlockTableRecord model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                    foreach (ObjectId objectId in model)
                    {
                        Entity entity = tr.GetObject(objectId, OpenMode.ForRead, false) as Entity;
                        if (entity == null || !IsTargetNativeAnnotation(entity)) continue;
                        objects++;
                        string rx = entity.GetRXClass().Name ?? string.Empty;
                        var found = new List<Tuple<string, Extents3d?>>();
                        CollectExplodedText(entity, 0, found);
                        if (found.Count == 0)
                        {
                            text.AppendLine(string.Join("\t", new string[] { entity.Handle.ToString(), rx, CleanCell(entity.Layer), "", "", "", "", "", "", "UNKNOWN", "FAIL_NO_TEXT" }));
                            failed++;
                            continue;
                        }
                        for (int i = 0; i < found.Count; i++)
                        {
                            string value = found[i].Item1;
                            string upper = value.ToUpperInvariant();
                            string semantic = upper.Contains("\\U+00B0") || value.Contains("°") || upper.Contains("%%D") ? "ANGLE"
                                : upper.TrimStart().StartsWith("R", StringComparison.Ordinal) ? "RADIUS" : "OTHER";
                            string minX = "", minY = "", maxX = "", maxY = "";
                            if (found[i].Item2.HasValue)
                            {
                                Extents3d ext = found[i].Item2.Value;
                                minX = ext.MinPoint.X.ToString("R", CultureInfo.InvariantCulture);
                                minY = ext.MinPoint.Y.ToString("R", CultureInfo.InvariantCulture);
                                maxX = ext.MaxPoint.X.ToString("R", CultureInfo.InvariantCulture);
                                maxY = ext.MaxPoint.Y.ToString("R", CultureInfo.InvariantCulture);
                            }
                            text.AppendLine(string.Join("\t", new string[] { entity.Handle.ToString(), rx, CleanCell(entity.Layer), i.ToString(CultureInfo.InvariantCulture), value, minX, minY, maxX, maxY, semantic, "PASS" }));
                            extracted++;
                        }
                    }
                    tr.Commit();
                }
                text.AppendLine(string.Format(CultureInfo.InvariantCulture, "SUMMARY\tOBJECTS={0}\tTEXTS={1}\tFAILED_OBJECTS={2}\tSTATUS={3}", objects, extracted, failed, failed == 0 ? "PASS" : "FAIL"));
                File.WriteAllText(reportPath, text.ToString(), new UTF8Encoding(false));
                ed.WriteMessage("\nCXNATIVEANNOTEXTAUDIT_DONE objects=" + objects.ToString(CultureInfo.InvariantCulture) + " failed=" + failed.ToString(CultureInfo.InvariantCulture));
            }
            catch (System.Exception ex)
            {
                File.WriteAllText(reportPath + ".error.txt", ex.GetType().FullName + ":" + ex.Message, new UTF8Encoding(false));
                ed.WriteMessage("\nCXNATIVEANNOTEXTAUDIT_FAILED");
            }
        }

        [CommandMethod("CXNATIVEGRIPINVENTORY", CommandFlags.Session)]
        public static void NativeGripInventory()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string reportPath = Ask(ed, "REPORT_PATH");
            var text = new StringBuilder();
            text.AppendLine("HANDLE\tTYPE\tRXCLASS\tLAYER\tEXTMIN_X\tEXTMIN_Y\tEXTMAX_X\tEXTMAX_Y\tGRIP_INDEX\tGRIP_X\tGRIP_Y\tGRIP_Z\tTOOLTIP");
            int entities = 0;
            int gripRows = 0;
            try
            {
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    BlockTable table = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    BlockTableRecord model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                    foreach (ObjectId objectId in model)
                    {
                        Entity entity = tr.GetObject(objectId, OpenMode.ForRead, false) as Entity;
                        if (entity == null || !IsTargetNativeAnnotation(entity)) continue;
                        double minX = double.NaN, minY = double.NaN, maxX = double.NaN, maxY = double.NaN;
                        try
                        {
                            Extents3d bounds = entity.GeometricExtents;
                            minX = bounds.MinPoint.X; minY = bounds.MinPoint.Y;
                            maxX = bounds.MaxPoint.X; maxY = bounds.MaxPoint.Y;
                        }
                        catch { }
                        GripDataCollection grips = ReadAdvanced(entity);
                        for (int i = 0; i < grips.Count; i++)
                        {
                            Point3d p = grips[i].GripPoint;
                            string tip = Tooltip(grips[i]).Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
                            text.AppendLine(string.Format(CultureInfo.InvariantCulture,
                                "{0}\t{1}\t{2}\t{3}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8}\t{9:R}\t{10:R}\t{11:R}\t{12}",
                                entity.Handle, entity.GetType().FullName ?? string.Empty,
                                entity.GetRXClass().Name ?? string.Empty, entity.Layer ?? string.Empty,
                                minX, minY, maxX, maxY, i, p.X, p.Y, p.Z, tip));
                            gripRows++;
                        }
                        entities++;
                    }
                    tr.Commit();
                }
                File.WriteAllText(reportPath, text.ToString(), new UTF8Encoding(false));
                ed.WriteMessage("\nCXNATIVEGRIPINVENTORY_DONE entities=" + entities.ToString(CultureInfo.InvariantCulture)
                    + " grips=" + gripRows.ToString(CultureInfo.InvariantCulture));
            }
            catch (System.Exception ex)
            {
                File.WriteAllText(reportPath + ".error.txt", ex.GetType().FullName + ":" + ex.Message, new UTF8Encoding(false));
                ed.WriteMessage("\nCXNATIVEGRIPINVENTORY_FAILED");
            }
        }

        private sealed class GenericMoveSpec
        {
            public string HandleText;
            public int GripIndex;
            public double Dx;
            public double Dy;
            public double Dz;
        }

        [CommandMethod("CXNATIVECLONETRANSLATE", CommandFlags.Session)]
        public static void NativeCloneTranslate()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("SOURCE_HANDLE\tNEW_HANDLE\tTYPE\tDX\tDY\tDZ\tSTATUS");
            int cloned = 0;
            string status = "FAIL";
            string error = string.Empty;
            try
            {
                List<GenericMoveSpec> plan = ReadGenericMovePlan(planPath);
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    BlockTable table = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    BlockTableRecord model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForWrite);
                    foreach (GenericMoveSpec spec in plan)
                    {
                        Entity source = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForRead);
                        if (!IsTargetNativeAnnotation(source)) throw new InvalidOperationException("CLONE_TYPE_NOT_NATIVE_ANNO:" + spec.HandleText);
                        Entity clone = source.Clone() as Entity;
                        if (clone == null) throw new InvalidOperationException("CLONE_FAILED:" + spec.HandleText);
                        clone.TransformBy(Matrix3d.Displacement(new Vector3d(spec.Dx, spec.Dy, spec.Dz)));
                        ObjectId newId = model.AppendEntity(clone);
                        tr.AddNewlyCreatedDBObject(clone, true);
                        report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                            "{0}\t{1}\t{2}\t{3:R}\t{4:R}\t{5:R}\tPASS",
                            source.Handle, clone.Handle, clone.GetRXClass().Name, spec.Dx, spec.Dy, spec.Dz));
                        cloned++;
                    }
                    tr.Commit();
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t',' ').Replace('\r',' ').Replace('\n',' ');
            }
            report.AppendLine("SUMMARY\t" + status + "\t" + cloned.ToString(CultureInfo.InvariantCulture) + "\t" + error);
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXNATIVECLONETRANSLATE_DONE status=" + status + " count=" + (status == "PASS" ? cloned : 0).ToString(CultureInfo.InvariantCulture));
        }

        private static List<GenericMoveSpec> ReadGenericMovePlan(string planPath)
        {
            var result = new List<GenericMoveSpec>();
            foreach (string raw in File.ReadAllLines(planPath, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal)) continue;
                string[] parts = line.Split('\t');
                if (parts.Length < 5) throw new InvalidOperationException("GENERIC_PLAN_COLUMN_COUNT");
                if (parts[0].Equals("HANDLE", StringComparison.OrdinalIgnoreCase)) continue;
                int gripIndex;
                double dx, dy, dz;
                if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out gripIndex) || gripIndex < 0)
                    throw new InvalidOperationException("GENERIC_PLAN_GRIP_INVALID:" + parts[1]);
                if (!double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out dx)
                    || !double.TryParse(parts[3], NumberStyles.Float, CultureInfo.InvariantCulture, out dy)
                    || !double.TryParse(parts[4], NumberStyles.Float, CultureInfo.InvariantCulture, out dz))
                    throw new InvalidOperationException("GENERIC_PLAN_DELTA_INVALID");
                result.Add(new GenericMoveSpec { HandleText = parts[0].Trim().ToUpperInvariant(), GripIndex = gripIndex, Dx = dx, Dy = dy, Dz = dz });
            }
            if (result.Count == 0) throw new InvalidOperationException("GENERIC_PLAN_EMPTY");
            return result;
        }

        [CommandMethod("CXGENERICGRIPBATCHMOVE", CommandFlags.Session)]
        public static void GenericGripBatchMove()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("HANDLE\tTYPE\tGRIP_INDEX\tDX\tDY\tDZ\tREQUEST_LENGTH\tSELECTED_GRIP_MOVE\tMOVE_COSINE\tANCHOR_DRIFT\tSTATUS");
            int moved = 0;
            string status = "FAIL";
            string error = string.Empty;
            var timer = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                List<GenericMoveSpec> plan = ReadGenericMovePlan(planPath);
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    foreach (GenericMoveSpec spec in plan)
                    {
                        Entity entity = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite);
                        if (!IsTargetNativeAnnotation(entity))
                            throw new InvalidOperationException("GENERIC_TYPE_NOT_NATIVE_ANNO:" + spec.HandleText);
                        GripDataCollection before = ReadAdvanced(entity);
                        if (spec.GripIndex >= before.Count) throw new InvalidOperationException("GENERIC_GRIP_RANGE:" + spec.HandleText);
                        Point3d anchorBefore = before[0].GripPoint;
                        Point3d selectedBefore = before[spec.GripIndex].GripPoint;
                        Vector3d requestedMove = new Vector3d(spec.Dx, spec.Dy, spec.Dz);
                        Point3d sourceABefore = before.Count > 3 ? before[2].GripPoint : Point3d.Origin;
                        Point3d sourceBBefore = before.Count > 3 ? before[3].GripPoint : Point3d.Origin;
                        var selected = new GripDataCollection { before[spec.GripIndex] };
                        entity.MoveGripPointsAt(selected, requestedMove, (MoveGripPointsFlags)0);
                        entity.RecordGraphicsModified(true);
                        GripDataCollection after = ReadAdvanced(entity);
                        if (after.Count != before.Count) throw new InvalidOperationException("GENERIC_GRIP_COUNT_CHANGED:" + spec.HandleText);
                        double anchorDrift = anchorBefore.DistanceTo(after[0].GripPoint);
                        Vector3d actualMove = after[spec.GripIndex].GripPoint - selectedBefore;
                        double requestLength = requestedMove.Length;
                        double selectedGripMove = actualMove.Length;
                        double moveCosine = requestLength > 1.0e-9 && selectedGripMove > 1.0e-9
                            ? requestedMove.DotProduct(actualMove) / (requestLength * selectedGripMove)
                            : 1.0;
                        string typeName = entity.GetType().FullName ?? string.Empty;
                        string rxName = entity.GetRXClass().Name ?? string.Empty;
                        bool dimension2 = rxName.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase);
                        double sourceDrift = dimension2 && after.Count > 3
                            ? Math.Max(sourceABefore.DistanceTo(after[2].GripPoint), sourceBBefore.DistanceTo(after[3].GripPoint)) : 0.0;
                        if (dimension2 && sourceDrift > 1.0e-6)
                            throw new InvalidOperationException("GENERIC_SOURCE_DRIFT:" + spec.HandleText);
                        if (!dimension2 && spec.GripIndex != 0 && anchorDrift > 1.0e-6)
                            throw new InvalidOperationException("GENERIC_ANCHOR_DRIFT:" + spec.HandleText);
                        if (requestLength > 1.0e-6)
                        {
                            double minimumEffectiveMove = Math.Max(1.0e-6, requestLength * 0.05);
                            if (selectedGripMove < minimumEffectiveMove)
                                throw new InvalidOperationException("GENERIC_MOVE_NOT_APPLIED:" + spec.HandleText);
                            if (moveCosine < 0.25)
                                throw new InvalidOperationException("GENERIC_MOVE_WRONG_DIRECTION:" + spec.HandleText);
                        }
                        report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                            "{0}\t{1}\t{2}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8:R}\t{9:R}\tPASS",
                            entity.Handle, typeName, spec.GripIndex, spec.Dx, spec.Dy, spec.Dz,
                            requestLength, selectedGripMove, moveCosine, anchorDrift));
                        moved++;
                    }
                    tr.Commit();
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
            }
            timer.Stop();
            report.AppendLine("SUMMARY\t" + status + "\t" + moved.ToString(CultureInfo.InvariantCulture)
                + "\t" + timer.Elapsed.TotalMilliseconds.ToString("F3", CultureInfo.InvariantCulture) + "\t" + error);
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXGENERICGRIPBATCHMOVE_DONE status=" + status + " count=" + (status == "PASS" ? moved : 0).ToString(CultureInfo.InvariantCulture));
        }

        [CommandMethod("CXNATIVEDIMENDPOINTREPAIR", CommandFlags.Session)]
        public static void NativeDimEndpointRepair()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("HANDLE\tRXCLASS\tBEFORE_A_X\tBEFORE_A_Y\tBEFORE_B_X\tBEFORE_B_Y\tTARGET_A_X\tTARGET_A_Y\tTARGET_B_X\tTARGET_B_Y\tAFTER_A_X\tAFTER_A_Y\tAFTER_B_X\tAFTER_B_Y\tMAX_ERROR\tSTATUS");
            int repaired = 0;
            string status = "FAIL";
            string error = string.Empty;
            var timer = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                List<NativeDimEndpointRepairSpec> plan = ReadNativeDimEndpointRepairPlan(planPath);
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    foreach (NativeDimEndpointRepairSpec spec in plan)
                    {
                        Entity entity = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite);
                        string rxName = entity.GetRXClass().Name ?? string.Empty;
                        if (!rxName.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("ENDPOINT_REPAIR_NOT_TDBDIMENSION2:" + spec.HandleText + ":" + rxName);
                        GripDataCollection before = ReadAdvanced(entity);
                        if (before.Count < 4) throw new InvalidOperationException("ENDPOINT_REPAIR_GRIP_COUNT:" + spec.HandleText);
                        Point3d beforeA = before[2].GripPoint;
                        Point3d beforeB = before[3].GripPoint;

                        // Preserve the native object's current endpoint orientation whenever possible.
                        double direct = beforeA.DistanceTo(spec.EndpointA) + beforeB.DistanceTo(spec.EndpointB);
                        double reverse = beforeA.DistanceTo(spec.EndpointB) + beforeB.DistanceTo(spec.EndpointA);
                        Point3d targetForGrip2 = direct <= reverse ? spec.EndpointA : spec.EndpointB;
                        Point3d targetForGrip3 = direct <= reverse ? spec.EndpointB : spec.EndpointA;

                        Point3d afterA = beforeA;
                        Point3d afterB = beforeB;
                        double maxError = double.MaxValue;
                        for (int iteration = 0; iteration < 16; iteration++)
                        {
                            GripDataCollection current = ReadAdvanced(entity);
                            if (current.Count < 4) throw new InvalidOperationException("ENDPOINT_REPAIR_ITER_GRIP_COUNT:" + spec.HandleText);
                            var selected2 = new GripDataCollection { current[2] };
                            entity.MoveGripPointsAt(selected2, targetForGrip2 - current[2].GripPoint, (MoveGripPointsFlags)0);
                            entity.RecordGraphicsModified(true);

                            GripDataCollection middle = ReadAdvanced(entity);
                            if (middle.Count < 4) throw new InvalidOperationException("ENDPOINT_REPAIR_MIDDLE_GRIP_COUNT:" + spec.HandleText);
                            var selected3 = new GripDataCollection { middle[3] };
                            entity.MoveGripPointsAt(selected3, targetForGrip3 - middle[3].GripPoint, (MoveGripPointsFlags)0);
                            entity.RecordGraphicsModified(true);

                            GripDataCollection after = ReadAdvanced(entity);
                            if (after.Count < 4) throw new InvalidOperationException("ENDPOINT_REPAIR_AFTER_GRIP_COUNT:" + spec.HandleText);
                            afterA = after[2].GripPoint;
                            afterB = after[3].GripPoint;
                            double errorDirect = Math.Max(afterA.DistanceTo(spec.EndpointA), afterB.DistanceTo(spec.EndpointB));
                            double errorReverse = Math.Max(afterA.DistanceTo(spec.EndpointB), afterB.DistanceTo(spec.EndpointA));
                            maxError = Math.Min(errorDirect, errorReverse);
                            report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                                "TRACE\t{0}\tITER={1}\tA={2:R},{3:R}\tB={4:R},{5:R}\tERROR={6:R}",
                                entity.Handle, iteration + 1, afterA.X, afterA.Y, afterB.X, afterB.Y, maxError));
                            if (maxError <= 1.0e-6) break;
                        }
                        if (maxError > 1.0e-6)
                        {
                            report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                                "{0}\t{1}\t{2:R}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8:R}\t{9:R}\t{10:R}\t{11:R}\t{12:R}\t{13:R}\t{14:R}\tFAIL",
                                entity.Handle, rxName, beforeA.X, beforeA.Y, beforeB.X, beforeB.Y,
                                spec.EndpointA.X, spec.EndpointA.Y, spec.EndpointB.X, spec.EndpointB.Y,
                                afterA.X, afterA.Y, afterB.X, afterB.Y, maxError));
                            throw new InvalidOperationException("ENDPOINT_REPAIR_VERIFY_FAILED:" + spec.HandleText + ":" + maxError.ToString("R", CultureInfo.InvariantCulture));
                        }
                        report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                            "{0}\t{1}\t{2:R}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8:R}\t{9:R}\t{10:R}\t{11:R}\t{12:R}\t{13:R}\t{14:R}\tPASS",
                            entity.Handle, rxName, beforeA.X, beforeA.Y, beforeB.X, beforeB.Y,
                            spec.EndpointA.X, spec.EndpointA.Y, spec.EndpointB.X, spec.EndpointB.Y,
                            afterA.X, afterA.Y, afterB.X, afterB.Y, maxError));
                        repaired++;
                    }
                    tr.Commit();
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
            }
            timer.Stop();
            report.AppendLine("SUMMARY\t" + status + "\t" + repaired.ToString(CultureInfo.InvariantCulture)
                + "\t" + timer.Elapsed.TotalMilliseconds.ToString("F3", CultureInfo.InvariantCulture) + "\t" + error);
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXNATIVEDIMENDPOINTREPAIR_DONE status=" + status + " count=" + (status == "PASS" ? repaired : 0).ToString(CultureInfo.InvariantCulture));
        }

        [CommandMethod("CXNATIVEDIMGRIP0ENDPOINTRESTORE", CommandFlags.Session)]
        public static void NativeDimGrip0EndpointRestore()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("HANDLE\tDX\tDY\tGRIP0_DX\tGRIP0_DY\tGRIP1_DX\tGRIP1_DY\tTEXT_DX\tTEXT_DY\tSOURCE_DRIFT\tMOVE_COSINE\tSTATUS");
            int moved = 0;
            string status = "FAIL";
            string error = string.Empty;
            try
            {
                List<GenericMoveSpec> plan = ReadGenericMovePlan(planPath);
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    foreach (GenericMoveSpec spec in plan)
                    {
                        if (spec.GripIndex != 0)
                            throw new InvalidOperationException("GRIP0_RESTORE_PLAN_INDEX_INVALID:" + spec.HandleText);
                        Entity entity = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite);
                        string rxName = entity.GetRXClass().Name ?? string.Empty;
                        if (!rxName.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("GRIP0_RESTORE_NOT_TDBDIMENSION2:" + spec.HandleText);
                        GripDataCollection before = ReadAdvanced(entity);
                        if (before.Count < 5)
                            throw new InvalidOperationException("GRIP0_RESTORE_GRIP_COUNT:" + spec.HandleText);
                        Point3d grip0Before = before[0].GripPoint;
                        Point3d grip1Before = before[1].GripPoint;
                        Point3d sourceABefore = before[2].GripPoint;
                        Point3d sourceBBefore = before[3].GripPoint;
                        Point3d textBefore = before[4].GripPoint;
                        Vector3d requested = new Vector3d(spec.Dx, spec.Dy, spec.Dz);

                        var selected0 = new GripDataCollection { before[0] };
                        entity.MoveGripPointsAt(selected0, requested, (MoveGripPointsFlags)0);
                        entity.RecordGraphicsModified(true);

                        for (int iteration = 0; iteration < 32; iteration++)
                        {
                            GripDataCollection current = ReadAdvanced(entity);
                            if (current.Count < 5)
                                throw new InvalidOperationException("GRIP0_RESTORE_ITER_GRIP_COUNT:" + spec.HandleText);
                            var selected2 = new GripDataCollection { current[2] };
                            entity.MoveGripPointsAt(selected2, sourceABefore - current[2].GripPoint, (MoveGripPointsFlags)0);
                            entity.RecordGraphicsModified(true);
                            GripDataCollection middle = ReadAdvanced(entity);
                            var selected3 = new GripDataCollection { middle[3] };
                            entity.MoveGripPointsAt(selected3, sourceBBefore - middle[3].GripPoint, (MoveGripPointsFlags)0);
                            entity.RecordGraphicsModified(true);
                            GripDataCollection restored = ReadAdvanced(entity);
                            double iterationDrift = Math.Max(
                                sourceABefore.DistanceTo(restored[2].GripPoint),
                                sourceBBefore.DistanceTo(restored[3].GripPoint));
                            if (iterationDrift <= 1.0e-6) break;
                        }

                        GripDataCollection after = ReadAdvanced(entity);
                        Vector3d grip0Move = after[0].GripPoint - grip0Before;
                        Vector3d grip1Move = after[1].GripPoint - grip1Before;
                        Vector3d textMove = after[4].GripPoint - textBefore;
                        double sourceDrift = Math.Max(
                            sourceABefore.DistanceTo(after[2].GripPoint),
                            sourceBBefore.DistanceTo(after[3].GripPoint));
                        double requestLength = requested.Length;
                        double grip0Length = grip0Move.Length;
                        double moveCosine = requestLength > 1.0e-9 && grip0Length > 1.0e-9
                            ? requested.DotProduct(grip0Move) / (requestLength * grip0Length)
                            : 1.0;
                        if (sourceDrift > 1.0e-6)
                            throw new InvalidOperationException("GRIP0_RESTORE_SOURCE_DRIFT:" + spec.HandleText + ":" + sourceDrift.ToString("R", CultureInfo.InvariantCulture));
                        if (requestLength > 1.0e-6 && grip0Length < Math.Max(1.0e-6, requestLength * 0.05))
                            throw new InvalidOperationException("GRIP0_RESTORE_MOVE_NOT_APPLIED:" + spec.HandleText);
                        if (requestLength > 1.0e-6 && moveCosine < 0.25)
                            throw new InvalidOperationException("GRIP0_RESTORE_WRONG_DIRECTION:" + spec.HandleText);
                        report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                            "{0}\t{1:R}\t{2:R}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8:R}\t{9:R}\t{10:R}\tPASS",
                            entity.Handle, spec.Dx, spec.Dy, grip0Move.X, grip0Move.Y,
                            grip1Move.X, grip1Move.Y, textMove.X, textMove.Y, sourceDrift, moveCosine));
                        moved++;
                    }
                    tr.Commit();
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
            }
            report.AppendLine("SUMMARY\t" + status + "\t" + moved.ToString(CultureInfo.InvariantCulture) + "\t" + error);
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXNATIVEDIMGRIP0ENDPOINTRESTORE_DONE status=" + status + " count=" + (status == "PASS" ? moved : 0).ToString(CultureInfo.InvariantCulture));
        }

        [CommandMethod("CXNATIVEDIMDUALGRIPMOVE", CommandFlags.Session)]
        public static void NativeDimDualGripMove()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("HANDLE\tDX\tDY\tGRIP0_DX\tGRIP0_DY\tGRIP1_DX\tGRIP1_DY\tTEXT_DX\tTEXT_DY\tSOURCE_DRIFT\tSTATUS");
            int moved = 0;
            string status = "FAIL";
            string error = string.Empty;
            try
            {
                List<GenericMoveSpec> plan = ReadGenericMovePlan(planPath);
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    foreach (GenericMoveSpec spec in plan)
                    {
                        if (spec.GripIndex != 0)
                            throw new InvalidOperationException("DUAL_GRIP_PLAN_INDEX_INVALID:" + spec.HandleText);
                        Entity entity = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite);
                        string rxName = entity.GetRXClass().Name ?? string.Empty;
                        if (!rxName.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("DUAL_GRIP_NOT_TDBDIMENSION2:" + spec.HandleText);
                        GripDataCollection before = ReadAdvanced(entity);
                        if (before.Count < 5)
                            throw new InvalidOperationException("DUAL_GRIP_COUNT:" + spec.HandleText);
                        Point3d grip0Before = before[0].GripPoint;
                        Point3d grip1Before = before[1].GripPoint;
                        Point3d sourceABefore = before[2].GripPoint;
                        Point3d sourceBBefore = before[3].GripPoint;
                        Point3d textBefore = before[4].GripPoint;
                        Vector3d requested = new Vector3d(spec.Dx, spec.Dy, spec.Dz);
                        var selected = new GripDataCollection { before[0], before[1] };
                        entity.MoveGripPointsAt(selected, requested, (MoveGripPointsFlags)0);
                        entity.RecordGraphicsModified(true);
                        GripDataCollection after = ReadAdvanced(entity);
                        Vector3d grip0Move = after[0].GripPoint - grip0Before;
                        Vector3d grip1Move = after[1].GripPoint - grip1Before;
                        Vector3d textMove = after[4].GripPoint - textBefore;
                        double sourceDrift = Math.Max(
                            sourceABefore.DistanceTo(after[2].GripPoint),
                            sourceBBefore.DistanceTo(after[3].GripPoint));
                        if (sourceDrift > 1.0e-6)
                            throw new InvalidOperationException("DUAL_GRIP_SOURCE_DRIFT:" + spec.HandleText + ":" + sourceDrift.ToString("R", CultureInfo.InvariantCulture));
                        if (requested.Length > 1.0e-6 &&
                            (grip0Move.Length < requested.Length * 0.05 || grip1Move.Length < requested.Length * 0.05))
                            throw new InvalidOperationException("DUAL_GRIP_MOVE_NOT_APPLIED:" + spec.HandleText);
                        report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                            "{0}\t{1:R}\t{2:R}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8:R}\t{9:R}\tPASS",
                            entity.Handle, spec.Dx, spec.Dy, grip0Move.X, grip0Move.Y,
                            grip1Move.X, grip1Move.Y, textMove.X, textMove.Y, sourceDrift));
                        moved++;
                    }
                    tr.Commit();
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
            }
            report.AppendLine("SUMMARY\t" + status + "\t" + moved.ToString(CultureInfo.InvariantCulture) + "\t" + error);
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXNATIVEDIMDUALGRIPMOVE_DONE status=" + status + " count=" + (status == "PASS" ? moved : 0).ToString(CultureInfo.InvariantCulture));
        }

        [CommandMethod("CXNATIVEDIMGRIPRESPONSEPROBE", CommandFlags.Session)]
        public static void NativeDimGripResponseProbe()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("HANDLE\tGRIP_INDEX\tINPUT_DX\tINPUT_DY\tA_DX\tA_DY\tB_DX\tB_DY\tSTATUS");
            int probed = 0;
            string status = "FAIL";
            string error = string.Empty;
            try
            {
                List<GenericMoveSpec> plan = ReadGenericMovePlan(planPath);
                using (DocumentLock docLock = doc.LockDocument())
                {
                    foreach (GenericMoveSpec spec in plan)
                    {
                        using (Transaction tr = db.TransactionManager.StartTransaction())
                        {
                            Entity entity = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite);
                            string rxName = entity.GetRXClass().Name ?? string.Empty;
                            if (!rxName.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase))
                                throw new InvalidOperationException("GRIP_RESPONSE_NOT_TDBDIMENSION2:" + spec.HandleText);
                            GripDataCollection before = ReadAdvanced(entity);
                            if (before.Count < 4 || (spec.GripIndex != 2 && spec.GripIndex != 3))
                                throw new InvalidOperationException("GRIP_RESPONSE_INPUT_INVALID:" + spec.HandleText);
                            Point3d beforeA = before[2].GripPoint;
                            Point3d beforeB = before[3].GripPoint;
                            var selected = new GripDataCollection { before[spec.GripIndex] };
                            entity.MoveGripPointsAt(selected, new Vector3d(spec.Dx, spec.Dy, spec.Dz), (MoveGripPointsFlags)0);
                            entity.RecordGraphicsModified(true);
                            GripDataCollection after = ReadAdvanced(entity);
                            if (after.Count < 4) throw new InvalidOperationException("GRIP_RESPONSE_AFTER_COUNT:" + spec.HandleText);
                            Vector3d deltaA = after[2].GripPoint - beforeA;
                            Vector3d deltaB = after[3].GripPoint - beforeB;
                            report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                                "{0}\t{1}\t{2:R}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\tPASS",
                                entity.Handle, spec.GripIndex, spec.Dx, spec.Dy, deltaA.X, deltaA.Y, deltaB.X, deltaB.Y));
                            probed++;
                            tr.Abort();
                        }
                    }
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
            }
            report.AppendLine("SUMMARY\t" + status + "\t" + probed.ToString(CultureInfo.InvariantCulture) + "\t" + error);
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXNATIVEDIMGRIPRESPONSEPROBE_DONE status=" + status + " count=" + probed.ToString(CultureInfo.InvariantCulture));
        }

        [CommandMethod("CXNATIVEANNOINVENTORY", CommandFlags.Session)]
        public static void NativeAnnotationInventory()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string reportPath = Ask(ed, "REPORT_PATH");
            var text = new StringBuilder();
            text.AppendLine("HANDLE\tTYPE\tRXCLASS\tLAYER\tLEGACY_GRIPS\tADVANCED_GRIPS\tEXTMIN\tEXTMAX");
            int matched = 0;
            try
            {
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    BlockTable table = (BlockTable)tr.GetObject(db.BlockTableId, OpenMode.ForRead);
                    BlockTableRecord model = (BlockTableRecord)tr.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                    foreach (ObjectId objectId in model)
                    {
                        Entity entity = tr.GetObject(objectId, OpenMode.ForRead, false) as Entity;
                        if (entity == null || !IsTargetNativeAnnotation(entity)) continue;
                        int legacyCount = -1;
                        int advancedCount = -1;
                        try
                        {
                            var points = new Point3dCollection();
                            var osnap = new IntegerCollection();
                            var geometry = new IntegerCollection();
                            entity.GetGripPoints(points, osnap, geometry);
                            legacyCount = points.Count;
                        }
                        catch { }
                        try { advancedCount = ReadAdvanced(entity).Count; }
                        catch { }
                        string minimum = string.Empty;
                        string maximum = string.Empty;
                        try
                        {
                            Extents3d bounds = entity.GeometricExtents;
                            minimum = string.Format(CultureInfo.InvariantCulture, "{0:R},{1:R},{2:R}", bounds.MinPoint.X, bounds.MinPoint.Y, bounds.MinPoint.Z);
                            maximum = string.Format(CultureInfo.InvariantCulture, "{0:R},{1:R},{2:R}", bounds.MaxPoint.X, bounds.MaxPoint.Y, bounds.MaxPoint.Z);
                        }
                        catch { }
                        text.AppendLine(string.Join("\t", new string[] {
                            entity.Handle.ToString(),
                            entity.GetType().FullName ?? string.Empty,
                            entity.GetRXClass().Name ?? string.Empty,
                            entity.Layer ?? string.Empty,
                            legacyCount.ToString(CultureInfo.InvariantCulture),
                            advancedCount.ToString(CultureInfo.InvariantCulture),
                            minimum,
                            maximum
                        }));
                        matched++;
                    }
                    tr.Commit();
                }
                File.WriteAllText(reportPath, text.ToString(), new UTF8Encoding(false));
                ed.WriteMessage("\nCXNATIVEANNOINVENTORY_DONE count=" + matched.ToString(CultureInfo.InvariantCulture));
            }
            catch (System.Exception ex)
            {
                File.WriteAllText(reportPath + ".error.txt", ex.GetType().FullName + ":" + ex.Message, new UTF8Encoding(false));
                ed.WriteMessage("\nCXNATIVEANNOINVENTORY_FAILED");
            }
        }

        [CommandMethod("CXGRIPMOVE", CommandFlags.Session)]
        public static void GripMove()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string handleText = Ask(ed, "HANDLE");
            int index = int.Parse(Ask(ed, "GRIP_INDEX"), CultureInfo.InvariantCulture);
            double dx = double.Parse(Ask(ed, "DX"), CultureInfo.InvariantCulture);
            double dy = double.Parse(Ask(ed, "DY"), CultureInfo.InvariantCulture);
            double dz = double.Parse(Ask(ed, "DZ"), CultureInfo.InvariantCulture);
            string reportPath = Ask(ed, "REPORT_PATH");
            var text = new StringBuilder();
            text.AppendLine("STATUS\tBEGIN");
            try
            {
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    Entity entity = (Entity)tr.GetObject(Resolve(db, handleText), OpenMode.ForWrite);
                    AppendEntityState(text, "BEFORE", entity);
                    GripDataCollection all = ReadAdvanced(entity);
                    if (index < 0 || index >= all.Count) throw new IndexOutOfRangeException("GRIP_INDEX_OUT_OF_RANGE");
                    var selected = new GripDataCollection { all[index] };
                    entity.MoveGripPointsAt(selected, new Vector3d(dx, dy, dz), (MoveGripPointsFlags)0);
                    entity.RecordGraphicsModified(true);
                    AppendEntityState(text, "AFTER", entity);
                    tr.Commit();
                }
                ed.Regen();
                text.AppendLine("STATUS\tPASS");
            }
            catch (System.Exception ex)
            {
                text.AppendLine("STATUS\tFAIL\t" + ex.GetType().FullName + "\t" + ex.Message.Replace('\t', ' '));
            }
            File.WriteAllText(reportPath, text.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXGRIPMOVE_DONE");
        }

        [CommandMethod("CXGRIPBATCHMOVE", CommandFlags.Session)]
        public static void GripBatchMove()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            Database db = doc.Database;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            string detailPath = Path.Combine(
                Path.GetDirectoryName(reportPath) ?? string.Empty,
                Path.GetFileNameWithoutExtension(reportPath) + ".details.tsv");
            var summary = new StringBuilder();
            var details = new StringBuilder();
            details.AppendLine("HANDLE\tMODE\tTARGET_OFFSET\tBEFORE_OFFSET\tAFTER_OFFSET\tSIDE_DOT\tSOURCE_DRIFT\tOFFSET_ERROR\tTYPE\tSTATUS");
            var timer = System.Diagnostics.Stopwatch.StartNew();
            int moved = 0;
            double maxSourceDrift = 0.0;
            double maxOffsetError = 0.0;
            string status = "FAIL";
            string error = string.Empty;
            int planCount = 0;
            try
            {
                List<BatchMoveSpec> plan = ReadBatchMovePlan(planPath);
                planCount = plan.Count;
                using (DocumentLock docLock = doc.LockDocument())
                using (Transaction tr = db.TransactionManager.StartTransaction())
                {
                    foreach (BatchMoveSpec spec in plan)
                    {
                        Entity entity = (Entity)tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite);
                        string typeName = entity.GetType().FullName;
                        string rxName = entity.GetRXClass().Name ?? string.Empty;
                        if (!rxName.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase))
                            throw new InvalidOperationException("TYPE_NOT_TDBDIMENSION2:" + spec.HandleText + ":" + typeName + ":" + rxName);

                        GripDataCollection before = ReadAdvanced(entity);
                        if (before.Count < 4) throw new InvalidOperationException("GRIP_CONTRACT_FAILED:" + spec.HandleText);
                        Point3d sourceA = before[2].GripPoint;
                        Point3d sourceB = before[3].GripPoint;
                        Point3d sourceMid = Mid(sourceA, sourceB);
                        Point3d dimMid = Mid(before[0].GripPoint, before[1].GripPoint);
                        Vector3d beforeVector = dimMid - sourceMid;
                        double beforeOffset = beforeVector.Length;
                        if (beforeOffset <= 1.0e-9) throw new InvalidOperationException("ZERO_CURRENT_OFFSET:" + spec.HandleText);
                        Vector3d direction = beforeVector.GetNormal();
                        if (spec.Mode == "FLIP") direction = direction.Negate();
                        Point3d targetMid = sourceMid + direction.MultiplyBy(spec.TargetOffset);
                        Vector3d delta = targetMid - dimMid;
                        var selected = new GripDataCollection { before[0] };
                        entity.MoveGripPointsAt(selected, delta, (MoveGripPointsFlags)0);
                        entity.RecordGraphicsModified(true);

                        GripDataCollection after = ReadAdvanced(entity);
                        if (after.Count < 4) throw new InvalidOperationException("POST_GRIP_CONTRACT_FAILED:" + spec.HandleText);
                        Point3d afterSourceA = after[2].GripPoint;
                        Point3d afterSourceB = after[3].GripPoint;
                        double sourceDrift = Math.Max(sourceA.DistanceTo(afterSourceA), sourceB.DistanceTo(afterSourceB));
                        Point3d afterSourceMid = Mid(afterSourceA, afterSourceB);
                        Point3d afterDimMid = Mid(after[0].GripPoint, after[1].GripPoint);
                        Vector3d afterVector = afterDimMid - afterSourceMid;
                        double afterOffset = afterVector.Length;
                        double sideDot = beforeVector.DotProduct(afterVector);
                        double offsetError = Math.Abs(afterOffset - spec.TargetOffset);
                        bool sideOk = spec.Mode == "FLIP" ? sideDot < 0.0 : sideDot > 0.0;
                        bool sourceOk = sourceDrift <= 1.0e-6;
                        if (!sideOk) throw new InvalidOperationException("SIDE_VERIFY_FAILED:" + spec.HandleText);
                        if (!sourceOk) throw new InvalidOperationException("SOURCE_DRIFT_FAILED:" + spec.HandleText);

                        maxSourceDrift = Math.Max(maxSourceDrift, sourceDrift);
                        maxOffsetError = Math.Max(maxOffsetError, offsetError);
                        moved++;
                        details.AppendLine(string.Format(CultureInfo.InvariantCulture,
                            "{0}\t{1}\t{2:R}\t{3:R}\t{4:R}\t{5:R}\t{6:R}\t{7:R}\t{8}\tPASS",
                            entity.Handle, spec.Mode, spec.TargetOffset, beforeOffset, afterOffset,
                            sideDot, sourceDrift, offsetError, typeName));
                    }
                    tr.Commit();
                }
                ed.Regen();
                status = "PASS";
            }
            catch (System.Exception ex)
            {
                error = ex.GetType().FullName + ":" + ex.Message.Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
            }
            timer.Stop();
            summary.AppendLine("KEY\tVALUE");
            summary.AppendLine("STATUS\t" + status);
            summary.AppendLine("PLAN_COUNT\t" + planCount.ToString(CultureInfo.InvariantCulture));
            summary.AppendLine("MOVED_COUNT\t" + (status == "PASS" ? moved : 0).ToString(CultureInfo.InvariantCulture));
            summary.AppendLine("ROLLBACK\t" + (status == "PASS" ? "0" : "1"));
            summary.AppendLine("MAX_SOURCE_DRIFT\t" + maxSourceDrift.ToString("R", CultureInfo.InvariantCulture));
            summary.AppendLine("MAX_OFFSET_ERROR\t" + maxOffsetError.ToString("R", CultureInfo.InvariantCulture));
            summary.AppendLine("ELAPSED_MS\t" + timer.Elapsed.TotalMilliseconds.ToString("F3", CultureInfo.InvariantCulture));
            summary.AppendLine("DETAIL_PATH\t" + detailPath);
            summary.AppendLine("ERROR\t" + error);
            File.WriteAllText(reportPath, summary.ToString(), new UTF8Encoding(false));
            File.WriteAllText(detailPath, details.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXGRIPBATCHMOVE_DONE status=" + status + " count=" + (status == "PASS" ? moved : 0).ToString(CultureInfo.InvariantCulture));
        }
    }
}
