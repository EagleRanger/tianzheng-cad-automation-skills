function Initialize-CadFileRotBackendV5 {
 if('CadExactFileRotV5.Backend'-as[type]){return}
 Add-Type -TypeDefinition @'
using System;using System.Runtime.InteropServices;using System.Runtime.InteropServices.ComTypes;
namespace CadExactFileRotV5 {
 public sealed class ObjectResult {public int hr;public object Instance;}
 public sealed class Backend:IDisposable {
  [DllImport("ole32.dll",PreserveSig=true)] static extern int GetRunningObjectTable(int reserved,out IRunningObjectTable table);
  [DllImport("ole32.dll",CharSet=CharSet.Unicode,PreserveSig=true)] static extern int CreateFileMoniker(string path,out IMoniker name);
  IRunningObjectTable table;IMoniker name;
  public int CreateTable(){if(table!=null)throw new InvalidOperationException("TABLE_ALREADY_CREATED");return GetRunningObjectTable(0,out table);}
  public int CreateName(string path){if(name!=null)throw new InvalidOperationException("NAME_ALREADY_CREATED");return CreateFileMoniker(path,out name);}
  public int IsRunning(){return table.IsRunning(name);}
  public ObjectResult GetObject(){object value;int hr=table.GetObject(name,out value);return new ObjectResult{hr=hr,Instance=value};}
  public void Dispose(){try{if(name!=null){Marshal.ReleaseComObject(name);name=null;}}finally{if(table!=null){Marshal.ReleaseComObject(table);table=null;}}}
 }
}
'@
}

# Backend is injectable for offline tests only; the actual worker constructs the
# fixed native backend. No caller-supplied code/path/COM instance crosses READY.
function Invoke-CadFileRotLookupV5([string]$FullPath,$Backend,$Events,[scriptblock]$Emit){
 $status='FAILED_OR_UNKNOWN';$detail=$null;$entry=$null;$disposed=$false
 $counts=[ordered]@{table=0;create=0;is_running=0;get_object=0}
 try{
  foreach($name in @('CreateTable','CreateName','IsRunning','GetObject')){
   $event=[ordered]@{stage=$name;at_utc=[DateTime]::UtcNow.ToString('o');status='ENTERED';raw_hresult=$null;hresult_hex=$null;error=$null}
   $Events.Add($event);if($null-ne$Emit){& $Emit $event}
   try{
    switch($name){
     'CreateTable' {$counts.table++;$hr=[int]$Backend.CreateTable()}
     'CreateName' {$counts.create++;$hr=[int]$Backend.CreateName($FullPath)}
     'IsRunning' {$counts.is_running++;$hr=[int]$Backend.IsRunning()}
     'GetObject' {$counts.get_object++;$objectResult=$Backend.GetObject();$hr=[int]$objectResult.hr}
    }
    $event.raw_hresult=$hr;$event.hresult_hex=([uint32]([long]$hr-band4294967295)).ToString('X8');$event.status='RETURNED'
    if($name-ceq'IsRunning'-and$hr-eq1){$status='FILE_MONIKER_NOT_RUNNING';break}
    if($name-ceq'GetObject'-and$hr-eq1){$status='OBJECT_GONE_BETWEEN_CHECK_AND_GET';break}
    if($hr-ne0){throw ('NON_S_OK:'+ $name+':'+$event.hresult_hex)}
    if($name-ceq'GetObject'){
     if($null-eq$objectResult.Instance){throw 'S_OK_WITH_NULL_OBJECT'}
     $entry=[pscustomobject]@{Name=$FullPath;Instance=$objectResult.Instance};$status='REGISTERED_OBJECT_OBTAINED_IDENTITY_UNVERIFIED'
    }
   }catch{
    $event.status='FAILED';$event.error=$_.Exception.ToString()
    if($null-eq$event.raw_hresult){$native=$_.Exception;while($null-ne$native.InnerException){$native=$native.InnerException};$event.raw_hresult=[int]$native.HResult;$event.hresult_hex=([uint32]([long]$event.raw_hresult-band4294967295)).ToString('X8')}
    throw
   }finally{if($null-ne$Emit){& $Emit $event}}
  }
 }catch{$detail=$_.Exception.ToString();$status='FAILED_OR_UNKNOWN'}
 finally{
  $event=[ordered]@{stage='ReleaseOwnedNameAndTable';at_utc=[DateTime]::UtcNow.ToString('o');status='ENTERED';raw_hresult=$null;hresult_hex=$null;error=$null};$Events.Add($event);if($null-ne$Emit){& $Emit $event}
  try{$Backend.Dispose();$disposed=$true;$event.status='RETURNED'}catch{$event.status='FAILED';$event.error=$_.Exception.ToString();$status='OWNED_COM_RELEASE_UNKNOWN';$detail=$event.error}finally{if($null-ne$Emit){& $Emit $event}}
 }
 [pscustomobject]@{status=$status;detail=$detail;counts=[pscustomobject]$counts;entry=$entry;owned_name_and_table_released=$disposed;object_identity_unverified=($null-ne$entry);activation_count=0;fallback_count=0;enumeration_count=0}
}
