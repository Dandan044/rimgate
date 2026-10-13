"""Registered AI identity/body/equipment layers; original PNGs remain unchanged."""
from pathlib import Path
from PIL import Image
import base64
import json
import itertools

HERE=Path(__file__).resolve().parent
OUT=HERE/'svg'; OUT.mkdir(exist_ok=True)
IDS=itertools.count()

def bounds(file,slot,columns=3,rows=1,row=0):
    im=Image.open(HERE/file)
    left=round(im.width*slot/columns); right=round(im.width*(slot+1)/columns)
    top=round(im.height*row/rows); bottom=round(im.height*(row+1)/rows)
    a=im.getchannel('A').crop((left,top,right,bottom))
    box=a.point(lambda v:255 if v>160 else 0).getbbox()
    if box is None: raise ValueError(f'Empty slot {file} {slot}')
    return (box[0]+left,box[1]+top,box[2]+left,box[3]+top)

def patch(file,box,dest,extra_clip=None):
    im=Image.open(HERE/file); x0,y0,x1,y1=box; x,y,w,h=dest
    sx,sy=w/(x1-x0),h/(y1-y0)
    data=base64.b64encode((HERE/file).read_bytes()).decode('ascii')
    cid=f'clip{next(IDS)}'
    rect=extra_clip or (x,y,w,h)
    return f'<defs><clipPath id="{cid}"><rect x="{rect[0]}" y="{rect[1]}" width="{rect[2]}" height="{rect[3]}"/></clipPath></defs><g clip-path="url(#{cid})"><image x="{x-x0*sx}" y="{y-y0*sy}" width="{im.width*sx}" height="{im.height*sy}" preserveAspectRatio="none" href="data:image/png;base64,{data}"/></g>'

# Per-hair source rectangles maintain back/front separation in the AI atlas.
BACK=[(125,28,525,603),(574,40,963,387),(1007,25,1417,590)]
FRONT=[(155,610,501,1005),(580,612,958,1005),(1028,615,1407,1008)]

def head(i,helmet=None,back=False):
    if back:
        return patch('hair.png',BACK[i],(146,132,220,[365,223,345][i]))
    content=patch('faces.png',bounds('faces.png',i),(153,150,206,205))
    content+=patch('features.png',bounds('features.png',i),(178,253,156,75))
    # Fringe is rooted at the crown, but its new lower locks cover the forehead.
    content+=patch('hair.png',FRONT[i],(146,132,220,[230,223,245][i]),extra_clip=(130,242,260,280) if helmet else None)
    if helmet:
        hi=0 if helmet=='standard' else 1
        content+=patch('helmets.png',bounds('helmets.png',hi,2),(139,119,234,220))
    return content

def document(i,outfit='base'):
    widths=[153,181,183]
    hgear='standard' if outfit=='standard' else 'heavy' if outfit=='heavy' else None
    pieces=head(i,back=True)
    pieces+=patch('base-bodies.png',bounds('base-bodies.png',i),(256-widths[i]/2,346,widths[i],400),extra_clip=(150,346,212,32) if outfit!='base' else None)
    if outfit!='base':
        extra=0 if outfit=='light' else 10 if outfit=='standard' else 27
        w=widths[i]+extra
        pieces+=patch(outfit+'-kit.png',bounds(outfit+'-kit.png',i),(256-w/2,346,w,400))
    pieces+=head(i,hgear)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="832" viewBox="0 0 512 832">'+pieces+'</svg>'

def main():
    manifest=[]
    for i in range(3):
        for kit in ['base','light','standard','heavy']:
            path=OUT/f'{i+1:02d}-{kit}.svg'
            path.write_text(document(i,kit),encoding='utf-8')
            manifest.append({'file':path.name,'features':i,'face':i,'hair':i,'body':i,'outfit':kit})
    (HERE/'manifest.json').write_text(json.dumps({'status':'front static art review; runtime unchanged','source_pixels_unchanged':True,'identity_axes':['features','face','hair','body'],'equipment_independent':True,'head_socket':[256,355],'foot_anchor':[256,746],'combinations':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
    print('EQUIPMENT_ASSEMBLY_SVG_OK',len(manifest))

if __name__=='__main__': main()
