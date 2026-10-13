"""Original SVG chibi study: features, face, hair and body are separate parts."""
from pathlib import Path
from copy import deepcopy
import hashlib
import importlib.util
import json
import sys
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('face_v2',HERE.parent/'facial_combinations_v2/make_revision.py')
v2=importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
INK='#302f32'
PEOPLE=deepcopy(v2.PEOPLE)
for p,skin in zip(PEOPLE,['#efd0b6','#d2ad8d','#f2d9c4','#e5c8ac','#c8a388','#efd8c6']):
    p['skin']=skin
PEOPLE[1]['face']='M25 11Q20.5 12.4 20.6 18L20.9 26.3Q22 31.9 26.2 33.8Q32 35 37.8 33.8Q42 31.9 43.1 26.3L43.4 18Q43.5 12.4 39 11Z'
PEOPLE[2]['face']='M32 10C22 9.5 19.7 16 20 22C20.4 28 25.8 33 30.8 35.1Q32 35.9 33.2 35.1C38.2 33 43.6 28 44 22C44.3 16 42 9.5 32 10Z'
for p,c,l in zip(PEOPLE,['#3f5358','#695447','#735b50','#9b9180','#48434c','#b1b3ad'],['#71878a','#9d8270','#ab8a74','#c5baa2','#79717c','#dfddd1']):
    p['hair'],p['light']=c,l

BODIES=[
 {'id':'B01','name':'纤细','shoulder':8.1,'waist':5.8,'hip':7.2,'arm':2.7,'leg':2.7,'torso':25,'legs':19},
 {'id':'B02','name':'匀称','shoulder':9.7,'waist':7.2,'hip':8.5,'arm':3.2,'leg':3.1,'torso':26,'legs':20},
 {'id':'B03','name':'宽肩壮实','shoulder':12.7,'waist':9.1,'hip':10.1,'arm':4.1,'leg':3.7,'torso':28,'legs':18},
 {'id':'B04','name':'圆润','shoulder':11.6,'waist':12.2,'hip':12.4,'arm':4.0,'leg':4.0,'torso':29,'legs':16},
 {'id':'B05','name':'娇小','shoulder':8.1,'waist':6.4,'hip':7.3,'arm':2.8,'leg':2.8,'torso':22,'legs':15},
 {'id':'B06','name':'高挑','shoulder':9.1,'waist':6.6,'hip':8.0,'arm':2.9,'leg':2.9,'torso':29,'legs':25},
]
for b in BODIES:
    b.pop('arm',None)
    b['neck_y']=94-(b['torso']+b['legs']+5)
    b['foot_y']=94
HAIR_NAMES=['侧分长直发','侧分短发','波浪中长发','后梳短发','柔软短卷发','偏分长马尾']
PROFILES=[{'id':f'{i+1:02d}','features':i,'face':i,'hair':i,'body':b} for i,b in enumerate([0,2,1,5,3,4])]

DEFS='''<defs>
<linearGradient id="coat" x1="0" y1="0" x2=".9" y2="1"><stop stop-color="#96a699"/><stop offset=".54" stop-color="#7f9387"/><stop offset="1" stop-color="#5f766d"/></linearGradient>
<linearGradient id="shirt" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#f0e8d5"/><stop offset="1" stop-color="#d1c8b2"/></linearGradient>
<linearGradient id="trousers" x1="0" y1="0" x2="1" y2=".2"><stop stop-color="#505d64"/><stop offset="1" stop-color="#3c444d"/></linearGradient>
</defs>'''


