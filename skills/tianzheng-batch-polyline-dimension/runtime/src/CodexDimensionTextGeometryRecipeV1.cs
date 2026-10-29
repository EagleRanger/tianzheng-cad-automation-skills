using System;
using System.Runtime.InteropServices;
using Autodesk.AutoCAD.DatabaseServices;

namespace CodexDimensionTextMetricsProbeV2
{
    // Fixed-module ABI proven by constructor writes and FindSubText call sites.
    // Values are native constructed and destructed; TDbText itself uses RXClass factory.
    internal static class GeometryRecipe
    {
        [DllImport("kernel32.dll",CharSet=CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr module,string name);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr PointGetter(IntPtr self,IntPtr result,int index,IntPtr flag);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr CurveGetter(IntPtr self,IntPtr result);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr Constructor(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void Destructor(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ProjectPoint(IntPtr self,IntPtr input,IntPtr output);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate double PathDistance(IntPtr self,IntPtr point,int extended);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Polar(IntPtr self,double distance,IntPtr direction,int extended);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate double AngleTransform(IntPtr self,double angle);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void LocationSetter(IntPtr self,IntPtr value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void RotationSetter(IntPtr self,double value);
        static T Resolve<T>(IntPtr module,string name) where T:class
        {
            IntPtr address=GetProcAddress(module,name);
            if(address==IntPtr.Zero) throw new InvalidOperationException("GEOMETRY_EXPORT_MISSING:"+name);
            return Marshal.GetDelegateForFunctionPointer(address,typeof(T)) as T;
        }
        sealed class Storage:IDisposable
        {
            readonly IntPtr allocation;readonly int bytes;public readonly IntPtr Value;
            public Storage(int size)
            {
                bytes=size;allocation=Marshal.AllocHGlobal(size+32);Value=IntPtr.Add(allocation,16);
                for(int n=0;n<size+32;n++)Marshal.WriteByte(allocation,n,0xA5);
                for(int n=0;n<size;n++)Marshal.WriteByte(Value,n,0);
            }
            public void Check()
            {
                for(int n=0;n<16;n++)if(Marshal.ReadByte(allocation,n)!=0xA5||Marshal.ReadByte(Value,bytes+n)!=0xA5)
                    throw new InvalidOperationException("GEOMETRY_ABI_CANARY");
            }
            public double Read(int offset){return BitConverter.Int64BitsToDouble(Marshal.ReadInt64(Value,offset));}
            public void Dispose(){Marshal.FreeHGlobal(allocation);}
        }
        public static double[] Apply(IntPtr module,Entity source,Entity text,Action<string> mark)
        {
            var position=Resolve<PointGetter>(module,"?GetTextPos@TDbDimension2@@QEBA?AVTADSGePoint3d@@HPEAH@Z");
            var curve=Resolve<CurveGetter>(module,"?GetDimCurve@TDbDimension2@@QEBA?AVTGGeCurveSegment@@XZ");
            var directionCtor=Resolve<Constructor>(module,"??0TADSGePointDir2d@@QEAA@XZ");
            var pointDtor=Resolve<Destructor>(module,"??1TADSGePoint3d@@QEAA@XZ");
            var curveDtor=Resolve<Destructor>(module,"??1TGGeCurveSegment@@UEAA@XZ");
            var directionDtor=Resolve<Destructor>(module,"??1TADSGePointDir2d@@QEAA@XZ");
            var project=Resolve<ProjectPoint>(module,"?ProjectToMe@TGGeCurveSegment@@QEBAHAEBVTADSGePoint3d@@AEAV2@@Z");
            var distance=Resolve<PathDistance>(module,"?PathDistance@TGGeCurveSegment@@UEBANAEBVTADSGePoint3d@@H@Z");
            var polar=Resolve<Polar>(module,"?Polar@TGGeCurveSegment@@UEBAHNAEAVTADSGePointDir2d@@H@Z");
            var normal=Resolve<AngleTransform>(module,"?ChangeToNormalViewAngle@TDbDimension2@@QEBANN@Z");
            var toLayout=Resolve<AngleTransform>(module,"?Wcs2Layout@TEntityBase@@QEBANN@Z");
            var toWcs=Resolve<AngleTransform>(module,"?Layout2Wcs@TEntityBase@@QEBANN@Z");
            var setPosition=Resolve<LocationSetter>(module,"?SetLocation@TDbText@@QEAAXVTADSGePoint3d@@@Z");
            var setRotation=Resolve<RotationSetter>(module,"?SetRotation@TDbText@@QEAAXN@Z");
            using(var p=new Storage(24))
            using(var c=new Storage(72))
            using(var projected=new Storage(24))
            using(var direction=new Storage(32))
            {
                bool pointConstructed=false,curveConstructed=false,directionConstructed=false;
                try
                {
                    mark("BEFORE_NATIVE_TEXT_POSITION");
                    IntPtr returned=position(source.UnmanagedObject,p.Value,0,IntPtr.Zero);pointConstructed=true;p.Check();
                    if(returned!=p.Value)throw new InvalidOperationException("POSITION_RETURN_BUFFER");
                    mark("BEFORE_NATIVE_DIM_CURVE");
                    returned=curve(source.UnmanagedObject,c.Value);curveConstructed=true;c.Check();
                    if(returned!=c.Value)throw new InvalidOperationException("CURVE_RETURN_BUFFER");
                    directionCtor(direction.Value);directionConstructed=true;direction.Check();
                    mark("BEFORE_NATIVE_PROJECT");
                    int projectStatus=project(c.Value,p.Value,projected.Value);projected.Check();c.Check();
                    if(projectStatus==0)throw new InvalidOperationException("CURVE_PROJECT_FAILED");
                    double length=distance(c.Value,projected.Value,1);
                    if(Double.IsNaN(length)||Double.IsInfinity(length))throw new InvalidOperationException("CURVE_DISTANCE_INVALID");
                    mark("BEFORE_NATIVE_POLAR");
                    int polarStatus=polar(c.Value,length,direction.Value,1);direction.Check();c.Check();
                    if(polarStatus==0)throw new InvalidOperationException("CURVE_POLAR_FAILED");
                    double angle=normal(source.UnmanagedObject,direction.Read(24));
                    // The native FindSubText and ChangeToNormalViewAngle use TEntityBase at +0x18.
                    double layoutAngle=toLayout(IntPtr.Add(source.UnmanagedObject,24),angle);
                    mark("BEFORE_DETACHED_TEXT_POSITION_ROTATION");
                    setPosition(text.UnmanagedObject,p.Value);p.Check();
                    setRotation(text.UnmanagedObject,layoutAngle);
                    double wcsAngle=toWcs(IntPtr.Add(text.UnmanagedObject,24),layoutAngle);
                    mark("BEFORE_DETACHED_TEXT_GEOMETRIC_EXTENTS");
                    Extents3d box=text.GeometricExtents;
                    double[] result={p.Read(0),p.Read(8),p.Read(16),wcsAngle,box.MinPoint.X,box.MinPoint.Y,box.MaxPoint.X,box.MaxPoint.Y};
                    foreach(double number in result)if(Double.IsNaN(number)||Double.IsInfinity(number))throw new InvalidOperationException("NATIVE_TEXT_GEOMETRY_INVALID");
                    if(result[6]<=result[4]||result[7]<=result[5])throw new InvalidOperationException("NATIVE_TEXT_BBOX_EMPTY");
                    mark("NATIVE_TEXT_GEOMETRY_READ");return result;
                }
                finally
                {
                    if(directionConstructed)directionDtor(direction.Value);
                    if(curveConstructed)curveDtor(c.Value);
                    if(pointConstructed)pointDtor(p.Value);
                    mark("NATIVE_GEOMETRY_VALUES_RELEASED");
                }
            }
        }
    }
}
