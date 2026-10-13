"""Full-pawn review: lighter contours, softer face 06, fitted helmet hair."""
from pathlib import Path
from copy import deepcopy
import hashlib
import importlib.util
import json
import sys
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('previous_faces',HERE.parent/'facial_combinations_v1/make_combinations.py')
previous=importlib.util.module_from_spec(spec)
spec.loader.exec_module(previous)
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
INK=previous.INK
PEOPLE=deepcopy(previous.PEOPLE)
PEOPLE[5]['name']='柔和收颌脸 · 偏分低马尾'
PEOPLE[5]['face']='M32 10C26 10 22.2 13.6 21.5 19Q20.7 23.4 22 27.5C23.8 32.5 28.2 35.1 31.3 35.5Q32 35.7 32.7 35.5C35.8 35.1 40.2 32.5 42 27.5Q43.3 23.4 42.5 19C41.8 13.6 38 10 32 10Z'
HAIR=deepcopy(previous.HAIR)
PONY='M42.8 22.5C47.8 20.8 49.9 25.4 47.5 29.1C46 31.8 48.4 33.9 47.1 37C44.1 36.1 42.9 34.2 43.4 31.9C44.9 29.8 43.1 27.7 41.9 26.3Z'
HAIR[5]=(PONY+' M19.5 24L19 16.4Q18.7 7.3 31 7.5Q43 6.5 44.8 15.5L44.7 24.4L41.6 21H22.6Z',HAIR[5][1],'M24.1 13.8Q28 11.3 34 11.5M44.1 25.1Q47.2 26.5 45.2 29.3M45 32Q45.8 34.2 46.6 35.1')

# Each hairstyle has authored, compressed parts for wearing this helmet.
# These are not the bare hairstyle chopped by a horizontal rectangle.
HELMET_HAIR=[
 ('M20.5 20.1Q19.4 24 20.7 27.5L22.3 25.1L22.5 20.5Z M41.5 20.5Q44.6 22.7 43.1 26.5L41.4 24.2Z',
  'M22.2 19.7Q28.3 20.2 36.1 18.6Q31.7 22.1 24.1 22.3L22.3 24.1Z M39.8 19.9L42.7 21.1L43.1 24.2L40.8 22.2Z',
  'M24.2 20.8Q28.3 21.2 31.7 20.4'),
 ('M20.5 20.7L22 20.5L21.9 23.6L20.5 24.4Z M42 20.5L43.5 20.7V24.4L42.1 23.6Z',
  'M22.4 20.1L23.8 20.4L23.7 21.2L22.3 21.5Z M40.2 20.4L41.6 20.1L41.7 21.5L40.3 21.2Z',''),
 ('M20.3 19.8L18.9 30.2Q20.4 31.9 22.6 29.3L24 21.2Z M43.7 19.8L45.1 30.2Q43.6 31.9 41.4 29.3L40 21.2Z',
  'M22.5 19.9Q32 18.1 41.5 19.9L41 21.7L37.8 21.2L35.2 22.5L32.1 21.2L29.2 22.4L26.1 21.3L23.1 22Z M20.3 21L22.7 22L21.8 28.5L20 29.2Z M41.3 22L43.7 21L44 29.2L42.2 28.5Z',
  'M20.8 23.4L20.7 27.2M43.2 23.4L43.3 27.2'),
 ('M20.5 20.5Q19.7 23.3 21 26.8L22.3 23.1L22 20Z M43.5 20.5Q44.3 23.3 43 26.8L41.7 23.1L42 20Z',
  'M22.3 20.1L24.8 20.5L22.7 22.9L21.8 24Z M39.2 20.5L41.7 20.1L42.2 24L41.3 22.9Z',
  'M21.5 22.7L21.7 24.6M42.5 22.7L42.3 24.6'),
 ('M20.5 20.8Q17.9 21.2 18.9 23.2Q17.5 25.1 19.6 26.8L22 24.9L22.1 21Z M43.5 20.8Q46.1 21.2 45.1 23.2Q46.5 25.1 44.4 26.8L42 24.9L41.9 21Z',
  'M23.6 19.9Q24.2 22.3 26.3 21.2Q28.1 23.2 30 21.1Q32 22.5 34 21.1Q35.9 23.2 37.7 21.2Q39.8 22.3 40.4 19.9L39.4 19.1H24.6Z',
  'M20.3 22.2Q19.1 23.6 20.1 24.5M43.7 22.2Q44.9 23.6 43.9 24.5'),
 (PONY+' M20.5 20.3Q19.5 24.5 21 27.2L22.5 24.2L22.4 20.6Z M41.5 20.8L43.3 21.1L43.1 25.8L41.4 24Z',
  'M22.1 19.7Q28 20.4 37.2 18.5Q34.1 22.7 25 22.1L22.1 24.1Z M40.4 20L42.7 21.4L42.9 24.8L40.7 22.4Z',
  'M24.2 20.9Q28.2 21.5 32.2 20.3M44.1 25.1Q47.2 26.5 45.2 29.3M45 32Q45.8 34.2 46.6 35.1'),
]


