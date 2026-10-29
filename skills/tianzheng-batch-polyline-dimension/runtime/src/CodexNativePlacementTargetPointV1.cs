using System;
using System.Globalization;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexNativePlacementTargetPointV1
{
    public static class LispFunctions
    {
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

        private static ResultBuffer Failure(string detail)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Text, "FAIL"),
                new TypedValue((int)LispDataType.Text, detail ?? string.Empty),
                new TypedValue((int)LispDataType.ListEnd));
        }

        private static ResultBuffer Success(
            Point3d target,
            Point3d grip0,
            Point3d center,
            Vector3d radial,
            double actualBand,
            double targetBand)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Text, "PASS"),
                new TypedValue((int)LispDataType.Text,
                    "CURRENT_GRIP0_RADIAL_TARGET"),
                new TypedValue((int)LispDataType.Double, target.X),
                new TypedValue((int)LispDataType.Double, target.Y),
                new TypedValue((int)LispDataType.Double, target.Z),
                new TypedValue((int)LispDataType.Double, grip0.X),
                new TypedValue((int)LispDataType.Double, grip0.Y),
                new TypedValue((int)LispDataType.Double, grip0.Z),
                new TypedValue((int)LispDataType.Double, center.X),
                new TypedValue((int)LispDataType.Double, center.Y),
                new TypedValue((int)LispDataType.Double, center.Z),
                new TypedValue((int)LispDataType.Double, radial.X),
                new TypedValue((int)LispDataType.Double, radial.Y),
                new TypedValue((int)LispDataType.Double, radial.Z),
                new TypedValue((int)LispDataType.Double, actualBand),
                new TypedValue((int)LispDataType.Double, targetBand),
                new TypedValue((int)LispDataType.Double,
                    targetBand - actualBand),
                new TypedValue((int)LispDataType.ListEnd));
        }

        [LispFunction("CXNATIVEPLACEMENTTARGETPOINTV1")]
        public static ResultBuffer TargetPoint(ResultBuffer arguments)
        {
            try
            {
                TypedValue[] values = Values(arguments);
                if (values.Length != 4) return Failure("ARGUMENT_COUNT");

                string sourceHandle = Text(values[0]).Trim().ToUpperInvariant();
                int segmentIndex = Integer(values[1]);
                string dimensionHandle = Text(values[2]).Trim().ToUpperInvariant();
                double targetBand = Number(values[3]);
                if (segmentIndex < 0 || Math.Abs(targetBand) <= 1.0e-9)
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
                        Resolve(database, dimensionHandle), OpenMode.ForRead) as Entity;
                    if (source == null) return Failure("SOURCE_NOT_POLYLINE");
                    if (dimension == null) return Failure("DIMENSION_NOT_ENTITY");

                    string identity = (dimension.GetType().FullName ?? string.Empty)
                        + "|" + (dimension.GetRXClass().Name ?? string.Empty);
                    if (identity.IndexOf("TDbDimension2",
                            StringComparison.OrdinalIgnoreCase) < 0)
                        return Failure("DIMENSION_TYPE");

                    GripDataCollection grips = ReadGrips(dimension);
                    if (grips.Count < 1) return Failure("GRIP0_MISSING");
                    Point3d grip0 = grips[0].GripPoint;
                    CircularArc3d arc = source.GetArcSegmentAt(segmentIndex);
                    Vector3d fromCenter = grip0 - arc.Center;
                    if (fromCenter.Length <= 1.0e-9)
                        return Failure("GRIP0_AT_ARC_CENTER");
                    double targetRadius = arc.Radius + targetBand;
                    if (targetRadius <= 1.0e-6)
                        return Failure("TARGET_RADIUS_NONPOSITIVE");

                    Vector3d radial = fromCenter.GetNormal();
                    double actualBand = fromCenter.Length - arc.Radius;
                    Point3d target = arc.Center + radial * targetRadius;
                    return Success(target, grip0, arc.Center, radial,
                        actualBand, targetBand);
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
