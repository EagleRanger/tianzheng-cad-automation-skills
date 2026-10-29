using System;
using System.Globalization;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.Geometry;
using Autodesk.AutoCAD.Runtime;

namespace CodexNativePlacementTranslatorV1
{
    public static class LispFunctions
    {
        private const double TranslationTolerance = 1.0e-6;

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

        private static ResultBuffer Success(Vector3d requested,
            double maximumGripVectorError, int gripCount)
        {
            return new ResultBuffer(
                new TypedValue((int)LispDataType.ListBegin),
                new TypedValue((int)LispDataType.Text, "PASS"),
                new TypedValue((int)LispDataType.Text,
                    "TRANSFORMBY_FIVE_GRIP_VECTOR_COMMITTED"),
                new TypedValue((int)LispDataType.Double, requested.X),
                new TypedValue((int)LispDataType.Double, requested.Y),
                new TypedValue((int)LispDataType.Double, requested.Z),
                new TypedValue((int)LispDataType.Double, maximumGripVectorError),
                new TypedValue((int)LispDataType.Int16, gripCount),
                new TypedValue((int)LispDataType.ListEnd));
        }

        [LispFunction("CXNATIVEPLACEMENTTRANSLATEV1")]
        public static ResultBuffer Translate(ResultBuffer arguments)
        {
            try
            {
                TypedValue[] values = Values(arguments);
                if (values.Length != 4) return Failure("ARGUMENT_COUNT");

                string dimensionHandle = Text(values[0]).Trim().ToUpperInvariant();
                double dx = Number(values[1]);
                double dy = Number(values[2]);
                double dz = Number(values[3]);
                if (double.IsNaN(dx) || double.IsInfinity(dx)
                    || double.IsNaN(dy) || double.IsInfinity(dy)
                    || double.IsNaN(dz) || double.IsInfinity(dz))
                    return Failure("ARGUMENT_NONFINITE");

                Vector3d requested = new Vector3d(dx, dy, dz);
                if (requested.Length <= 1.0e-9) return Failure("REQUEST_ZERO");

                Document document = Application.DocumentManager.MdiActiveDocument;
                if (document == null) return Failure("NO_ACTIVE_DOCUMENT");
                Database database = document.Database;
                using (Transaction transaction =
                    database.TransactionManager.StartTransaction())
                {
                    Entity dimension = transaction.GetObject(
                        Resolve(database, dimensionHandle), OpenMode.ForWrite) as Entity;
                    if (dimension == null) return Failure("DIMENSION_NOT_ENTITY");

                    string identity = (dimension.GetType().FullName ?? string.Empty)
                        + "|" + (dimension.GetRXClass().Name ?? string.Empty);
                    if (identity.IndexOf("TDbDimension2",
                            StringComparison.OrdinalIgnoreCase) < 0)
                        return Failure("DIMENSION_TYPE");

                    GripDataCollection before = ReadGrips(dimension);
                    if (before.Count != 5)
                        return Failure("GRIP_COUNT_BEFORE:" +
                            before.Count.ToString(CultureInfo.InvariantCulture));

                    Point3d[] beforePoints = new Point3d[5];
                    for (int i = 0; i < 5; i++) beforePoints[i] = before[i].GripPoint;

                    dimension.TransformBy(Matrix3d.Displacement(requested));
                    dimension.RecordGraphicsModified(true);

                    GripDataCollection after = ReadGrips(dimension);
                    if (after.Count != 5)
                        return Failure("GRIP_COUNT_AFTER:" +
                            after.Count.ToString(CultureInfo.InvariantCulture));

                    double maximumError = 0.0;
                    for (int i = 0; i < 5; i++)
                    {
                        Vector3d actual = after[i].GripPoint - beforePoints[i];
                        double error = (actual - requested).Length;
                        if (error > maximumError) maximumError = error;
                    }
                    if (maximumError > TranslationTolerance)
                        return Failure("GRIP_VECTOR_MISMATCH:" +
                            maximumError.ToString("R", CultureInfo.InvariantCulture));

                    transaction.Commit();
                    return Success(requested, maximumError, after.Count);
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
