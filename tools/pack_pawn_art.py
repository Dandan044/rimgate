"""Register/crop AI component atlases for runtime; no combined identity redraws."""
from pathlib import Path
from PIL import Image
import json
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/art/pawns_ai'
SOURCE=OUT/'source'
CELL=256

def row_cuts(file,rows):
    im=Image.open(file).convert('RGBA')
    occupancy=(np.asarray(im.getchannel('A'))>160).sum(axis=1)>20
    starts=np.where(np.diff(np.r_[False,occupancy,False].astype(int))==1)[0]
    ends=np.where(np.diff(np.r_[False,occupancy,False].astype(int))==-1)[0]
    runs=[(int(a),int(b)) for a,b in zip(starts,ends) if b-a>40]
    if len(runs)!=rows: raise ValueError(f'{file}: expected {rows} isolated rows, got {runs}')
    return [0]+[(runs[i][1]+runs[i+1][0])//2 for i in range(rows-1)]+[im.height]

def crop_part(file,col,row,columns,rows,cuts=None):
    im=Image.open(file).convert('RGBA')
    y0,y1=(cuts[row],cuts[row+1]) if cuts else (round(im.height*row/rows),round(im.height*(row+1)/rows))
    tile=im.crop((round(im.width*col/columns),y0,round(im.width*(col+1)/columns),y1))
    # Registration ignores faint alpha outliers; production pixels remain in the crop.
    box=tile.getchannel('A').point(lambda a:255 if a>160 else 0).getbbox()
    if not box: raise ValueError(f'Empty component {file} {col} {row}')
    return tile.crop(box)

def put(page,tile,col,row,stretch=False):
    tile=tile.copy()
    if stretch: tile=tile.resize((232,232),Image.Resampling.LANCZOS)
    else: tile.thumbnail((232,232),Image.Resampling.LANCZOS)
    page.alpha_composite(tile,(col*CELL+(CELL-tile.width)//2,row*CELL+(CELL-tile.height)//2))

def main():
    groups=3 if (SOURCE/'heads-c.png').exists() else 2
    heads=Image.new('RGBA',(CELL*4,CELL*groups*3))
    details=[]
    for group in range(groups):
        src=SOURCE/f'heads-{chr(97+group)}.png'
        height=Image.open(src).height
        cuts=[0,392,720,1046,height] if group==0 else [0,395,738,1060,height]
        if group==2:
            occupancy=(np.asarray(Image.open(src).getchannel('A'))>160).sum(axis=1)>20
            starts=np.where(np.diff(np.r_[False,occupancy,False].astype(int))==1)[0]
            ends=np.where(np.diff(np.r_[False,occupancy,False].astype(int))==-1)[0]
            runs=[(int(a),int(b)) for a,b in zip(starts,ends) if b-a>80]
            if len(runs)!=4: raise ValueError(f'Male head atlas needs four distinct rows: {runs}')
            cuts=[0]+[(runs[i][1]+runs[i+1][0])//2 for i in range(3)]+[height]
        for identity in range(3):
            for direction in range(4):
                part=crop_part(src,identity,direction,3,4,cuts)
                if group==0 and direction==0:
                    # Preserve the exact approved face/fringe in the south-facing view.
                    approved=ROOT/f'docs/art_review/pawn_ai_equipment_v2/png/{identity+1:02d}-base.png'
                    part=Image.open(approved).convert('RGBA').crop((130,132,382,355))
                    part=part.crop(part.getchannel('A').getbbox())
                elif group<2:
                    # Head source slots include a neck stub; the body socket must
                    # own that space once, instead of stacking two neck lengths.
                    part=part.crop((0,0,part.width,round(part.height*0.93)))
                else:
                    part=part.crop((0,0,part.width,round(part.height*0.95)))
                put(heads,part,direction,identity+group*3)
                details.append({'head':identity+group*3,'direction':direction,'source':src.name})
    heads.save(OUT/'heads.png')
    for gear in ['base','light','standard','heavy']:
        src=SOURCE/f'body-{gear}.png'; im=Image.open(src)
        cuts=[0,460,780,im.height]
        body=Image.new('RGBA',(CELL*4,CELL*3))
        for posture in [0,1]:
            for direction in range(4):
                revised=SOURCE/f'crouch-v2-{gear}.png'
                if gear=='base' and posture==1 and revised.exists():
                    part=crop_part(revised,direction,0,4,1)
                    if gear=='base' and direction in [1,3]:
                        part=part.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                else:
                    part=crop_part(src,direction,posture,4,3,cuts)
                put(body,part,direction,posture,True)
        # The AI's north/south prone slots were inconsistent. Register the actual
        # horizontal prone component instead, keeping its neck at the leading end.
        prone=crop_part(src,1,2,4,3,cuts)
        if gear=='base': prone=prone.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        for direction,rotation in enumerate([-90,0,90,180]):
            part=prone.rotate(rotation,expand=True)
            put(body,part,direction,2,True)
        body.save(OUT/f'body_{gear}.png')
    # Garments are independent of the canonical body and of each other. The
    # torso is a rigid socket (standing/kneeling); lower garments own bent legs.
    if (SOURCE/'modular-uniform_top.png').exists():
        shirt=Image.new('RGBA',(CELL*4,CELL*3))
        for posture in [0,1]:
            for direction in range(4):
                put(shirt,crop_part(SOURCE/'modular-uniform_top.png',direction,0,4,1),direction,posture,True)
        back=crop_part(SOURCE/'modular-uniform_top.png',2,0,4,1)
        for direction,rotation in enumerate([180,-90,0,90]):
            put(shirt,back.rotate(rotation,expand=True),direction,2,True)
        shirt.save(OUT/'uniform_top.png')
        trousers=Image.new('RGBA',(CELL*4,CELL*3))
        src=SOURCE/'modular-uniform_legs.png'
        cuts=row_cuts(src,3)
        for posture in [0,1]:
            for direction in range(4):
                put(trousers,crop_part(src,direction,posture,4,3,cuts),direction,posture,True)
        # Prone feet/waist are registered from one coherent axis, as for body.
        prone=crop_part(src,1,2,4,3,cuts)
        for direction,rotation in enumerate([-90,0,90,180]):
            put(trousers,prone.rotate(rotation,expand=True),direction,2,True)
        trousers.save(OUT/'uniform_legs.png')
        for gear,row in [('light',0),('standard',1),('heavy',2)]:
            armor=Image.new('RGBA',(CELL*4,CELL*3))
            src=SOURCE/'modular-torso_gear.png'
            cuts=row_cuts(src,3)
            for posture in [0,1]:
                for direction in range(4):
                    put(armor,crop_part(src,direction,row,4,3,cuts),direction,posture,True)
            back=crop_part(src,2,row,4,3,cuts)
            for direction,rotation in enumerate([180,-90,0,90]):
                put(armor,back.rotate(rotation,expand=True),direction,2,True)
            armor.save(OUT/f'vest_{gear}.png')
    # Rear long hair stays a separate occluding component.
    hair=Image.open(ROOT/'docs/art_review/pawn_ai_equipment_v2/hair.png').convert('RGBA')
    hair=hair.crop((125,28,525,603))
    hair=hair.crop(hair.getchannel('A').point(lambda a:255 if a>160 else 0).getbbox())
    hair.save(OUT/'long_hair.png')
    if (SOURCE/'helmets.png').exists():
        helmet=Image.new('RGBA',(CELL*4,CELL*2))
        for row in range(2):
            for direction in range(4): put(helmet,crop_part(SOURCE/'helmets.png',direction,row,4,2),direction,row,True)
        helmet.save(OUT/'helmets.png')
    (OUT/'manifest.json').write_text(json.dumps({'cell':CELL,'directions':['south','east','north','west'],'postures':['standing','crouching','prone'],'identities':groups*3,'male_identities':[6,7,8] if groups==3 else [],'body_types':['slender','broad','rounded'],'runtime_body':'body_base.png','garment_layers':['uniform_top','uniform_legs','vest_light','vest_standard','vest_heavy'],'legacy_outfit_bodies_reference_only':True,'heads':details,'original_atlases_preserved':True,'shared_weapon_mount_calibrated':True,'balance_ai_cover_rules_modified':False},ensure_ascii=False,indent=2),encoding='utf-8')
    print('PAWN_COMPONENTS_PACKED:',groups*12,'head views, 48 body/pose views')

if __name__=='__main__': main()