def body(body_id,skin):
    b=BODIES[body_id];n=b['neck_y'];s=b['shoulder'];w=b['waist'];h=b['hip'];hem=n+b['torso'];boot=89
    pieces=[]
    # One continuous lower silhouette: no transparent gap between the legs.
    lower=h*.66;foot=lower*.83
    pieces.append(f'<path id="joined-trousers" d="M{32-lower} {hem-3}Q32 {hem-5} {32+lower} {hem-3}L{32+foot} {boot+1}Q32 {boot+2} {32-foot} {boot+1}Z" fill="url(#trousers)"/>')
    pieces.append(f'<path id="joined-boots" d="M{32-foot} {boot-.5}Q32 {boot-1.4} {32+foot} {boot-.5}L{32+foot+.7} 93Q{32+foot*.5} 95 32 94.4Q{32-foot*.5} 95 {32-foot-.7} 93Z" fill="#514c49"/>')
    pieces.append(f'<path d="M32 {hem+6}V{boot-.5}" fill="none" stroke="#717c81" stroke-width=".24" opacity=".4"/>')
    pieces.append(f'<path d="M32 {boot+1}V93.8M{32-foot+.5} {boot+1}H{32+foot-.5}" fill="none" stroke="#969384" stroke-width=".24" opacity=".7"/>')
    torso=f'M{32-s} {n+3}Q{32-s+1} {n+1} 28.5 {n+1}H35.5Q{32+s-1} {n+1} {32+s} {n+3}Q{32+s+.8} {n+11} {32+w} {hem-7}L{32+h} {hem+1}Q32 {hem+4} {32-h} {hem+1}L{32-w} {hem-7}Q{32-s-.8} {n+11} {32-s} {n+3}Z'
    pieces.append(f'<path d="{torso}" fill="url(#coat)"/>')
    pieces.append(f'<path d="M28.8 {n-.5}H35.2L35 {n+5}Q32 {n+7} 29 {n+5}Z" fill="{skin}" stroke-width=".4"/>')
    pieces.append(f'<path d="M29 {n+4}Q32 {n+7} 35 {n+4}L36.3 {hem-.2}Q32 {hem+1} 27.7 {hem-.2}Z" fill="url(#shirt)" stroke-width=".45"/>')
    pieces.append(f'<path d="M{32-s+1.5} {n+3}L29 {n+2.2}L30.7 {n+11}L27.5 {n+8.7}Z M{32+s-1.5} {n+3}L35 {n+2.2}L33.3 {n+11}L36.5 {n+8.7}Z" fill="#c6cbb7" stroke-width=".45"/>')
    pieces.append(f'<path d="M{32-w} {hem-5}L27.7 {hem-3}M{32+w} {hem-5}L36.3 {hem-3}M{32-s+2} {n+10}L{32-w+1.2} {hem-8}" fill="none" stroke="#b5c0aa" stroke-width=".38"/>')
    for side in [-1,1]:
        px=32+side*(w*.68)
        pieces.append(f'<path d="M{px-1.8} {hem-9}H{px+1.8}L{px+1.3} {hem-5}H{px-1.3}Z" fill="#72877b" stroke-width=".4"/>')
    pieces.append(f'<path d="M{32-h+.8} {hem+.6}Q32 {hem+2.8} {32+h-.8} {hem+.6}" fill="none" stroke="#4d625b" stroke-width=".7"/>')
    return f'<g id="body-{b["id"]}" stroke="{INK}" stroke-width=".65" stroke-linejoin="round" stroke-linecap="round">'+''.join(pieces)+'</g>'


LONG_HAIR=[
 ('M19.3 28L18.3 17Q18.2 7 31 7Q44.2 6.6 45.5 16L47.5 60Q46 64 42.6 63L43.2 58L40.2 61L38.7 34H25.2L23.1 63L20 59.8L19.7 65Q16.6 63.6 17.9 59Z',
  'M20.2 21L20.7 14Q25 8.6 36 9Q43.1 9.5 44.1 17L42.5 26L40 22.8L38.7 14.2Q33 20.1 24.2 20.2L22.5 26.8Z',
  'M24 13.6Q29 11.1 35.7 11.5M40.8 17.5L42.8 24.2M20.8 31Q19 45 20.5 57M43.6 32Q45.2 46 44.5 56'),
 None,
 ('M19.8 21Q18.3 10 29 8.3Q42.4 6.2 45 17L45.1 29Q48.8 33 45.7 37Q49.3 41 45.5 45Q48.4 49.5 43.8 53Q46.8 58.5 40.8 60L39 48L25 48Q23.5 60 19.3 60Q15.2 57.7 18.5 53Q14.8 49 18.6 45Q14.7 41.4 18.4 37Q14.8 33 18.9 29Z',
  'M20 21L20.8 14Q23.8 8.6 32 9Q41.2 8.7 44 16.5L43 25L40.8 20.4L38.5 22L36 20.1L33 22.2L30.1 20.4L27.3 22.1L24.4 20.8L22.6 26.2Z',
  'M24 13.7Q32.1 10.8 40.4 14M20.9 30Q17.8 34 21 37Q24 40 20.6 44Q17.7 48 21.2 52Q23.3 55 21 57.5M43.1 30Q46.2 34 43 37Q40 40 43.4 44Q46.3 48 42.8 52Q40.7 55 43 57.5'),
 None,
 None,
 ('M42.9 23Q49.3 22.8 48.4 31.5Q45.8 37 48.3 42.2Q50.2 48 46.2 53Q49.6 59.2 44 64L41.8 60Q45.3 56.3 42.3 52.4Q40 47.5 43.1 42.8Q45.1 38 42.4 33Z M19.5 24L19 16.4Q18.7 7.3 31 7.5Q43 6.5 44.8 15.5L44.7 24.4L41.6 21H22.6Z',
  'M20.3 21Q20 14 24 11Q28.6 8.1 35 9.1Q42.8 10.1 44 17.4L42.2 25.1L39.5 22L39 13.9Q34.7 21 24.3 20.8L22.3 24.5Z',
  'M24.1 14.2Q28.5 11.5 35.2 12.1M45 29Q47.1 33 44.8 37M45.8 43.5Q47.4 48 44.7 51.2M45.2 55Q47 58 44.8 60.8'),
]


