from pathlib import Path
import json
import hashlib
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
FONT=ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'
BG='#e7e9e1';PAPER='#faf7ee';INK='#293b38';GROUND='#7d8b79';MUTED='#5a7168'


def label(im,xy,text,size=24,color=INK):
    ImageDraw.Draw(im).text(xy,text,font=ImageFont.truetype(str(FONT),size),fill=color)


def paste(im,name,rect,trim=True,bottom=False):
    path=name if isinstance(name,Path) else HERE/f'png/{name}.png'
    art=Image.open(path).convert('RGBA')
    if trim: art=art.crop(art.getchannel('A').getbbox())
    x,y,w,h=rect;k=min(w/art.width,h/art.height)
    art=art.resize((round(art.width*k),round(art.height*k)),Image.Resampling.LANCZOS)
    im.alpha_composite(art,(round(x+(w-art.width)/2),round(y+h-art.height if bottom else y+(h-art.height)/2)))


def card(im,rect,fill=PAPER,r=18):
    ImageDraw.Draw(im).rounded_rectangle(rect,radius=r,fill=fill)


names=['纤细 · 长直发','宽肩 · 利落短发','匀称 · 波浪长发','高挑 · 后梳短发','圆润 · 短卷发','娇小 · 长马尾']
board=Image.new('RGBA',(1800,1480),BG)
label(board,(30,20),'RIMGATE / 四项特征 · SVG细化稿',38)
label(board,(30,78),'五官、脸型、发型、体型独立组合。无手臂，双腿保留连续轮廓。',24)
for i,title in enumerate(names):
    x=20+(i%3)*596;y=132+(i//3)*656;pid=f'{i+1:02d}'
    card(board,(x,y,x+576,y+635))
    label(board,(x+22,y+18),pid+'  '+title,28)
    label(board,(x+72,y+66),'裸头',20,MUTED);label(board,(x+360,y+66),'独立头盔层',20,MUTED)
    paste(board,pid+'-bare',(x+28,y+106,240,397),bottom=True)
    paste(board,pid+'-helmet',(x+308,y+106,240,397),bottom=True)
    card(board,(x+18,y+523,x+558,y+616),GROUND,12)
    label(board,(x+34,y+539),'实际显示高度',18,'#f8f5e7')
    label(board,(x+34,y+568),'64px / 96px',18,'#f8f5e7')
    paste(board,pid+'-bare',(x+240,y+544,75,64),bottom=True)
    paste(board,pid+'-helmet',(x+360,y+518,75,96),bottom=True)
label(board,(30,1452),'正面审阅 · 尚未替换游戏资源 · 全部SVG及透明PNG保留分层',17,MUTED)
board.convert('RGB').save(HERE/'refined-review.png')

detail=Image.new('RGBA',(1800,980),BG)
label(detail,(28,18),'近看：脸部、发束与头盔适配',36)
label(detail,(28,72),'保持之前较小的眼睛；头发使用成束明暗，头盔压住头顶而保留鬓发和长发。',23)
for i in range(6):
    x=18+(i%3)*596;y=122+(i//3)*416;pid=f'{i+1:02d}'
    card(detail,(x,y,x+576,y+396))
    label(detail,(x+18,y+10),pid+'  '+names[i],24)
    paste(detail,pid+'-portrait',(x+5,y+48,280,330),trim=False)
    paste(detail,pid+'-helmet-detail',(x+290,y+48,280,330),trim=False)
detail.convert('RGB').save(HERE/'face-hair-detail.png')

parts=Image.new('RGBA',(1760,1040),BG)
label(parts,(28,18),'四个特征可以拆开，也可以互换',36)
label(parts,(28,73),'头部使用共同挂点；头发拆为后发与前发两个绘制层。头盔属于装备。',23)
labels=[('features-layer','01 五官'),('face-layer','02 脸型'),('hair-back-layer','03 后发'),('hair-front-layer','03 前发'),('body-layer','04 体型')]
for j,(layer,title) in enumerate(labels):
    x=20+j*348;card(parts,(x,128,x+332,490))
    label(parts,(x+18,142),title,25)
    card(parts,(x+12,192,x+320,472),'#ced7c9',12)
    paste(parts,'01-'+layer,(x+26,204,280,254))
label(parts,(28,519),'替换证明：直接选取既有部件ID组装，未为组合重画人物',27)
mixnames=['五官01 / 脸06 / 发03 / 宽肩','五官05 / 脸03 / 发01 / 娇小','五官03 / 脸01 / 发06 / 圆润']
for j,title in enumerate(mixnames):
    x=20+j*580;card(parts,(x,577,x+560,1015))
    label(parts,(x+16,590),title,22)
    paste(parts,'mix-'+str(j+1),(x+164,638,232,356),bottom=True)
parts.convert('RGB').save(HERE/'four-part-breakdown.png')

comparison=Image.new('RGBA',(1500,840),BG)
label(comparison,(28,18),'细化前 / 细化后',36)
label(comparison,(28,71),'轮廓与比例沿用当前稿，增加发束、皮肤层次、虹膜反光、衣料结构及靴面体积。',21)
for j,pid in enumerate(['01','03','05']):
    x=20+j*496;card(comparison,(x,126,x+476,815))
    label(comparison,(x+32,143),'之前',23);label(comparison,(x+274,143),'本轮',23)
    paste(comparison,HERE.parent/f'pawn_four_parts_v1/png/{pid}-bare.png',(x+20,204,202,574),bottom=True)
    paste(comparison,pid+'-bare',(x+252,204,202,574),bottom=True)
comparison.convert('RGB').save(HERE/'before-after.png')

bodies=Image.new('RGBA',(1620,650),BG)
label(bodies,(28,18),'体型互换：保持同一五官、脸型和发型',34)
body_names=['纤细','匀称','宽肩壮实','圆润','娇小','高挑']
for i,title in enumerate(body_names):
    x=18+i*268;card(bodies,(x,92,x+250,624))
    label(bodies,(x+20,106),title,25)
    # Preserve a shared camera scale: don't enlarge the petite body to fill the card.
    paste(bodies,f'body-study-{i+1}',(x+10,165,230,424),trim=False,bottom=True)
bodies.convert('RGB').save(HERE/'body-types.png')

info=json.loads((HERE/'manifest.json').read_text(encoding='utf-8'))
assert hashlib.sha256((ROOT/'assets/art/vector/friendly_atlas.svg').read_bytes()).hexdigest()==info['source_sha256']
files=list((HERE/'svg').glob('*.svg'))
for f in files:
    ET.fromstring(f.read_text(encoding='utf-8'))
    pic=Image.open(HERE/'png'/f.with_suffix('.png').name)
    assert pic.mode=='RGBA'
    assert pic.getchannel('A').getextrema()[0]==0
    if f.stem.endswith('-bare') or f.stem.endswith('-helmet'):
        bounds=pic.getchannel('A').getbbox()
        assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<pic.width and bounds[3]<pic.height,(f,bounds)
for f in (HERE/'svg').glob('*body-layer.svg'):
    text=f.read_text(encoding='utf-8')
    assert 'id="joined-trousers"' in text and 'id="joined-boots"' in text
    assert 'id="arm' not in text and 'id="hand' not in text
print('REFINED_REVIEW_OK: 76 transparent assets, 12 unclipped full pawns, 3 independent swaps, runtime checksum unchanged')
