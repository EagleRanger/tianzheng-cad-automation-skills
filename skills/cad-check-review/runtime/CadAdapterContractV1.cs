using System;using System.Reflection;using System.Collections.Generic;
using Autodesk.AutoCAD.ApplicationServices;
// Check the actual extension surface, not a list of unrelated adapter builds.
// Exact loaded binary/host/document binding remains checked by the caller.
public static class CadAdapterContractV1 {
 public static void CheckBaseReplace(Type t){
  Check(t);var flags=BindingFlags.Static|BindingFlags.NonPublic;
  var sw=t.GetNestedType("Switch",BindingFlags.Public);
  if(sw==null)throw new InvalidOperationException("ADAPTER_CONTRACT_SWITCH_TYPE");
  foreach(string name in new[]{"input","input_sha256","save_path","next_path","next_sha256","receipt"}){var f=sw.GetField(name);if(f==null||f.FieldType!=typeof(string))throw new InvalidOperationException("ADAPTER_CONTRACT_SWITCH_FIELD:"+name);}
  foreach(var row in new Dictionary<string,Type[]>{{"VerifyDwg",new[]{typeof(string)}},{"SwitchDocument",new[]{sw}}}){var m=t.GetMethod(row.Key,flags,null,row.Value,null);if(m==null||m.ReturnType!=typeof(void))throw new InvalidOperationException("ADAPTER_CONTRACT_BASE_METHOD:"+row.Key);}
 }
 public const string Name="V736_NATIVE_EXTENSION_V1";
 public static void Check(Type t){
  var flags=BindingFlags.Static|BindingFlags.NonPublic;
  foreach(var row in new Dictionary<string,Type>{{"doc",typeof(Document)},{"dir",typeof(string)},{"currentPath",typeof(string)},{"currentHash",typeof(string)},{"busy",typeof(bool)},{"blocked",typeof(bool)},{"approved",typeof(Dictionary<string,string>)},{"gardenPaths",typeof(HashSet<string>)}}){var f=t.GetField(row.Key,flags);if(f==null||f.FieldType!=row.Value)throw new InvalidOperationException("ADAPTER_CONTRACT_FIELD:"+row.Key);}
  foreach(var row in new Dictionary<string,Type[]>{{"CheckLive",new[]{typeof(string),typeof(string)}},{"CheckOutput",new[]{typeof(string),typeof(string)}},{"CheckPath",new[]{typeof(string)}},{"SaveModified",new[]{typeof(string),typeof(string),typeof(object)}},{"State",Type.EmptyTypes}})if(t.GetMethod(row.Key,flags,null,row.Value,null)==null)throw new InvalidOperationException("ADAPTER_CONTRACT_METHOD:"+row.Key);
 }
}
