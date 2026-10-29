using System;
using System.Globalization;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexNativeGenerationPlacementAuditV4
{
    public static class LispFunctions
    {
        private const double EndpointTolerance = 1.0e-6;

        private static ResultBuffer Result(string detail, int gripCount)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Int32, 0),
                new TypedValue((int)LispDataType.Text, detail),
                new TypedValue((int)LispDataType.Double, 0.0),
                new TypedValue((int)LispDataType.Double, 0.0),
                new TypedValue((int)LispDataType.Double, double.MaxValue),
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

        private static string Point(Point3d point)
        {
            return string.Format(CultureInfo.InvariantCulture,
                "({0:R},{1:R},{2:R})", point.X, point.Y, point.Z);
        }

        private static string Vector(Vector3d vector)
        {
            return string.Format(CultureInfo.InvariantCulture,
                "({0:R},{1:R},{2:R})", vector.X, vector.Y, vector.Z);
        }

        private static double Dot(Vector3d vector, Vector3d axis)
        {
            return vector.DotProduct(axis);
        }

        [LispFunction("CXNATIVEPLACEMENTAUDITV4")]
        public static ResultBuffer Audit(ResultBuffer arguments)
        {
            try
            {
                TypedValue[] values = Values(arguments);
                if (values.Length != 9)
                    return Result("V4_ARGUMENT_COUNT", 0);

                string sourceHandle = Text(values[0]).Trim().ToUpperInvariant();
                int segmentIndex = Integer(values[2]);
                string dimensionHandle = Text(values[3]).Trim().ToUpperInvariant();
                Document document = Application.DocumentManager.MdiActiveDocument;
                if (document == null) return Result("V4_NO_ACTIVE_DOCUMENT", 0);

                Database database = document.Database;
                using (Transaction transaction =
                    database.TransactionManager.StartTransaction())
                {
                    Polyline source = transaction.GetObject(
                        Resolve(database, sourceHandle), OpenMode.ForRead) as Polyline;
                    Entity dimension = transaction.GetObject(
                        Resolve(database, dimensionHandle), OpenMode.ForRead) as Entity;
                    if (source == null) return Result("V4_SOURCE_NOT_POLYLINE", 0);
                    if (dimension == null) return Result("V4_DIMENSION_NOT_ENTITY", 0);

                    GripDataCollection grips = ReadGrips(dimension);
                    if (grips.Count < 4)
                        return Result("V4_SOURCE_ENDPOINT_GRIPS_MISSING", grips.Count);

                    Point3d sourceStart = source.GetPointAtParameter(segmentIndex);
                    Point3d sourceEnd = source.GetPointAtParameter(segmentIndex + 1.0);
                    Point3d grip2 = grips[2].GripPoint;
                    Point3d grip3 = grips[3].GripPoint;
                    double directError = Math.Max(
                        grip2.DistanceTo(sourceStart), grip3.DistanceTo(sourceEnd));
                    double reverseError = Math.Max(
                        grip2.DistanceTo(sourceEnd), grip3.DistanceTo(sourceStart));

                    if (Math.Min(directError, reverseError) <= EndpointTolerance)
                        return CodexNativeGenerationPlacementAuditV3.LispFunctions
                            .Audit(arguments);

                    CircularArc3d arc = source.GetArcSegmentAt(segmentIndex);
                    Vector3d delta2 = grip2 - sourceStart;
                    Vector3d delta3 = grip3 - sourceEnd;
                    Vector3d radialStart = (sourceStart - arc.Center).GetNormal();
                    Vector3d radialEnd = (sourceEnd - arc.Center).GetNormal();
                    Vector3d tangentStart = new Vector3d(
                        -radialStart.Y, radialStart.X, 0.0);
                    Vector3d tangentEnd = new Vector3d(
                        -radialEnd.Y, radialEnd.X, 0.0);

                    string detail = string.Format(CultureInfo.InvariantCulture,
                        "SOURCE_ENDPOINT_VECTOR_FAILED:direct={0:R},reverse={1:R},tol={2:R},source_start={3},source_end={4},grip2={5},grip3={6},delta2={7},delta3={8},delta2_radial={9:R},delta2_tangent={10:R},delta3_radial={11:R},delta3_tangent={12:R},center={13},radius={14:R}",
                        directError, reverseError, EndpointTolerance,
                        Point(sourceStart), Point(sourceEnd), Point(grip2),
                        Point(grip3), Vector(delta2), Vector(delta3),
                        Dot(delta2, radialStart), Dot(delta2, tangentStart),
                        Dot(delta3, radialEnd), Dot(delta3, tangentEnd),
                        Point(arc.Center), arc.Radius);
                    return Result(detail, grips.Count);
                }
            }
            catch (System.Exception error)
            {
                string detail = (error.GetType().Name + ":" + error.Message)
                    .Replace('\t', ' ').Replace('\r', ' ').Replace('\n', ' ');
                return Result("V4_AUDIT_EXCEPTION:" + detail, 0);
            }
        }
    }
}
