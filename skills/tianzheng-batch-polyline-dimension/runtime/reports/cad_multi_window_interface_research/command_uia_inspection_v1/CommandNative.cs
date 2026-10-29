using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace CadCommandUiaNativeV1 {
 public sealed class Node {
  public long hwnd,parent,root,root_owner,structural_parent;
  public uint window_style;
  public bool style_child,style_popup;
  public uint pid,thread;
  public int control_id;
  public bool valid,visible,enabled,child_of_main;
  public string window_class;
 }
 public sealed class TextRead { public string text;public bool complete,timeout,truncated;public int error;public long result; }
 public static class Native {
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsChild(IntPtr main,IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h,uint f);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll",EntryPoint="GetWindowLongW",ExactSpelling=true)] static extern int GetWindowStyleLong(IntPtr h,int index);
  [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
  // Private fixed WM_GETTEXT only. No generic sending surface is exposed.
  [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr SendMessageTimeout(IntPtr h,uint m,IntPtr w,StringBuilder b,uint f,uint t,out IntPtr result);
  public static Node Describe(long handle,long main) {
   IntPtr h=new IntPtr(handle);uint p;uint t=GetWindowThreadProcessId(h,out p);
   StringBuilder cls=new StringBuilder(256);GetClassName(h,cls,256);
   uint style=unchecked((uint)GetWindowStyleLong(h,-16));
   return new Node {structural_parent=GetAncestor(h,1).ToInt64(),window_style=style,style_child=(style&0x40000000U)!=0,style_popup=(style&0x80000000U)!=0,hwnd=handle,pid=p,thread=t,parent=GetParent(h).ToInt64(),root=GetAncestor(h,2).ToInt64(),root_owner=GetAncestor(h,3).ToInt64(),control_id=GetDlgCtrlID(h),valid=IsWindow(h),visible=IsWindowVisible(h),enabled=IsWindowEnabled(h),child_of_main=IsChild(new IntPtr(main),h),window_class=cls.ToString()};
  }
  public static bool Descends(long main,long handle) { return IsChild(new IntPtr(main),new IntPtr(handle)); }
  public static TextRead ReadText(long handle,int capacity) {
   if(capacity<2||capacity>4096)throw new InvalidOperationException("TEXT_CAPACITY");
   StringBuilder b=new StringBuilder(capacity);IntPtr result;
   IntPtr ok=SendMessageTimeout(new IntPtr(handle),0x000D,new IntPtr(capacity),b,3,100,out result);
   int error=ok==IntPtr.Zero?Marshal.GetLastWin32Error():0;
   return new TextRead{text=b.ToString(),complete=ok!=IntPtr.Zero,timeout=ok==IntPtr.Zero&&error==1460,error=error,result=result.ToInt64(),truncated=ok!=IntPtr.Zero&&result.ToInt64()>=capacity-1};
  }
 }
}
