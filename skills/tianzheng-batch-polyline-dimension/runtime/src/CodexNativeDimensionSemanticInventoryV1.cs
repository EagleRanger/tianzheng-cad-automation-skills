using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Runtime;

namespace CodexCadAutomation
{
    public sealed class NativeDimensionSemanticInventoryV1
    {
        private static string Ask(Editor editor, string label)
        {
            PromptStringOptions options = new PromptStringOptions("\n" + label + ": ");
            options.AllowSpaces = true;
            PromptResult result = editor.GetString(options);
            if (result.Status != PromptStatus.OK || string.IsNullOrWhiteSpace(result.StringResult))
                throw new InvalidOperationException(label + "_REQUIRED");
            return result.StringResult.Trim();
        }

        private static string Clean(object value)
        {
            if (value == null) return string.Empty;
            string text;
            IFormattable formattable = value as IFormattable;
            if (formattable != null) text = formattable.ToString(null, CultureInfo.InvariantCulture);
            else text = Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty;
            return text.Replace("\t", " ").Replace("\r", " ").Replace("\n", " ").Trim();
        }

        private static string TryComProperty(Entity entity, string name)
        {
            try
            {
                object acadObject = entity.AcadObject;
                if (acadObject == null) return string.Empty;
                object value = acadObject.GetType().InvokeMember(
                    name,
                    BindingFlags.GetProperty,
                    null,
                    acadObject,
                    null,
                    CultureInfo.InvariantCulture);
                return Clean(value);
            }
            catch { return string.Empty; }
        }

        private static void CollectExplodedText(DBObject source, int depth, List<string> output)
        {
            if (source == null || depth > 3) return;
            DBText dbText = source as DBText;
            if (dbText != null)
            {
                string value = Clean(dbText.TextString);
                if (value.Length > 0) output.Add(value);
                return;
            }
            MText mText = source as MText;
            if (mText != null)
            {
                string value = Clean(mText.Contents);
                if (value.Length > 0) output.Add(value);
                return;
            }
            Entity entity = source as Entity;
            if (entity == null) return;
            DBObjectCollection children = new DBObjectCollection();
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

        [CommandMethod("CXNATIVEDIMSEMANTICINVENTORYV1", CommandFlags.Session)]
        public static void Run()
        {
            Document document = Application.DocumentManager.MdiActiveDocument;
            if (document == null) throw new InvalidOperationException("ACTIVE_DOCUMENT_REQUIRED");
            Editor editor = document.Editor;
            string reportPath = Ask(editor, "REPORT_PATH");
            StringBuilder report = new StringBuilder();
            report.AppendLine("HANDLE\tRXCLASS\tLAYER\tTEXT\tTEXTSTRING\tTEXTOVERRIDE\tDIMENSIONTEXT\tMEASUREMENT\tEXPLODED_TEXT\tDIRECT_TEXT_COUNT\tEXPLODED_TEXT_COUNT\tSTATUS");
            int objectCount = 0;
            int anyTextCount = 0;
            using (Transaction transaction = document.Database.TransactionManager.StartTransaction())
            {
                BlockTable table = (BlockTable)transaction.GetObject(document.Database.BlockTableId, OpenMode.ForRead);
                BlockTableRecord model = (BlockTableRecord)transaction.GetObject(table[BlockTableRecord.ModelSpace], OpenMode.ForRead);
                foreach (ObjectId id in model)
                {
                    Entity entity = transaction.GetObject(id, OpenMode.ForRead, false) as Entity;
                    if (entity == null) continue;
                    string rxClass = entity.GetRXClass().Name ?? string.Empty;
                    if (!rxClass.Equals("TDbDimension2", StringComparison.OrdinalIgnoreCase)) continue;
                    objectCount++;
                    string text = TryComProperty(entity, "Text");
                    string textString = TryComProperty(entity, "TextString");
                    string textOverride = TryComProperty(entity, "TextOverride");
                    string dimensionText = TryComProperty(entity, "DimensionText");
                    string measurement = TryComProperty(entity, "Measurement");
                    List<string> exploded = new List<string>();
                    CollectExplodedText(entity, 0, exploded);
                    string explodedText = string.Join(" | ", exploded.ToArray());
                    int directCount = 0;
                    foreach (string value in new string[] { text, textString, textOverride, dimensionText })
                        if (!string.IsNullOrWhiteSpace(value)) directCount++;
                    bool hasText = directCount > 0 || exploded.Count > 0;
                    if (hasText) anyTextCount++;
                    report.AppendLine(string.Join("\t", new string[] {
                        entity.Handle.ToString(), Clean(rxClass), Clean(entity.Layer), text, textString,
                        textOverride, dimensionText, measurement, explodedText,
                        directCount.ToString(CultureInfo.InvariantCulture),
                        exploded.Count.ToString(CultureInfo.InvariantCulture),
                        hasText ? "PASS" : "NO_TEXT_EVIDENCE"
                    }));
                }
                transaction.Commit();
            }
            report.AppendLine(string.Format(CultureInfo.InvariantCulture,
                "SUMMARY\tOBJECTS={0}\tOBJECTS_WITH_TEXT={1}\tSTATUS={2}",
                objectCount, anyTextCount, objectCount > 0 && objectCount == anyTextCount ? "PASS" : "PARTIAL"));
            File.WriteAllText(reportPath, report.ToString(), new UTF8Encoding(false));
            editor.WriteMessage("\nCXNATIVEDIMSEMANTICINVENTORYV1_DONE objects=" + objectCount.ToString(CultureInfo.InvariantCulture));
        }
    }
}
