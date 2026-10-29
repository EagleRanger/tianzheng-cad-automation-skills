using System;
using System.Globalization;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexNativeGenerationPlacementAuditV5
{
    public static class LispFunctions
    {
        private const double EndpointTolerance = 1.0e-6;

        private static ResultBuffer Result(int rank, string detail,
            double actual, double expected, double residual, int gripCount)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Int32, rank),
                new TypedValue((int)LispDataType.Text, detail),
                new TypedValue((int)LispDataType.Double, actual),
                new TypedValue((int)LispDataType.Double, expected),
                new TypedValue((int)LispDataType.Double, residual),
                new TypedValue((int)LispDataType.Int32, gripCount),
                new TypedValue((int)LispDataType.ListEnd));
        }

        private static TypedValue[] Values(ResultBuffer arguments)
        {
            if (arguments == null) return new TypedValue[0];
            TypedValue[] raw = arguments.AsArray();
            if (raw.Length >= 2
                && raw[0].TypeCode == (int)LispDataType.ListBegin
                && raw[raw.Length - 1].TypeCode == (int)LispDataType.ListEnd)
            {
                var trimmed = new TypedValue[raw.Length - 2];
                Array.Copy(raw, 1, trimmed, 0, trimmed.Length);
                return trimmed;
            }
            return raw;
        }

        private static string Text(TypedValue value)
        {
            return Convert.ToString(value.Value, CultureInfo.InvariantCulture)
                ?? string.Empty;
        }

        private static double Number(TypedValue value)
        {
            return Convert.ToDouble(value.Value, CultureInfo.InvariantCulture);
        }

        private static int Integer(TypedValue value)
        {
            return Convert.ToInt32(value.Value, CultureInfo.InvariantCulture);
        }

        private static ObjectId Resolve(Database database, string handleText)
        {
            long value = long.Parse(handleText, NumberStyles.HexNumber,
                CultureInfo.InvariantCulture);
            return database.GetObjectId(false, new Handle(value), 0);
        }

        private static GripDataCollection ReadGrips(Entity entity)
        {
            var grips = new GripDataCollection();
            entity.GetGripPoints(grips, 1.0, 1, Vector3d.ZAxis,
                GetGripPointsFlags.GripPointsOnly);
            return grips;
        }

        private static double PlanarDistance(Point3d first, Point3d second)
        {
            double dx = first.X - second.X;
            double dy = first.Y - second.Y;
            return Math.Sqrt(dx * dx + dy * dy);
        }

        private static string EndpointFailure(double direct, double reverse,
            Point3d start, Point3d end, Point3d grip2, Point3d grip3)
        {
            return string.Format(CultureInfo.InvariantCulture,
                "SOURCE_ENDPOINT_XY_ASSOCIATION_FAILED:direct_xy={0:R},reverse_xy={1:R},tol={2:R},start_z={3:R},end_z={4:R},grip2_z={5:R},grip3_z={6:R}",
                direct, reverse, EndpointTolerance, start.Z, end.Z,
                grip2.Z, grip3.Z);
        }

        [LispFunction("CXNATIVEPLACEMENTAUDITV5")]
        public static ResultBuffer Audit(ResultBuffer arguments)
        {
            try
            {
                TypedValue[] values = Values(arguments);
                if (values.Length != 9)
                    return Result(0, "ARGUMENT_COUNT", 0.0, 0.0,
                        double.MaxValue, 0);

                string sourceHandle = Text(values[0]).Trim().ToUpperInvariant();
                string segmentType = Text(values[1]).Trim().ToUpperInvariant();
                int segmentIndex = Integer(values[2]);
                string dimensionHandle = Text(values[3]).Trim().ToUpperInvariant();
                double requestedOffset = Number(values[4]);
                double seedBandH = Number(values[5]);
                double minimumUsableBandH = Number(values[6]);
                double normalBandH = Number(values[7]);
                double maximumUsableBandH = Number(values[8]);

                if (segmentIndex < 0 || Math.Abs(requestedOffset) <= 1.0e-9
                    || seedBandH <= 0.0 || minimumUsableBandH <= 0.0
                    || normalBandH < minimumUsableBandH
                    || maximumUsableBandH < normalBandH)
                {
                    return Result(0, "ARGUMENT_RANGE", 0.0, 0.0,
                        double.MaxValue, 0);
                }

                Document document = Application.DocumentManager.MdiActiveDocument;
                if (document == null)
                    return Result(0, "NO_ACTIVE_DOCUMENT", 0.0, 0.0,
                        double.MaxValue, 0);

                Database database = document.Database;
                using (Transaction transaction =
                    database.TransactionManager.StartTransaction())
                {
                    Polyline source = transaction.GetObject(
                        Resolve(database, sourceHandle), OpenMode.ForRead) as Polyline;
                    Entity dimension = transaction.GetObject(
                        Resolve(database, dimensionHandle), OpenMode.ForRead) as Entity;
                    if (source == null)
                        return Result(0, "SOURCE_NOT_POLYLINE", 0.0, 0.0,
                            double.MaxValue, 0);
                    if (dimension == null)
                        return Result(0, "DIMENSION_NOT_ENTITY", 0.0, 0.0,
                            double.MaxValue, 0);

                    string identity = (dimension.GetType().FullName ?? string.Empty)
                        + "|" + (dimension.GetRXClass().Name ?? string.Empty);
                    if (identity.IndexOf("TDbDimension2",
                            StringComparison.OrdinalIgnoreCase) < 0)
                    {
                        return Result(0, "DIMENSION_TYPE", 0.0, 0.0,
                            double.MaxValue, 0);
                    }

                    double textHeight = Math.Abs(requestedOffset) / seedBandH;
                    double minimumUsableBand = textHeight * minimumUsableBandH;
                    double normalBand = textHeight * normalBandH;
                    double maximumUsableBand = textHeight * maximumUsableBandH;
                    double signTolerance = Math.Max(1.0e-6, textHeight * 1.0e-6);

                    GripDataCollection grips = ReadGrips(dimension);
                    if (grips.Count < 4)
                        return Result(0, "SOURCE_ENDPOINT_GRIPS_MISSING", 0.0,
                            0.0, double.MaxValue, grips.Count);

                    Point3d sourceStart = source.GetPointAtParameter(segmentIndex);
                    Point3d sourceEnd = source.GetPointAtParameter(segmentIndex + 1.0);
                    Point3d grip2 = grips[2].GripPoint;
                    Point3d grip3 = grips[3].GripPoint;
                    double directError = Math.Max(
                        PlanarDistance(grip2, sourceStart),
                        PlanarDistance(grip3, sourceEnd));
                    double reverseError = Math.Max(
                        PlanarDistance(grip2, sourceEnd),
                        PlanarDistance(grip3, sourceStart));
                    if (Math.Min(directError, reverseError) > EndpointTolerance)
                        return Result(0, EndpointFailure(directError, reverseError,
                            sourceStart, sourceEnd, grip2, grip3), 0.0, 0.0,
                            double.MaxValue, grips.Count);

                    Point3d grip0 = grips[0].GripPoint;
                    double coincidenceTolerance = Math.Max(1.0e-6,
                        textHeight * 0.005);
                    if (PlanarDistance(grip0, grip2) <= coincidenceTolerance
                        || PlanarDistance(grip0, grip3) <= coincidenceTolerance)
                    {
                        return Result(0, "GRIP0_SOURCE_ENDPOINT_COINCIDENT_XY",
                            0.0, 0.0, double.MaxValue, grips.Count);
                    }

                    Point3d pick = source.GetPointAtParameter(segmentIndex + 0.5);
                    Vector3d tangent = source.GetFirstDerivative(segmentIndex + 0.5);
                    tangent = new Vector3d(tangent.X, tangent.Y, 0.0);
                    if (tangent.Length <= 1.0e-9)
                        return Result(0, "SOURCE_TANGENT_ZERO", 0.0, 0.0,
                            double.MaxValue, grips.Count);
                    tangent = tangent.GetNormal();
                    Vector3d leftNormal = new Vector3d(-tangent.Y, tangent.X, 0.0);
                    Point3d requestedPoint = pick + leftNormal * requestedOffset;

                    double actualBand;
                    double expectedBand;
                    if (segmentType == "ARC")
                    {
                        CircularArc3d arc = source.GetArcSegmentAt(segmentIndex);
                        actualBand = PlanarDistance(grip0, arc.Center) - arc.Radius;
                        expectedBand = PlanarDistance(requestedPoint, arc.Center)
                            - arc.Radius;
                    }
                    else if (segmentType == "LINE")
                    {
                        LineSegment3d line = source.GetLineSegmentAt(segmentIndex);
                        Point3d midpoint = new Point3d(
                            (line.StartPoint.X + line.EndPoint.X) * 0.5,
                            (line.StartPoint.Y + line.EndPoint.Y) * 0.5,
                            (line.StartPoint.Z + line.EndPoint.Z) * 0.5);
                        actualBand = (grip0 - midpoint).DotProduct(leftNormal);
                        expectedBand = (requestedPoint - midpoint).DotProduct(leftNormal);
                    }
                    else
                    {
                        return Result(0, "SEGMENT_TYPE", 0.0, 0.0,
                            double.MaxValue, grips.Count);
                    }

                    double residual = Math.Abs(actualBand - expectedBand);
                    double actualMagnitude = Math.Abs(actualBand);
                    if (Math.Abs(expectedBand) <= signTolerance)
                        return Result(0, "EXPECTED_BAND_AMBIGUOUS", actualBand,
                            expectedBand, residual, grips.Count);
                    if (actualBand * expectedBand <= 0.0)
                        return Result(0, "WRONG_SIDE", actualBand, expectedBand,
                            residual, grips.Count);
                    if (actualMagnitude < minimumUsableBand)
                        return Result(0, "BELOW_MINIMUM_USABLE_BAND", actualBand,
                            expectedBand, residual, grips.Count);
                    if (actualMagnitude > maximumUsableBand)
                        return Result(0, "ABOVE_MAXIMUM_USABLE_BAND", actualBand,
                            expectedBand, residual, grips.Count);
                    if (actualMagnitude >= normalBand)
                        return Result(2, "PASS_NORMAL_GENERATION_BAND_XY", actualBand,
                            expectedBand, residual, grips.Count);
                    return Result(1, "PASS_LAYOUT_REQUIRED_MINIMUM_BAND_XY",
                        actualBand, expectedBand, residual, grips.Count);
                }
            }
            catch (System.Exception error)
            {
                string detail = (error.GetType().Name + ":" + error.Message)
                    .Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
                return Result(0, "AUDIT_V5_EXCEPTION:" + detail, 0.0, 0.0,
                    double.MaxValue, 0);
            }
        }
    }
}
