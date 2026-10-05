"""A2-only fictional text degradation; historical fixtures are read-only.
Grid pixels are drawn last, at exact historical coordinates/strength.
No OCR output/expected strings are sourced from the SUT.
"""
import hashlib, json, pathlib, zlib, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pypdf import PdfReader

ROOT = pathlib.Path(__file__).parent
FONT = pathlib.Path('C:/Windows/Fonts/malgun.ttf')
ROWS = [['업체명','주소','전화번호','혜택'],
        ['가상 가람 식당','가상시 가람로 12','031-123-4567','시험 할인 10%'],
        ['가상 누리 식당','가상시 누리로 23','031-234-5678','시험 할인 20%\n방문 시 적용']]
XS = [50,400,950,1220,1550]; YS = [70,170,450,750]
MILD_RADIUS = 0.6  # Fixed before any mild OCR. No iterative authoring/tuning.

def make_image(mild=False):
    text = Image.new('L', (1600,900), 255)
    draw = ImageDraw.Draw(text)
    font = ImageFont.truetype(str(FONT),32)
    for r,row in enumerate(ROWS):
        for c,value in enumerate(row):
            draw.multiline_text((XS[c]+15,YS[r]+25),value,font=font,fill=0,spacing=10)
    # Fixed authoring degradation, not runtime preprocessing or OCR-guided tuning.
    image = text.filter(ImageFilter.GaussianBlur(MILD_RADIUS)) if mild else text.resize((400,225)).resize((1600,900)).filter(ImageFilter.GaussianBlur(2))
    draw = ImageDraw.Draw(image)
    for x in XS: draw.line((x,YS[0],x,YS[-1]),fill=0,width=3)
    for y in YS: draw.line((XS[0],y,XS[-1],y),fill=0,width=3)
    return image

def encode_pdf(image, mode):
    data = zlib.compress(image.convert(mode).tobytes(),9)
    color = 'DeviceGray' if mode == 'L' else 'DeviceRGB'
    content = b'q 800 0 0 450 0 0 cm /I Do Q\n'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Count 1 /Kids [5 0 R] >>',
        f'<< /Type /XObject /Subtype /Image /Width 1600 /Height 900 /BitsPerComponent 8 /ColorSpace /{color} /Filter /FlateDecode /Length {len(data)} >>\nstream\n'.encode()+data+b'\nendstream',
        f'<< /Length {len(content)} >>\nstream\n'.encode()+content+b'endstream',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 800 450] /Resources << /XObject << /I 3 0 R >> >> /Contents 4 0 R >>']
    result=bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n'); offsets=[0]
    for i,obj in enumerate(objects,1):
        offsets.append(len(result)); result+=f'{i} 0 obj\n'.encode()+obj+b'\nendobj\n'
    start=len(result); result+=f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
    for offset in offsets[1:]: result+=f'{offset:010} 00000 n \n'.encode()
    result+=f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode()
    return bytes(result)

def decoded_gray(path):
    page = PdfReader(path).pages[0]
    xobject = page['/Resources']['/XObject']['/I'].get_object()
    assert xobject['/Width'] == 1600 and xobject['/Height'] == 900 and xobject['/BitsPerComponent'] == 8
    assert xobject['/ColorSpace'] == '/DeviceGray'
    return xobject.get_data()

def check_mild_grid():
    clear = decoded_gray(ROOT.parent.parent/'p4-3a-ocr/fixtures/gray.pdf')
    mild = decoded_gray(ROOT/'mild-degraded-gray.pdf')
    mask = Image.new('L',(1600,900),0); draw=ImageDraw.Draw(mask)
    for x in XS: draw.line((x,YS[0],x,YS[-1]),fill=255,width=3)
    for y in YS: draw.line((XS[0],y,XS[-1],y),fill=255,width=3)
    selected=[i for i,value in enumerate(mask.tobytes()) if value]
    clear_grid=bytes(clear[i] for i in selected); mild_grid=bytes(mild[i] for i in selected)
    assert clear_grid == mild_grid and all(value == 0 for value in mild_grid), 'Grid pixels changed'
    assert clear != mild, 'Mild must change text pixels'
    return dict(gridPixelCount=len(selected),gridPixelsSha256=hashlib.sha256(mild_grid).hexdigest(),clearGridPixelsSha256=hashlib.sha256(clear_grid).hexdigest())

