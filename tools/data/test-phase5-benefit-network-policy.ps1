param([ValidateSet('Policy','Qualification','Transport','LoadedTypes','All')][string]$Group='All')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$library=Join-Path $PSScriptRoot 'phase5-benefit-network-policy.ps1'
if(-not (Test-Path -LiteralPath $library)){throw 'RED: missing strict network policy boundary'}
. $library
function Check($Value,[string]$Message){if(-not $Value){throw $Message}}
function Equal($Actual,$Expected,[string]$Message){if($Actual -cne $Expected){throw "$Message expected=$Expected actual=$Actual"}}
function Reject([scriptblock]$Action,[string]$Message){$hit=$false;try{& $Action | Out-Null}catch{$hit=$true};Check $hit $Message}
if($Group -cin @('Qualification','All')){
    Initialize-InternalPhase5NetworkTypes
    $actual=Get-Phase5NetworkTransportIdentity
    $actualQualified=Test-InternalPhase5NetworkQualification $actual
    Write-Host ('P5-2C actual runtime: '+($actual | ConvertTo-Json -Compress)+' qualified='+$actualQualified)
    if($actual.OS -ceq 'Microsoft Windows 10.0.26300' -and $actual.Architecture -ceq 'X64' -and $actual.Framework -cin @('.NET 10.0.12','.NET 10.0.14')){
        Check $actualQualified 'Actual exact qualified Windows runtime must be accepted with trusted implementation'
    }else{Check (-not $actualQualified) 'Actual unqualified runtime remains blocked'}
    # Literal identity controls are not evidence that the test ran on each framework.
    foreach($case in @(
        @{Framework='.NET 10.0.12';Expected=$true},@{Framework='.NET 10.0.14';Expected=$true},
        @{Framework='.NET 10.0.11';Expected=$false},@{Framework='.NET 10.0.13';Expected=$false},
        @{Framework='.NET 10.0.15';Expected=$false},@{Framework='.NET 10.0.140';Expected=$false},
        @{Framework='.NET 10.0.14-preview';Expected=$false},@{Framework='.net 10.0.14';Expected=$false}
    )){
        $synthetic=[pscustomobject]@{Profile='P52_HTTP11_SINGLE_CONNECTION_V1';Framework=$case.Framework;OS='Microsoft Windows 10.0.26300';Architecture='X64'}
        Equal (Test-InternalPhase5NetworkQualification $synthetic) $case.Expected ('Synthetic exact framework gate '+$case.Framework)
    }
    foreach($case in @(
        @{Field='OS';Value='Microsoft Windows 10.0.26301'},@{Field='OS';Value='Ubuntu 26.04.1 LTS'},
        @{Field='Architecture';Value='X86'},@{Field='Architecture';Value='Arm64'},
        @{Field='Profile';Value='P52_HTTP11_SINGLE_CONNECTION_V2'}
    )){
        $synthetic=[pscustomobject]@{Profile='P52_HTTP11_SINGLE_CONNECTION_V1';Framework='.NET 10.0.14';OS='Microsoft Windows 10.0.26300';Architecture='X64'}
        $synthetic.($case.Field)=$case.Value
        Check (-not (Test-InternalPhase5NetworkQualification $synthetic)) ('Synthetic changed '+$case.Field+' remains unqualified')
    }
    Write-Host 'P5-2C Qualification PASS: actual runtime result above; synthetic exact 10.0.12/10.0.14 and negative identities'
}
if($Group -cin @('Policy','All')){
    $policy=New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('example.go.kr','open.mma.go.kr') -MaxPhysicalAttempts 2
    Assert-Phase5BenefitNetworkPolicy $policy
    Equal (Get-Phase5NetworkPolicyFingerprint $policy) (Get-Phase5NetworkPolicyFingerprint (New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('open.mma.go.kr','example.go.kr') -MaxPhysicalAttempts 2)) 'Host ordering is canonical'
    foreach($url in @('http://example.go.kr/a','https://x.example.go.kr/a','https://example.go.kr:444/a','https://user@example.go.kr/a','https://example.go.kr./a','https://example.go.kr/a#secret','https://127.0.0.1/a','https://example.go.kr/a/../b','https://example.go.kr/%2e%2e/b')){
        Reject {Assert-InternalPhase5NetworkUrl -Policy $policy -Url $url} "Reject unsafe URL $url"
    }
    Assert-InternalPhase5NetworkUrl -Policy $policy -Url 'https://example.go.kr/a'
    $allowed=@('https://example.go.kr/a')
    $state=New-InternalPhase5NetworkState -Policy $policy -BatchId ('batch-'+('a'*64)) -SourceUrls $allowed
    Reject {Assert-InternalPhase5NetworkDestination -State $state -Url 'https://example.go.kr/other'} 'Same approved host does not authorize another URL'
    $mma=New-InternalPhase5NetworkState -Policy $policy -BatchId ('batch-'+('b'*64)) -SourceUrls @('https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357')
    Assert-InternalPhase5NetworkDestination -State $mma -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList'
    Assert-InternalPhase5NetworkDestination -State $mma -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=123&callback=MmaBenefitDetail'
    Reject {Assert-InternalPhase5NetworkDestination -State $mma -Url 'https://open.mma.go.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall.json?udgigwan_cd=123&callback=evil'} 'MMA callback shape bound'
    $zero=New-InternalPhase5NetworkState -Policy (New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('example.go.kr') -MaxPhysicalAttempts 0) -BatchId ('batch-'+('c'*64)) -SourceUrls $allowed
    Reject {$zero.Accounting.Reserve()} 'Budget0 denies reservation'
    Equal $zero.Accounting.ReservationsConsumed 0 'No reservation on denial'
    Equal $zero.Accounting.DeniedCount 1 'Admission denied measured'
    Equal $zero.Accounting.FirstStopReason BUDGET_EXHAUSTED 'Sticky budget reason'
    Reject {$zero.Accounting.Reserve()} 'Sticky stop blocks further admission'
    $one=$state.Accounting.Reserve();$state.Accounting.Dispatch($one);$state.Accounting.Response($one);$state.Accounting.Finish($one,$false)
    $two=$state.Accounting.Reserve();$state.Accounting.Dispatch($two);$state.Accounting.Finish($two,$true)
    Reject {$state.Accounting.Reserve()} 'Third request denied after two consumed tokens'
    Equal $state.Accounting.AttemptedCount 2 'Dispatch count distinct'
    Equal $state.Accounting.RespondedCount 1 'Headers observed count'
    Equal $state.Accounting.UnknownOutcomeCount 1 'Timeout outcome unknown'
    Equal $state.Accounting.FirstStopReason BUDGET_EXHAUSTED 'Timeout itself is not budget denial'
    $copy=$policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json;$copy.MaxRetries=1
    Reject {Assert-Phase5BenefitNetworkPolicy $copy} 'Retry override rejected'
    $copy=$policy | ConvertTo-Json -Depth 10 | ConvertFrom-Json;$copy | Add-Member NoteProperty Verified $true
    Reject {Assert-Phase5BenefitNetworkPolicy $copy} 'Self-verified field rejected'
    $identity=Get-Phase5NetworkTransportIdentity
    $bad=$identity | Select-Object *;$bad.Framework='unknown'
    Check (-not (Test-InternalPhase5NetworkQualification $bad)) 'Unknown runtime remains unqualified'
    foreach($ip in @('127.0.0.1','10.1.2.3','169.254.169.254','::1','::ffff:127.0.0.1','fc00::1','2001:db8::1')){Check (-not [Milimap.P52.NetworkBoundary]::IsPublicAddress([Net.IPAddress]::Parse($ip))) "Unsafe resolved address $ip"}
    Check ([Milimap.P52.NetworkBoundary]::IsPublicAddress([Net.IPAddress]::Parse('8.8.8.8'))) 'Public address accepted'
    Write-Host 'P5-2B Policy PASS: budget0, sticky stop, exact URL/MMA destinations, runtime and unsafe IP rejection'
}
if($Group -cin @('Transport','All')){
    Initialize-InternalPhase5NetworkTypes
    $a=[Milimap.P52.Accounting]::new(1);$token=$a.Reserve();$a.Dispatch($token)
    Reject {$a.Dispatch($token)} 'A reservation must not authorize a second transport dispatch'
    $a.Finish($token,$false)
}
if($Group -cin @('Transport','All')){
    if(-not ('P52CountingServer' -as [type])){Add-Type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Sockets;
using System.Net.Security;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
public sealed class P52AiaProbe : IDisposable {
 private readonly TcpListener listener=new TcpListener(IPAddress.Loopback,0);private readonly CancellationTokenSource cancel=new CancellationTokenSource();private readonly Task worker;private int count;
 public int Count=>count;public string Url {get;}
 public P52AiaProbe(){listener.Start();Url="http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port+"/issuer.cer";worker=Task.Run(async()=>{while(!cancel.IsCancellationRequested){try{using(var c=await listener.AcceptTcpClientAsync(cancel.Token)){Interlocked.Increment(ref count);using(var stream=c.GetStream()){await stream.WriteAsync(Encoding.ASCII.GetBytes("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),cancel.Token);}}}catch{return;}}});}
 public void Dispose(){cancel.Cancel();listener.Stop();try{worker.GetAwaiter().GetResult();}catch{}cancel.Dispose();}
}
public static class P52RawHello {
 public static byte[] Capture(){
  var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();int port=((IPEndPoint)listener.LocalEndpoint).Port;
  var task=Task.Run(async()=>{try{using(var client=new TcpClient()){await client.ConnectAsync(IPAddress.Loopback,port);using(var ssl=new SslStream(client.GetStream(),false)){await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions{TargetHost="localhost",EnabledSslProtocols=System.Security.Authentication.SslProtocols.Tls12});}}}catch{}});
  byte[] result;using(var peer=listener.AcceptTcpClient())using(var stream=peer.GetStream()){
   stream.ReadTimeout=2000;byte[] header=new byte[5];stream.ReadExactly(header);int length=header[3]*256+header[4];if(length>16384)throw new Exception("HELLO_LIMIT");byte[] body=new byte[length];stream.ReadExactly(body);result=new byte[5+length];header.CopyTo(result,0);body.CopyTo(result,5);
  }listener.Stop();task.GetAwaiter().GetResult();return result;
 }
 public static void Send(Uri uri,byte[] hello){using(var tcp=new TcpClient()){tcp.Connect(IPAddress.Loopback,uri.Port);using(var stream=tcp.GetStream()){stream.ReadTimeout=3000;stream.Write(hello);byte[] reply=new byte[1];stream.Read(reply,0,1);}}}
}
public sealed class P52CountingServer : IDisposable {
 private SslStreamCertificateContext serverContext; private P52AiaProbe aia;public int AiaRequests=>aia?.Count ?? 0;public X509Certificate2 TrustRoot {get;private set;}
 private X509Certificate2 AiaCertificate(){
  aia=new P52AiaProbe();
  using(var rootKey=RSA.Create(2048))using(var intermediateKey=RSA.Create(2048))using(var leafKey=RSA.Create(2048)){
   var rootReq=new CertificateRequest("CN=fixture-root-"+Guid.NewGuid().ToString("N"),rootKey,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);rootReq.CertificateExtensions.Add(new X509BasicConstraintsExtension(true,false,0,true));rootReq.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign,true));
   using(var root=rootReq.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-2),DateTimeOffset.UtcNow.AddHours(2))){
    TrustRoot=X509CertificateLoader.LoadCertificate(root.Export(X509ContentType.Cert));
    var interReq=new CertificateRequest("CN=missing-intermediate-"+Guid.NewGuid().ToString("N"),intermediateKey,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);interReq.CertificateExtensions.Add(new X509BasicConstraintsExtension(true,false,0,true));interReq.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.KeyCertSign,true));
    using(var interPublic=interReq.Create(root,DateTimeOffset.UtcNow.AddMinutes(-1),DateTimeOffset.UtcNow.AddHours(1),new byte[]{1,2,3,4}))using(var intermediate=interPublic.CopyWithPrivateKey(intermediateKey)){
     var leafReq=new CertificateRequest("CN=localhost",leafKey,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);var san=new SubjectAlternativeNameBuilder();san.AddDnsName("localhost");leafReq.CertificateExtensions.Add(san.Build());
     var writer=new System.Formats.Asn1.AsnWriter(System.Formats.Asn1.AsnEncodingRules.DER);writer.PushSequence();writer.PushSequence();writer.WriteObjectIdentifier("1.3.6.1.5.5.7.48.2");writer.WriteCharacterString(System.Formats.Asn1.UniversalTagNumber.IA5String,aia.Url,new System.Formats.Asn1.Asn1Tag(System.Formats.Asn1.TagClass.ContextSpecific,6));writer.PopSequence();writer.PopSequence();leafReq.CertificateExtensions.Add(new X509Extension("1.3.6.1.5.5.7.1.1",writer.Encode(),false));
     using(var leafPublic=leafReq.Create(intermediate,DateTimeOffset.UtcNow.AddSeconds(-30),DateTimeOffset.UtcNow.AddMinutes(30),new byte[]{2,3,4,5}))using(var leaf=leafPublic.CopyWithPrivateKey(leafKey)){return X509CertificateLoader.LoadPkcs12(leaf.Export(X509ContentType.Pkcs12),null,X509KeyStorageFlags.DefaultKeySet);}
    }
   }
  }
 }
 private readonly TcpListener listener;private readonly CancellationTokenSource cancel=new CancellationTokenSource();private readonly Task worker;private int requests,connections;
 public string LastError {get;private set;} public int Requests=>requests; public int Connections=>connections; public Uri Url {get;} public X509Certificate2 Certificate {get;}
 public P52CountingServer(string mode){
  if(mode=="aia"){Certificate=AiaCertificate();}else using(var key=RSA.Create(2048)){
   var req=new CertificateRequest("CN=localhost",key,HashAlgorithmName.SHA256,RSASignaturePadding.Pkcs1);
   var san=new SubjectAlternativeNameBuilder();san.AddDnsName("localhost");req.CertificateExtensions.Add(san.Build());
   req.CertificateExtensions.Add(new X509BasicConstraintsExtension(true,false,0,true));
   using(var generated=req.CreateSelfSigned(DateTimeOffset.UtcNow.AddMinutes(-1),DateTimeOffset.UtcNow.AddHours(1))){Certificate=X509CertificateLoader.LoadPkcs12(generated.Export(X509ContentType.Pkcs12),null,X509KeyStorageFlags.DefaultKeySet);}
  }
  serverContext=SslStreamCertificateContext.Create(Certificate,null,true);
  listener=new TcpListener(IPAddress.Loopback,0);listener.Start();Url=new Uri("https://localhost:"+((IPEndPoint)listener.LocalEndpoint).Port+"/fixture");
  worker=Task.Run(async()=>{
   while(!cancel.IsCancellationRequested){
    TcpClient client;try{client=await listener.AcceptTcpClientAsync(cancel.Token);}catch{return;}
    Interlocked.Increment(ref connections);
    using(client)using(var ssl=new SslStream(client.GetStream(),false)){
     try{
      await ssl.AuthenticateAsServerAsync(new SslServerAuthenticationOptions{ServerCertificateContext=serverContext},cancel.Token);
      var bytes=new MemoryStream();byte[] one=new byte[1];
      while(bytes.Length<10000){int n=await ssl.ReadAsync(one,cancel.Token);if(n==0)break;bytes.WriteByte(one[0]);if(bytes.Length>=4 && Encoding.ASCII.GetString(bytes.ToArray()).EndsWith("\r\n\r\n"))break;}
      if(bytes.Length==0)continue;Interlocked.Increment(ref requests);
      if(mode=="reset"){client.Client.LingerState=new LingerOption(true,0);continue;}
      if(mode=="timeout"){await Task.Delay(2000,cancel.Token);continue;}
      if(mode=="delayed"){await Task.Delay(200,cancel.Token);}
      string response="HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nOK";
      if(mode=="redirect")response="HTTP/1.1 302 Found\r\nLocation: /again\r\nContent-Length: 0\r\n\r\n";
      if(mode=="auth")response="HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=fixture\r\nContent-Length: 0\r\n\r\n";
      if(mode=="large")response="HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n"+new string('x',100);
      if(mode=="chunked")response="HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n20\r\n"+new string('x',32)+"\r\n0\r\n\r\n";
      if(mode=="trailers")response="HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nTrailer: X-Large\r\n\r\n0\r\nX-Large: "+new string('x',4096)+"\r\n\r\n";
      if(mode=="headers")response="HTTP/1.1 200 OK\r\nX-Large: "+new string('x',4096)+"\r\nContent-Length: 0\r\n\r\n";
      await ssl.WriteAsync(Encoding.ASCII.GetBytes(response),cancel.Token);await ssl.FlushAsync(cancel.Token);
      // Deliberately close even the keep-alive response; a subsequent request must use a fresh connection.
     }catch(Exception e){LastError=e.ToString();}
    }
   }
  });
 }
 public void Dispose(){cancel.Cancel();listener.Stop();try{worker.GetAwaiter().GetResult();}catch{}Certificate.Dispose();TrustRoot?.Dispose();aia?.Dispose();cancel.Dispose();}
}
"@}
    $flags=[Reflection.BindingFlags]'NonPublic,Static'
    $factory=[Milimap.P52.NetworkBoundary].GetMethod('CreateHandler',$flags)
    $exchange=[Milimap.P52.NetworkBoundary].GetMethod('Exchange',$flags)
    foreach($case in @('ok','redirect','auth','timeout','reset','large','chunked','headers','trailers','untrusted-tls','aia')){
        $server=[P52CountingServer]::new($case)
        try{
            $account=[Milimap.P52.Accounting]::new(2)
            $iterations=if($case -ceq 'ok'){2}else{1}
            for($i=0;$i -lt $iterations;$i++){
                # Reflection reaches the same private handler/exchange core only in tests.
                # The production Send entrypoint never accepts an address, certificate, handler or callback.
                $handler=$factory.Invoke($null,@([Net.IPAddress[]]@([Net.IPAddress]::Loopback),[int]500,[int]1024,$account))
                Check ($null -eq $handler.SslOptions.RemoteCertificateValidationCallback) 'TLS validation callback is never bypassed'
                Check ($null -ne $handler.SslOptions.CertificateChainPolicy -and $handler.SslOptions.CertificateChainPolicy.DisableCertificateDownloads) 'TLS issuer downloads must be disabled outside the counted transport'
                Check (-not $handler.AllowAutoRedirect -and -not $handler.UseProxy -and -not $handler.UseCookies) 'Redirect/proxy/cookie suppression'
                if($case -cne 'untrusted-tls'){
                    $chain=[Security.Cryptography.X509Certificates.X509ChainPolicy]::new()
                    $chain.TrustMode=[Security.Cryptography.X509Certificates.X509ChainTrustMode]::CustomRootTrust
                    [void]$chain.CustomTrustStore.Add($(if($null -ne $server.TrustRoot){$server.TrustRoot}else{$server.Certificate}));$chain.DisableCertificateDownloads=$handler.SslOptions.CertificateChainPolicy.DisableCertificateDownloads
                    $chain.RevocationMode=[Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
                    $handler.SslOptions.CertificateChainPolicy=$chain
                }
                if($case -ceq 'aia'){
                    # Isolate client chain validation from Schannel's server credential construction.
                    # The leaf has an uncached missing issuer and a separate local HTTP AIA endpoint.
                    $clientChain=[Security.Cryptography.X509Certificates.X509Chain]::new()
                    try{
                        $clientChain.ChainPolicy=$handler.SslOptions.CertificateChainPolicy
                        Check (-not $clientChain.Build($server.Certificate)) 'Missing intermediate fails the owned client chain policy'
                        Check (@($clientChain.ChainStatus | Where-Object Status -EQ PartialChain).Count -gt 0) 'Failure is incomplete trust, not an unrelated TLS failure'
                        Equal $server.AiaRequests 0 'Client chain validation sends zero issuer HTTP requests'
                    }finally{$clientChain.Dispose();$handler.Dispose()}
                    if([OperatingSystem]::IsWindows()){
                        [P52RawHello]::Send($server.Url,[P52RawHello]::Capture())
                        Write-Host "P5-2B AIA fixture attribution: raw ClientHello, no client chain validation, server-side requests=$($server.AiaRequests)"
                    }
                    Write-Host 'P5-2B AIA PASS: owned client chain policy rejects missing intermediate / client issuer HTTP0; server construction measured separately'
                    break
                }
                $token=$account.Reserve();$response=$null;$caught=$null;$beforeHeaders=$account.RespondedCount
                $exchangeDeadline=[Threading.CancellationTokenSource]::new($(if($case -ceq 'timeout'){200}else{1500}))
                try{$response=$exchange.Invoke($null,@($server.Url,$handler,[int]1500,[long]16,$account,[long]$token,$exchangeDeadline.Token))}catch{$caught=$_.Exception.ToString()}finally{$account.Finish($token,($account.RespondedCount -eq $beforeHeaders));$exchangeDeadline.Dispose()}
                if($case -cin @('ok','auth')){Check ($null -eq $caught) "$case completes without transport retry: $caught server=$($server.LastError)";Equal $response.StatusCode $(if($case -ceq 'ok'){200}else{401}) 'Actual response status'}else{Check ($null -ne $caught) "$case fails closed"}
            }
            if($case -ceq 'aia'){continue}
            Equal $account.AttemptedCount $iterations "$case actual dispatch count"
            Equal $server.Requests $(if($case -cin @('untrusted-tls','aia')){0}else{$iterations}) "$case independently counted HTTP requests / no retry or redirect"
            Equal $server.Connections $iterations "$case no connection reuse or reconnect"
            switch($case){
                headers {Equal $account.FirstStopReason RESPONSE_HEADERS_EXCEEDED 'Excess headers set sticky policy stop';Check (-not $account.CanStart()) 'No next cycle after header limit'}
                trailers {Equal $account.FirstStopReason RESPONSE_HEADERS_EXCEEDED 'Excess trailers set sticky policy stop';Check (-not $account.CanStart()) 'No next cycle after trailer limit'}
                redirect {Equal $account.FirstStopReason REDIRECT_DENIED 'Redirect is a sticky policy stop'}
                large {Equal $account.FirstStopReason RESPONSE_SIZE_EXCEEDED 'Content-Length bound'}
                chunked {Equal $account.FirstStopReason RESPONSE_SIZE_EXCEEDED 'Streaming body bound without length'}
                timeout {Equal $account.FirstStopReason $null 'Ordinary timeout is not budget exhaustion';Equal $account.UnknownOutcomeCount 1 'Timeout transmission outcome preserved unknown'}
                reset {Equal $account.UnknownOutcomeCount 1 'Reset after server receives request remains unknown at client'}
                untrusted-tls {Equal $account.UnknownOutcomeCount 1 'TLS failure cannot be called a completed HTTP response'}
            }
            Write-Host "P5-2B Transport $case PASS: dispatch=$($account.AttemptedCount) countedHTTP=$($server.Requests) connections=$($server.Connections) unknown=$($account.UnknownOutcomeCount)"
        }finally{$server.Dispose()}
    }
    # Atomic concurrency: two simultaneous admissions cannot both obtain the one token.
    $parallel=[Milimap.P52.Accounting]::new(1)
    $jobs=@(1..2 | ForEach-Object {$parallel} | ForEach-Object -Parallel {try{$_.Reserve()}catch{} } -ThrottleLimit 2)
    Equal $parallel.ReservationsConsumed 1 'Concurrent admissions consume exactly one token'
    Equal @($jobs).Count 1 'Exactly one concurrent admission succeeds'
    Write-Host ('P5-2B qualification evidence: '+(Get-Phase5NetworkTransportIdentity | ConvertTo-Json -Compress))
}
if($Group -cin @('Transport','All')){
    $server=[P52CountingServer]::new('ok')
    $reconnectAccounting=[Milimap.P52.Accounting]::new(2)
    try{
        $handler=$factory.Invoke($null,@([Net.IPAddress[]]@([Net.IPAddress]::Loopback),[int]1000,[int]1024,$reconnectAccounting))
        $chain=[Security.Cryptography.X509Certificates.X509ChainPolicy]::new();$chain.TrustMode='CustomRootTrust';[void]$chain.CustomTrustStore.Add($(if($null -ne $server.TrustRoot){$server.TrustRoot}else{$server.Certificate}));$chain.DisableCertificateDownloads=$handler.SslOptions.CertificateChainPolicy.DisableCertificateDownloads;$chain.RevocationMode='NoCheck';$handler.SslOptions.CertificateChainPolicy=$chain
        $client=[Net.Http.HttpClient]::new($handler)
        try{
            $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$server.Url);$request.Version=[Version]'1.1';$request.VersionPolicy='RequestVersionExact';$request.Headers.ConnectionClose=$true
            try{$response=$client.SendAsync($request).GetAwaiter().GetResult();$response.Dispose()}finally{$request.Dispose()}
            $next=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$server.Url);$next.Version=[Version]'1.1';$next.VersionPolicy='RequestVersionExact';$next.Headers.ConnectionClose=$true
            try{Reject {$client.SendAsync($next).GetAwaiter().GetResult()} 'Reconnect on the same handler is blocked before another connection'}finally{$next.Dispose()}
            Equal $server.Connections 1 'Reconnect denied before TCP connect'
            Equal $server.Requests 1 'Reuse failure cannot transmit a second request'
            Equal $reconnectAccounting.FirstStopReason TRANSPORT_RECONNECT_BLOCKED 'Denied hidden reconnect must latch policy stop, not permit another pristine cycle'
        }finally{$client.Dispose()}
    }finally{$server.Dispose()}
    Write-Host 'P5-2B reconnect guard PASS: handler reuse/reconnect transmits no additional request'
}
if($Group -cin @('Transport','All')){
    $server=[P52CountingServer]::new('delayed')
    $deadline=[Threading.CancellationTokenSource]::new(300)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $account=[Milimap.P52.Accounting]::new(1);$token=$account.Reserve()
        $handler=$factory.Invoke($null,@([Net.IPAddress[]]@([Net.IPAddress]::Loopback),[int]1000,[int]1024,$account))
        $handler.SslOptions.CertificateChainPolicy.TrustMode='CustomRootTrust';[void]$handler.SslOptions.CertificateChainPolicy.CustomTrustStore.Add($server.Certificate)
        # Controlled resolver-phase delay, then a separately delayed response.
        [Threading.Tasks.Task]::Delay(150).GetAwaiter().GetResult()
        $errorRecord=$null
        $arguments=@($server.Url,$handler,[int]300,[long]16,$account,[long]$token)
        if($exchange.GetParameters().Count -eq 7){$arguments+=@($deadline.Token)}
        try{[void]$exchange.Invoke($null,$arguments)}catch{$errorRecord=$_}finally{$account.Finish($token,($account.RespondedCount -eq 0))}
        Check ($null -ne $errorRecord) 'One total deadline must cover resolver phase plus response phase, not restart after resolution'
        Equal $server.Requests 1 'Deadline test actually transmitted one request before response delay'
        Check ($clock.ElapsedMilliseconds -lt 650) 'Single deadline honored within scheduling tolerance'
        Write-Host "P5-2B total deadline PASS: elapsed=$($clock.ElapsedMilliseconds)ms budget=300ms, controlled resolver delay150ms"
    }finally{$deadline.Dispose();$server.Dispose()}
}
if($Group -cin @('Transport','All')){
    $account=[Milimap.P52.Accounting]::new(1);$token=$account.Reserve()
    $handler=$factory.Invoke($null,@([Net.IPAddress[]]@([Net.IPAddress]::Loopback),[int]1000,[int]1024,$account))
    $expired=[Threading.CancellationTokenSource]::new();$expired.Cancel()
    try{Reject {$exchange.Invoke($null,@([Uri]'https://localhost:1/expired',$handler,[int]1000,[long]16,$account,[long]$token,$expired.Token))} 'Expired shared deadline fails before dispatch';Equal $account.AttemptedCount 0 'No dispatch after deadline expiration'}finally{$account.Finish($token,$false);$expired.Dispose()}
}

