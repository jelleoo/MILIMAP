using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using UglyToad.PdfPig;
using UglyToad.PdfPig.Core;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
Console.OutputEncoding = new UTF8Encoding(false);
var pages = new List<object>();
var diagnostics = new List<object>();
string status = "FAILED", hash = "";
bool encrypted = false;
int exit = 1;
try
{
    if (args.Length != 3 || args[0] != "inspect" || args[1] != "--input")
        diagnostics.Add(new { Code = "INVALID_ARGUMENTS" });
    else if (!File.Exists(args[2]))
        diagnostics.Add(new { Code = "FILE_NOT_FOUND" });
    else
    {
        if (new FileInfo(args[2]).Length > 10 * 1024 * 1024) throw new PdfQuotaException("PDF_SOURCE_LIMIT");
        var bytes = File.ReadAllBytes(args[2]);
        hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        using var pdf = PdfDocument.Open(bytes, new ParsingOptions
        {
            UseLenientParsing = false, SkipMissingFonts = false,
            ClipPaths = true, MaxStackDepth = 128
        });
        encrypted = pdf.IsEncrypted;
        if (encrypted) { status = "UNSUPPORTED"; diagnostics.Add(new { Code = "ENCRYPTED_PDF" }); }
        else
        {
            if (pdf.NumberOfPages > 32) throw new PdfQuotaException("PDF_PAGE_LIMIT");
            int totalLetters = 0, totalCommands = 0;
            foreach (var page in pdf.GetPages())
            {
                totalLetters += page.Letters.Count;
                if (page.Letters.Count > 20000 || totalLetters > 100000) throw new PdfQuotaException("PDF_LETTER_LIMIT");
                if (page.Paths.Count > 2048) throw new PdfQuotaException("PDF_PATH_LIMIT");
                totalCommands += page.Paths.Sum(p => p.Sum(s => s.Commands.Count));
                if (totalCommands > 16384) throw new PdfQuotaException("PDF_PATH_LIMIT");
                var letters = page.Letters.Select((l, i) => new
                {
                    Index = i, Text = l.Value,
                    BaselineX = l.StartBaseLine.X, BaselineY = l.StartBaseLine.Y,
                    X0 = l.BoundingBox.Left, Y0 = l.BoundingBox.Bottom,
                    X1 = l.BoundingBox.Right, Y1 = l.BoundingBox.Top
                }).ToArray();
                var paths = page.Paths.Select((p, i) => new
                {
                    Index = i, p.IsStroked, p.IsFilled,
                    Subpaths = p.Select(s => s.Commands.Select(c => new
                    {
                        Kind = c.GetType().Name,
                        Bounds = Rectangle(c.GetBoundingRectangle()), Points = Points(c)
                    }).ToArray()).ToArray()
                }).ToArray();
                pages.Add(new
                {
                    PageNumber = page.Number, RotationDegrees = page.Rotation.Value,
                    page.Width, page.Height, Letters = letters, Paths = paths,
                    ImageCount = page.NumberOfImages
                });
            }
            status = "COMPLETE"; exit = 0;
        }
    }
}
catch (Exception ex)
{
    // A later-page failure invalidates the whole projection. No partial page evidence.
    pages.Clear();
    encrypted = ex.GetType().Name.Contains("Encrypted", StringComparison.OrdinalIgnoreCase);
    status = encrypted ? "UNSUPPORTED" : "FAILED";
    diagnostics.Add(new { Code = ex is PdfQuotaException quota ? quota.Code : encrypted ? "ENCRYPTED_PDF" : "PDF_PARSE_FAILED" });
}
var output = JsonSerializer.Serialize(new
{
    SchemaVersion = 1, ParserId = "PDFPIG", ParserVersion = "0.1.16",
    FileSha256 = hash, OpenStatus = status, Encrypted = encrypted,
    Pages = pages, Diagnostics = diagnostics
});
if (Encoding.UTF8.GetByteCount(output) > 16777216)
{
    output = JsonSerializer.Serialize(new { SchemaVersion = 1, ParserId = "PDFPIG", ParserVersion = "0.1.16",
        FileSha256 = hash, OpenStatus = "FAILED", Encrypted = false, Pages = Array.Empty<object>(),
        Diagnostics = new[] { new { Code = "PDF_OUTPUT_LIMIT" } } });
    exit = 1;
}
Console.WriteLine(output);
return exit;

static object? Rectangle(PdfRectangle? r) => r is null ? null : new
{
    X0 = r.Value.Left, Y0 = r.Value.Bottom, X1 = r.Value.Right, Y1 = r.Value.Top
};
static object Points(PdfSubpath.IPathCommand c) => c.GetType().GetProperties()
    .Where(p => p.PropertyType == typeof(PdfPoint)).OrderBy(p => p.Name, StringComparer.Ordinal)
    .ToDictionary(p => p.Name, p =>
    {
        var point = (PdfPoint)p.GetValue(c)!;
        return new { point.X, point.Y };
    });

sealed class PdfQuotaException(string code) : Exception(code)
{
    public string Code { get; } = code;
}
