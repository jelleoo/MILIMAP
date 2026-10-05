using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using UglyToad.PdfPig;
using UglyToad.PdfPig.Core;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
Console.OutputEncoding = new UTF8Encoding(false);
var pages = new List<object>();
var diagnostics = new List<string>();
string status = "FAILED", hash = "";
bool? encrypted = null;
int exit = 1;
try
{
    if (args.Length == 0 || !File.Exists(args[0])) { diagnostics.Add("FILE_NOT_FOUND"); }
    else
    {
        var bytes = File.ReadAllBytes(args[0]);
        hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        using var pdf = PdfDocument.Open(bytes, new ParsingOptions { UseLenientParsing = false, SkipMissingFonts = false, ClipPaths = true, MaxStackDepth = 128 });
        encrypted = pdf.IsEncrypted;
        if (pdf.IsEncrypted) { status = "UNSUPPORTED"; diagnostics.Add("ENCRYPTED"); }
        else
        {
            foreach (var page in pdf.GetPages())
            {
                var letters = page.Letters.Select((l, i) => new { Index = i, Text = l.Value, BaselineY = l.StartBaseLine.Y, X0 = l.BoundingBox.Left, Y0 = l.BoundingBox.Bottom, X1 = l.BoundingBox.Right, Y1 = l.BoundingBox.Top }).ToArray();
                var paths = page.Paths.Select((p, i) => new { Index = i, p.IsStroked, p.IsFilled, Subpaths = p.Select(s => s.Commands.Select(c => new { Kind = c.GetType().Name, Bounds = Rect(c.GetBoundingRectangle()), Points = Points(c) }).ToArray()).ToArray() }).ToArray();
                var text = string.Concat(page.Letters.Select(l => l.Value));
                pages.Add(new { PageNumber = page.Number, RotationDegrees = page.Rotation.Value, page.Width, page.Height, LetterCount = letters.Length, ImageCount = page.NumberOfImages, PathCount = paths.Length, DecodedTextSha256 = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant(), ContainsExpectedText = args.Length > 1 && text.Contains(args[1], StringComparison.Ordinal), Letters = letters, Paths = paths });
            }
            status = "COMPLETE"; exit = 0;
        }
    }
}
catch (Exception ex)
{
    diagnostics.Add(ex.GetType().FullName ?? "ERROR");
    if (ex.GetType().FullName?.Contains("Encrypted", StringComparison.OrdinalIgnoreCase) == true) { encrypted = true; status = "UNSUPPORTED"; diagnostics.Add("ENCRYPTED"); }
}
var output = new { ProbeSchemaVersion = 1, PdfPigVersion = "0.1.16", Runtime = RuntimeInformation.FrameworkDescription, Os = RuntimeInformation.OSDescription, FileSha256 = hash, OpenStatus = status, Encrypted = encrypted, Pages = pages, Diagnostics = diagnostics };
var json = JsonSerializer.Serialize(output, new JsonSerializerOptions { WriteIndented = true });
File.WriteAllText("evaluation.json", json, new UTF8Encoding(false));
Console.WriteLine(json);
return exit;

static object? Rect(PdfRectangle? r) => r is null ? null : new { X0 = r.Value.Left, Y0 = r.Value.Bottom, X1 = r.Value.Right, Y1 = r.Value.Top };
static object Points(PdfSubpath.IPathCommand c) => c.GetType().GetProperties().Where(p => p.PropertyType == typeof(PdfPoint)).OrderBy(p => p.Name, StringComparer.Ordinal).ToDictionary(p => p.Name, p => { var point = (PdfPoint)p.GetValue(c)!; return new { point.X, point.Y }; });