def thinner(xml,factor):
    root=ET.fromstring(f'<svg xmlns="{NS}">{xml}</svg>')
    for node in root.iter():
        if 'stroke-width' in node.attrib:
            node.set('stroke-width',str(round(float(node.get('stroke-width'))*factor,3)))
    return ''.join(ET.tostring(n,encoding='unicode') for n in root)


BODY=thinner(previous.base.BODY,.5)
HELMET=thinner(previous.base.HELMET,.5)


def hair(index,front=False,helmet=False):
    p=PEOPLE[index]
    paths=HELMET_HAIR[index] if helmet else HAIR[index]
    shape=paths[1 if front else 0]
    shine=paths[2] if front else ''
    result=f'<g id="hair-{"front" if front else "back"}" fill="{p["hair"]}" stroke="{INK}" stroke-width=".78" stroke-linejoin="round" stroke-linecap="round"><path d="{shape}"/>'
    if shine:
        result+=f'<path d="{shine}" fill="none" stroke="{p["light"]}" stroke-width=".48"/>'
    if index==5 and not front:
        result+='<path d="M43.2 24.1L45.3 24.7" fill="none" stroke="#668d88" stroke-width="1.1"/>'
    return result+'</g>'


def head(index):
    p=PEOPLE[index]
    return f'<g id="head" fill="{p["skin"]}" stroke="{INK}" stroke-linejoin="round"><ellipse cx="20.8" cy="24.8" rx="1.45" ry="2.05" stroke-width=".65"/><ellipse cx="43.2" cy="24.8" rx="1.45" ry="2.05" stroke-width=".65"/><path d="{p["face"]}" stroke-width="1.1"/></g>'


def features(index,frame=-1):
    # Static review sheets show open eyes for every person.
    actual_frame=(-(index*5))%36 if frame<0 else frame
    return thinner(previous.features(index,actual_frame),.8)


def document(index,frame=-1,helmet=False,portrait=False,part=None):
    content={'body':BODY,'helmet':HELMET,'head':head(index),'features':features(index,frame),
      'hair-back':hair(index),'hair-front':hair(index,True),
      'helmet-hair-back':hair(index,helmet=True),'helmet-hair-front':hair(index,True,True)}.get(part)
    if content is None:
        content=('' if portrait else BODY)+hair(index,helmet=helmet)+head(index)+features(index,frame)+hair(index,True,helmet)+(HELMET if helmet else '')
    view='13 3 38 38' if portrait else '0 0 64 64'
    return f'<svg xmlns="{NS}" width="512" height="512" viewBox="{view}">{content}</svg>'


def generate():
    (HERE/'svg').mkdir(parents=True,exist_ok=True)
    for i,p in enumerate(PEOPLE):
        for name,kw in [('bare',{}),('helmet',{'helmet':True}),('portrait',{'portrait':True}),('helmet-detail',{'portrait':True,'helmet':True})]+[(part+'-layer',{'part':part}) for part in ['head','features','hair-back','hair-front','helmet-hair-back','helmet-hair-front']]:
            (HERE/f'svg/{p["id"]}-{name}.svg').write_text(document(i,**kw),encoding='utf-8')
    for part in ['body','helmet']:
        (HERE/f'svg/{part}-layer.svg').write_text(document(0,part=part),encoding='utf-8')
    (HERE/'animation.json').write_text(json.dumps([[document(i,frame,helmet=h) for i in range(6) for h in [False,True]] for frame in range(36)]),encoding='utf-8')
    (HERE/'manifest.json').write_text(json.dumps({'source':'assets/art/vector/friendly_atlas.svg','source_sha256':hashlib.sha256(previous.base.SOURCE.read_bytes()).hexdigest(),'people':PEOPLE,'eye_base_scale':previous.EYE_SCALE,'outline_widths':{'body':1.5,'helmet':1.5,'face':1.1,'hair':.78},'helmet_hair':'six individually authored fitted hairstyles','runtime_modified':False,'approval':'pending','view':'front'},ensure_ascii=False,indent=2),encoding='utf-8')
    print('FACE_V2_SVG_OK: softer face06, half-width contours, 6 fitted helmet hairstyles')


