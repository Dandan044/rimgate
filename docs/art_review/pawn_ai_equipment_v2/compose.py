"""Review-page layout. All component art comes from the saved source atlases."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
import hashlib
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
FONT=ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'
def font(n): return ImageFont.truetype(str(FONT),n)
def put(page,file,area,crop=None):
    im=Image.open(file).convert('RGBA')
    if crop: im=im.crop(crop)
    x,y,w,h=area; im.thumbnail((w,h),Image.Resampling.LANCZOS)
    page.paste(im,(round(x+(w-im.width)/2),round(y+(h-im.height)/2)),im)

def equipment():
    page=Image.new('RGB',(1800,1660),'#e8ebe3'); d=ImageDraw.Draw(page)
    d.text((30,20),'RIMGATE / AI风格修订 · 基础身体与独立装备',font=font(36),fill='#303e37')
    d.text((30,76),'同一行保留五官、脸型、发型和体型，只更换装备层；无手臂、双腿靠拢。',font=font(24),fill='#5a6d62')
    labels=[('base','基础 / 白T恤＋短裤'),('light','轻装 / 胸挂＋作战服'),('standard','标准 / 防弹衣＋头盔'),('heavy','重装 / 厚甲＋重型盔')]
    names=['01 纤细 / 长直发','02 宽肩 / 短发','03 圆润 / 波浪发']
    for col,(_,label) in enumerate(labels):
        d.text((35+col*445,120),label,font=font(26),fill='#303e37')
    for row,name in enumerate(names):
        y=169+row*474
        for col,(kit,_) in enumerate(labels):
            x=20+col*445
            d.rounded_rectangle((x,y,x+430,y+455),radius=18,fill='#faf6ec')
            d.text((x+15,y+10),name,font=font(21),fill='#6c7b70')
            put(page,HERE/f'png/{row+1:02d}-{kit}.png',(x+20,y+39,390,404),(115,108,397,758))
    d.text((28,1614),'正面静态审稿；装备与人物分层，尚未替换游戏内素材。',font=font(23),fill='#647366')
    page.save(HERE/'equipment-review.png')

def heads():
    page=Image.new('RGB',(1500,540),'#e8ebe3'); d=ImageDraw.Draw(page)
    d.text((28,15),'额头与刘海修订 / 同一张脸、同一组五官',font=font(34),fill='#303e37')
    d.text((28,67),'降低发际线观感、补足中间刘海、收紧头顶比例；保留原本的眼睛和表情。',font=font(23),fill='#627363')
    for i in range(3):
        x=15+i*495
        d.rounded_rectangle((x,111,x+480,504),radius=17,fill='#faf6ec')
        d.text((x+12,122),['长直发','短发','波浪发'][i],font=font(25),fill='#344239')
        d.text((x+62,168),'修改前',font=font(21),fill='#7e7264')
        d.text((x+302,168),'修改后',font=font(21),fill='#496d58')
        old=HERE.parent/f'pawn_refined_ai_v1/assembly-png/{i+1:02d}-assembled.png'
        put(page,old,(x+10,205,220,275),(120,105,392,370))
        put(page,HERE/f'png/{i+1:02d}-base.png',(x+250,205,220,275),(120,105,392,370))
    page.save(HERE/'hair-before-after.png')

def layers():
    page=Image.new('RGB',(1600,740),'#e8ebe3'); d=ImageDraw.Draw(page)
    d.text((28,19),'换装分层 / 人物基础与装备分离',font=font(34),fill='#303e37')
    d.text((28,70),'当前衣装以套装层展示；头盔独立，可与不同衣装组合。',font=font(24),fill='#627363')
    cells=[('基础身体 / 三体型','base-bodies.png'),('轻装套装 / 三体型','light-kit.png'),('标准套装 / 三体型','standard-kit.png'),('重装套装 / 三体型','heavy-kit.png')]
    for i,(label,file) in enumerate(cells):
        x=15+i*395
        d.rounded_rectangle((x,118,x+380,680),radius=16,fill='#faf6ec')
        d.text((x+14,132),label,font=font(23),fill='#344239')
        put(page,HERE/file,(x+10,172,360,470))
    page.save(HERE/'body-equipment-layers.png')

def verify():
    checks=[]
    for svg in sorted((HERE/'svg').glob('*.svg')):
        ET.parse(svg)
        im=Image.open(HERE/'png'/svg.with_suffix('.png').name)
        box=im.getchannel('A').getbbox()
        assert box and box[0]>0 and box[1]>0 and box[2]<im.width and box[3]<im.height
        checks.append({'file':svg.name,'size':im.size,'alpha_bbox':box})
    sources=[]
    for file in sorted(HERE.glob('*.png')):
        if file.name in ['equipment-review.png','hair-before-after.png','body-equipment-layers.png']: continue
        im=Image.open(file); a=im.getchannel('A'); h=a.histogram()
        sources.append({'file':file.name,'size':im.size,'mode':im.mode,'alpha_range':a.getextrema(),'transparent_fraction':round(h[0]/(im.width*im.height),5)})
    sha=hashlib.sha256((ROOT/'assets/art/vector/friendly_atlas.svg').read_bytes()).hexdigest()
    assert sha=='94bc97e1ddaaa4b67496f4d5835ddf331e9e92a458dedf03f53098fd3ac83abf'
    (HERE/'verification.json').write_text(json.dumps({'assemblies':checks,'sources':sources,'runtime_sha256':sha,'runtime_unchanged':True},ensure_ascii=False,indent=2),encoding='utf-8')
    print('VERIFIED',len(checks),'SVG/PNG assemblies; runtime unchanged')

if __name__=='__main__':
    equipment();heads();layers();verify()