if($Group -cin @('LoadedTypes','All')){
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('milimap-p52-loaded-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($scratch)
    $driver=Join-Path $scratch 'probe.ps1'
    @'
param([string]$Case,[string]$Module,[string]$Scratch)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($Case -cin @('preloaded-drift','untrusted-provenance')){
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Module,[ref]$tokens,[ref]$parseErrors)
    $literal=$ast.Find({param($node);$node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('namespace Milimap.P52')},$true)
    if($null -eq $literal -or $parseErrors.Count -ne 0){throw 'PRELOAD_SOURCE_FIXTURE_INVALID'}
    $drift=$literal.Value.Replace('request.Headers.ConnectionClose=true;','request.Headers.ConnectionClose=false;')
    if($drift -ceq $literal.Value){throw 'PRELOAD_SOURCE_MUTATION_MISSING'}
    if($Case -eq 'untrusted-provenance'){Add-Type -TypeDefinition $literal.Value}else{Add-Type -TypeDefinition $drift}
}
if($Case -eq 'incompatible'){
    Add-Type 'namespace Milimap.P52 { public static class NetworkBoundary { public static string ClaimedProfile = "P52_HTTP11_SINGLE_CONNECTION_V1"; } public sealed class Accounting { public Accounting(long n){} } }'
}
if($Case -eq 'crlf'){
    $dependency=Join-Path (Split-Path -Parent $Module) 'lib/history/history-fingerprints.ps1'
    $source=[IO.File]::ReadAllText($Module).Replace("`r`n","`n").Replace("`n","`r`n")
    $source=$source.Replace('. (Join-Path $PSScriptRoot ''lib/history/history-fingerprints.ps1'')',(". '"+$dependency.Replace("'","''")+"'"))
    $Module=Join-Path $Scratch 'crlf-policy.ps1';[IO.File]::WriteAllText($Module,$source)
}
if($Case -cin @('repeat','crlf')){
    . $Module
    Initialize-InternalPhase5NetworkTypes
    $first='Milimap.P52.NetworkBoundary' -as [type]
    & {param($Path);. $Path;Initialize-InternalPhase5NetworkTypes} $Module
    . $Module
    Initialize-InternalPhase5NetworkTypes
    if(-not [object]::ReferenceEquals($first,('Milimap.P52.NetworkBoundary' -as [type]))){throw 'VALID_REPEAT_TYPE_CHANGED'}
    Write-Host "LoadedTypes $Case PASS: same exact validated types survive module reload"
    exit 0
}
if($Case -eq 'changed-loaded'){
    . $Module
    Initialize-InternalPhase5NetworkTypes
    $originalDefinition=(Get-InternalPhase5NetworkTypeDefinition).Replace("`r`n","`n")
    $oldPin=Get-HistorySha256 -Text $originalDefinition
    $newPin=Get-HistorySha256 -Text $originalDefinition.Replace('request.Headers.ConnectionClose=true;','request.Headers.ConnectionClose=false;')
}
if($Case -cin @('changed-source','changed-loaded')){
    $source=[IO.File]::ReadAllText($Module)
    $changed=$source.Replace('request.Headers.ConnectionClose=true;','request.Headers.ConnectionClose=false;')
    if($changed -ceq $source){throw 'FIXTURE_MUTATION_DID_NOT_CHANGE_SOURCE'}
    $dependency=Join-Path (Split-Path -Parent $Module) 'lib/history/history-fingerprints.ps1'
    $changed=$changed.Replace('. (Join-Path $PSScriptRoot ''lib/history/history-fingerprints.ps1'')',(". '"+$dependency.Replace("'","''")+"'"))
    if($Case -eq 'changed-loaded'){$changed=$changed.Replace($oldPin,$newPin)}
    $Module=Join-Path $Scratch 'changed-policy.ps1'
    [IO.File]::WriteAllText($Module,$changed)
}
. $Module
$identity=Get-Phase5NetworkTransportIdentity
$qualified=Test-InternalPhase5NetworkQualification $identity
$rejected=$false
try{Initialize-InternalPhase5NetworkTypes}catch{$rejected=$true}
$stateCreated=$false
try{$state=New-InternalPhase5NetworkState -Policy (New-Phase5BenefitNetworkPolicy -AllowedHttpsHosts @('example.go.kr') -MaxPhysicalAttempts 0) -BatchId ('batch-'+('d'*64)) -SourceUrls @('https://example.go.kr/a');$stateCreated=$true}catch{}
Write-Host "LoadedTypes $Case observed: qualified=$qualified initRejected=$rejected stateCreated=$stateCreated profile=$($identity.Profile)"
if(-not $rejected -or $qualified -or $stateCreated){throw 'RED: incompatible or changed transport accepted solely by type/profile/environment identity'}
'@ | Set-Content -LiteralPath $driver -Encoding utf8
    try{
        $failures=@()
        foreach($case in @('incompatible','preloaded-drift','untrusted-provenance','changed-source','changed-loaded','repeat','crlf')){
            & (Get-Command pwsh).Source -NoProfile -File $driver -Case $case -Module $library -Scratch $scratch
            if($LASTEXITCODE -ne 0){$failures+=@($case)}
        }
        if($failures.Count -gt 0){throw ('LoadedTypes regressions failed: '+($failures -join ','))}
    }finally{
        $full=[IO.Path]::GetFullPath($scratch)
        if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or -not ([IO.Path]::GetFileName($full)).StartsWith('milimap-p52-loaded-')){throw 'UNSAFE_LOADED_TEST_CLEANUP'}
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
