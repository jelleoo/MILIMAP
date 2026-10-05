using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using UglyToad.PdfPig;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
Console.OutputEncoding = new UTF8Encoding(false);
string status = "FAILED", hash = "";
int opens = 0;
var pages = new List<object>();
var diagnostics = new List<string>();
try
{
    if (args.Length != 5 || args[0] != "inspect" || args[1] != "--input" || args[3] != "--artifact-dir") throw new InvalidDataException("ARGUMENTS_INVALID");
    if (!File.Exists(args[2])) throw new InvalidDataException("PDF_MISSING");
    if (new FileInfo(args[2]).Length > 10485760) throw new InvalidDataException("PDF_BYTE_LIMIT");
    var bytes = File.ReadAllBytes(args[2]);
    hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    opens++;
    using var pdf = PdfDocument.Open(bytes, new ParsingOptions { UseLenientParsing = false, SkipMissingFonts = false, MaxStackDepth = 128 });
    if (pdf.IsEncrypted) throw new InvalidDataException("PDF_ENCRYPTED");
    if (pdf.NumberOfPages > 4) throw new InvalidDataException("PDF_PAGE_LIMIT");
    int nativeLetters = 0;
    foreach (var page in pdf.GetPages())
    {
        nativeLetters += page.Letters.Count;
        if (nativeLetters > 100000) throw new InvalidDataException("PDF_LETTER_LIMIT");
        pages.Add(new { PageNumber = page.Number, page.Width, page.Height, Rotation = page.Rotation.Value, NativeLetterCount = page.Letters.Count, ImageCount = page.NumberOfImages });
    }
    status = nativeLetters > 0 ? "NATIVE_TEXT" : "IMAGE_INSPECTION_PENDING";
}
catch (Exception ex) { pages.Clear(); diagnostics.Add(ex is InvalidDataException ? ex.Message : "PDF_PARSE_FAILED"); }
Console.WriteLine(JsonSerializer.Serialize(new { SchemaVersion = 1, ProbeId = "MILIMAP_P4_3A_OCR_EVAL", PdfPigVersion = "0.1.16", PdfSha256 = hash, OpenCount = opens, Status = status, Pages = pages, Diagnostics = diagnostics }));
return status == "FAILED" ? 1 : 0;
