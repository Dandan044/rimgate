"""Code-native SVG component layers; does not edit AI source pixels."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/art/v3'
OUT.mkdir(parents=True,exist_ok=True)

def svg(body,w=1024,h=768):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs><linearGradient id="skin" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="#ffebd1"/><stop offset=".6" stop-color="#f9d7ba"/><stop offset="1" stop-color="#e7b298"/></linearGradient><linearGradient id="metal" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="#9ca183"/><stop offset=".4" stop-color="#6e785d"/><stop offset="1" stop-color="#3d4b3e"/></linearGradient><linearGradient id="steel" x1="0" y1="0" x2=".5" y2="1"><stop stop-color="#9b9c8d"/><stop offset=".35" stop-color="#555c57"/><stop offset="1" stop-color="#252e2c"/></linearGradient><radialGradient id="cheek"><stop stop-color="#eaaa97" stop-opacity=".40"/><stop offset="1" stop-color="#eaaa97" stop-opacity="0"/></radialGradient></defs>{body}</svg>'

def group(x,y,body):return f'<g transform="translate({x} {y})">{body}</g>'
faces=[]
for shape in range(3):
    chin=["Q172 226 128 236 Q82 226 51 191","Q181 227 145 233 L111 233 Q74 226 51 191","Q191 222 128 236 Q66 224 43 187"][shape]
    for d in range(4):
        if d==0:
            face=f'<path d="M51 152 Q43 88 83 73 Q128 52 173 75 Q213 98 207 156 L205 191 {chin} Z" fill="url(#skin)" stroke="#5b4038" stroke-width="2.7"/><ellipse cx="47" cy="169" rx="12" ry="20" fill="url(#skin)" stroke="#66483a" stroke-width="2.2"/><ellipse cx="209" cy="169" rx="12" ry="20" fill="url(#skin)" stroke="#66483a" stroke-width="2.2"/><ellipse cx="73" cy="192" rx="24" ry="13" fill="url(#cheek)"/><ellipse cx="184" cy="192" rx="24" ry="13" fill="url(#cheek)"/>'
        elif d==2:
            face='<path d="M52 126 Q55 67 128 64 Q205 68 207 126 L198 197 Q164 231 128 235 Q89 224 58 197Z" fill="url(#skin)" stroke="#604438" stroke-width="2.7"/>'
        else:
            body='<path d="M83 116 Q97 67 158 80 Q206 88 208 143 L222 166 L210 176 Q217 207 194 222 Q163 239 124 224 L89 197Z" fill="url(#skin)" stroke="#5b4038" stroke-width="2.7"/><ellipse cx="99" cy="168" rx="13" ry="20" fill="url(#skin)" stroke="#66483a" stroke-width="2.2"/><path d="M97 158 Q108 162 98 177" fill="none" stroke="#cb967e" stroke-width="2"/><ellipse cx="188" cy="195" rx="19" ry="11" fill="url(#cheek)"/>'
            face=f'<g transform="translate(256 0) scale(-1 1)">{body}</g>' if d==3 else body
        faces.append(group(d*256,shape*256,face))
(OUT/'faces.svg').write_text(svg(''.join(faces)),encoding='utf8')
colors=['#4c7a80','#8f733e','#7b638d','#597b5c','#4b6470','#92723e']
expressions=['natural','blink','aim','hurt','panic','closed']
for expression in expressions:
    pieces=[]
    for f,color in enumerate(colors):
        male=f>=3
        browwidth=4.3 if male else 2.6
        for d in range(4):
            if d==2:continue
            eyes=''
            for eye in range(2 if d==0 else 1):
                cx=[86,169][eye] if d==0 else 182
                cy=170
                eye_w=33 if not male else 32
                eye_h=23 if not male else 19
                if expression=='aim':eye_h*=.63
                if expression=='panic':eye_h*=1.2
                if expression in ('blink','closed','hurt'):
                    curve=6 if expression!='hurt' else -7
                    eyes+=f'<path d="M{cx-eye_w/2} {cy} Q{cx} {cy+curve} {cx+eye_w/2} {cy}" fill="none" stroke="#3b3430" stroke-width="3.1" stroke-linecap="round"/>'
                else:
                    top=cy-eye_h/2;bot=cy+eye_h/2
                    eyes+=f'<path d="M{cx-eye_w/2-2} {top+2} Q{cx} {top-5} {cx+eye_w/2+2} {top+1} L{cx+eye_w/2-1} {bot-1} Q{cx} {bot+4} {cx-eye_w/2+1} {bot-1}Z" fill="#f8f2e7" stroke="#3e3532" stroke-width="2.2"/><ellipse cx="{cx+1}" cy="{cy+1}" rx="{eye_w*.29}" ry="{eye_h*.52}" fill="{color}"/><path d="M{cx-eye_w*.22} {cy+eye_h*.25} Q{cx} {cy+eye_h*.70} {cx+eye_w*.24} {cy+eye_h*.25}" fill="none" stroke="#d7ddad" stroke-width="2.6" opacity=".63"/><ellipse cx="{cx+1}" cy="{cy}" rx="3.6" ry="{eye_h*.42}" fill="#263738"/><ellipse cx="{cx-3}" cy="{cy-eye_h*.20}" rx="3" ry="4" fill="#fffdf4"/><path d="M{cx-eye_w/2-3} {top+2} Q{cx} {top-4} {cx+eye_w/2+3} {top+1}" fill="none" stroke="#382f2d" stroke-width="{4.2 if not male else 3.3}" stroke-linecap="round"/>'
                brow_y=145 if expression!='panic' else 139
                offset=4 if expression=='aim' else (-4 if expression=='panic' else 0)
                eyes+=f'<path d="M{cx-eye_w/2} {brow_y+offset} Q{cx} {brow_y-5} {cx+eye_w/2} {brow_y-offset}" fill="none" stroke="#55453a" stroke-width="{browwidth}" stroke-linecap="round"/>'
            nose_x=128 if d==0 else 211
            eyes+=f'<path d="M{nose_x-1} 187 l2 4" stroke="#ae7967" stroke-width="1.8" fill="none" stroke-linecap="round"/>'
            mouth_x=128 if d==0 else 200
            if expression=='panic':eyes+=f'<ellipse cx="{mouth_x}" cy="211" rx="5" ry="6" fill="#7d4b43"/>'
            elif expression=='hurt':eyes+=f'<path d="M{mouth_x-7} 211 q7 -4 14 0" stroke="#8b584c" stroke-width="2" fill="none"/>'
            else:eyes+=f'<path d="M{mouth_x-6} 211 q6 {2 if expression=="natural" else 0} 12 0" stroke="#80594d" stroke-width="1.9" fill="none" stroke-linecap="round"/>'
            if d==3:eyes=f'<g transform="translate(256 0) scale(-1 1)">{eyes}</g>'
            pieces.append(group(d*256,f*256,eyes))
    (OUT/f'features_{expression}.svg').write_text(svg(''.join(pieces),1024,1536),encoding='utf8')
# Independent military props. Canonical barrel endpoints are explicit.
props={
'mg_base':('<path d="M12 20 L28 8 L97 8 L116 25 L115 100 L95 119 L28 119 L10 100Z" fill="#aaa998" stroke="#3a4638" stroke-width="2.5"/><path d="M17 26 L32 13 L94 13 L110 29 L108 96 L92 111 L31 111 L18 96Z" fill="url(#metal)" stroke="#4c5945" stroke-width="2"/><circle cx="64" cy="63" r="32" fill="#3e4a3a" stroke="#acaf8d" stroke-width="3"/><circle cx="64" cy="63" r="24" fill="url(#steel)" stroke="#27362f" stroke-width="2"/><path d="M24 32 l13 -9 M23 39 l11 -6 M86 99 l14 -7" stroke="#c8c7aa" stroke-width="2" opacity=".3"/>'+''.join(f'<circle cx="{x}" cy="{y}" r="4" fill="#777f65" stroke="#303f34" stroke-width="1.5"/><path d="M{x-2} {y-1} l4 0" stroke="#c4c2a2" stroke-width="1"/>' for x,y in [(25,27),(102,28),(24,99),(103,99)]),128,128),
'mg_gun':('<path d="M7 8 L27 8 L31 11 L39 11 L42 13 L59 13 L61 14 L61 18 L59 19 L42 19 L39 21 L28 21 L24 25 L7 25 L4 22 L4 11Z" fill="url(#steel)" stroke="#252f2b" stroke-width="1.1"/><path d="M13 10 H28 V22 H13Z" fill="url(#metal)" stroke="#2e3b30" stroke-width=".8"/><rect x="29" y="12" width="12" height="8" rx="1.4" fill="#4b544c"/><path d="M42 14 H60 M13 11 H27" stroke="#b3b4a2" stroke-width="1"/>'+''.join(f'<circle cx="{x}" cy="16" r="1" fill="#202b27"/>' for x in [43,47,51,55])+'<path d="M18 9 V6 H22 V10 M20 24 V28 H26 V22" fill="none" stroke="#343e35" stroke-width="2"/><path d="M4 15 L12 15" stroke="#c9b371" stroke-width="3"/>',64,32),
'rifle':('<path d="M7 28 L21 28 L24 25 L39 25 L42 29 L57 29 L59 30 L59 34 L42 34 L37 37 L30 37 L27 44 L22 43 L24 36 L15 36 L7 39Z" fill="url(#steel)" stroke="#27322d" stroke-width="1.2"/><path d="M8 29 L21 29 L17 35 L8 37Z" fill="#6a7557"/><rect x="24" y="27" width="13" height="8" rx="1" fill="#69775d"/><path d="M27 25 V22 H34 V25 M42 30 H58" stroke="#9caa94" stroke-width="1" fill="none"/><path d="M33 36 l-1 8 l6 0 l0 -9" fill="#4d5947" stroke="#26382b" stroke-width="1"/>',64,64),
'mortar_base':('<ellipse cx="64" cy="78" rx="49" ry="34" fill="#334234" opacity=".25"/><path d="M29 21 L98 21 L111 96 L90 113 L30 111 L16 93Z" fill="url(#metal)" stroke="#2f3d31" stroke-width="3"/><path d="M34 32 L92 32 L100 91 L85 101 L36 100 L27 87Z" fill="#68745b" stroke="#a0a48a" stroke-width="1.8"/><ellipse cx="64" cy="65" rx="25" ry="23" fill="url(#steel)" stroke="#24332b" stroke-width="2"/>',128,128),
'mortar_gun':('<path d="M6 12 L19 11 L24 13 L28 12 L54 12 L58 13 L58 19 L54 20 L28 20 L24 19 L19 23 L6 22Z" fill="url(#metal)" stroke="#28382c" stroke-width="1.3"/><path d="M26 13 H55 M8 14 H20" stroke="#bdc1a3" stroke-width="1.1"/><ellipse cx="56" cy="16" rx="2" ry="4" fill="#28352c"/><path d="M17 20 L8 29 M24 20 L32 28" stroke="#303f33" stroke-width="2"/>',64,32),
'ammo_box':('<path d="M8 12 L51 9 L59 17 L57 48 L13 53 L7 44Z" fill="url(#metal)" stroke="#384535" stroke-width="2"/><path d="M9 14 L52 12 L57 18 L12 22Z" fill="#a4a787" stroke="#46523d" stroke-width="1"/><path d="M13 24 V46 L53 42 V22Z" fill="#647451"/><path d="M22 17 V48 M43 15 V45" stroke="#b7b393" stroke-width="3"/><path d="M27 30 H41 V37 H27Z" fill="#c1b681"/><path d="M29 32 H39 M29 35 H36" stroke="#69725a" stroke-width="1"/><rect x="24" y="8" width="20" height="5" rx="2" fill="#68735b" stroke="#384535" stroke-width="1"/>',64,64),
'medical_bed':('<path d="M8 10 H55 V53 H8Z" fill="#67745c" stroke="#354735" stroke-width="2"/><rect x="12" y="13" width="39" height="36" rx="4" fill="#c4c8ac" stroke="#697a61" stroke-width="1.6"/><rect x="16" y="16" width="31" height="10" rx="3" fill="#e5e5cd"/><path d="M31 30 V43 M24 36 H38" stroke="#789277" stroke-width="4"/><path d="M8 8 V56 M55 8 V56" stroke="#445c45" stroke-width="3"/>',64,64),
'core_damage':('<path d="M17 28 L38 18 L58 32 L71 21 L89 37 L101 25 L115 48 L105 71 L113 98 L86 108 L66 97 L43 113 L20 93 L25 72 L12 49Z" fill="#454b3c" opacity=".66"/><path d="M32 24 L47 48 L39 62 L68 87 L61 112 M108 37 L88 53 L97 73 L82 90" stroke="#262e27" stroke-width="4" fill="none"/><path d="M35 25 L49 46 M91 57 L99 70" stroke="#a09d77" stroke-width="1.2"/>',128,128)
}
mask_front='<path d="M57 121 Q61 86 128 82 Q196 88 199 123 L195 192 Q179 226 128 236 Q77 224 60 192Z" fill="url(#steel)" stroke="#27342e" stroke-width="3"/><path d="M64 150 Q127 137 192 150 L185 181 Q127 192 70 181Z" fill="#263a36" stroke="#152c29" stroke-width="4"/><path d="M72 152 Q128 144 185 152 L179 172 Q127 181 76 172Z" fill="#7d9c91"/><path d="M76 155 Q128 149 181 155" fill="none" stroke="#d2d7b8" stroke-width="3" opacity=".7"/><path d="M124 148 L127 178" stroke="#344c43" stroke-width="4"/><path d="M86 186 Q128 176 169 186 L159 222 Q129 231 98 222Z" fill="url(#metal)" stroke="#263b2f" stroke-width="3"/>'+''.join(f'<path d="M{103+i*10} 190 V216" stroke="#2e4435" stroke-width="4"/><path d="M{105+i*10} 191 V214" stroke="#a7ae8b" stroke-width="1"/>' for i in range(6))+'<circle cx="70" cy="196" r="12" fill="#435c46" stroke="#233a2b" stroke-width="3"/><circle cx="187" cy="196" r="12" fill="#435c46" stroke="#233a2b" stroke-width="3"/><path d="M70 119 L91 112 M155 114 L182 124 M84 219 L91 217" stroke="#9baf90" stroke-width="2" opacity=".5"/>'
mask_side='<path d="M92 121 Q105 87 161 89 Q209 100 210 150 L225 168 L213 181 L208 205 Q187 235 151 232 L109 215Z" fill="url(#steel)" stroke="#29362e" stroke-width="3"/><path d="M139 150 Q175 140 214 153 L209 178 Q180 188 147 179Z" fill="#263a36" stroke="#172d29" stroke-width="4"/><path d="M147 153 Q180 148 207 155 L202 171 Q180 180 152 172Z" fill="#86a196"/><path d="M151 155 L200 154" stroke="#d3d8b8" stroke-width="3" opacity=".65"/><path d="M163 184 L210 184 L201 219 L172 225Z" fill="url(#metal)" stroke="#263b2f" stroke-width="3"/>'+''.join(f'<path d="M{175+i*7} 190 V215" stroke="#2e4435" stroke-width="3"/>' for i in range(4))+'<circle cx="124" cy="198" r="15" fill="#435c46" stroke="#233a2b" stroke-width="3"/><path d="M113 122 L132 113 M143 218 L153 222" stroke="#a1ae8d" stroke-width="2" opacity=".6"/>'
props['enemy_mask']=(''.join([group(0,0,mask_front),group(256,0,mask_side),group(768,0,f'<g transform="translate(256 0) scale(-1 1)">{mask_side}</g>')]),1024,256)
for name,(body,w,h) in props.items():(OUT/f'{name}.svg').write_text(svg(body,w,h),encoding='utf8')
# Enemy atlases are fixed outfits, with masks instead of expensive facial animation.
for kind,palette in [('trooper',('#76644e','#544d40','#b0885f')),('flanker',('#536c70','#344b50','#8da6a2')),('heavy',('#4e594d','#313e35','#899074'))]:
    parts=[]
    for pose in range(5):
        for d in range(4):
            width=29 if kind=='heavy' else (23 if kind=='flanker' else 25)
            body_h=[34,27,24,23,24][pose]
            base_y=[59,59,48,55,48][pose]
            x0=32-width/2
            color,dark,light=palette
            body=f'<path d="M{x0+4} {base_y-body_h} Q32 {base_y-body_h-6} {x0+width-4} {base_y-body_h} L{x0+width} {base_y-13} L{x0+width-3} {base_y-4} Q32 {base_y+1} {x0+3} {base_y-4} L{x0} {base_y-13}Z" fill="{color}" stroke="#2f352e" stroke-width="1.1"/><path d="M{x0+3} {base_y-14} Q32 {base_y-9} {x0+width-3} {base_y-14} L{x0+width-3} {base_y-5} Q32 {base_y} {x0+3} {base_y-5}Z" fill="{dark}" stroke="#2c3830" stroke-width=".9"/><path d="M32 {base_y-11} V{base_y-3}" stroke="#454b3c" stroke-width=".6"/><path d="M{x0+5} {base_y-body_h+4} Q32 {base_y-body_h+7} {x0+width-5} {base_y-body_h+4}" stroke="{light}" stroke-width=".8" opacity=".65"/>'
            head_y=base_y-body_h-5
            if pose==2:head_y=base_y-body_h+2
            if pose==3:head_y=base_y-body_h+6
            if pose==4:head_y=base_y-body_h+2
            head=f'<path d="M18 {head_y-13} Q32 {head_y-22} 46 {head_y-13} L48 {head_y+5} Q32 {head_y+16} 16 {head_y+5}Z" fill="{dark}" stroke="#27352e" stroke-width="1.1"/><path d="M20 {head_y-11} Q32 {head_y-17} 44 {head_y-11}" fill="none" stroke="{light}" stroke-width="1" opacity=".6"/>'
            if d!=2:
                gx=32 if d==0 else (39 if d==1 else 25)
                head+=f'<path d="M{gx-11} {head_y-3} Q{gx} {head_y-7} {gx+11} {head_y-3} L{gx+9} {head_y+2} L{gx-9} {head_y+2}Z" fill="#adc1ad" stroke="#212e29" stroke-width="1.4"/><path d="M{gx-8} {head_y-2} H{gx+7}" stroke="#e0dcc1" stroke-width=".7"/><path d="M{gx-7} {head_y+5} L{gx+7} {head_y+5} L{gx+6} {head_y+11} H{gx-6}Z" fill="#6a6c54" stroke="#26372e" stroke-width=".8"/>'+''.join(f'<path d="M{gx-4+i*3} {head_y+6} V{head_y+10}" stroke="#303c30" stroke-width=".7"/>' for i in range(3))
            if kind=='heavy':body+=f'<path d="M{x0+1} {base_y-body_h+4} L32 {base_y-body_h+8} L{x0+width-1} {base_y-body_h+4} L{x0+width-2} {base_y-15} Q32 {base_y-10} {x0+2} {base_y-15}Z" fill="url(#metal)" stroke="#25372b" stroke-width="1"/><path d="M27 {base_y-body_h+11} H37" stroke="#bfa775" stroke-width="2"/>'
            if pose in [2,4]:body=f'<g transform="translate(32 36) rotate({[90,0,-90,180][d]}) translate(-32 -36)">{body}{head}</g>';head=''
            if pose==3:body=f'<g transform="translate(32 47) scale(.82 .82) translate(-32 -47)">{body}{head}</g>';head=''
            parts.append(group(d*64,pose*64,body+head))
    (OUT/f'enemy_{kind}.svg').write_text(svg(''.join(parts),256,320),encoding='utf8')
(OUT/'manifest.json').write_text(json.dumps({'version':3,'approved_sources':{'ground':'docs/art_review/terrain_style_v1/source/a-materials.png','sandbags':'docs/art_review/building_style_v1/source/sandbags-lumpy-v3.png','sandbag_layout':'approved v4, native independent sacks','buildings':'style 1 field military','hair':'assets/art/pawns_ai/heads.png'},'independent_components':{'face':3,'features':6,'hair_front_back':6,'body_rigs':3,'expressions':expressions,'directions':['south','east','north','west']},'enemy_fixed_outfits':['trooper','flanker','heavy'],'connections':{'directions':['north','east','south','west'],'masks':16,'variants':3,'atlas_cell':128,'lighting':'fixed upper-left rim and lower-right contact shadows, not rotated whole tiles'},'source_preservation':'AI originals and prompts retained in original source paths; SVG overlays are code-native; no garment outfit combinations baked','reproduce':['tools/create_v3_vector_layers.py','tools/bake_v3_art.gd']},ensure_ascii=False,indent=2),encoding='utf8')
metadata=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
metadata.update({'runtime_enemy_representation':'Fixed whole PNG atlases from approved AI body/clothes/armor/helmet plus code-native mask; independent weapons; no enemy expression processing','runtime_buildings':{'machine_gun':'Approved style-1 original material extracted into independent fixed base and rotated gun PNGs','walls':'AI concrete top plus 32/128 south face, 7/128 east face, exterior bevel, fixed light and three crack patterns','core':'Approved AI subject plus independent glow/damage overlay'},'offline_only_inputs':['mg_source.png','ground_grass.png','ground_dirt.png','ground_gravel.png','ground_concrete.png','ground_metal.png','enemy_trooper.svg','enemy_flanker.svg','enemy_heavy.svg','enemy_mask.svg','mg_base.svg','mg_gun.svg'],'runtime_ground':'ground_map.png retained as 16 static chunks; offline five-material originals and decoration seeds independent of battle state'})
(OUT/'manifest.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf8')
print('V3_VECTOR_LAYERS_CREATED')
