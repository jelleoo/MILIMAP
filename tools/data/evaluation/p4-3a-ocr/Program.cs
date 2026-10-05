using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using UglyToad.PdfPig;
using UglyToad.PdfPig.Graphics.Colors;
using UglyToad.PdfPig.Tokens;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
Console.OutputEncoding = new UTF8Encoding(false);
string status = "FAILED", hash = "";
int opens = 0;
var pages = new List<object>();
var diagnostics = new List<string>();
var images = new List<object>();
var createdArtifacts = new List<string>();
int decoded = 0, pageReads = 0;
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
    var parsedPages = pdf.GetPages().ToArray();
    int nativeLetters = 0;
    foreach (var page in parsedPages)
    {
        pageReads++;
        nativeLetters += page.Letters.Count;
        if (nativeLetters > 100000) throw new InvalidDataException("PDF_LETTER_LIMIT");
        pages.Add(new { PageNumber = page.Number, page.Width, page.Height, Rotation = page.Rotation.Value, NativeLetterCount = page.Letters.Count, ImageCount = page.NumberOfImages });
    }
    if (nativeLetters > 0) status = "NATIVE_TEXT";
    else
    {
        // The pages remain in the same PdfDocument. Never reopen for image handoff.
        var selected = new List<(UglyToad.PdfPig.Content.Page Page, UglyToad.PdfPig.Content.IPdfImage Image)>();
        foreach (var page in parsedPages)
        {
            if (page.NumberOfImages != 1 || page.Rotation.Value != 0) throw new UnsupportedImage("IMAGE_COUNT_OR_ROTATION");
            var candidates = page.GetImages().ToArray();
            if (candidates.Length != 1) throw new UnsupportedImage("IMAGE_COUNT");
            var image = candidates[0];
            if (image.BitsPerComponent != 8 || image.ColorSpaceDetails is null || image.ColorSpaceDetails.Type is not (ColorSpace.DeviceGray or ColorSpace.DeviceRGB)) throw new UnsupportedImage("PIXEL_FORMAT");
            if (image.IsImageMask || image.MaskImage != null || image.ImageDictionary.Data.ContainsKey(NameToken.Create("SMask"))) throw new UnsupportedImage("IMAGE_MASK");
            if (image.Decode.Count != 0 && !image.Decode.SequenceEqual(image.ColorSpaceDetails.Type == ColorSpace.DeviceGray ? new double[]{0,1} : new double[]{0,1,0,1,0,1})) throw new UnsupportedImage("CUSTOM_DECODE");
            // Fixed zero coverage tolerance for generated axis-aligned controls; no adaptive widening.
            var b = image.BoundingBox;
            if (b.BottomLeft.X != 0 || b.BottomLeft.Y != 0 || b.BottomRight.X != page.Width || b.BottomRight.Y != 0 || b.TopLeft.X != 0 || b.TopLeft.Y != page.Height || b.TopRight.X != page.Width || b.TopRight.Y != page.Height) throw new UnsupportedImage("IMAGE_PLACEMENT");
            if (image.WidthInSamples <= 0 || image.HeightInSamples <= 0 || image.WidthInSamples > 4096 || image.HeightInSamples > 4096 || (long)image.WidthInSamples * image.HeightInSamples > 8000000) throw new InvalidDataException("IMAGE_PIXEL_LIMIT");
            selected.Add((page,image));
        }
        long total = 0;
        foreach (var (page,image) in selected)
        {
            var components = image.ColorSpaceDetails!.Type == ColorSpace.DeviceGray ? 1 : 3;
            var b = image.BoundingBox;
            var filter = image.ImageDictionary.Data.TryGetValue(NameToken.Filter, out var f) ? f : null;
            if (filter != null && filter is not NameToken { Data: "FlateDecode" }) throw new UnsupportedImage("IMAGE_FILTER");
            if (!image.TryGetBytesAsMemory(out var pixels)) throw new InvalidDataException("IMAGE_DECODE_FAILED");
            decoded++;
            var size = checked(image.WidthInSamples * image.HeightInSamples * components);
            total += size;
            if (pixels.Length != size || total > 32000000) throw new InvalidDataException("IMAGE_DECODE_LENGTH_OR_LIMIT");
            Directory.CreateDirectory(args[4]);
            var path = Path.GetFullPath(Path.Combine(args[4],$"page-{page.Number}-image-1.{(components == 1 ? "pgm" : "ppm")}"));
            createdArtifacts.Add(path);
            using (var stream = File.Create(path))
            {
                stream.Write(Encoding.ASCII.GetBytes($"{(components == 1 ? "P5" : "P6")}\n{image.WidthInSamples} {image.HeightInSamples}\n255\n"));
                stream.Write(pixels.Span);
            }
            images.Add(new { PageNumber = page.Number, ImageNumber = 1, Width = image.WidthInSamples, Height = image.HeightInSamples, Components = components, PdfBounds = new {X0=b.Left,Y0=b.Bottom,X1=b.Right,Y1=b.Top}, ArtifactPath = path, PixelSha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).ToLowerInvariant() });
        }
        status = "ELIGIBLE";
    }
}
catch (Exception ex) { pages.Clear(); images.Clear(); foreach(var path in createdArtifacts) File.Delete(path); status = ex is UnsupportedImage ? "UNSUPPORTED" : "FAILED"; diagnostics.Add(ex is InvalidDataException or UnsupportedImage ? ex.Message : "PDF_PARSE_FAILED"); }
Console.WriteLine(JsonSerializer.Serialize(new { SchemaVersion = 1, ProbeId = "MILIMAP_P4_3A_OCR_EVAL", PdfPigVersion = "0.1.16", PdfSha256 = hash, OpenCount = opens, PageReadCount = pageReads, ImageDecodeCount = decoded, Status = status, Pages = pages, Images = images, Diagnostics = diagnostics }));
return status is "FAILED" or "UNSUPPORTED" ? 1 : 0;

sealed class UnsupportedImage(string code) : Exception(code);
