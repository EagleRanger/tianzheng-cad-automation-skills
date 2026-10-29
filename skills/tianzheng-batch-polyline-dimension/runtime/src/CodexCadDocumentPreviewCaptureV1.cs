using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Runtime;
using AcApplication = Autodesk.AutoCAD.ApplicationServices.Core.Application;

namespace CodexCadDocumentPreviewCaptureV1
{
    public static class Commands
    {
        private const string Backend = "AUTOCAD_DOCUMENT_CAPTURE_PREVIEW_IMAGE";
        private const double PreviewScale = 2.0;

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect { public int Left; public int Top; public int Right; public int Bottom; }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetClientRect(IntPtr windowHandle, out NativeRect rectangle);

        private static bool ValidDimension(double width, double height)
        {
            return width >= 64.0 && height >= 64.0 && width <= 8192.0 && height <= 8192.0;
        }

        private static string Ask(Editor editor, string label)
        {
            var options = new PromptStringOptions("\n" + label + ":") { AllowSpaces = true };
            PromptResult result = editor.GetString(options);
            if (result.Status != PromptStatus.OK)
                throw new Autodesk.AutoCAD.Runtime.Exception(Autodesk.AutoCAD.Runtime.ErrorStatus.UserBreak);
            return (result.StringResult ?? string.Empty).Trim().Trim('"');
        }

        private static string CleanJson(string value)
        {
            return (value ?? string.Empty).Replace("\\", "\\\\").Replace("\"", "\\\"")
                .Replace("\r", " ").Replace("\n", " ").Replace("\t", " ");
        }

        private static string ProjectRoot()
        {
            string assembly = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
            DirectoryInfo build = Directory.GetParent(assembly);
            if (build == null || !build.Name.Equals("build", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("PREVIEW_ASSEMBLY_NOT_IN_BUILD");
            DirectoryInfo root = build.Parent;
            if (root == null) throw new InvalidOperationException("PREVIEW_PROJECT_ROOT_MISSING");
            return root.FullName.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        }

        private static string ResolveOutput(string raw, string extension)
        {
            string path = Path.GetFullPath(raw);
            if (!path.StartsWith(ProjectRoot(), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("PREVIEW_OUTPUT_OUTSIDE_PROJECT");
            if (!Path.GetExtension(path).Equals(extension, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("PREVIEW_OUTPUT_EXTENSION");
            string parent = Path.GetDirectoryName(path);
            if (string.IsNullOrWhiteSpace(parent))
                throw new InvalidOperationException("PREVIEW_OUTPUT_PARENT");
            Directory.CreateDirectory(parent);
            if (File.Exists(path))
                throw new InvalidOperationException("PREVIEW_OUTPUT_PREEXISTS");
            return path;
        }

        private static void ResolveDimensions(Document document, out int width, out int height, out string source)
        {
            double rawWidth = 0.0;
            double rawHeight = 0.0;
            System.Windows.Size displaySize = document.GraphicsManager.DeviceIndependentDisplaySize;
            if (ValidDimension(displaySize.Width, displaySize.Height))
            {
                rawWidth = displaySize.Width;
                rawHeight = displaySize.Height;
                source = "GRAPHICS_MANAGER_DEVICE_INDEPENDENT_DISPLAY_SIZE";
            }
            else
            {
                System.Windows.Size windowSize = document.Window.DeviceIndependentSize;
                if (ValidDimension(windowSize.Width, windowSize.Height))
                {
                    rawWidth = windowSize.Width;
                    rawHeight = windowSize.Height;
                    source = "DOCUMENT_WINDOW_DEVICE_INDEPENDENT_SIZE";
                }
                else
                {
                    NativeRect rectangle;
                    if (GetClientRect(document.Window.Handle, out rectangle))
                    {
                        rawWidth = Math.Abs(rectangle.Right - rectangle.Left);
                        rawHeight = Math.Abs(rectangle.Bottom - rectangle.Top);
                    }
                    if (!ValidDimension(rawWidth, rawHeight))
                        throw new InvalidOperationException("PREVIEW_RUNTIME_DIMENSION_UNAVAILABLE");
                    source = "DOCUMENT_WINDOW_GETCLIENTRECT";
                }
            }
            width = (int)Math.Ceiling(rawWidth * PreviewScale);
            height = (int)Math.Ceiling(rawHeight * PreviewScale);
            if (!ValidDimension(width, height))
                throw new InvalidOperationException("PREVIEW_SCALED_DIMENSION_INVALID");
        }

        private static void WriteReceipt(string path, string status, string detail,
            string imagePath, int width, int height, string dimensionSource, int previewCaptureCount)
        {
            string json = string.Format(CultureInfo.InvariantCulture,
                "{{\"schema_version\":1,\"status\":\"{0}\",\"detail\":\"{1}\",\"backend\":\"{2}\",\"image_path\":\"{3}\",\"width\":{4},\"height\":{5},\"dimension_source\":\"{6}\",\"preview_scale\":{7},\"preview_capture_count\":{8},\"database_transaction_count\":0,\"object_open_count\":0,\"business_object_mutation_count\":0,\"save_count\":0,\"retry_count\":0}}",
                CleanJson(status), CleanJson(detail), Backend, CleanJson(imagePath), width, height,
                CleanJson(dimensionSource), PreviewScale, previewCaptureCount);
            File.WriteAllText(path, json, new UTF8Encoding(false));
        }

        [CommandMethod("CXCADDOCUMENTPREVIEWCAPTUREV1", CommandFlags.Modal)]
        public static void Capture()
        {
            Document document = AcApplication.DocumentManager.MdiActiveDocument;
            if (document == null) return;
            Editor editor = document.Editor;
            string imagePath = string.Empty;
            string receiptPath = string.Empty;
            string dimensionSource = "NONE";
            int width = 0;
            int height = 0;
            int previewCaptureCount = 0;
            try
            {
                imagePath = ResolveOutput(Ask(editor, "OUTPUT_PNG_PATH"), ".png");
                receiptPath = ResolveOutput(Ask(editor, "RECEIPT_JSON_PATH"), ".json");
                ResolveDimensions(document, out width, out height, out dimensionSource);
                using (Bitmap bitmap = DocumentExtension.CapturePreviewImage(document, (uint)width, (uint)height))
                {
                    if (bitmap == null) throw new InvalidOperationException("PREVIEW_BITMAP_NULL");
                    bitmap.Save(imagePath, ImageFormat.Png);
                    previewCaptureCount = 1;
                }
                WriteReceipt(receiptPath, "PASS", string.Empty, imagePath, width, height,
                    dimensionSource, previewCaptureCount);
            }
            catch (System.Exception error)
            {
                if (!string.IsNullOrWhiteSpace(receiptPath) && !File.Exists(receiptPath))
                {
                    try
                    {
                        WriteReceipt(receiptPath, "FAIL", error.GetType().Name + ":" + error.Message,
                            imagePath, width, height, dimensionSource, previewCaptureCount);
                    }
                    catch { }
                }
                editor.WriteMessage("\nCXCADDOCUMENTPREVIEWCAPTUREV1_FAIL:" + error.Message);
            }
        }
    }
}
