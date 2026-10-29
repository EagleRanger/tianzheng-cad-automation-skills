using System;
using System.Globalization;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexNativePlacementGrip0MoverV1
{
    public static class LispFunctions
    {
        private const double EndpointTolerance = 1.0e-6;

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

        private static int Integer(TypedValue value)
        {
            return Convert.ToInt32(value.Value, CultureInfo.InvariantCulture);
        }

        private static double Number(TypedValue value)
        {
            return Convert.ToDouble(value.Value, CultureInfo.InvariantCulture);
        }

        private static ObjectId Resolve(Database database, string handleText)
        {
            long value;
            if (!long.TryParse(handleText, NumberStyles.HexNumber,
                    CultureInfo.InvariantCulture, out value))
                throw new InvalidOperationException("INVALID_HANDLE:" + handleText);
            return database.GetObjectId(false, new Handle(value), 0);
        }

        private static GripDataCollection ReadGrips(Entity entity)
        {
            var grips = new GripDataCollection();
            entity.GetGripPoints(grips, 1.0, 5, Vector3d.ZAxis,
                GetGripPointsFlags.GripPointsOnly);
            return grips;
        }

        private static double PlanarDistance(Point3d first, Point3d second)
        {
            double dx = first.X - second.X;
            double dy = first.Y - second.Y;
            return Math.Sqrt(dx * dx + dy * dy);
        }

        private static double EndpointError(GripDataCollection grips,
            Point3d start, Point3d end)
        {
            double direct = Math.Max(PlanarDistance(grips[2].GripPoint, start),
                PlanarDistance(grips[3].GripPoint, end));
            double reverse = Math.Max(PlanarDistance(grips[2].GripPoint, end),
                PlanarDistance(grips[3].GripPoint, start));
            return Math.Min(direct, reverse);
        }

        private static ResultBuffer Failure(string detail)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Text, "FAIL"),
                new TypedValue((int)LispDataType.Text, detail ?? string.Empty),
                new TypedValue((int)LispDataType.ListEnd));
        }

        private static ResultBuffer Success(Point3d before, Point3d after,
            Point3d target, double requestedLength, double actualLength,
            double directionCosine, double endpointBefore, double endpointAfter,
            double endpointDrift, double actualBand, double targetBand,
            double bandError, int gripCount)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Text, "PASS"),
                new TypedValue((int)LispDataType.Text,
                    "GRIP0_RADIAL_TARGET_COMMITTED"),
                new TypedValue((int)LispDataType.Double, before.X),
                new TypedValue((int)LispDataType.Double, before.Y),
                new TypedValue((int)LispDataType.Double, after.X),
                new TypedValue((int)LispDataType.Double, after.Y),
                new TypedValue((int)LispDataType.Double, target.X),
                new TypedValue((int)LispDataType.Double, target.Y),
                new TypedValue((int)LispDataType.Double, requestedLength),
                new TypedValue((int)LispDataType.Double, actualLength),
                new TypedValue((int)LispDataType.Double, directionCosine),
                new TypedValue((int)LispDataType.Double, endpointBefore),
                new TypedValue((int)LispDataType.Double, endpointAfter),
                new TypedValue((int)LispDataType.Double, endpointDrift),
                new TypedValue((int)LispDataType.Double, actualBand),
                new TypedValue((int)LispDataType.Double, targetBand),
                new TypedValue((int)LispDataType.Double, bandError),
                new TypedValue((int)LispDataType.Int16, gripCount),
                new TypedValue((int)LispDataType.ListEnd));
        }

        [LispFunction("CXNATIVEPLACEMENTMOVEGRIP0V1")]
        public static ResultBuffer MoveGrip0(ResultBuffer arguments)
        {
            try
            {
                TypedValue[] values = Values(arguments);
                if (values.Length != 4) return Failure("ARGUMENT_COUNT");

                string sourceHandle = Text(values[0]).Trim().ToUpperInvariant();
                int segmentIndex = Integer(values[1]);
                string dimensionHandle = Text(values[2]).Trim().ToUpperInvariant();
                double targetBand = Number(values[3]);
                if (segmentIndex < 0 || targetBand <= 1.0e-9)
                    return Failure("ARGUMENT_RANGE");

                Document document = Application.DocumentManager.MdiActiveDocument;
                if (document == null) return Failure("NO_ACTIVE_DOCUMENT");
                Database database = document.Database;
                using (Transaction transaction =
                    database.TransactionManager.StartTransaction())
                {
                    Polyline source = transaction.GetObject(
                        Resolve(database, sourceHandle), OpenMode.ForRead) as Polyline;
                    Entity dimension = transaction.GetObject(
                        Resolve(database, dimensionHandle), OpenMode.ForWrite) as Entity;
                    if (source == null) return Failure("SOURCE_NOT_POLYLINE");
                    if (dimension == null) return Failure("DIMENSION_NOT_ENTITY");

                    string identity = (dimension.GetType().FullName ?? string.Empty)
                        + "|" + (dimension.GetRXClass().Name ?? string.Empty);
                    if (identity.IndexOf("TDbDimension2",
                            StringComparison.OrdinalIgnoreCase) < 0)
                        return Failure("DIMENSION_TYPE");

                    GripDataCollection beforeGrips = ReadGrips(dimension);
                    if (beforeGrips.Count != 5)
                        return Failure("GRIP_COUNT_BEFORE:" +
                            beforeGrips.Count.ToString(CultureInfo.InvariantCulture));

                    Point3d sourceStart = source.GetPointAtParameter(segmentIndex);
                    Point3d sourceEnd = source.GetPointAtParameter(segmentIndex + 1.0);
                    double endpointBefore = EndpointError(beforeGrips,
                        sourceStart, sourceEnd);
                    if (endpointBefore > EndpointTolerance)
                        return Failure("ENDPOINT_BEFORE:" +
                            endpointBefore.ToString("R", CultureInfo.InvariantCulture));

                    CircularArc3d arc = source.GetArcSegmentAt(segmentIndex);
                    Point3d before = beforeGrips[0].GripPoint;
                    Vector3d radial = new Vector3d(before.X - arc.Center.X,
                        before.Y - arc.Center.Y, 0.0);
                    if (radial.Length <= 1.0e-9)
                        return Failure("GRIP0_AT_ARC_CENTER");
                    radial = radial.GetNormal();
                    double targetRadius = arc.Radius + targetBand;
                    if (targetRadius <= 1.0e-6)
                        return Failure("TARGET_RADIUS_NONPOSITIVE");

                    Point3d target = new Point3d(
                        arc.Center.X + radial.X * targetRadius,
                        arc.Center.Y + radial.Y * targetRadius,
                        before.Z);
                    Vector3d requested = target - before;
                    double requestedLength = requested.Length;
                    if (requestedLength <= 1.0e-9)
                        return Failure("REQUEST_ZERO");

                    var selected = new GripDataCollection { beforeGrips[0] };
                    dimension.MoveGripPointsAt(selected, requested,
                        (MoveGripPointsFlags)0);
                    dimension.RecordGraphicsModified(true);

                    GripDataCollection afterGrips = ReadGrips(dimension);
                    if (afterGrips.Count != 5)
                        return Failure("GRIP_COUNT_AFTER:" +
                            afterGrips.Count.ToString(CultureInfo.InvariantCulture));

                    Point3d after = afterGrips[0].GripPoint;
                    Vector3d actual = after - before;
                    double actualLength = actual.Length;
                    double minimumResponse = Math.Max(1.0e-6,
                        requestedLength * 0.05);
                    if (actualLength < minimumResponse)
                        return Failure("MOVE_RESPONSE_TOO_SMALL:" +
                            actualLength.ToString("R", CultureInfo.InvariantCulture));
                    double directionCosine = actual.DotProduct(requested)
                        / (actualLength * requestedLength);
                    if (directionCosine < 0.25)
                        return Failure("MOVE_WRONG_DIRECTION:" +
                            directionCosine.ToString("R", CultureInfo.InvariantCulture));

                    double endpointAfter = EndpointError(afterGrips,
                        sourceStart, sourceEnd);
                    double endpointDrift = Math.Max(
                        PlanarDistance(beforeGrips[2].GripPoint,
                            afterGrips[2].GripPoint),
                        PlanarDistance(beforeGrips[3].GripPoint,
                            afterGrips[3].GripPoint));
                    if (endpointAfter > EndpointTolerance
                        || endpointDrift > EndpointTolerance)
                        return Failure("ENDPOINT_AFTER_OR_DRIFT:" +
                            endpointAfter.ToString("R", CultureInfo.InvariantCulture)
                            + ":" + endpointDrift.ToString("R",
                                CultureInfo.InvariantCulture));

                    double actualBand = PlanarDistance(after, arc.Center)
                        - arc.Radius;
                    double bandError = Math.Abs(actualBand - targetBand);
                    double bandTolerance = Math.Max(1.0e-6,
                        Math.Abs(targetBand) * 1.0e-5);
                    if (bandError > bandTolerance)
                        return Failure("TARGET_BAND_NOT_REACHED:" +
                            actualBand.ToString("R", CultureInfo.InvariantCulture)
                            + ":" + targetBand.ToString("R",
                                CultureInfo.InvariantCulture));

                    transaction.Commit();
                    return Success(before, after, target, requestedLength,
                        actualLength, directionCosine, endpointBefore,
                        endpointAfter, endpointDrift, actualBand, targetBand,
                        bandError, afterGrips.Count);
                }
            }
            catch (System.Exception error)
            {
                return Failure((error.GetType().Name + ":" + error.Message)
                    .Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' '));
            }
        }
    }
}
