"""Page layout for reviewing the original generated layers and SVG assemblies."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent
FONT=HERE.parents[2]/'assets/fonts/NotoSansCJKsc-Regular.otf'
# docs/art_review/<folder> -> repository root is parents[2].
def font(n): return ImageFont.truetype(str(FONT),n)
page=Image.new('RGB',(1800,1260),'#e8ebe3'); d=ImageDraw.Draw(page)
d.text((30,22),'RIMGATE / AI独立部件 · 组装审阅',font=font(38),fill='#303c3a')
d.text((30,77),'四类部件分别生成；下列人物直接叠放原部件像素，未重新生成人物。',font=font(24),fill='#52635d')
titles=['01 纤细 / 长直发','02 宽肩 / 短发','03 圆润 / 波浪发','04 混搭 / 五官01＋脸03＋发02＋体型03']
for i,title in enumerate(titles):
    x=20+i*445
    d.rounded_rectangle((x,128,x+430,759),radius=18,fill='#f8f5eb')
    d.text((x+16,145),title,font=font(19 if i==3 else 25),fill='#35433e')
    im=Image.open(HERE/f'assembly-png/{i+1:02d}-assembled.png').convert('RGBA')
    im.thumbnail((350,570),Image.Resampling.LANCZOS)
    page.paste(im,(x+(430-im.width)//2,181),im)
files=[('五官 / 独立透明叠层','features.png'),('脸型 / 椭圆、方颌、圆颊','faces-v2.png'),('发型 / 后发＋前发','hair-v1.png'),('体型 / 无手臂、双腿靠拢','bodies.png')]
for i,(title,file) in enumerate(files):
    x=20+i*445
    d.rounded_rectangle((x,781,x+430,1190),radius=18,fill='#f8f5eb')
    d.text((x+16,796),title,font=font(24),fill='#35433e')
    d.rounded_rectangle((x+15,842,x+415,1168),radius=12,fill='#cdd7c7')
    im=Image.open(HERE/file).convert('RGBA'); im.thumbnail((390,305),Image.Resampling.LANCZOS)
    page.paste(im,(x+215-im.width//2,1005-im.height//2),im)
d.text((28,1210),'适配验证稿：AI锚点需逐部件校准；头发仍有半透明光晕，尚不可直接作为正式贴图入库。',font=font(23),fill='#6d5748')
page.save(HERE/'ai-review.png')
print('AI_REVIEW_PAGE_OK')
