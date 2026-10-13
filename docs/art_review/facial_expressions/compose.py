from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
FONT = ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'
INFO = json.loads((HERE/'source.json').read_text(encoding='utf-8'))
BG = '#e7e8df'
PAPER = '#f3f2e9'
INK = '#293c37'
GROUND = '#7a856e'


def text(canvas, pos, value, size=24, color=INK):
    ImageDraw.Draw(canvas).text(pos, value, fill=color, font=ImageFont.truetype(str(FONT), size))


def paste(canvas, path, xy, size=256):
    pic = Image.open(path).convert('RGBA').resize((size,size), Image.Resampling.LANCZOS)
    canvas.alpha_composite(pic, xy)


def board():
    canvas = Image.new('RGBA',(1420,1270),BG)
    text(canvas,(35,22),'RIMGATE · 参考图方向：半垂眼睑与彩色大虹膜',34)
    text(canvas,(35,80),'身体、头盔、配色直接沿用当前游戏；只叠加眉眼与嘴部。',22)
    for col, label in enumerate(['当前原版']+INFO['styles']):
        x=35+col*345
        text(canvas,(x+14,135),label,25)
        for state in range(4):
            y=185+state*260
            ImageDraw.Draw(canvas).rounded_rectangle((x,y,x+325,y+245),radius=18,fill=PAPER)
            path=HERE/'png'/('original.png' if col==0 else f'{col-1}-{state}.png')
            paste(canvas,path,(x+40,y-18),245)
            text(canvas,(x+18,y+208),INFO['states'][state],18)
    text(canvas,(35,1240),'正面表情示例 · 尚未接入游戏 · 每种状态都有独立透明脸部图层',16)
    canvas.convert('RGB').save(HERE/'reference-expressions.png')


def animated():
    frames=[]
    for frame in range(48):
        state=frame//12
        canvas=Image.new('RGBA',(1080,650),BG)
        text(canvas,(28,18),'参考图方向 · 粗眼线 / 半垂眼睑 / 彩色虹膜',28)
        text(canvas,(28,65),INFO['states'][state],24)
        for style, label in enumerate(INFO['styles']):
            x=22+style*355
            ImageDraw.Draw(canvas).rounded_rectangle((x,112,x+330,620),radius=18,fill=PAPER)
            text(canvas,(x+20,130),label,25)
            paste(canvas,HERE/f'frames/{style}-{frame:02d}.png',(x+5,175),320)
            # Actual renderer uses a 68px square for an ordinary pawn.
            ImageDraw.Draw(canvas).rounded_rectangle((x+18,490,x+312,604),radius=12,fill=GROUND)
            paste(canvas,HERE/f'frames/{style}-{frame:02d}.png',(x+26,510),68)
            paste(canvas,HERE/f'frames/{style}-{frame:02d}.png',(x+138,500),96)
            text(canvas,(x+16,580),'68px游戏尺寸 / 96px放大',15,'#f0efdd')
        frames.append(canvas.convert('RGB'))
    palette=frames[0].quantize(colors=192,method=Image.Quantize.MEDIANCUT)
    images=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    images[0].save(HERE/'reference-animated.gif',save_all=True,append_images=images[1:],duration=110,loop=0,disposal=2,optimize=False)
    for style, label in enumerate(INFO['styles']):
        small=[]
        for frame in range(48):
            canvas=Image.new('RGBA',(320,350),BG)
            paste(canvas,HERE/f'frames/{style}-{frame:02d}.png',(32,15))
            text(canvas,(15,280),label,22)
            text(canvas,(15,316),INFO['states'][frame//12],17)
            small.append(canvas.convert('RGB'))
        small[0].save(HERE/f'reference-{chr(65+style)}.gif',save_all=True,append_images=small[1:],duration=110,loop=0,disposal=2,optimize=False)


if __name__=='__main__':
    assert hashlib.sha256((ROOT/INFO['source']).read_bytes()).hexdigest()==INFO['sha256'], 'Runtime pawn was modified'
    board()
    animated()
    gif=Image.open(HERE/'reference-animated.gif')
    # GIF writers merge identical static frames while preserving their duration.
    duration=0
    for frame in range(gif.n_frames):
        gif.seek(frame)
        duration+=gif.info.get('duration',0)
    assert gif.n_frames >= 20 and duration == 48*110
    print(f'FACE_REVIEW_OK: static board, {gif.n_frames} GIF frames / {duration}ms, 3 individual GIFs; runtime original unchanged')
