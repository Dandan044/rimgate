"""Create vector registration wrappers around unchanged AI atlas pixels.

No repainting, masking, or AI re-generation of assembled identities: the source
PNGs are embedded unchanged and positioned using per-part registration data.
These are front-view assembly studies, not certified runtime assets.
"""
from pathlib import Path
from PIL import Image
import base64
import json
import itertools
IDS=itertools.count()

HERE=Path(__file__).resolve().parent
OUT=HERE/'assembly-svg'
OUT.mkdir(exist_ok=True)

def bounds(file, slot):
    im=Image.open(HERE/file)
    left=round(im.width*slot/3); right=round(im.width*(slot+1)/3)
    a=im.getchannel('A').crop((left,0,right,im.height))
    box=a.point(lambda v:255 if v>160 else 0).getbbox()
    return (box[0]+left,box[1],box[2]+left,box[3])

def patch(file, box, dest):
    im=Image.open(HERE/file)
    x0,y0,x1,y1=box; x,y,w,h=dest
    data=base64.b64encode((HERE/file).read_bytes()).decode('ascii')
    sx,sy=w/(x1-x0),h/(y1-y0)
    cid=f'crop-{next(IDS)}'
    return f'<defs><clipPath id="{cid}"><rect x="{x}" y="{y}" width="{w}" height="{h}"/></clipPath></defs><g clip-path="url(#{cid})"><image x="{x-x0*sx}" y="{y-y0*sy}" width="{im.width*sx}" height="{im.height*sy}" preserveAspectRatio="none" href="data:image/png;base64,{data}"/></g>'

def main():
    face='faces-v2.png' if (HERE/'faces-v2.png').exists() else 'faces-v1.png'
    hair='hair-v2.png' if (HERE/'hair-v2.png').exists() else 'hair-v1.png'
    # Explicit front/back socket rectangles for the source atlas, in pixels.
    back=[(128,32,516,604),(585,38,954,386),(1010,30,1405,588)]
    front=[(150,615,510,1007),(587,610,962,1008),(1025,615,1400,1009)]
    configs=[(0,0,0,0),(1,1,1,1),(2,2,2,2),(0,2,1,2)]
    manifest=[]
    for i,(fi,fa,ha,bo) in enumerate(configs):
        # Identical face/feet sockets, intentional per-hairstyle length.
        bh=[365,230,345][ha]
        fh=[220,225,245][ha]
        body_width=[153,181,183][bo]
        layers=[patch(hair,back[ha],(146,112,220,bh)),
                patch('bodies.png',bounds('bodies.png',bo),(256-body_width/2,346,body_width,400)),
                patch(face,bounds(face,fa),(153,130,206,225)),
                patch('features.png',bounds('features.png',fi),(178,253,156,75)),
                patch(hair,front[ha],(146,112,220,fh))]
        name=f'{i+1:02d}-assembled.svg'
        (OUT/name).write_text('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="832" viewBox="0 0 512 832">'+''.join(layers)+'</svg>',encoding='utf-8')
        manifest.append({'file':name,'features':fi,'face':fa,'hair':ha,'body':bo})
    (HERE/'assembly-manifest.json').write_text(json.dumps({'status':'manual registration study; no runtime replacement','face_source':face,'hair_source':hair,'source_pixels_unchanged':True,'combinations':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
    print('AI source-pixel SVG assembly studies:',len(configs))

if __name__=='__main__': main()
