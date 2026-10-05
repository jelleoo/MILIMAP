"""Offline, independent ReportLab controls (CC0); not a product dependency.

Run only when authoring committed fixture bytes. CI consumes PDFs, not ReportLab.
"""
from pathlib import Path
import io
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.cidfonts import UnicodeCIDFont
from reportlab.lib.pdfencrypt import StandardEncryption
from PIL import Image

root = Path(__file__).parent
pdfmetrics.registerFont(UnicodeCIDFont("HYSMyeongJo-Medium"))
headers = ["업소명", "주소", "전화번호", "혜택"]
data = [["합성가게 A", "서울특별시 마포구 테스트로 12", "02-0000-0012", "합성 A 혜택\n합성 조건 A"],
        ["합성가게 B", "서울특별시 마포구 테스트로 34", "02-0000-0034", "합성 B 혜택"]]

def table(c, rows, top=500, mode="", left=20):
    xs=[left,left+150,left+360,left+470,left+700]
    ys=[top-i*40 for i in range(len(rows)+1)]
    for x in xs:
        if mode in ("merged-header", "merged-value") and x==xs[1]:
            gap=0 if mode=="merged-header" else 1
            c.line(x,ys[-1],x,ys[gap+1]);c.line(x,ys[gap],x,ys[0])
        else:c.line(x,ys[-1],x,ys[0])
    for i,y in enumerate(ys):
        if mode=="broken" and i==2:c.line(xs[0],y,xs[2]-20,y);c.line(xs[2]+20,y,xs[-1],y)
        else:c.line(xs[0],y,xs[-1],y)
    c.setFont("HYSMyeongJo-Medium",10)
    for r,row in enumerate(rows):
        for col,text in enumerate(row):
            x=xs[col]+5
            if mode=="crossing" and r==1 and col==0:x=xs[1]-15
            for line_no,line in enumerate(text.split("\n")):
                y=ys[r]-16-line_no*12;c.drawString(x,y,line)
                if mode=="overlap" and r==1 and col==0:c.drawString(x,y,line)

for mode in ("two-business","decorative","multi-table","multi-page","native-no-grid","image-only",
             "missing-name-header","duplicate-header","ambiguous-header","merged-header","merged-value",
             "broken","crossing","overlap","continuation","repeated","duplicate-name","empty-name",
             "rotation-90","rotation-180","rotation-270","encrypted","malformed-later"):
    encryption=StandardEncryption("test-only",ownerPassword="test-owner",strength=128) if mode=="encrypted" else None
    size=(600,800) if mode in ("rotation-90","rotation-270") else (800,600)
    c=canvas.Canvas(str(root/(mode+".pdf")),pagesize=size,invariant=1,encrypt=encryption)
    if mode.startswith("rotation-"):c.setPageRotation(int(mode.split("-")[1]))
    if mode=="native-no-grid":c.setFont("HYSMyeongJo-Medium",10);c.drawString(20,500,"합성 문서 표 없음")
    elif mode=="image-only":
        image=Image.new("RGB",(40,20),"white");c.drawInlineImage(image,20,400,200,100)
    else:
        h=list(headers);d=[list(row) for row in data]
        if mode=="missing-name-header":h[0]="설명"
        if mode=="duplicate-header":h[1]="업체명"
        if mode=="duplicate-name":d[1][0]=d[0][0]
        if mode=="empty-name":d[1][0]=""
        if mode=="decorative":table(c,[["장식","","",""]],top=590)
        if mode=="ambiguous-header":d=[h]+d
        if mode=="continuation":d[1][0]=""
        table(c,[h]+d,mode=mode)
        if mode=="multi-table":table(c,[h]+d,top=280)
        if mode=="repeated":
            c.setFont("HYSMyeongJo-Medium",10);c.drawString(20,580,"문서 머리말");c.drawString(20,30,"문서 꼬리말")
        if mode in ("multi-page","continuation","repeated","malformed-later"):
            c.showPage()
            if mode=="malformed-later":c._code.append("BT /MissingFont 12 Tf 20 40 Td (Untrusted later page) Tj ET")
            else:table(c,[h]+(d if mode!="continuation" else [["","","","다른 페이지 연속 혜택"]]))
    c.save()
(root/"truncated.pdf").write_bytes((root/"two-business.pdf").read_bytes()[:100])
