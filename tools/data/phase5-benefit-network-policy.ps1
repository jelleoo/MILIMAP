Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib/history/history-fingerprints.ps1')

function Get-Phase5NetworkTransportIdentity {
    [pscustomobject][ordered]@{Profile='P52_HTTP11_SINGLE_CONNECTION_V1';Framework=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;OS=[Runtime.InteropServices.RuntimeInformation]::OSDescription;Architecture=[string][Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture}
}
function Test-InternalPhase5NetworkQualification {
    param($Identity)
    # Qualification is deliberately exact. Other runtimes never inherit these results.
    return ($Identity.Profile -ceq 'P52_HTTP11_SINGLE_CONNECTION_V1' -and $Identity.Framework -ceq '.NET 10.0.12' -and $Identity.OS -ceq 'Microsoft Windows 10.0.26300' -and $Identity.Architecture -ceq 'X64')
}
function New-Phase5BenefitNetworkPolicy {
    param([Parameter(Mandatory)][string[]]$AllowedHttpsHosts,[Parameter(Mandatory)][long]$MaxPhysicalAttempts,[int]$RequestTimeoutMilliseconds=30000,[long]$MaxResponseBodyBytes=33554432,[int]$MaxResponseHeaderBytes=65536)
    $hosts=@($AllowedHttpsHosts | ForEach-Object {$_.ToLowerInvariant()} | Sort-Object -Unique -CaseSensitive)
    $p=[pscustomobject][ordered]@{PolicyVersion=1;TransportProfileId='P52_HTTP11_SINGLE_CONNECTION_V1';AllowedHttpsHosts=$hosts;MaxPhysicalAttempts=$MaxPhysicalAttempts;RequestTimeoutMilliseconds=$RequestTimeoutMilliseconds;MaxResponseBodyBytes=$MaxResponseBodyBytes;MaxResponseHeaderBytes=$MaxResponseHeaderBytes;MaxRedirects=0;MaxRetries=0;MaxInFlight=1}
    Assert-Phase5BenefitNetworkPolicy $p
    return $p
}
function Assert-Phase5BenefitNetworkPolicy {
    param($Policy)
    $fields=@('PolicyVersion','TransportProfileId','AllowedHttpsHosts','MaxPhysicalAttempts','RequestTimeoutMilliseconds','MaxResponseBodyBytes','MaxResponseHeaderBytes','MaxRedirects','MaxRetries','MaxInFlight')
    if($null -eq $Policy -or $Policy -isnot [pscustomobject] -or (@($Policy.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join '|') -cne (@($fields | Sort-Object -CaseSensitive) -join '|')){throw 'P52B_POLICY_SHAPE_INVALID'}
    foreach($key in @('PolicyVersion','MaxPhysicalAttempts','RequestTimeoutMilliseconds','MaxResponseBodyBytes','MaxResponseHeaderBytes','MaxRedirects','MaxRetries','MaxInFlight')){if($Policy.$key -isnot [int] -and $Policy.$key -isnot [long]){throw 'P52B_POLICY_INTEGER_REQUIRED'}}
    if($Policy.PolicyVersion -ne 1 -or $Policy.TransportProfileId -cne 'P52_HTTP11_SINGLE_CONNECTION_V1' -or $Policy.MaxRedirects -ne 0 -or $Policy.MaxRetries -ne 0 -or $Policy.MaxInFlight -ne 1){throw 'P52B_POLICY_PROFILE_INVALID'}
    if($Policy.MaxPhysicalAttempts -lt 0 -or $Policy.MaxPhysicalAttempts -gt 20 -or $Policy.RequestTimeoutMilliseconds -lt 1 -or $Policy.RequestTimeoutMilliseconds -gt 30000 -or $Policy.MaxResponseBodyBytes -lt 1 -or $Policy.MaxResponseBodyBytes -gt 33554432 -or $Policy.MaxResponseHeaderBytes -lt 1024 -or $Policy.MaxResponseHeaderBytes -gt 65536 -or $Policy.MaxResponseHeaderBytes % 1024 -ne 0){throw 'P52B_POLICY_BOUNDS_INVALID'}
    if($Policy.AllowedHttpsHosts -isnot [array] -or $Policy.AllowedHttpsHosts.Count -lt 1 -or $Policy.AllowedHttpsHosts.Count -gt 20){throw 'P52B_POLICY_HOSTS_INVALID'}
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($hostName in $Policy.AllowedHttpsHosts){if($hostName -isnot [string] -or $hostName -cnotmatch '^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{1,62}$' -or $hostName.EndsWith('.localhost') -or $hostName.EndsWith('.local') -or -not $seen.Add($hostName)){throw 'P52B_POLICY_HOST_INVALID'}}
    if(($Policy.AllowedHttpsHosts -join '|') -cne (@($Policy.AllowedHttpsHosts | Sort-Object -CaseSensitive) -join '|')){throw 'P52B_POLICY_HOST_ORDER_INVALID'}
}
function Copy-InternalPhase5NetworkPolicy {
    param($Policy)
    Assert-Phase5BenefitNetworkPolicy $Policy
    # Pure defensive value copy; no transport or qualification in this path.
    return (ConvertTo-HistoryCanonicalJson $Policy | ConvertFrom-Json)
}
function Get-Phase5NetworkPolicyFingerprint {param($Policy);Assert-Phase5BenefitNetworkPolicy $Policy;Get-HistorySha256 -Text (ConvertTo-HistoryCanonicalJson $Policy)}
function Assert-InternalPhase5NetworkUrl {
    param($Policy,[string]$Url)
    Assert-Phase5BenefitNetworkPolicy $Policy
    if([string]::IsNullOrWhiteSpace($Url) -or $Url -match '[\s\\#]' -or $Url -match '(?i)%(?:0[0-9a-f]|1[0-9a-f]|20|2e|2f|5c)' -or $Url -match '(?:^|/)\.{1,2}(?:/|$)'){throw 'P52B_UNSAFE_URL'}
    $uri=$null
    if(-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -cne 'https' -or $uri.Port -ne 443 -or $uri.UserInfo -or $uri.HostNameType -ne [UriHostNameType]::Dns -or $uri.Host.EndsWith('.') -or $uri.DnsSafeHost -cne $uri.IdnHost -or $Policy.AllowedHttpsHosts -cnotcontains $uri.Host){throw 'P52B_DESTINATION_DENIED'}
    $authority=($Url -split '/',4)[2]
    if($authority -cne $uri.Host -and $authority -cne ($uri.Host+':443')){throw 'P52B_AUTHORITY_REPRESENTATION_DENIED'}
}
function Initialize-InternalPhase5NetworkTypes {
    if('Milimap.P52.NetworkBoundary' -as [type]){return}
    Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Text;
namespace Milimap.P52 {
 public sealed class Accounting {
  private readonly object gate=new object(); private readonly long limit; private long active, next; private bool dispatched;
  public long ReservationsConsumed {get;private set;} public long AttemptedCount {get;private set;}
  public long DeniedCount {get;private set;} public long RespondedCount {get;private set;}
  public long UnknownOutcomeCount {get;private set;} public string FirstStopReason {get;private set;}
  public Accounting(long maximum) {if(maximum<0 || maximum>20)throw new ArgumentException("BUDGET_INVALID");limit=maximum;}
  public void Stop(string reason){lock(gate){if(FirstStopReason==null)FirstStopReason=reason;}}
  public bool CanStart(){lock(gate){if(FirstStopReason!=null)return false;if(ReservationsConsumed>=limit){Stop("BUDGET_EXHAUSTED");return false;}return true;}}
  public long Reserve(){lock(gate){if(FirstStopReason!=null){DeniedCount++;throw new InvalidOperationException(FirstStopReason);}if(active!=0){Stop("CONCURRENT_ADMISSION");DeniedCount++;throw new InvalidOperationException(FirstStopReason);}if(ReservationsConsumed>=limit){Stop("BUDGET_EXHAUSTED");DeniedCount++;throw new InvalidOperationException(FirstStopReason);}ReservationsConsumed++;active=++next;dispatched=false;return active;}}
  public void Dispatch(long token){lock(gate){if(active!=token || FirstStopReason!=null || dispatched)throw new InvalidOperationException("DISPATCH_DENIED");dispatched=true;AttemptedCount++;}}
  public void Response(long token){lock(gate){if(active!=token)throw new InvalidOperationException("TOKEN_MISMATCH");RespondedCount++;}}
  public void Finish(long token,bool unknown){lock(gate){if(active!=token)throw new InvalidOperationException("TOKEN_MISMATCH");if(unknown && dispatched)UnknownOutcomeCount++;active=0;}}
 }
 public sealed class ResponseData {public int StatusCode;public string ContentType;public string Text;public byte[] Bytes;}
 public static class NetworkBoundary {
  public static bool IsPublicAddress(IPAddress ip){
   if(ip.IsIPv4MappedToIPv6)return IsPublicAddress(ip.MapToIPv4());
   byte[] b=ip.GetAddressBytes();
   if(b.Length==4){return !(b[0]==0 || b[0]==10 || b[0]==127 || b[0]>=224 || (b[0]==100 && b[1]>=64 && b[1]<=127) || (b[0]==169 && b[1]==254) || (b[0]==172 && b[1]>=16 && b[1]<=31) || (b[0]==192 && (b[1]==0 || b[1]==168)) || (b[0]==198 && (b[1]==18 || b[1]==19 || b[1]==51)) || (b[0]==203 && b[1]==0 && b[2]==113));}
   // Only global unicast, excluding documentation, transition and special-use blocks.
   return b.Length==16 && (b[0]&0xe0)==0x20 && !(b[0]==0x20 && b[1]==0x01 && b[2]<0x20) && !(b[0]==0x20 && b[1]==0x01 && b[2]==0x0d && b[3]==0xb8) && !(b[0]==0x20 && b[1]==0x02);
  }
  private static SocketsHttpHandler CreateHandler(IPAddress[] addresses,int timeoutMs,int headerBytes,Accounting accounting){
   int connections=0;
   var handler=new SocketsHttpHandler {AllowAutoRedirect=false,AutomaticDecompression=DecompressionMethods.None,UseProxy=false,UseCookies=false,Credentials=null,PreAuthenticate=false,MaxConnectionsPerServer=1,ConnectTimeout=TimeSpan.FromMilliseconds(timeoutMs),MaxResponseHeadersLength=headerBytes/1024,PooledConnectionLifetime=TimeSpan.Zero};
   handler.SslOptions.CertificateChainPolicy=new System.Security.Cryptography.X509Certificates.X509ChainPolicy {
    DisableCertificateDownloads=true,
    RevocationMode=System.Security.Cryptography.X509Certificates.X509RevocationMode.NoCheck,
    VerificationFlags=System.Security.Cryptography.X509Certificates.X509VerificationFlags.NoFlag
   };
   handler.SslOptions.CertificateChainPolicy.ApplicationPolicy.Add(new System.Security.Cryptography.Oid("1.3.6.1.5.5.7.3.1"));
   handler.ConnectCallback=async (context,cancellation)=>{
    if(Interlocked.Increment(ref connections)!=1){accounting.Stop("TRANSPORT_RECONNECT_BLOCKED");throw new InvalidOperationException("TRANSPORT_RECONNECT_BLOCKED");}
    var socket=new Socket(addresses[0].AddressFamily,SocketType.Stream,ProtocolType.Tcp);
    try{await socket.ConnectAsync(new IPEndPoint(addresses[0],context.DnsEndPoint.Port),cancellation);return new NetworkStream(socket,true);}catch{socket.Dispose();throw;}
   };
   return handler;
  }
  private static ResponseData Exchange(Uri uri,SocketsHttpHandler handler,int timeoutMs,long bodyLimit,Accounting accounting,long token,CancellationToken cancellation){
   try{
   using(handler)using(var client=new HttpClient(handler)){client.Timeout=Timeout.InfiniteTimeSpan;
    using(var request=new HttpRequestMessage(HttpMethod.Get,uri)){
     request.Version=HttpVersion.Version11;request.VersionPolicy=HttpVersionPolicy.RequestVersionExact;request.Headers.ConnectionClose=true;request.Headers.TryAddWithoutValidation("Accept-Encoding","identity");
     cancellation.ThrowIfCancellationRequested();accounting.Dispatch(token);
     using(var response=client.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,cancellation).GetAwaiter().GetResult()){
      accounting.Response(token);
      if((int)response.StatusCode>=300 && (int)response.StatusCode<=399){accounting.Stop("REDIRECT_DENIED");throw new InvalidOperationException("REDIRECT_DENIED");}
      if(response.Content.Headers.ContentEncoding.Count!=0){accounting.Stop("CONTENT_ENCODING_DENIED");throw new InvalidOperationException("CONTENT_ENCODING_DENIED");}
      if(response.Content.Headers.ContentLength>bodyLimit){accounting.Stop("RESPONSE_SIZE_EXCEEDED");throw new InvalidOperationException("RESPONSE_SIZE_EXCEEDED");}
      using(var stream=response.Content.ReadAsStreamAsync(cancellation).GetAwaiter().GetResult())using(var buffer=new MemoryStream()){
       byte[] chunk=new byte[8192];int count;
       while((count=stream.ReadAsync(chunk,0,chunk.Length,cancellation).GetAwaiter().GetResult())!=0){if(buffer.Length+count>bodyLimit){accounting.Stop("RESPONSE_SIZE_EXCEEDED");throw new InvalidOperationException("RESPONSE_SIZE_EXCEEDED");}buffer.Write(chunk,0,count);}
       byte[] bytes=buffer.ToArray();Encoding encoding=Encoding.UTF8;
       string charset=response.Content.Headers.ContentType?.CharSet;
       if(!String.IsNullOrEmpty(charset))encoding=Encoding.GetEncoding(charset.Trim('"'));
       return new ResponseData {StatusCode=(int)response.StatusCode,ContentType=response.Content.Headers.ContentType?.ToString() ?? "",Bytes=bytes,Text=encoding.GetString(bytes)};
      }
     }
    }
   }
   }catch(HttpRequestException e) when(e.HttpRequestError==HttpRequestError.ConfigurationLimitExceeded){accounting.Stop("RESPONSE_HEADERS_EXCEEDED");throw;}
   catch(HttpIOException e) when(e.HttpRequestError==HttpRequestError.ConfigurationLimitExceeded){accounting.Stop("RESPONSE_HEADERS_EXCEEDED");throw;}
  }
  public static ResponseData Send(Uri uri,int timeoutMs,long bodyLimit,int headerBytes,Accounting accounting,long token){
   // No caller supplied resolver, handler, certificate callback, proxy or invoker.
   using(var cancel=new CancellationTokenSource(timeoutMs)){
    var addresses=Dns.GetHostAddressesAsync(uri.DnsSafeHost,cancel.Token).GetAwaiter().GetResult();
    if(addresses.Length==0)throw new InvalidOperationException("DNS_EMPTY");
    foreach(var ip in addresses)if(!IsPublicAddress(ip)){accounting.Stop("UNSAFE_RESOLVED_ADDRESS");throw new InvalidOperationException("UNSAFE_RESOLVED_ADDRESS");}
    cancel.Token.ThrowIfCancellationRequested();
    return Exchange(uri,CreateHandler(addresses,timeoutMs,headerBytes,accounting),timeoutMs,bodyLimit,accounting,token,cancel.Token);
   }
  }
 }
}
"@
}
function New-InternalPhase5NetworkState {
    param($Policy,[string]$BatchId,[string[]]$SourceUrls)
    $copy=Copy-InternalPhase5NetworkPolicy $Policy
    Initialize-InternalPhase5NetworkTypes
    $urls=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $mma=$false
    foreach($url in $SourceUrls){
        if($url -ceq 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'){$mma=$true;Assert-InternalPhase5NetworkUrl $copy 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList'}
        else{Assert-InternalPhase5NetworkUrl $copy $url;[void]$urls.Add($url)}
    }
    [pscustomobject]@{Policy=$copy;BatchId=$BatchId;Urls=$urls;Mma=$mma;Accounting=[Milimap.P52.Accounting]::new($copy.MaxPhysicalAttempts)}
}
function Assert-InternalPhase5NetworkDestination {
    param($State,[string]$Url)
    Assert-InternalPhase5NetworkUrl $State.Policy $Url
    if($State.Urls.Contains($Url)){return}
    if($State.Mma -and ($Url -ceq 'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList' -or $Url -cmatch '^https://open\.mma\.go\.kr/caisGGGS/mmanrsrSangSeAjaxJsonCall\.json\?udgigwan_cd=[0-9]+&callback=MmaBenefitDetail$')){return}
    throw 'P52B_UNFROZEN_DESTINATION'
}
function Invoke-InternalPhase5NetworkDispatch {
    param($State,[Uri]$Uri,[long]$Token)
    $p=$State.Policy
    [Milimap.P52.NetworkBoundary]::Send($Uri,$p.RequestTimeoutMilliseconds,$p.MaxResponseBodyBytes,$p.MaxResponseHeaderBytes,$State.Accounting,$Token)
}
function Invoke-InternalPhase5NetworkRequest {
    param($State,[Uri]$Uri)
    try{Assert-InternalPhase5NetworkDestination $State ([string]$Uri)}catch{$State.Accounting.Stop('DESTINATION_DENIED');throw}
    $token=$State.Accounting.Reserve();$responded=$State.Accounting.RespondedCount
    try{return Invoke-InternalPhase5NetworkDispatch -State $State -Uri $Uri -Token $token}
    finally{$State.Accounting.Finish($token,($State.Accounting.RespondedCount -eq $responded))}
}
function Get-InternalPhase5NetworkMetrics {
    param($State,[string]$Qualification='QUALIFIED_EXACT_PROFILE')
    $a=$State.Accounting
    [pscustomobject][ordered]@{ReservationsConsumed=$a.ReservationsConsumed;AttemptedCount=$a.AttemptedCount;DeniedCount=$a.DeniedCount;RespondedCount=$a.RespondedCount;UnknownOutcomeCount=$a.UnknownOutcomeCount;PhysicalRequestCount=$(if($a.AttemptedCount -eq 0){0}else{$null});FirstStopReason=$a.FirstStopReason;TransportQualification=$Qualification}
}
function Assert-InternalPhase5NetworkSources {
    param($Policy,[string[]]$SourceUrls)
    foreach($url in $SourceUrls){
        $target=if($url -ceq 'https://www.mma.go.kr/about/udgg/list.do?mc=mma0003357'){'https://open.mma.go.kr/caisGGGS/mmanrsrListAjaxJsonCallNew.json?jbc_cd=&udggeopjong_gbcd=&callback=MmaBenefitList'}else{$url}
        Assert-InternalPhase5NetworkUrl $Policy $target
    }
}
function Assert-InternalPhase5NetworkIdentity {
    param($Identity)
    if($null -eq $Identity -or $Identity -isnot [pscustomobject] -or (@($Identity.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join '|') -cne 'Architecture|Framework|OS|Profile'){throw 'P52B_IDENTITY_INVALID'}
    foreach($field in @('Architecture','Framework','OS','Profile')){if($Identity.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Identity.$field) -or $Identity.$field.Length -gt 256){throw 'P52B_IDENTITY_INVALID'}}
    if($Identity.Profile -cne 'P52_HTTP11_SINGLE_CONNECTION_V1'){throw 'P52B_PROFILE_INVALID'}
}
