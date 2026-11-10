using System;using CadChannelV11;
class TestChannel {
 static int rejected;static void Reject(Boot b,Request r){try{ChannelProtocol.ValidateRequest(b,r,11,22,33,1);throw new Exception("ACCEPTED_BAD_ROUTE");}catch(InvalidOperationException){rejected++;}}
 static int Main(){var b=new Boot{run_id="test",owner="A",source_thread_id=ChannelProtocol.Source,expires_utc=DateTimeOffset.UtcNow.AddMinutes(2).ToString("o"),operations=new[]{"KNOWN_WRITE_BATCH"},cases=new[]{new CadFixedResearchV3.CaseInput{work=@"C:\test\a.dwg"}}};var r=new Request{schema_version=10,run_id="test",owner="A",source_thread_id=ChannelProtocol.Source,request_id="r1",nonce="n1",sequence=1,pid=11,created=22,hwnd=33,document=@"C:\test\a.dwg",operation="KNOWN_WRITE_BATCH",expires_utc=DateTimeOffset.UtcNow.AddMinutes(1).ToString("o")};
 ChannelProtocol.ValidateRequest(b,r,11,22,33,1);
 r.source_thread_id=ChannelProtocol.Executor;Reject(b,r);r.source_thread_id=ChannelProtocol.Source;
 r.pid=12;Reject(b,r);r.pid=11;r.created=23;Reject(b,r);r.created=22;r.document=@"C:\test\b.dwg";Reject(b,r);r.document=@"C:\test\a.dwg";
 r.operation="ARBITRARY";Reject(b,r);r.operation="KNOWN_WRITE_BATCH";r.sequence=2;Reject(b,r);
 Console.WriteLine("PASS_CHANNEL_PROTOCOL_REAL_ORIGIN_OWNER_DOCUMENT_OPERATION_BOUNDARIES rejected="+rejected);return rejected==6?0:1;}
}

