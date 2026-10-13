"""One original face, three expressions; SVG layers on the existing game pawn."""
from pathlib import Path
from copy import deepcopy
import hashlib
import json
import math
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT/'assets/art/vector/friendly_atlas.svg'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
PAWN = ET.parse(SOURCE).getroot()[0][0]
OUTLINE = '#263b3b'
INK = '#171f24'
NAMES = ['平静 · 自然眨眼', '专注 · 眉眼收紧', '受伤 · 闭眼忍痛']


def svg_group(items):
    return f'<g stroke="{OUTLINE}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">'+''.join(ET.tostring(deepcopy(item),encoding='unicode') for item in items)+'</g>'


BODY = svg_group(list(PAWN)[:4])
HEAD = svg_group([PAWN[4]])
HELMET = svg_group(list(PAWN)[5:])


def eye(side, state, closure=0):
    mirror = 'translate(64 0) scale(-1 1)' if side else ''
    if closure >= .98:
        return f'<g transform="{mirror}"><path d="M22.5 28Q26.3 29.5 29.9 28" fill="none" stroke="{INK}" stroke-width=".9" stroke-linecap="round"/></g>'
    if state == 2:
        return f'<g transform="{mirror}"><path d="M22.7 26.9Q26.3 24.9 29.7 27.1" stroke="{INK}" stroke-width=".95" fill="none" stroke-linecap="round"/><path d="M23.2 28Q25.1 27.2 26.4 27.7" fill="none" stroke="#93725e" stroke-width=".35"/></g>'
    # The iris never shrinks during blinking. The moving lid clips it instead.
    outer = 24.5 if state == 0 else 24.1
    inner = 24.8 if state == 0 else 25.3
    outer += (28.4-outer)*closure
    inner += (28.5-inner)*closure
    crest = min(outer,inner)-1.2*(1-closure)
    shape = f'M22.3 {outer}Q25.6 {crest} 30.1 {inner}L29.4 28.8Q26.5 29.8 23.5 28.7Z'
    key = f'eye-{side}'
    shift = (.28 if state == 1 else 0)*(-1 if side else 1)
    return f'''<g transform="{mirror}">
    <defs><clipPath id="{key}"><path d="{shape}"/></clipPath>
    <linearGradient id="iris-{key}" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#1f332e"/><stop offset=".62" stop-color="#3c8c54"/><stop offset="1" stop-color="#a2d887"/></linearGradient></defs>
    <path d="M22.2 {outer-1.05}Q25.7 {crest-1} 30.2 {inner-.9}L30 {inner+.4}Q25.7 {crest} 22.3 {outer+.4}Z" fill="#6c6b60" opacity=".18"/>
    <path d="{shape}" fill="#f7f5e9" stroke="{INK}" stroke-width=".55"/>
    <g clip-path="url(#{key})"><g transform="translate({shift} 0)">
    <path d="M24.1 23.4Q26.5 22.8 28.9 23.4L28.7 28.6Q26.6 29.8 24.3 28.6Z" fill="url(#iris-{key})" stroke="{INK}" stroke-width=".65"/>
    <rect x="26" y="23.7" width=".9" height="3.6" rx=".4" fill="{INK}" opacity=".75"/>
    <ellipse cx="24.9" cy="25.5" rx=".43" ry=".62" fill="#fffbed" opacity=".9"/>
    </g></g>
    <path d="M21.9 {outer-.1}Q25.6 {crest-1.0*(1-closure)} 30.5 {inner-.1}L29.9 {inner+1.05}Q25.6 {crest+.5} 22.7 {outer+1.15}Z" fill="{INK}"/>
    </g>'''


def features(state, frame=0):
    blink = {11:.25,12:.7,13:1,14:.7,15:.2}.get(frame,0) if state == 0 else 0
    parts = [eye(0,state,blink),eye(1,state,blink)]
    if state == 0:
        brow='M22.2 22.2Q25.8 20.7 29.7 22.3L29.7 23Q25.8 22 22.2 22.9ZM41.8 22.2Q38.2 20.7 34.3 22.3L34.3 23Q38.2 22 41.8 22.9Z'
        mouth='<path d="M31 32.1H33" stroke="#6c554c" stroke-width=".48" stroke-linecap="round"/>'
    elif state == 1:
        brow='M22.1 21.8Q26 22.4 30 23.8L29.7 24.4Q25.6 23.6 22.1 22.5ZM41.9 21.8Q38 22.4 34 23.8L34.3 24.4Q38.4 23.6 41.9 22.5Z'
        mouth='<path d="M30.8 32.1H33.2" stroke="#6c554c" stroke-width=".6" stroke-linecap="round"/>'
    else:
        brow='M22.3 23.6Q26.2 22.9 29.7 21.9L29.8 22.7Q26 24.1 22.4 24.3ZM41.7 23.6Q37.8 22.9 34.3 21.9L34.2 22.7Q38 24.1 41.6 24.3Z'
        amount=.10*math.sin(frame*1.2)
        mouth=f'<path d="M30.8 {32.1+amount}Q32 {31.2+amount} 33.2 {32.1+amount}" fill="none" stroke="#6c554c" stroke-width=".55" stroke-linecap="round"/>'
        drop=27.5+.5*min(1,frame/12)
        parts.append(f'<path d="M40.8 {drop}Q39.5 {drop+1.8} 40.8 {drop+2}Q42.1 {drop+1.8} 40.8 {drop}Z" fill="#b8d9d3" stroke="#648a85" stroke-width=".28"/>')
    parts += [f'<path d="{brow}" fill="{INK}"/>','<path d="M31.7 29.7L32.3 29.7L32 30.4Z" fill="#766354" opacity=".8"/>',mouth]
    return '<g id="face-features">'+''.join(parts)+'</g>'


