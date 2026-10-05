import json, sys, math
from pathlib import Path

# Temporary geometry experiment only; no PDF parser, semantic header map or product code.
SNAP=.5
THIN=.75
CONTAIN=.01
LINE=1.0
e=json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
expected=sys.argv[3] if len(sys.argv)>3 else ''
cells=[]
ambiguous=False
def cluster(values):
    groups=[]
    for v in sorted(set(values)):
        if groups and v-groups[-1][0]<=SNAP: groups[-1].append(v)
        else: groups.append([v])
    return [sum(g)/len(g) for g in groups]
def cover(parts,lo,hi):
    cursor=lo
    for a,b in sorted(parts):
        if a>cursor+SNAP: return False
        if b>=cursor: cursor=max(cursor,b)
        if cursor>=hi-SNAP: return True
    return False
for page in e['Pages']:
    if page['RotationDegrees']!=0: raise ValueError('Temporary probe evaluated rotation 0 only; no guessed normalization')
    h=[]; v=[]
    for p in page['Paths']:
        for sub in p['Subpaths']:
            bounds=[c['Bounds'] for c in sub if c['Bounds']]
            if p['IsFilled'] and bounds:
                x0=min(b['X0'] for b in bounds); x1=max(b['X1'] for b in bounds)
                y0=min(b['Y0'] for b in bounds); y1=max(b['Y1'] for b in bounds)
                # Require straight closed rectangle, not an arbitrary curve's bbox.
                pts=[c['Points'] for c in sub if c['Kind']=='Line']
                rect=(len(pts)==3 and any(c['Kind']=='Close' for c in sub) and all(abs(q['From']['X']-q['To']['X'])<1e-8 or abs(q['From']['Y']-q['To']['Y'])<1e-8 for q in pts))
                if rect and 0<x1-x0<=THIN and y1-y0>THIN: v.append(((x0+x1)/2,y0,y1))
                if rect and 0<y1-y0<=THIN and x1-x0>THIN: h.append(((y0+y1)/2,x0,x1))
            if p['IsStroked']:
                for c in sub:
                    if c['Kind']!='Line': continue
                    a,b=c['Points']['From'],c['Points']['To']
                    if abs(a['Y']-b['Y'])<1e-8: h.append((a['Y'],min(a['X'],b['X']),max(a['X'],b['X'])))
                    elif abs(a['X']-b['X'])<1e-8: v.append((a['X'],min(a['Y'],b['Y']),max(a['Y'],b['Y'])))
    xs=cluster([x for x,_,_ in v]); ys=cluster([y for y,_,_ in h])
    pagecells=[]
    for x0,x1 in zip(xs,xs[1:]):
        for y0,y1 in zip(ys,ys[1:]):
            if all(cover([(a,b) for q,a,b in h if abs(q-y)<=SNAP],x0,x1) for y in (y0,y1)) and all(cover([(a,b) for q,a,b in v if abs(q-x)<=SNAP],y0,y1) for x in (x0,x1)):
                pagecells.append(dict(Page=page['PageNumber'],X0=x0,Y0=y0,X1=x1,Y1=y1,Letters=[]))
    pagecells.sort(key=lambda c:(-c['Y1'],c['X0']))
    for letter in page['Letters']:
        if not all(math.isfinite(letter[k]) for k in ('X0','Y0','X1','Y1')): raise ValueError('Invalid coordinate')
        owners=[c for c in pagecells if letter['X0']>=c['X0']-CONTAIN and letter['X1']<=c['X1']+CONTAIN and letter['Y0']>=c['Y0']-CONTAIN and letter['Y1']<=c['Y1']+CONTAIN]
        if len(owners)>1: ambiguous=True
        if len(owners)==1: owners[0]['Letters'].append(letter)
    for cell in pagecells:
        lines=[]
        for l in sorted(cell['Letters'],key=lambda l:(-l['BaselineY'],l['X0'],l['Index'])):
            if lines and abs(lines[-1][0]['BaselineY']-l['BaselineY'])<=LINE: lines[-1].append(l)
            else: lines.append([l])
        cell['Text']='\n'.join(''.join(l['Text'] for l in sorted(line,key=lambda l:(l['X0'],l['Index']))) for line in lines)
        cell['LetterIndices']=[l['Index'] for l in cell.pop('Letters')]
    cells.extend(pagecells)
# Count connected physical cell components, not text-derived tables.
remaining=set(range(len(cells))); components=0
while remaining:
    components+=1; todo=[remaining.pop()]
    while todo:
        a=cells[todo.pop()]
        neighbors=[]
        for i in remaining:
            b=cells[i]
            vertical=(abs(a['X1']-b['X0'])<=SNAP or abs(b['X1']-a['X0'])<=SNAP) and min(a['Y1'],b['Y1'])-max(a['Y0'],b['Y0'])>SNAP
            horizontal=(abs(a['Y1']-b['Y0'])<=SNAP or abs(b['Y1']-a['Y0'])<=SNAP) and min(a['X1'],b['X1'])-max(a['X0'],b['X0'])>SNAP
            if a['Page']==b['Page'] and (vertical or horizontal): neighbors.append(i)
        for i in neighbors: remaining.remove(i); todo.append(i)
matches=[c for c in cells if expected and expected in c['Text']]
result=dict(GridCandidateCount=components,ClosedCellCount=len(cells),AmbiguousTopology=ambiguous,ExpectedBusinessCell=matches[0] if len(matches)==1 else None,ExpectedBusinessContainment='EXACTLY_ONE_CELL' if len(matches)==1 and not ambiguous else 'NOT_PROVEN',Tolerances=dict(SnapPoints=SNAP,ThinFilledRectanglePoints=THIN,ContainmentPoints=CONTAIN,LineGroupingPoints=LINE),Cells=cells,NegativeControls=[])
Path(sys.argv[2]).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k not in ('Cells','NegativeControls')},ensure_ascii=False))