def check_fixtures():
    manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
    assert sorted(item['name'] for item in manifest['fixtures']) == ['degraded-gray','degraded-rgb','mild-degraded-gray'], 'Only one additional mild Gray control permitted'
    assert sorted(path.name for path in ROOT.glob('*.pdf')) == ['degraded-gray.pdf','degraded-rgb.pdf','mild-degraded-gray.pdf'], 'Unexpected fixture expansion'
    for item in manifest['fixtures']:
        assert hashlib.sha256((ROOT/(item['name']+'.pdf')).read_bytes()).hexdigest() == item['sha256'], 'Fixture hash changed'
    mild=next(item for item in manifest['fixtures'] if item['name']=='mild-degraded-gray')
    assert mild['degradation'] == dict(textOnly=True,operation='GaussianBlur',radius=0.6,resize=False), 'Mild parameters changed'
    assert mild['gridProof'] == check_mild_grid(), 'Grid proof does not match actual PDF pixels'
    print('Fixture integrity PASS: exactly one mild Gray, fixed radius0.6/no resize, exact clear-grid bytes')

if __name__ == '__main__':
    if sys.argv[1:] == ['--check']:
        check_fixtures(); sys.exit(0)
    if sys.argv[1:] == ['--mild-only']:
        # Preserve existing degraded bytes/parameters; add one fixed control only.
        manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
        assert len(manifest['fixtures']) == 2 and not (ROOT/'mild-degraded-gray.pdf').exists(), 'Mild was already authored; do not retune'
        image=make_image(mild=True); raw=encode_pdf(image,'L')
        (ROOT/'mild-degraded-gray.pdf').write_bytes(raw)
        pnm=b'P5\n1600 900\n255\n'+image.tobytes()
        manifest['fixtures'].append(dict(name='mild-degraded-gray',sha256=hashlib.sha256(raw).hexdigest(),pixelHash=hashlib.sha256(pnm).hexdigest(),expectedGrid='COMPLETE',purpose='single approved fictional mild confidence control',expectedRows=ROWS,license='CC0-1.0',degradation=dict(textOnly=True,operation='GaussianBlur',radius=0.6,resize=False),gridProof=check_mild_grid()))
        (ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        check_fixtures(); sys.exit(0)
    assert not sys.argv[1:] and not (ROOT/'manifest.json').exists(), 'Do not overwrite authored controls'
    image=make_image(); fixtures=[]
    for name,mode in [('degraded-gray','L'),('degraded-rgb','RGB')]:
        raw=encode_pdf(image,mode); (ROOT/(name+'.pdf')).write_bytes(raw)
        pnm=(b'P5\n' if mode=='L' else b'P6\n')+b'1600 900\n255\n'+image.convert(mode).tobytes()
        fixtures.append(dict(name=name,sha256=hashlib.sha256(raw).hexdigest(),pixelHash=hashlib.sha256(pnm).hexdigest(),expectedGrid='COMPLETE',purpose='fictional safe-grid text-only degradation',expectedRows=ROWS,license='CC0-1.0'))
    (ROOT/'manifest.json').write_text(json.dumps(dict(generator='MILIMAP_P43A2_TEXT_ONLY_V1',pillowVersion='12.3.0',fontSha256=hashlib.sha256(FONT.read_bytes()).hexdigest(),gridPolicy='EVAL_PIXEL_GRID_V1_BLACK32_H800_V400_FULL_BORDER_INSET3',degradation='text-only resize 400x225 then 1600x900; GaussianBlur 2; exact black grid drawn last',fixtures=fixtures),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Generated 2 A2-only fictional fixtures; historical files untouched')
