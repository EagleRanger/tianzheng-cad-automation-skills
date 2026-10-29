using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Autodesk.AutoCAD.ApplicationServices;
using Autodesk.AutoCAD.DatabaseServices;
using Autodesk.AutoCAD.EditorInput;
using Autodesk.AutoCAD.Runtime;

namespace CodexDimensionTextMetricsProbeV2
{
    public static class Commands
    {
        const string KernelHash = "D0E8FA6DC5D69F64DCFE3E2BF7827E7E6529F7A9BFC053A516D90036DC9FC28C";
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern uint GetModuleFileName(IntPtr module, StringBuilder name, int size);
        [DllImport("kernel32.dll", CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module, string name);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SegmentCount(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr DimensionGetText(IntPtr self, IntPtr storage, int index, IntPtr defaultFlag);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int StringLength(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr StringWide(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void StringDestroy(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int CopyProperties(IntPtr destination, IntPtr source, byte copyExtra);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void SetInt(IntPtr self, int value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void SetHeight(IntPtr self, double value, int paperFlag);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void SetStyle(IntPtr self, IntPtr oldObjectId);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void SetText(IntPtr self, IntPtr utf16);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate double GetHeight(IntPtr self, int paperFlag);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetExtents(IntPtr self, out double width, out double ymax, out double span);

        static T Resolve<T>(IntPtr module, string export) where T:class
        {
            IntPtr address=GetProcAddress(module,export);
            if(address==IntPtr.Zero) throw new InvalidOperationException("EXPORT_MISSING:"+export);
            return Marshal.GetDelegateForFunctionPointer(address,typeof(T)) as T;
        }
        static string Ask(Editor ed,string label)
        {
            var reply=ed.GetString(new PromptStringOptions("\n"+label+":"){AllowSpaces=true});
            if(reply.Status!=PromptStatus.OK) throw new InvalidOperationException(label+"_REQUIRED");
            return reply.StringResult.Trim();
        }
        static string Clean(string text){return (text??"").Replace('\t',' ').Replace('\r',' ').Replace('\n',' ');}
        static string Number(double value){return value.ToString("R",CultureInfo.InvariantCulture);}
        static void Positive(double value,string label)
        {
            if(Double.IsNaN(value)||Double.IsInfinity(value)||value<=0) throw new InvalidOperationException(label+"_INVALID");
        }
        static object Property(Entity entity,string name)
        {
            object com=entity.AcadObject;
            return com.GetType().InvokeMember(name,BindingFlags.GetProperty,null,com,null,CultureInfo.InvariantCulture);
        }

        [CommandMethod("CXTDIMTEXTMETRICSV2",CommandFlags.Session)]
        public static void Run()
        {
            Document doc=Application.DocumentManager.MdiActiveDocument;
            if(doc==null) throw new InvalidOperationException("DOCUMENT_REQUIRED");
            string expected=Ask(doc.Editor,"EXPECTED_DOCUMENT");
            string report=Path.GetFullPath(Ask(doc.Editor,"REPORT_PATH"));
            string progress=Path.GetFullPath(Ask(doc.Editor,"PROGRESS_PATH"));
            string handles=Ask(doc.Editor,"SOURCE_HANDLES_CSV");
            if(!String.Equals(expected,doc.Name,StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("DOCUMENT_IDENTITY");
            if(File.Exists(report)||File.Exists(progress)) throw new InvalidOperationException("REPORT_EXISTS");
            string[] selected=handles.Split(',');
            if(selected.Length<1||selected.Length>2000)throw new InvalidOperationException("SCOPE_COUNT");
            var unique=new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach(string candidate in selected)
                if(String.IsNullOrWhiteSpace(candidate)||!unique.Add(candidate.Trim()))throw new InvalidOperationException("SCOPE_DUPLICATE");
            foreach(string candidate in selected)
                if(!Measure(doc,report,progress,candidate.Trim()))break;
        }
        static bool Measure(Document doc,string report,string progress,string handle)
        {
            Action<string> mark=step=>File.AppendAllText(progress,DateTimeOffset.Now.ToString("o")+"\t"+handle+"\t"+step+Environment.NewLine);
            string status="FAIL",detail="",body="",styleName="",rxName="",managedType="";
            double paperHeight=0,sourceScale=0,h0=0,h1=0,width=0,ymax=0,span=0;
            double[] geometry=new double[8];
            int count=0,defaultFlag=-1,createdCount=0,extentStatus=0,propertyStatus=-1;
            bool detached=false,disposed=false;
            int before=Convert.ToInt32(Application.GetSystemVariable("DBMOD"));
            Stopwatch timer=Stopwatch.StartNew();
            try
            {
                mark("BEFORE_KERNEL_IDENTITY");
                IntPtr module=GetModuleHandle("tch_kernal.arx");
                var path=new StringBuilder(4096);
                uint pathLength=module==IntPtr.Zero?0:GetModuleFileName(module,path,path.Capacity);
                if(pathLength==0||pathLength>=path.Capacity) throw new InvalidOperationException("KERNEL_PATH");
                string actualHash;
                using(var sha=SHA256.Create())
                using(var stream=File.Open(path.ToString(),FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
                    actualHash=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");
                if(actualHash!=KernelHash) throw new InvalidOperationException("KERNEL_HASH_MISMATCH");
                var segmentCount=Resolve<SegmentCount>(module,"?GetSegmentNum@TDbDimension2@@QEBAHXZ");
                var getText=Resolve<DimensionGetText>(module,"?GetText@TDbDimension2@@QEBA?AVTWCString@@HPEAH@Z");
                var length=Resolve<StringLength>(module,"?Length@TWCString@@QEAAHXZ");
                var wide=Resolve<StringWide>(module,"??BTWCString@@QEAAPEA_WXZ");
                var destroy=Resolve<StringDestroy>(module,"??1TWCString@@QEAA@XZ");
                var copy=Resolve<CopyProperties>(module,"?setPropertiesFrom@TDbEntity@@QEAA?AW4ErrorStatus@Acad@@PEBVAcDbEntity@@_N@Z");
                var alignment=Resolve<SetInt>(module,"?SetAlignment@TDbText@@QEAAXW4TextAlignment@TGGiExplodeDrawBase@@@Z");
                var setHeight=Resolve<SetHeight>(module,"?SetHeight@TDbText@@QEAAXNH@Z");
                var setStyle=Resolve<SetStyle>(module,"?SetStyleId@TDbText@@QEAAXVAcDbObjectId@@@Z");
                var setText=Resolve<SetText>(module,"?SetText@TDbText@@QEAAXPEB_W@Z");
                var getHeight=Resolve<GetHeight>(module,"?GetHeight@TDbText@@QEBANH@Z");
                var getExtents=Resolve<GetExtents>(module,"?GetExtents@TDbText@@QEBAHPEAN00@Z");
                mark("EXPORTS_RESOLVED");
                using(var tx=doc.Database.TransactionManager.StartOpenCloseTransaction())
                {
                    ObjectId id=doc.Database.GetObjectId(false,new Handle(Int64.Parse(handle,NumberStyles.HexNumber,CultureInfo.InvariantCulture)),0);
                    Entity source=tx.GetObject(id,OpenMode.ForRead,false) as Entity;
                    if(source==null||source.GetRXClass().Name!="TDbDimension2") throw new InvalidOperationException("SOURCE_CLASS");
                    // Current object's own style, never global DIMTXT or historical sample H.
                    styleName=Convert.ToString(Property(source,"DimStyle"),CultureInfo.InvariantCulture);
                    sourceScale=Convert.ToDouble(Property(source,"Scale"),CultureInfo.InvariantCulture);
                    Positive(sourceScale,"SOURCE_SCALE");
                    var styles=(DimStyleTable)tx.GetObject(doc.Database.DimStyleTableId,OpenMode.ForRead);
                    if(String.IsNullOrEmpty(styleName)||!styles.Has(styleName)) throw new InvalidOperationException("SOURCE_STYLE_NOT_FOUND:"+styleName);
                    var style=(DimStyleTableRecord)tx.GetObject(styles[styleName],OpenMode.ForRead);
                    paperHeight=style.Dimtxt;
                    Positive(paperHeight,"STYLE_DIMTXT");
                    ObjectId textStyle=style.Dimtxsty;
                    if(textStyle.IsNull) throw new InvalidOperationException("STYLE_DIMTXSTY_NULL");
                    mark("BEFORE_SEGMENT_COUNT");
                    count=segmentCount(source.UnmanagedObject);
                    mark("AFTER_SEGMENT_COUNT:"+count);
                    if(count!=1) throw new InvalidOperationException("SEGMENT_COUNT_BOUND");
                    IntPtr storage=Marshal.AllocHGlobal(8),flag=Marshal.AllocHGlobal(sizeof(int));
                    bool constructed=false;
                    try
                    {
                        Marshal.WriteInt64(storage,0L); Marshal.WriteInt32(flag,-1);
                        mark("BEFORE_GETTEXT_INDEX0");
                        IntPtr returned=getText(source.UnmanagedObject,storage,0,flag);
                        constructed=true;
                        mark("AFTER_GETTEXT_INDEX0");
                        if(returned!=storage) throw new InvalidOperationException("TEXT_RETURN_BUFFER");
                        defaultFlag=Marshal.ReadInt32(flag);
                        int n=length(storage);
                        if(n<1||n>4096) throw new InvalidOperationException("TEXT_LENGTH_BOUND:"+n);
                        IntPtr chars=wide(storage);
                        if(chars==IntPtr.Zero) throw new InvalidOperationException("TEXT_POINTER_NULL");
                        body=Marshal.PtrToStringUni(chars,n);
                    }
                    finally
                    {
                        if(constructed){mark("BEFORE_STRING_DESTROY");destroy(storage);mark("AFTER_STRING_DESTROY");}
                        Marshal.FreeHGlobal(flag);Marshal.FreeHGlobal(storage);
                    }
                    RXClass nativeClass=SystemObjects.ClassDictionary["TDbText"] as RXClass;
                    if(nativeClass==null) throw new InvalidOperationException("TDBTEXT_CLASS_NOT_REGISTERED");
                    mark("BEFORE_FACTORY_CREATE");
                    RXObject created=nativeClass.Create();
                    if(created==null) throw new InvalidOperationException("FACTORY_NULL");
                    createdCount=1;
                    try
                    {
                        using(created)
                        {
                            Entity text=created as Entity;
                            if(text==null) throw new InvalidOperationException("FACTORY_NOT_ENTITY");
                            rxName=text.GetRXClass().Name;managedType=created.GetType().FullName;
                            detached=text.ObjectId.IsNull && text.Database==null && !created.IsDisposed;
                            if(rxName!="TDbText"||!detached) throw new InvalidOperationException("FACTORY_NOT_DETACHED_TDBTEXT");
                            IntPtr destination=text.UnmanagedObject;
                            mark("BEFORE_COPY_PROPERTIES_TO_DETACHED");
                            propertyStatus=copy(destination,source.UnmanagedObject,1);
                            mark("AFTER_COPY_PROPERTIES_TO_DETACHED:"+propertyStatus);
                            if(propertyStatus!=0) throw new InvalidOperationException("COPY_PROPERTIES_STATUS");
                            mark("BEFORE_TEXT_ALIGNMENT");alignment(destination,5);
                            mark("BEFORE_TEXT_HEIGHT");setHeight(destination,paperHeight,1);
                            mark("BEFORE_TEXT_STYLE");setStyle(destination,textStyle.OldIdPtr);
                            IntPtr content=Marshal.StringToHGlobalUni(body);
                            try{mark("BEFORE_TEXT_CONTENT");setText(destination,content);}
                            finally{Marshal.FreeHGlobal(content);}
                            geometry=GeometryRecipe.Apply(module,source,text,mark);
                            mark("BEFORE_GET_HEIGHT");
                            h0=getHeight(destination,0);h1=getHeight(destination,1);
                            Positive(h0,"MODEL_HEIGHT");Positive(h1,"PAPER_HEIGHT");
                            mark("BEFORE_GET_EXTENTS");
                            extentStatus=getExtents(destination,out width,out ymax,out span);
                            mark("AFTER_GET_EXTENTS:"+extentStatus);
                            Positive(width,"WIDTH");Positive(span,"SPAN");
                            if(Double.IsNaN(ymax)||Double.IsInfinity(ymax)) throw new InvalidOperationException("YMAX_INVALID");
                            if(Math.Abs(h1-paperHeight)>1e-6||Math.Abs(h0-paperHeight*sourceScale)>1e-6)
                                throw new InvalidOperationException("HEIGHT_STYLE_SCALE_MISMATCH");
                            if(!text.ObjectId.IsNull||text.Database!=null) throw new InvalidOperationException("DESTINATION_APPENDED");
                            mark("BEFORE_FACTORY_DISPOSE");
                        }
                    }
                    finally{disposed=created.IsDisposed;mark("AFTER_FACTORY_DISPOSE:"+disposed);}
                    if(!disposed) throw new InvalidOperationException("FACTORY_NOT_DISPOSED");
                    tx.Abort();
                }
                status="PASS";
            }
            catch(System.Exception error){detail=error.GetBaseException().Message;mark("MANAGED_FAILURE:"+Clean(detail));}
            timer.Stop();
            int after=Convert.ToInt32(Application.GetSystemVariable("DBMOD"));
            if(before!=after){status="FAIL";detail+="|DBMOD_CHANGED";}
            string header="STATUS\tHANDLE\tRXCLASS\tMANAGED_TYPE\tTEXT_INDEX\tSEGMENT_COUNT\tDEFAULT_FLAG\tTEXT\tDIMSTYLE\tSTYLE_DIMTXT\tSOURCE_SCALE\tHEIGHT_MODEL\tHEIGHT_PAPER\tINTRINSIC_WIDTH\tINTRINSIC_YMAX\tINTRINSIC_VERTICAL_SPAN\tEXTENTS_STATUS\tCOPY_PROPERTIES_STATUS\tCREATED_COUNT\tDETACHED\tDISPOSED\tDBMOD_BEFORE\tDBMOD_AFTER\tELAPSED_MS\tGEOMETRY_BOUNDARY\tTEXT_X\tTEXT_Y\tTEXT_Z\tROTATION\tMIN_X\tMIN_Y\tMAX_X\tMAX_Y\tDETAIL\n";
            string[] row={status,handle,rxName,managedType,"0",count.ToString(),defaultFlag.ToString(),Clean(body),Clean(styleName),Number(paperHeight),Number(sourceScale),Number(h0),Number(h1),Number(width),Number(ymax),Number(span),extentStatus.ToString(),propertyStatus.ToString(),createdCount.ToString(),detached.ToString(),disposed.ToString(),before.ToString(),after.ToString(),Number(timer.Elapsed.TotalMilliseconds),"NATIVE_RECIPE_WCS_AABB__ARROWS_NOT_MEASURED",Number(geometry[0]),Number(geometry[1]),Number(geometry[2]),Number(geometry[3]),Number(geometry[4]),Number(geometry[5]),Number(geometry[6]),Number(geometry[7]),Clean(detail)};
            if(!File.Exists(report))File.WriteAllText(report,header,new UTF8Encoding(false));
            File.AppendAllText(report,String.Join("\t",row)+"\n",new UTF8Encoding(false));
            mark("REPORT_WRITTEN");
            return status=="PASS";
        }
    }
}

