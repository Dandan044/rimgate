"""Label/crop actual exported-game recordings, without redrawing game frames."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess
import json
import hashlib

ROOT=Path(__file__).resolve().parents[1]
EVIDENCE=ROOT/'build/pawn_art_evidence'
FF=ROOT/'.tools/video_runtime/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'

def ffmpeg(*args):
    subprocess.run([str(FF),'-y',*map(str,args),'-hide_banner','-loglevel','error'],check=True)

def clip(name,start,duration,source='fit-layered-final.avi',crop='560:400:360:240',fps=12):
    graph=f'crop={crop},fps={fps},split[a][b];[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a'
    ffmpeg('-ss',start,'-t',duration,'-i',EVIDENCE/source,'-filter_complex',graph,'-loop','0',EVIDENCE/name)

def main():
    clip('holding-v2.gif',3,7)
    clip('crouch-directions-v2.gif',10,14,fps=10)
    clip('movement-layered-v2.gif',0.4,11.2,source='layered-battle-final.avi',crop='800:440:250:230')
    clip('postures-layered-v2.gif',11,10.5,source='layered-battle-final.avi',crop='800:460:250:230')
    font=ImageFont.truetype(str(ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'),22)
    small=ImageFont.truetype(str(ROOT/'assets/fonts/NotoSansCJKsc-Regular.otf'),17)
    frames=[]
    labels=[(31,'基础身体：白T恤＋短裤'),(33,'单独加上标准防弹衣'),(35,'再叠加独立上衣、裤装'),(37,'身体不变，只换胸挂'),(39,'身体不变，换重甲与头盔')]
    for i,(time,title) in enumerate(labels):
        path=EVIDENCE/f'layer-proof-{i}.png'
        ffmpeg('-ss',time,'-i',EVIDENCE/'fit-layered-final.avi','-frames:v','1',path)
        crop=Image.open(path).convert('RGB').crop((510,340,710,525)).resize((400,370),Image.Resampling.LANCZOS)
        page=Image.new('RGB',(480,490),'#202d29'); draw=ImageDraw.Draw(page)
        draw.text((20,12),'同一身体 / 装备独立叠加',font=font,fill='#e5efdc')
        page.paste(crop,(40,54))
        draw.text((20,432),title,font=font,fill='#e5efdc')
        draw.text((20,467),'导出demo真实画面裁切 · 受控美术审阅',font=small,fill='#a9bbad')
        frames.append(page)
    frames[0].save(EVIDENCE/'independent-layers-v2.gif',save_all=True,append_images=frames[1:],duration=[1800]*5,loop=0,disposal=2,optimize=True)
    manifest={'kind':'local modular pawn art preview','identities':9,'friendly_roster':'3 male / 3 female','four_directions':True,'postures':['standing','one-knee crouching','prone'],'classic_preserved':True,'runtime_body_atlases':1,'independent_garments':['top','legs (currently with boots)','vest','helmet'],'shared_rifle_mount_and_projectile_origin_calibrated':True,'balance_ai_cover_rules_modified':False,'visual_report':str(EVIDENCE/'layered-battle-final-report.json'),'controlled_fitting_report':str(EVIDENCE/'fit-layered-final-report.json'),'files':{name:hashlib.sha256((ROOT/'build/pawn_art_demo'/name).read_bytes()).hexdigest() for name in ['Rimgate.exe','Rimgate.pck']}}
    (ROOT/'build/pawn_art_demo/preview_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for name in ['holding-v2.gif','crouch-directions-v2.gif','independent-layers-v2.gif','movement-layered-v2.gif','postures-layered-v2.gif']:
        im=Image.open(EVIDENCE/name)
        print(name, im.size,im.n_frames,'frames', (EVIDENCE/name).stat().st_size,'bytes')
        im.seek(min(40,im.n_frames-1)); im.convert('RGB').save(EVIDENCE/f'{Path(name).stem}-verified.png')

if __name__=='__main__': main()
