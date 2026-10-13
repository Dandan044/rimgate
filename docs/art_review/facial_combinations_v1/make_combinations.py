"""Six modular face / feature / hair studies on the existing Rimgate body."""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('rimgate_face_base', HERE.parent/'facial_single_v1/make.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
INK = '#263b3b'
FEATURE = '#20272b'
EYE_SCALE = .87

PEOPLE = [
 {'id':'01','name':'椭圆脸 · 侧分短发','detail':'细弧眉 / 青灰瞳 / 小幅微笑','skin':'#d9b992','hair':'#334b51','light':'#50666a','iris':['#283b41','#4c8588','#a0cec0'],'eye_y':1.0,'eye_x':.99,'brow':0,'face':'M32 10C24 10 20.8 15.8 20.8 22C20.8 28.8 25 34.5 32 35.6C39 34.5 43.2 28.8 43.2 22C43.2 15.8 40 10 32 10Z'},
 {'id':'02','name':'方脸 · 利落寸头','detail':'平直粗眉 / 茶金瞳 / 短平嘴','skin':'#cba980','hair':'#4c3d35','light':'#685548','iris':['#3d3527','#a38346','#ddc983'],'eye_y':.94,'eye_x':1.02,'brow':1,'face':'M25 11Q20 12 20 18L20 27Q21 32.5 25 34H39Q43 32.5 44 27V18Q44 12 39 11Z'},
 {'id':'03','name':'心形脸 · 齐刘海短发','detail':'柔细眉 / 翡翠瞳 / 小巧鼻嘴','skin':'#e7c8aa','hair':'#795443','light':'#a07558','iris':['#253e34','#40855a','#a6d99a'],'eye_y':1.02,'eye_x':1.01,'brow':2,'face':'M32 10C22 9.5 19.7 16 20 22C20.4 28 25.8 33 32 35.8C38.2 33 43.6 28 44 22C44.3 16 42 9.5 32 10Z'},
 {'id':'04','name':'长脸 · 后梳短发','detail':'斜挑眉 / 琥珀瞳 / 窄鼻梁','skin':'#e2c5a3','hair':'#9b8e6c','light':'#c1b58e','iris':['#45392b','#ad854d','#e4c88b'],'eye_y':.95,'eye_x':.96,'brow':3,'face':'M32 9Q22 9 21.3 17V27Q22.5 34 32 36.5Q41.5 34 42.7 27V17Q42 9 32 9Z'},
 {'id':'05','name':'梨形脸 · 蓬松卷发','detail':'柔弧浓眉 / 绛红瞳 / 宽鼻尖','skin':'#bc9473','hair':'#634739','light':'#8b6450','iris':['#423039','#a46066','#e8b3a4'],'eye_y':.97,'eye_x':.99,'brow':4,'face':'M32 10C24 10 21.6 14.9 22 21Q17.9 28.5 23.2 32.2Q27.3 35.4 32 35.2Q36.7 35.4 40.8 32.2Q46.1 28.5 42 21C42.4 14.9 40 10 32 10Z'},
 {'id':'06','name':'菱形脸 · 偏分低马尾','detail':'短锐眉 / 紫灰瞳 / 克制唇线','skin':'#e5cbb6','hair':'#a4aba5','light':'#d0d4c8','iris':['#363044','#796a9b','#c6b6df'],'eye_y':1.0,'eye_x':1.0,'brow':5,'face':'M32 10Q38 10.5 41 15L44 24Q41 30.5 32 35.8Q23 30.5 20 24L23 15Q26 10.5 32 10Z'},
]

HAIR = [
 ('M19.6 24L18.8 17Q18 7 31 7Q43 5.7 45 15L45.4 26L42.6 22L21.2 22Z', 'M20 20.9L20.5 14Q23 8 36 8.5Q43.8 9.5 44 16.8L42.6 22.8L39 19L38 13.6Q32.7 19.5 24 19.4L22.5 23Z', 'M24 13.6Q29 10.3 35 10.8M39.6 12Q42 15 42.1 18.5'),
 ('M20 22V15Q21 8.7 27 8.3H37Q43 9 44 15V22L41.5 18.4H22.5Z', 'M20.2 16L22 12.1L25.6 10.3L27.6 11.4L30.5 9.8L33 11.1L36.4 10.1L40.9 12.4L43.7 16L41.4 17.4L38.9 15.7L36 16.8L33 15.8L30 16.8L27.4 16L24.8 17.3L22 16.7Z', 'M24 13.3H28M31 12.8H35M38 14L40 14.5'),
 ('M19.3 30.8L18.8 17Q18.4 7.6 32 7.8Q45.6 7.6 45.2 17L44.7 30.8L41 28.6L23 28.6Z', 'M20 19V14.8Q22.6 8.8 32 9Q41.4 8.8 44 14.8V20.1L40 19.2L37.5 21.5L34.6 19.7L32 21.8L28.7 19.7L25.3 21L22.9 19.6L21.9 27L19.3 29Z', 'M23 13.4Q32 10 40.9 13.5M24 15.4L23.5 17.7M35 14.4L36 17.8'),
 ('M20.3 23L19.5 15.6L22 9.4L25 10.3L28 6.7L31 8.3L35.3 5.7L36.7 8L41.3 7.2L41.8 10.5L44.4 13.6L43.7 23L41 19L23 19Z', 'M20.7 18.5L21.7 13Q27.2 9.5 33 10.5Q40.5 10.9 43.1 16.5L41.8 20.5L39.7 17.7Q35.2 14.2 32.2 14Q27.4 15.7 23.4 15.4L22 21Z', 'M25 13.2L29 9.5M31.8 12.1L35.4 8.6M37.8 14L39.6 11.7'),
 ('M19.6 27Q16.5 25 18.3 21.5Q15.4 17.5 19.2 15.2Q17.8 10.5 22.5 10Q23.8 6.1 28.2 8Q32 4.5 35.8 8Q40.4 6.5 42 10.3Q46.2 10.4 45 15.1Q49 17.8 45.8 21.5Q47.6 25 44.5 27L41.5 24H22.6Z', 'M20.4 20Q18 17.7 21.2 15.7Q20 12.4 24 12.9Q24.8 9.2 28.3 11.3Q31.2 8.5 34 11.5Q37.7 9.2 39.1 12.9Q43.4 12.6 42.6 16.3Q45.1 18.6 42.9 21.2L40.1 19.3Q37.4 21.4 35.7 18.7Q33 21 30.7 18.8Q28.1 21.6 25.7 19.5L22.3 22.4Z', 'M22 16.4Q23 14.5 24.6 15.7M29 12.9Q30.7 11.7 32.2 13.4M37.6 15.1Q39.5 13.8 40.4 16'),
 ('M42 19Q47.7 18.7 48.4 24.5L46.3 27.8Q50 31.6 47.8 36.2L44.7 34.3L42.7 35L43.3 29.8L41 25.9Z M19.5 24L19 16.4Q18.7 7.3 31 7.5Q43 6.5 44.8 15.5L44.7 24.4L41.6 21H22.6Z', 'M20.4 20.7L20.7 14Q25 8.2 34.8 9Q41.3 9.8 43.8 16.7L42.5 24L39.4 20.6L39.1 13.3Q34.8 20.8 24.4 20L22.2 23Z', 'M24.1 13.8Q28 11.3 34 11.5M43.9 23.6Q46.3 26.3 45 29.8'),
]


def hair(index, part):
    p=PEOPLE[index]
    shape=HAIR[index][part]
    return f'<g id="hair-{part}" fill="{p["hair"]}" stroke="{INK}" stroke-width="1.55" stroke-linejoin="round"><path d="{shape}"/>'+ (f'<path d="{HAIR[index][2]}" fill="none" stroke="{p["light"]}" stroke-width=".8" stroke-linecap="round"/>' if part==1 else '')+'</g>'


def head(index):
    p=PEOPLE[index]
    return f'<g fill="{p["skin"]}" stroke="{INK}" stroke-linejoin="round"><ellipse cx="20.8" cy="24.8" rx="1.45" ry="2.05" stroke-width="1.1"/><ellipse cx="43.2" cy="24.8" rx="1.45" ry="2.05" stroke-width="1.1"/><path d="{p["face"]}" stroke-width="2.35"/></g>'


def features(index, frame=0):
    p=PEOPLE[index]
    phase=(frame+index*5)%36
    closure={11:.25,12:.7,13:1,14:.7,15:.2}.get(phase,0)
    parts=[]
    for side in range(2):
        raw=base.eye(side,1 if index in (1,3) else 0,closure)
        for original,replacement in zip(['#1f332e','#3c8c54','#a2d887'],p['iris']):
            raw=raw.replace(original,replacement)
        cx=26.2 if side==0 else 37.8
        sx,sy=EYE_SCALE*p['eye_x'],EYE_SCALE*p['eye_y']
        parts.append(f'<g transform="translate({cx} 26.4) scale({sx} {sy}) translate({-cx} -26.4)">{raw}</g>')
    brows=[
      'M23.3 22.9Q26.4 21.6 29.1 22.8M34.9 22.8Q37.6 21.6 40.7 22.9',
      'M23.2 22.7L29.1 23.1M34.9 23.1L40.8 22.7',
      'M23.6 22.8Q26.3 21.9 28.9 22.8M35.1 22.8Q37.7 21.9 40.4 22.8',
      'M23.7 22.6L29.1 23.8M34.9 23.8L40.3 22.6',
      'M23.3 23.2Q26.3 21.7 29.2 23M34.8 23Q37.7 21.7 40.7 23.2',
      'M24 22.5L28.9 23.1M35.1 23.1L40 22.5',
    ]
    thickness=[.55,.95,.48,.62,.83,.65][index]
    parts.append(f'<path d="{brows[index]}" fill="none" stroke="{FEATURE}" stroke-width="{thickness}" stroke-linecap="round"/>')
    noses=['M31.8 29.8L32.2 30.4','M31.4 30.1Q32 30.6 32.6 30.1','M31.8 30L32.2 30.4','M31.9 29.3L31.6 30.5H32.4','M31.2 30.2Q32 30.7 32.8 30.2','M31.8 29.7L32.3 30.3']
    mouths=['M30.7 32.1Q32 33 33.3 32.1','M30.5 32.2H33.5','M31.1 32.2Q32 32.6 32.9 32.2','M30.9 32.6H33.1','M30.5 32.4Q32 33.3 33.5 32.4','M31 32.1L33 32.2']
    parts.append(f'<path d="{noses[index]}" fill="none" stroke="#766354" stroke-width=".38" stroke-linecap="round"/>')
    parts.append(f'<path d="{mouths[index]}" fill="none" stroke="#72584e" stroke-width=".47" stroke-linecap="round"/>')
    return '<g id="features">'+''.join(parts)+'</g>'


def document(index, frame=0, helmet=False, portrait=False, part=None, hair_index=None):
    h=index if hair_index is None else hair_index
    content={'body':base.BODY,'head':head(index),'features':features(index,frame),'hair-back':hair(h,0),'hair-front':hair(h,1),'helmet':base.HELMET}.get(part)
    if content is None:
        back,front=hair(h,0),hair(h,1)
        if helmet:
            # Keep hair below the helmet. Crown hair cannot protrude through it.
            mask='<defs><clipPath id="helmet-hair"><rect x="14" y="21" width="38" height="20"/></clipPath></defs>'
            back=mask+f'<g clip-path="url(#helmet-hair)">{back}</g>'
            front=f'<g clip-path="url(#helmet-hair)">{front}</g>'
        content=('' if portrait else base.BODY)+back+head(index)+features(index,frame)+front+(base.HELMET if helmet else '')
    view='14 4 36 36' if portrait else '0 0 64 64'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="{view}">{content}</svg>'


def generate():
    (HERE/'svg').mkdir(parents=True,exist_ok=True)
    for i,p in enumerate(PEOPLE):
        for name,kw in [('portrait',{'portrait':True}),('bare',{}),('helmet',{'helmet':True}),('head-layer',{'part':'head'}),('features-layer',{'part':'features'}),('hair-back-layer',{'part':'hair-back'}),('hair-front-layer',{'part':'hair-front'})]:
            (HERE/f'svg/{p["id"]}-{name}.svg').write_text(document(i,**kw),encoding='utf-8')
    for name in ['body','helmet']:
        (HERE/f'svg/{name}-layer.svg').write_text(document(0,part=name),encoding='utf-8')
    # Two unchanged faces exchange hairstyles as a concrete layering check.
    for i,h in [(0,5),(5,0)]:
        (HERE/f'svg/mix-face{i+1}-hair{h+1}.svg').write_text(document(i,portrait=True,hair_index=h),encoding='utf-8')
    (HERE/'animation.json').write_text(json.dumps([[document(i,frame,portrait=True) for i in range(6)] for frame in range(36)]),encoding='utf-8')
    (HERE/'manifest.json').write_text(json.dumps({'source':'assets/art/vector/friendly_atlas.svg','source_sha256':hashlib.sha256(base.SOURCE.read_bytes()).hexdigest(),'eye_base_scale':EYE_SCALE,'people':PEOPLE,'runtime_modified':False,'approval':'pending','view':'front'},ensure_ascii=False,indent=2),encoding='utf-8')
    print('FACE_COMBINATION_SVG_OK: 6 face/hair combinations; shared original body and helmet')


def compose():
    from PIL import Image,ImageDraw,ImageFont
    bg,paper,ink,ground='#e5e7de','#f5f2e9','#293c37','#7b866f'
    font=ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'
    def label(im,xy,value,size=22,color=ink):
        ImageDraw.Draw(im).text(xy,value,font=ImageFont.truetype(str(font),size),fill=color)
    def paste(im,path,xy,size):
        art=Image.open(path).convert('RGBA').resize((size,size),Image.Resampling.LANCZOS)
        im.alpha_composite(art,xy)
    board=Image.new('RGBA',(1440,1200),bg)
    label(board,(24,18),'RIMGATE · 脸型 × 五官 × 发型',36)
    label(board,(24,73),'眼睛整体缩小约13%；同一画风，六组人物；身体与头盔沿用当前版本。',23)
    for i,p in enumerate(PEOPLE):
        x=18+(i%3)*475;y=125+(i//3)*525
        ImageDraw.Draw(board).rounded_rectangle((x,y,x+454,y+505),radius=18,fill=paper)
        label(board,(x+16,y+16),f'{p["id"]}  {p["name"]}',24)
        label(board,(x+16,y+55),p['detail'],18)
        paste(board,HERE/f'png/{p["id"]}-portrait.png',(x+7,y+88),278)
        label(board,(x+290,y+99),'无头盔',18)
        paste(board,HERE/f'png/{p["id"]}-bare.png',(x+284,y+118),160)
        label(board,(x+290,y+291),'戴原版头盔',18)
        paste(board,HERE/f'png/{p["id"]}-helmet.png',(x+284,y+310),160)
        ImageDraw.Draw(board).rounded_rectangle((x+16,y+375,x+272,y+482),radius=12,fill=ground)
        paste(board,HERE/f'png/{p["id"]}-bare.png',(x+30,y+384),68)
        paste(board,HERE/f'png/{p["id"]}-helmet.png',(x+146,y+378),96)
        label(board,(x+30,y+456),'68px / 96px',13,'#f4f0df')
    label(board,(24,1170),'仅正面审稿 · 脸、五官、前后头发独立制作 · 尚未接入游戏',18)
    board.convert('RGB').save(HERE/'combinations.png')
    frames=[]
    for frame in range(36):
        image=Image.new('RGBA',(960,800),bg)
        label(image,(20,16),'六组面部组合 · 错开眨眼时间',28)
        for i,p in enumerate(PEOPLE):
            x=14+(i%3)*316;y=70+(i//3)*355
            ImageDraw.Draw(image).rounded_rectangle((x,y,x+300,y+338),radius=16,fill=paper)
            label(image,(x+16,y+12),f'{p["id"]} {p["name"]}',19)
            paste(image,HERE/f'frames/{frame:02d}-{i}.png',(x+7,y+52),286)
        frames.append(image.convert('RGB'))
    palette=frames[0].quantize(colors=224,method=Image.Quantize.MEDIANCUT)
    out=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
    out[0].save(HERE/'combinations-animated.gif',save_all=True,append_images=out[1:],duration=100,loop=0,disposal=2,optimize=False)
    mix=Image.new('RGBA',(1100,390),bg)
    label(mix,(20,12),'同一张脸，也可以独立换发型',26)
    for j,(path,title) in enumerate([('01-portrait','01 原配发型'),('mix-face1-hair6','01脸 + 06发型'),('06-portrait','06 原配发型'),('mix-face6-hair1','06脸 + 01发型')]):
        paste(mix,HERE/f'png/{path}.png',(j*275,55),275)
        label(mix,(j*275+20,340),title,20)
    mix.convert('RGB').save(HERE/'hair-swaps.png')
    info=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
    assert info['source_sha256']==hashlib.sha256(base.SOURCE.read_bytes()).hexdigest()
    assert len(set(p['face'] for p in PEOPLE))==6
    for p in PEOPLE:
        for name in ['portrait','bare','helmet','head-layer','features-layer','hair-back-layer','hair-front-layer']:
            pic=Image.open(HERE/f'png/{p["id"]}-{name}.png')
            assert pic.size==(512,512) and pic.mode=='RGBA'
            assert pic.getchannel('A').getextrema()[0]==0
    gif=Image.open(HERE/'combinations-animated.gif');total=0
    for n in range(gif.n_frames):
        gif.seek(n);total+=gif.info['duration']
    assert total==3600 and gif.n_frames>20
    print('FACE_COMBINATION_REVIEW_OK: 6 unique faces, modular hair swaps, 3.6s GIF; runtime unchanged')


if __name__=='__main__':
    generate() if len(sys.argv)<2 or sys.argv[1]=='generate' else compose()
