using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexQuantizedGripScalarConverger
{
    public static class Commands
    {
        private sealed class TargetSpec
        {
            public string HandleText;
            public int GripIndex;
            public Point3d Target;
            public double Tolerance;
            public bool HasScalarContract;
            public string AxisKind;
            public Point3d Anchor;
            public Vector3d Axis;
            public double TargetScalar;
        }

        private sealed class AttemptResult
        {
            public bool Improved;
            public bool Converged;
            public double BeforeError;
            public double AfterError;
            public double SourceDrift;
            public double AppliedSign;
            public string Detail;
        }

        private sealed class ProbeResult
        {
            public bool Usable;
            public Vector3d Input;
            public Vector3d Response;
            public double ScalarResponse;
            public double SourceDrift;
            public string Detail;
        }

        private static string Ask(Editor ed, string label)
        {
            var options = new PromptStringOptions("\n" + label + ":") { AllowSpaces = true };
            PromptResult result = ed.GetString(options);
            if (result.Status != PromptStatus.OK)
                throw new Autodesk.AutoCAD.Runtime.Exception(ErrorStatus.UserBreak);
            return result.StringResult.Trim();
        }

        private static ObjectId Resolve(Database db, string handleText)
        {
            long value;
            if (!long.TryParse(handleText, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value))
                throw new InvalidOperationException("CONVERGE_INVALID_HANDLE:" + handleText);
            return db.GetObjectId(false, new Handle(value), 0);
        }

        private static GripDataCollection ReadGrips(Entity entity)
        {
            var grips = new GripDataCollection();
            entity.GetGripPoints(grips, 1.0, 5, Vector3d.ZAxis, GetGripPointsFlags.GripPointsOnly);
            return grips;
        }

        private static bool IsTargetNativeAnnotation(Entity entity)
        {
            string identity = (entity.GetType().FullName ?? string.Empty) + "|" + (entity.GetRXClass().Name ?? string.Empty);
            return identity.IndexOf("TDbRadiusDim", StringComparison.OrdinalIgnoreCase) >= 0
                || identity.IndexOf("TDbDimension2", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static string Clean(string value)
        {
            return (value ?? string.Empty).Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
        }

        private static List<TargetSpec> ReadPlan(string path)
        {
            var result = new List<TargetSpec>();
            foreach (string raw in File.ReadAllLines(path, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal)) continue;
                string[] parts = line.Split('\t');
                if (parts.Length < 6) throw new InvalidOperationException("CONVERGE_PLAN_COLUMN_COUNT");
                if (parts[0].Equals("HANDLE", StringComparison.OrdinalIgnoreCase)) continue;
                int gripIndex;
                double x, y, z, tolerance;
                if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out gripIndex) || gripIndex != 0)
                    throw new InvalidOperationException("CONVERGE_ONLY_GRIP0_ALLOWED:" + parts[1]);
                if (!double.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out x)
                    || !double.TryParse(parts[3], NumberStyles.Float, CultureInfo.InvariantCulture, out y)
                    || !double.TryParse(parts[4], NumberStyles.Float, CultureInfo.InvariantCulture, out z)
                    || !double.TryParse(parts[5], NumberStyles.Float, CultureInfo.InvariantCulture, out tolerance)
                    || tolerance <= 0.0)
                    throw new InvalidOperationException("CONVERGE_PLAN_NUMBER_INVALID:" + parts[0]);
                var spec = new TargetSpec {
                    HandleText = parts[0].Trim().ToUpperInvariant(),
                    GripIndex = gripIndex,
                    Target = new Point3d(x, y, z),
                    Tolerance = tolerance,
                    HasScalarContract = false,
                    AxisKind = string.Empty,
                    Anchor = Point3d.Origin,
                    Axis = Vector3d.XAxis,
                    TargetScalar = 0.0
                };
                if (parts.Length >= 12 && !string.IsNullOrWhiteSpace(parts[6]))
                {
                    double anchorX, anchorY, axisX, axisY, targetScalar;
                    if (!double.TryParse(parts[7], NumberStyles.Float, CultureInfo.InvariantCulture, out anchorX)
                        || !double.TryParse(parts[8], NumberStyles.Float, CultureInfo.InvariantCulture, out anchorY)
                        || !double.TryParse(parts[9], NumberStyles.Float, CultureInfo.InvariantCulture, out axisX)
                        || !double.TryParse(parts[10], NumberStyles.Float, CultureInfo.InvariantCulture, out axisY)
                        || !double.TryParse(parts[11], NumberStyles.Float, CultureInfo.InvariantCulture, out targetScalar))
                        throw new InvalidOperationException("CONVERGE_SCALAR_CONTRACT_NUMBER_INVALID:" + parts[0]);
                    string axisKind = parts[6].Trim().ToUpperInvariant();
                    if (axisKind != "ARC_RADIUS" && axisKind != "LINE_NORMAL_DISTANCE")
                        throw new InvalidOperationException("CONVERGE_AXIS_KIND_INVALID:" + axisKind);
                    var axis = new Vector3d(axisX, axisY, 0.0);
                    if (axis.Length <= 1.0e-12)
                        throw new InvalidOperationException("CONVERGE_AXIS_ZERO:" + parts[0]);
                    spec.HasScalarContract = true;
                    spec.AxisKind = axisKind;
                    spec.Anchor = new Point3d(anchorX, anchorY, z);
                    spec.Axis = axis.GetNormal();
                    spec.TargetScalar = targetScalar;
                }
                result.Add(spec);
            }
            if (result.Count == 0) throw new InvalidOperationException("CONVERGE_PLAN_EMPTY");
            return result;
        }

        private static double ScalarAt(TargetSpec spec, Point3d point)
        {
            if (spec.AxisKind == "ARC_RADIUS") return point.DistanceTo(spec.Anchor);
            return (point - spec.Anchor).DotProduct(spec.Axis);
        }

        private static double ErrorAt(TargetSpec spec, Point3d point)
        {
            return spec.HasScalarContract
                ? Math.Abs(ScalarAt(spec, point) - spec.TargetScalar)
                : point.DistanceTo(spec.Target);
        }

        private static Vector3d NominalInput(TargetSpec spec, Point3d current, double sign)
        {
            if (spec.HasScalarContract)
            {
                double scalarResidual = spec.TargetScalar - ScalarAt(spec, current);
                return spec.Axis * (scalarResidual * sign);
            }
            return (spec.Target - current) * sign;
        }

        private static List<Vector3d> ProbeInputs(TargetSpec spec, double step)
        {
            if (!spec.HasScalarContract)
                return new List<Vector3d> { new Vector3d(step, 0.0, 0.0), new Vector3d(0.0, step, 0.0) };
            Vector3d axis = spec.Axis.GetNormal();
            Vector3d tangent = new Vector3d(-axis.Y, axis.X, 0.0);
            return new List<Vector3d> {
                axis * step, axis * -step, tangent * step, tangent * -step,
                (axis + tangent).GetNormal() * step,
                (axis - tangent).GetNormal() * step,
                (-axis + tangent).GetNormal() * step,
                (-axis - tangent).GetNormal() * step
            };
        }

        private static ProbeResult TryResponseProbe(Document doc, TargetSpec spec, Vector3d input)
        {
            Database db = doc.Database;
            using (DocumentLock docLock = doc.LockDocument())
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                Entity entity = tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite) as Entity;
                if (entity == null || !IsTargetNativeAnnotation(entity))
                    return new ProbeResult { Detail = "TYPE_NOT_NATIVE_DIM" };
                GripDataCollection before = ReadGrips(entity);
                if (before.Count <= spec.GripIndex)
                    return new ProbeResult { Detail = "GRIP_RANGE" };
                Point3d current = before[spec.GripIndex].GripPoint;
                double scalarBefore = spec.HasScalarContract ? ScalarAt(spec, current) : 0.0;
                Point3d sourceA = before.Count > 3 ? before[2].GripPoint : Point3d.Origin;
                Point3d sourceB = before.Count > 3 ? before[3].GripPoint : Point3d.Origin;
                var selected = new GripDataCollection { before[spec.GripIndex] };
                entity.MoveGripPointsAt(selected, input, (MoveGripPointsFlags)0);
                entity.RecordGraphicsModified(true);
                GripDataCollection after = ReadGrips(entity);
                if (after.Count != before.Count)
                    return new ProbeResult { Input = input, Detail = "PROBE_GRIP_COUNT_CHANGED" };
                double sourceDrift = after.Count > 3
                    ? Math.Max(sourceA.DistanceTo(after[2].GripPoint), sourceB.DistanceTo(after[3].GripPoint)) : 0.0;
                Point3d moved = after[spec.GripIndex].GripPoint;
                Vector3d response = moved - current;
                double scalarResponse = spec.HasScalarContract ? ScalarAt(spec, moved) - scalarBefore : 0.0;
                bool responded = spec.HasScalarContract ? Math.Abs(scalarResponse) > 1.0e-9 : response.Length > 1.0e-9;
                bool usable = sourceDrift <= 1.0e-6 && responded;
                return new ProbeResult {
                    Usable = usable,
                    Input = input,
                    Response = response,
                    ScalarResponse = scalarResponse,
                    SourceDrift = sourceDrift,
                    Detail = usable ? "PROBE_USABLE" : (sourceDrift > 1.0e-6 ? "PROBE_SOURCE_DRIFT" : "PROBE_NO_RESPONSE")
                };
            }
        }

        private static AttemptResult TryAdaptiveCandidate(Document doc, TargetSpec spec)
        {
            Database db = doc.Database;
            Point3d current;
            double beforeError;
            using (DocumentLock docLock = doc.LockDocument())
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                Entity entity = tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForRead) as Entity;
                if (entity == null || !IsTargetNativeAnnotation(entity))
                    return new AttemptResult { Detail = "TYPE_NOT_NATIVE_DIM" };
                GripDataCollection grips = ReadGrips(entity);
                if (grips.Count <= spec.GripIndex)
                    return new AttemptResult { Detail = "GRIP_RANGE" };
                current = grips[spec.GripIndex].GripPoint;
                beforeError = ErrorAt(spec, current);
            }
            if (beforeError <= spec.Tolerance)
                return new AttemptResult { Improved = true, Converged = true, BeforeError = beforeError, AfterError = beforeError, AppliedSign = 1.0, Detail = "ALREADY_AT_SCALAR_TARGET" };

            double probeStep = Math.Max(0.05, Math.Min(0.50, beforeError * 0.10));
            Vector3d residual = spec.Target - current;
            double scalarResidual = spec.HasScalarContract ? spec.TargetScalar - ScalarAt(spec, current) : 0.0;
            ProbeResult best = null;
            double bestScore = 0.0;
            double probeDrift = 0.0;
            foreach (Vector3d probeInput in ProbeInputs(spec, probeStep))
            {
                ProbeResult probe = TryResponseProbe(doc, spec, probeInput);
                probeDrift = Math.Max(probeDrift, probe.SourceDrift);
                if (!probe.Usable) continue;
                double score = spec.HasScalarContract
                    ? Math.Abs(probe.ScalarResponse) / probe.Input.Length
                    : Math.Abs(probe.Response.DotProduct(residual)) / probe.Response.Length;
                if (score > bestScore) { best = probe; bestScore = score; }
            }
            if (best == null || bestScore <= 1.0e-8)
                return new AttemptResult { BeforeError = beforeError, AfterError = beforeError, SourceDrift = probeDrift, AppliedSign = 0.0, Detail = "SCALAR_RESPONSE_AXIS_NOT_IDENTIFIED" };

            double scale;
            if (spec.HasScalarContract)
                scale = scalarResidual / best.ScalarResponse;
            else
                scale = best.Response.DotProduct(residual) / best.Response.DotProduct(best.Response);
            if (double.IsNaN(scale) || double.IsInfinity(scale) || Math.Abs(scale) > 64.0)
                return new AttemptResult { BeforeError = beforeError, AfterError = beforeError, SourceDrift = probeDrift, AppliedSign = scale, Detail = "SCALAR_RESPONSE_SCALE_INVALID" };
            Vector3d input = best.Input * scale;

            using (DocumentLock docLock = doc.LockDocument())
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                Entity entity = tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite) as Entity;
                if (entity == null || !IsTargetNativeAnnotation(entity))
                    return new AttemptResult { BeforeError = beforeError, AfterError = beforeError, Detail = "TYPE_NOT_NATIVE_DIM" };
                GripDataCollection before = ReadGrips(entity);
                if (before.Count <= spec.GripIndex)
                    return new AttemptResult { BeforeError = beforeError, AfterError = beforeError, Detail = "GRIP_RANGE" };
                Point3d sourceA = before.Count > 3 ? before[2].GripPoint : Point3d.Origin;
                Point3d sourceB = before.Count > 3 ? before[3].GripPoint : Point3d.Origin;
                var selected = new GripDataCollection { before[spec.GripIndex] };
                entity.MoveGripPointsAt(selected, input, (MoveGripPointsFlags)0);
                entity.RecordGraphicsModified(true);
                GripDataCollection after = ReadGrips(entity);
                if (after.Count != before.Count)
                    return new AttemptResult { BeforeError = beforeError, AfterError = beforeError, SourceDrift = probeDrift, AppliedSign = scale, Detail = "SCALAR_RESPONSE_GRIP_COUNT_CHANGED" };
                double sourceDrift = after.Count > 3
                    ? Math.Max(sourceA.DistanceTo(after[2].GripPoint), sourceB.DistanceTo(after[3].GripPoint)) : 0.0;
                double afterError = ErrorAt(spec, after[spec.GripIndex].GripPoint);
                double requiredImprovement = Math.Max(spec.Tolerance * 0.25, beforeError * 0.001);
                bool improved = sourceDrift <= 1.0e-6 && afterError + requiredImprovement < beforeError;
                bool converged = sourceDrift <= 1.0e-6 && afterError <= spec.Tolerance;
                if (improved || converged) tr.Commit();
                return new AttemptResult {
                    Improved = improved || converged,
                    Converged = converged,
                    BeforeError = beforeError,
                    AfterError = afterError,
                    SourceDrift = Math.Max(probeDrift, sourceDrift),
                    AppliedSign = scale,
                    Detail = sourceDrift > 1.0e-6 ? "SCALAR_RESPONSE_SOURCE_DRIFT_ROLLBACK" : (improved || converged ? "SCALAR_RESPONSE_COMMITTED" : "SCALAR_RESPONSE_NO_IMPROVEMENT_ROLLBACK")
                };
            }
        }

        private static AttemptResult TryCandidate(Document doc, TargetSpec spec, double sign)
        {
            Database db = doc.Database;
            using (DocumentLock docLock = doc.LockDocument())
            using (Transaction tr = db.TransactionManager.StartTransaction())
            {
                Entity entity = tr.GetObject(Resolve(db, spec.HandleText), OpenMode.ForWrite) as Entity;
                if (entity == null || !IsTargetNativeAnnotation(entity))
                    return new AttemptResult { Detail = "TYPE_NOT_NATIVE_DIM" };
                GripDataCollection before = ReadGrips(entity);
                if (before.Count <= spec.GripIndex)
                    return new AttemptResult { Detail = "GRIP_RANGE" };
                Point3d current = before[spec.GripIndex].GripPoint;
                double beforeError = ErrorAt(spec, current);
                if (beforeError <= spec.Tolerance)
                    return new AttemptResult { Improved = true, Converged = true, BeforeError = beforeError, AfterError = beforeError, AppliedSign = sign, Detail = "ALREADY_AT_SCALAR_TARGET" };

                Point3d sourceA = before.Count > 3 ? before[2].GripPoint : Point3d.Origin;
                Point3d sourceB = before.Count > 3 ? before[3].GripPoint : Point3d.Origin;
                Vector3d input = NominalInput(spec, current, sign);
                var selected = new GripDataCollection { before[spec.GripIndex] };
                entity.MoveGripPointsAt(selected, input, (MoveGripPointsFlags)0);
                entity.RecordGraphicsModified(true);
                GripDataCollection after = ReadGrips(entity);
                if (after.Count != before.Count)
                    return new AttemptResult { BeforeError = beforeError, AfterError = beforeError, AppliedSign = sign, Detail = "GRIP_COUNT_CHANGED" };
                double sourceDrift = after.Count > 3
                    ? Math.Max(sourceA.DistanceTo(after[2].GripPoint), sourceB.DistanceTo(after[3].GripPoint)) : 0.0;
                double afterError = ErrorAt(spec, after[spec.GripIndex].GripPoint);
                double requiredImprovement = Math.Max(spec.Tolerance * 0.25, beforeError * 0.001);
                bool improved = sourceDrift <= 1.0e-6 && afterError + requiredImprovement < beforeError;
                bool converged = sourceDrift <= 1.0e-6 && afterError <= spec.Tolerance;
                if (improved || converged) tr.Commit();
                return new AttemptResult {
                    Improved = improved || converged,
                    Converged = converged,
                    BeforeError = beforeError,
                    AfterError = afterError,
                    SourceDrift = sourceDrift,
                    AppliedSign = sign,
                    Detail = sourceDrift > 1.0e-6 ? "SCALAR_SOURCE_DRIFT_ROLLBACK" : (improved || converged ? "SCALAR_COMMITTED" : "SCALAR_NO_IMPROVEMENT_ROLLBACK")
                };
            }
        }

        [CommandMethod("CXQUANTIZEDGRIPSCALARCONVERGE", CommandFlags.Session)]
        public static void QuantizedGripConverge()
        {
            Document doc = Application.DocumentManager.MdiActiveDocument;
            Editor ed = doc.Editor;
            string planPath = Ask(ed, "PLAN_PATH");
            string reportPath = Ask(ed, "REPORT_PATH");
            var report = new StringBuilder();
            report.AppendLine("HANDLE\tTARGET_X\tTARGET_Y\tTARGET_Z\tTOLERANCE\tATTEMPTS\tSTART_ERROR\tFINAL_ERROR\tIMPROVEMENT_COMMITS\tOPPOSITE_PROBES\tSOURCE_DRIFT_MAX\tSTATUS\tDETAIL");
            int convergedCount = 0;
            int partialCount = 0;
            int failedCount = 0;
            var timer = System.Diagnostics.Stopwatch.StartNew();
            try
            {
                foreach (TargetSpec spec in ReadPlan(planPath))
                {
                    int attempts = 0;
                    int commits = 0;
                    int opposite = 0;
                    double startError = double.NaN;
                    double finalError = double.NaN;
                    double maxSourceDrift = 0.0;
                    string detail = string.Empty;
                    bool converged = false;
                    for (int iteration = 0; iteration < 3 && !converged; iteration++)
                    {
                        AttemptResult normal = TryCandidate(doc, spec, 1.0);
                        attempts++;
                        if (double.IsNaN(startError)) startError = normal.BeforeError;
                        finalError = normal.AfterError;
                        maxSourceDrift = Math.Max(maxSourceDrift, normal.SourceDrift);
                        detail = normal.Detail;
                        if (normal.Improved) commits++;
                        converged = normal.Converged;
                        if (!converged && !normal.Improved)
                        {
                            AttemptResult adaptive = TryAdaptiveCandidate(doc, spec);
                            attempts++;
                            finalError = adaptive.AfterError;
                            maxSourceDrift = Math.Max(maxSourceDrift, adaptive.SourceDrift);
                            detail = adaptive.Detail;
                            if (adaptive.Improved) commits++;
                            converged = adaptive.Converged;
                            if (!converged && !adaptive.Improved)
                            {
                                AttemptResult reverse = TryCandidate(doc, spec, -1.0);
                                attempts++;
                                opposite++;
                                finalError = reverse.AfterError;
                                maxSourceDrift = Math.Max(maxSourceDrift, reverse.SourceDrift);
                                detail = reverse.Detail;
                                if (reverse.Improved) commits++;
                                converged = reverse.Converged;
                                if (!reverse.Improved) break;
                            }
                        }
                    }
                    string itemStatus;
                    if (converged) { itemStatus = "PASS"; convergedCount++; }
                    else if (commits > 0) { itemStatus = "PARTIAL_RESIDUAL"; partialCount++; }
                    else { itemStatus = "FAIL_ISOLATED"; failedCount++; }
                    report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                        "{0}\t{1:R}\t{2:R}\t{3:R}\t{4:R}\t{5}\t{6:R}\t{7:R}\t{8}\t{9}\t{10:R}\t{11}\t{12}",
                        spec.HandleText, spec.Target.X, spec.Target.Y, spec.Target.Z, spec.Tolerance,
                        attempts, startError, finalError, commits, opposite, maxSourceDrift, itemStatus, Clean(detail)));
                }
                ed.Regen();
            }
            catch (System.Exception ex)
            {
                report.AppendLine("FATAL\t" + Clean(ex.GetType().FullName + ":" + ex.Message));
                failedCount++;
            }
            timer.Stop();
            string status = failedCount == 0 && partialCount == 0 ? "PASS" : "PARTIAL";
            report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                "SUMMARY\t{0}\tPASS={1}\tPARTIAL={2}\tFAIL={3}\tELAPSED_MS={4:F3}",
                status, convergedCount, partialCount, failedCount, timer.Elapsed.TotalMilliseconds));
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            ed.WriteMessage("\nCXQUANTIZEDGRIPSCALARCONVERGE_DONE status=" + status);
        }
    }
}

