# Isolated native PDF helper

Approved runtime dependency: **PdfPig 0.1.16 exact** (`[0.1.16]`), Apache-2.0,
[upstream](https://github.com/UglyToad/PdfPig). The net8.0 lock graph has no
transitive NuGet packages. PdfPig types remain in the child process; stdout is
MILIMAP-owned primitive schema-1 JSON, never a parser object graph.

Requires .NET 8 SDK to build and .NET 8 runtime to execute (a newer SDK may target net8.0).

```powershell
dotnet restore tools/data/pdf-native/Milimap.PdfNative.csproj --locked-mode
dotnet build tools/data/pdf-native/Milimap.PdfNative.csproj -c Release --no-restore
dotnet tools/data/pdf-native/bin/Release/net8.0/Milimap.PdfNative.dll inspect --input control.pdf
```

Only `OpenStatus=COMPLETE` is parser success, not semantic table evidence.
Encrypted and malformed sources expose no pages. Native geometry must pass the
separate bounded ruled-grid policy before becoming PDF_ROW evidence.
