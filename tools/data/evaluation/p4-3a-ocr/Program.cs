using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using UglyToad.PdfPig;
using UglyToad.PdfPig.Graphics.Colors;
using UglyToad.PdfPig.Tokens;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
Console.OutputEncoding = new UTF8Encoding(false);
if (args.Length > 0 && args[0] == "grid") return PixelGrid.Execute(args);
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

static class PixelGrid
{
    // Evaluation config only. Full continuous ruled borders, no OCR/whitespace input.
    public static int Execute(string[] args)
    {
        try
        {
            if(args.Length != 9 || args[1] != "--input" || args[3] != "--metadata" || args[5] != "--page" || args[7] != "--image") throw new InvalidDataException("GRID_ARGUMENTS");
            using var metadata=JsonDocument.Parse(File.ReadAllText(args[4]));
            var root=metadata.RootElement;
            if(root.GetProperty("SchemaVersion").GetInt32()!=1 || root.GetProperty("ProbeId").GetString()!="MILIMAP_P4_3A_OCR_EVAL" || root.GetProperty("Status").GetString()!="ELIGIBLE") throw new InvalidDataException("GRID_METADATA");
            var matches=root.GetProperty("Images").EnumerateArray().Where(x=>x.GetProperty("PageNumber").GetInt32()==int.Parse(args[6]) && x.GetProperty("ImageNumber").GetInt32()==int.Parse(args[8])).ToArray();
            if(matches.Length!=1 || new FileInfo(args[2]).Length>32000032) throw new InvalidDataException("GRID_IMAGE_IDENTITY_OR_LIMIT");
            var bytes=File.ReadAllBytes(args[2]);
            if(Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant()!=matches[0].GetProperty("PixelSha256").GetString()) throw new InvalidDataException("GRID_PIXEL_HASH");
            int width=matches[0].GetProperty("Width").GetInt32(),height=matches[0].GetProperty("Height").GetInt32(),components=matches[0].GetProperty("Components").GetInt32();
            if(width<=0||height<=0||width>4096||height>4096||(long)width*height>8000000||components is not (1 or 3)) throw new InvalidDataException("GRID_PIXEL_LIMIT");
            var header=Encoding.ASCII.GetBytes($"{(components==1?"P5":"P6")}\n{width} {height}\n255\n");
            if(bytes.Length!=header.Length+width*height*components || !bytes.AsSpan(0,header.Length).SequenceEqual(header)) throw new InvalidDataException("GRID_PNM_INVALID");
            bool Dark(int x,int y){int p=header.Length+(y*width+x)*components;return components==1?bytes[p]<=32:Math.Max(bytes[p],Math.Max(bytes[p+1],bytes[p+2]))<=32;}
            var horizontal=new List<int>();var vertical=new List<int>();
            for(int y=0;y<height;y++){int run=0,longest=0;for(int x=0;x<width;x++){run=Dark(x,y)?run+1:0;longest=Math.Max(longest,run);}if(longest>=800)horizontal.Add(y);}
            for(int x=0;x<width;x++){int run=0,longest=0;for(int y=0;y<height;y++){run=Dark(x,y)?run+1:0;longest=Math.Max(longest,run);}if(longest>=400)vertical.Add(x);}
            static int[] Collapse(List<int> values){var result=new List<int>();for(int i=0;i<values.Count;){int first=values[i],last=first;while(++i<values.Count&&values[i]==last+1)last=values[i];if(last-first>4)throw new UnsupportedImage("GRID_LINE_WIDTH");result.Add((first+last)/2);}return result.ToArray();}
            var xs=Collapse(vertical);var ys=Collapse(horizontal);
            if(xs.Length<2||ys.Length<2||xs.Length>32||ys.Length>32||(xs.Length-1)*(ys.Length-1)>256)throw new UnsupportedImage("GRID_TOPOLOGY");
            foreach(var x in xs)for(int y=ys[0];y<=ys[^1];y++)if(!Dark(x,y))throw new UnsupportedImage("GRID_BROKEN_OR_MERGED");
            foreach(var y in ys)for(int x=xs[0];x<=xs[^1];x++)if(!Dark(x,y))throw new UnsupportedImage("GRID_BROKEN_OR_MERGED");
            var cells=new List<object>();int id=0;
            for(int row=0;row<ys.Length-1;row++)for(int col=0;col<xs.Length-1;col++){
                if(xs[col+1]-xs[col]<10||ys[row+1]-ys[row]<10)throw new UnsupportedImage("GRID_CELL_SIZE");
                cells.Add(new{Id=++id,Row=row+1,Column=col+1,X0=xs[col]+3,Y0=ys[row]+3,X1=xs[col+1]-3,Y1=ys[row+1]-3});
            }
            Console.WriteLine(JsonSerializer.Serialize(new{Status="COMPLETE",Config="EVAL_PIXEL_GRID_V1_BLACK32_H800_V400_FULL_BORDER_INSET3",Cells=cells,GridBuildCount=1,PixelSha256=matches[0].GetProperty("PixelSha256").GetString()}));return 0;
        }
        catch(Exception ex){Console.WriteLine(JsonSerializer.Serialize(new{Status=ex is UnsupportedImage?"UNSUPPORTED":"FAILED",Cells=Array.Empty<object>(),Diagnostics=new[]{ex is InvalidDataException or UnsupportedImage?ex.Message:"GRID_FAILED"}}));return 1;}
    }
}