def compose():
    from PIL import Image,ImageDraw,ImageFont
    bg,paper,ink,ground='#e7e9e1','#f7f4ec','#293c37','#7f8b75'
    font=ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'
    def label(im,xy,value,size=24,color=ink):
        ImageDraw.Draw(im).text(xy,value,font=ImageFont.truetype(str(font),size),fill=color)
    def paste(im,path,rect,trim=False,bottom=False):
        art=Image.open(path).convert('RGBA')
        if trim:
            art=art.crop(art.getchannel('A').getbbox())
        x,y,w,h=rect;scale=min(w/art.width,h/art.height)
        art=art.resize((round(art.width*scale),round(art.height*scale)),Image.Resampling.LANCZOS)
        im.alpha_composite(art,(round(x+(w-art.width)/2),round(y+h-art.height if bottom else y+(h-art.height)/2)))
    board=Image.new('RGBA',(1800,1420),bg)
    label(board,(28,18),'RIMGATE · 完整小人 / 减细描边 / 戴盔发型',38)
    label(board,(28,78),'06号改为柔和收颌脸；每组展示相同人物的无盔与戴盔状态。',25)
    for i,p in enumerate(PEOPLE):
        x=18+(i%3)*595;y=138+(i//3)*625
        ImageDraw.Draw(board).rounded_rectangle((x,y,x+578,y+603),radius=20,fill=paper)
        label(board,(x+22,y+17),p['id']+'  '+p['name'],27)
        label(board,(x+22,y+62),p['detail'],21)
        label(board,(x+90,y+111),'无头盔',23)
        label(board,(x+375,y+111),'戴头盔',23)
        for h,name in enumerate(['bare','helmet']):
            left=x+20+h*281
            paste(board,HERE/f'png/{p["id"]}-{name}.png',(left,y+146,255,343),trim=True,bottom=True)
        ImageDraw.Draw(board).rounded_rectangle((x+22,y+510,x+556,y+582),radius=12,fill=ground)
        paste(board,HERE/f'png/{p["id"]}-bare.png',(x+230,y+507,68,68))
        paste(board,HERE/f'png/{p["id"]}-helmet.png',(x+350,y+507,68,68))
        label(board,(x+38,y+530),'游戏尺寸 68px',18,'#f5f2df')
    label(board,(28,1390),'正面审稿 · 当前小人的完整身体轮廓 · 头发与头盔分层 · 尚未接入游戏',18)
    board.convert('RGB').save(HERE/'full-body-review.png')
    detail=Image.new('RGBA',(1500,1020),bg)
    label(detail,(24,18),'头盔下的发型细节',34)
    for i,p in enumerate(PEOPLE):
        x=12+(i%3)*496;y=82+(i//3)*458
        ImageDraw.Draw(detail).rounded_rectangle((x,y,x+480,y+442),radius=18,fill=paper)
        label(detail,(x+16,y+14),p['id']+' '+p['name'],23)
        paste(detail,HERE/f'png/{p["id"]}-helmet-detail.png',(x+42,y+56,396,370))
    detail.convert('RGB').save(HERE/'helmet-hair-detail.png')
    comparison=Image.new('RGBA',(1080,470),bg)
    label(comparison,(22,14),'06号修改：柔和颧骨与下巴，减细边缘',30)
    for j,(path,title) in enumerate([(HERE.parent/'facial_combinations_v1/png/06-portrait.png','修改前'),(HERE/'png/06-portrait.png','修改后'),(HERE/'png/06-helmet-detail.png','戴盔与马尾')]):
        paste(comparison,path,(j*360+20,72,320,320))
        label(comparison,(j*360+110,412),title,23)
    comparison.convert('RGB').save(HERE/'06-revision.png')
    frames=[]
    for frame in range(36):
        image=Image.new('RGBA',(1200,1000),bg)
        label(image,(22,16),'完整小人 · 无盔 / 戴盔',30)
        for i,p in enumerate(PEOPLE):
            x=12+(i%3)*396;y=76+(i//3)*454
            ImageDraw.Draw(image).rounded_rectangle((x,y,x+380,y+438),radius=16,fill=paper)
            label(image,(x+16,y+14),p['id']+' '+p['name'],20)
            for h in range(2):
                paste(image,HERE/f'frames/{frame:02d}-{i*2+h}.png',(x+12+h*185,y+80,170,300),trim=True,bottom=True)
            label(image,(x+50,y+396),'无盔',18)
            label(image,(x+237,y+396),'戴盔',18)
        frames.append(image.convert('RGB'))
    palette=frames[0].quantize(colors=224,method=Image.Quantize.MEDIANCUT)
    out=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
    out[0].save(HERE/'full-body-animated.gif',save_all=True,append_images=out[1:],duration=100,loop=0,disposal=2,optimize=False)
    info=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
    assert info['source_sha256']==hashlib.sha256(previous.base.SOURCE.read_bytes()).hexdigest()
    for p in PEOPLE:
        for name in ['bare','helmet','portrait','helmet-detail']:
            im=Image.open(HERE/f'png/{p["id"]}-{name}.png')
            assert im.size==(512,512) and im.mode=='RGBA'
            bounds=im.getchannel('A').getbbox()
            assert bounds and min(bounds[:2])>0 and max(bounds[2:])<512,(p['id'],name,bounds)
    assert 'L' not in PEOPLE[5]['face']
    print('FACE_V2_REVIEW_OK: 12 full-pawn views, 6 helmet details, unclipped silhouettes; runtime unchanged')


if __name__=='__main__':
    generate() if len(sys.argv)<2 or sys.argv[1]=='generate' else compose()