def hair(hair_id,front=False,helmet=False):
    p=PEOPLE[hair_id]
    data=LONG_HAIR[hair_id] or v2.HAIR[hair_id]
    if helmet:
        data=list(v2.HELMET_HAIR[hair_id])
        if hair_id in (0,2):
            # Long sections remain; only the scalp hair is compressed under the helmet.
            data[0]=LONG_HAIR[hair_id][0]
        if hair_id==5:
            data[0]=LONG_HAIR[hair_id][0].split(' M19.5')[0]+' M20.5 20.3L22 20.6V25.3L20.5 26Z M42 21L43.4 21.2V26L41.5 24Z'
    d=data[1 if front else 0]
    shine=data[2] if front else ''
    xml=f'<g id="hair-{"front" if front else "back"}" fill="{p["hair"]}" stroke="{INK}" stroke-width=".62" stroke-linejoin="round" stroke-linecap="round"><path d="{d}"/>'
    if shine:
        xml+=f'<path d="{shine}" fill="none" stroke="{p["light"]}" stroke-width=".42" opacity=".8"/>'
    if hair_id==5 and not front:
        xml+='<path d="M43.4 25.5L46.6 26.3" fill="none" stroke="#6d908a" stroke-width="1.1"/>'
    return xml+'</g>'


def face(face_id):
    p=PEOPLE[face_id]
    return f'<g id="face-{face_id+1:02d}" fill="{p["skin"]}" stroke="{INK}" stroke-width=".78" stroke-linejoin="round"><ellipse cx="20.8" cy="24.8" rx="1.35" ry="2" stroke-width=".5"/><ellipse cx="43.2" cy="24.8" rx="1.35" ry="2" stroke-width=".5"/><path d="{p["face"]}"/></g>'


def features(features_id,frame=-1):
    return v2.thinner(v2.features(features_id,frame),.85).replace('#263b3b',INK)


def helmet_art():
    return v2.thinner(v2.HELMET,.5).replace('#263b3b',INK).replace('#d7dfd8','#cbd1c6').replace('#92d8c8','#a6c1b5')


def document(profile,frame=-1,helmet=False,part=None):
    fi,fa,ha,bi=[profile[k] for k in ['features','face','hair','body']]
    b=BODIES[bi];dy=b['neck_y']-34
    own={'features':features(fi,frame),'face':face(fa),'hair':hair(ha)+hair(ha,True),'body':body(bi,PEOPLE[fa]['skin']),
       'hair-back':hair(ha),'hair-front':hair(ha,True),'helmet-hair-back':hair(ha,helmet=True),'helmet-hair-front':hair(ha,True,True),'helmet':helmet_art()}
    if part:
        # Library head parts use local coordinates; head_socket_y supplies placement.
        content=own[part]
    else:
        content=f'<g transform="translate(0 {dy})">{hair(ha,helmet=helmet)}</g>'+own['body']
        content+=f'<g id="head-assembly" transform="translate(0 {dy})">{own["face"]}{own["features"]}{hair(ha,True,helmet)}{helmet_art() if helmet else ""}</g>'
    return f'<svg xmlns="{NS}" width="512" height="832" viewBox="0 0 64 104">{DEFS}{content}</svg>'


def generate():
    (HERE/'svg').mkdir(parents=True,exist_ok=True)
    for profile in PROFILES:
        for name,kw in [('bare',{}),('helmet',{'helmet':True})]+[(part+'-layer',{'part':part}) for part in ['features','face','hair','body','hair-back','hair-front','helmet-hair-back','helmet-hair-front']]:
            (HERE/f'svg/{profile["id"]}-{name}.svg').write_text(document(profile,**kw),encoding='utf-8')
    for i in range(6):
        p={'features':1,'face':1,'hair':1,'body':i}
        (HERE/f'svg/body-study-{i+1:02d}.svg').write_text(document(p),encoding='utf-8')
    (HERE/'svg/helmet-layer.svg').write_text(document(PROFILES[0],part='helmet'),encoding='utf-8')
    # Exchange all four IDs without redrawing any source component.
    mixed={'id':'mix','features':0,'face':5,'hair':2,'body':2}
    (HERE/'svg/four-way-mix.svg').write_text(document(mixed),encoding='utf-8')
    (HERE/'animation.json').write_text(json.dumps([[document(p,frame) for p in PROFILES] for frame in range(36)]),encoding='utf-8')
    manifest={'source':'assets/art/vector/friendly_atlas.svg','source_sha256':hashlib.sha256(v2.previous.base.SOURCE.read_bytes()).hexdigest(),'profiles':PROFILES,'bodies':BODIES,'faces':PEOPLE,'hair_names':HAIR_NAMES,'component_axes':['features','face','hair','body'],'head_local_socket':[32,34],'foot_anchor':[32,94],'canvas':[512,832],'runtime_modified':False,'approval':'pending','view':'front','four_way_mix':mixed,'structural_constraints':{'arms':False,'hands':False,'leg_gap':'continuous silhouette with faint central seam'},'art_status':'structure study, not polished final art'}
    (HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('FOUR_PARTS_SVG_OK: 6 four-component characters; 6 body-only swaps; independent source layers')


if __name__=='__main__':
    generate()