def document(state=0, frame=0, helmet=False, head_only=False, part=None):
    content={'body':BODY,'helmet':HELMET,'face':features(state,frame)}.get(part)
    if content is None:
        content=('' if head_only else BODY)+HEAD+features(state,frame)+(HELMET if helmet else '')
    view='18 9 28 28' if head_only else '0 0 64 64'
    return f'<svg xmlns="{NS}" width="512" height="512" viewBox="{view}">{content}</svg>'


def generate():
    (HERE/'svg').mkdir(parents=True,exist_ok=True)
    for state in range(3):
        for name,kw in [('head',{'head_only':True}),('bare',{}),('helmet',{'helmet':True}),('face-layer',{'part':'face'})]:
            (HERE/f'svg/{state}-{name}.svg').write_text(document(state,**kw),encoding='utf-8')
    for part in ['body','helmet']:
        (HERE/f'svg/{part}-layer.svg').write_text(document(part=part),encoding='utf-8')
    animation=[]
    for i in range(72):
        state,frame=divmod(i,24)
        animation.append([document(state,frame,head_only=True),document(state,frame),document(state,frame,helmet=True)])
    (HERE/'animation.json').write_text(json.dumps(animation),encoding='utf-8')
    (HERE/'source.json').write_text(json.dumps({'source':'assets/art/vector/friendly_atlas.svg','sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'states':NAMES,'approval':'pending','runtime_modified':False},ensure_ascii=False,indent=2),encoding='utf-8')
    print('FACE_SINGLE_SVG_OK: one face, three states, bare/helmet shared face layer')


def compose():
    from PIL import Image, ImageDraw, ImageFont
    bg,paper,ink,ground='#e6e7df','#f4f2e8','#293c37','#7b866f'
    fontfile=ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'
    def label(im,xy,value,size=24,color=ink):
        ImageDraw.Draw(im).text(xy,value,font=ImageFont.truetype(str(fontfile),size),fill=color)
    def paste(im,path,xy,size):
        pic=Image.open(path).convert('RGBA').resize((size,size),Image.Resampling.LANCZOS)
        im.alpha_composite(pic,xy)
    board=Image.new('RGBA',(1200,1040),bg)
    label(board,(28,20),'RIMGATE · 一套脸，三种表情',34)
    label(board,(28,72),'同一眼型与瞳色；原版身体、脸部轮廓、头盔均保留。',22)
    for state,name in enumerate(NAMES):
        x=20+state*395
        ImageDraw.Draw(board).rounded_rectangle((x,122,x+375,1005),radius=20,fill=paper)
        label(board,(x+24,140),name,25)
        paste(board,HERE/f'png/{state}-head.png',(x+27,190),320)
        label(board,(x+26,525),'无头盔',21)
        label(board,(x+215,525),'戴原版头盔',21)
        paste(board,HERE/f'png/{state}-bare.png',(x-5,565),200)
        paste(board,HERE/f'png/{state}-helmet.png',(x+180,565),200)
        ImageDraw.Draw(board).rounded_rectangle((x+18,803,x+357,977),radius=12,fill=ground)
        paste(board,HERE/f'png/{state}-bare.png',(x+45,820),68)
        paste(board,HERE/f'png/{state}-helmet.png',(x+153,807),96)
        label(board,(x+36,910),'68px / 96px 尺寸对照',18,'#f5f2df')
    label(board,(28,1014),'正面审稿 · 独立面部覆盖层 · 尚未接入游戏',16)
    board.convert('RGB').save(HERE/'preview.png')
    heads,bodies=[],[]
    for i in range(72):
        state=i//24
        head=Image.new('RGBA',(560,620),paper)
        label(head,(22,16),'原版小人 · 动态面部',28)
        paste(head,HERE/f'frames/{i:02d}-0.png',(24,68),512)
        label(head,(22,580),NAMES[state],23)
        heads.append(head.convert('RGB'))
        body=Image.new('RGBA',(800,540),bg)
        label(body,(24,16),NAMES[state],28)
        for j,title in [(1,'无头盔'),(2,'原版头盔')]:
            x=18+(j-1)*395
            ImageDraw.Draw(body).rounded_rectangle((x,75,x+375,510),radius=16,fill=paper)
            label(body,(x+20,90),title,24)
            paste(body,HERE/f'frames/{i:02d}-{j}.png',(x+9,130),356)
        bodies.append(body.convert('RGB'))
    for name,frames in [('face-animated.gif',heads),('pawn-animated.gif',bodies)]:
        palette=frames[0].quantize(colors=160,method=Image.Quantize.MEDIANCUT)
        out=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
        out[0].save(HERE/name,save_all=True,append_images=out[1:],duration=100,loop=0,optimize=False,disposal=2)
        gif=Image.open(HERE/name)
        duration=0
        for k in range(gif.n_frames):
            gif.seek(k);duration+=gif.info.get('duration',0)
        assert duration==7200 and gif.n_frames>=12,(name,duration,gif.n_frames)
    info=json.loads((HERE/'source.json').read_text(encoding='utf-8'))
    assert info['sha256']==hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    print('FACE_SINGLE_REVIEW_OK: static board, two 7.2s GIFs, original runtime asset unchanged')


if __name__=='__main__':
    generate() if len(sys.argv)<2 or sys.argv[1]=='generate' else compose()
