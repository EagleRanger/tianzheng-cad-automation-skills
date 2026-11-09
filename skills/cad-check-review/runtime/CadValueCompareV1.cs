// DWG save/reopen may normalize ellipse axes at floating-point precision.
// Only numeric values tolerate 1e-9 drawing units; structure and text stay exact.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;
public static class CadValueCompareV1 {
 public const double ReopenTolerance=1e-9;
 static bool Number(object x){return x is byte||x is short||x is int||x is long||x is float||x is double||x is decimal;}
 public static bool Equivalent(object a,object b){
  if(a==null||b==null)return a==null&&b==null;
  if(Number(a)&&Number(b)){
   if(a.Equals(b))return true;
   double x=Convert.ToDouble(a),y=Convert.ToDouble(b);
   return !Double.IsNaN(x)&&!Double.IsNaN(y)&&!Double.IsInfinity(x)&&!Double.IsInfinity(y)&&Math.Abs(x-y)<=ReopenTolerance;
  }
  var da=a as IDictionary<string,object>;var db=b as IDictionary<string,object>;
  if(da!=null||db!=null){if(da==null||db==null||da.Count!=db.Count)return false;foreach(var p in da){object v;if(!db.TryGetValue(p.Key,out v)||!Equivalent(p.Value,v))return false;}return true;}
  var aa=a as IList;var ab=b as IList;
  if(aa!=null||ab!=null){if(aa==null||ab==null||aa.Count!=ab.Count)return false;for(int i=0;i<aa.Count;i++)if(!Equivalent(aa[i],ab[i]))return false;return true;}
  return a.GetType()==b.GetType()&&a.Equals(b);
 }
 public static bool Json(string a,string b){var j=new JavaScriptSerializer{MaxJsonLength=100000000,RecursionLimit=100};return Equivalent(j.DeserializeObject(a),j.DeserializeObject(b));}
}
