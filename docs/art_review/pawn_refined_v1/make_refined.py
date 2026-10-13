"""Front-view modular SVG refinement, built on the approved no-arms study."""
from pathlib import Path
from copy import deepcopy
import importlib.util
import json
import hashlib
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('approved_pawn', HERE.parent/'pawn_four_parts_v1/make_pawns.py')
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)
PEOPLE = deepcopy(old.PEOPLE)
BODIES = deepcopy(old.BODIES)
PROFILES = deepcopy(old.PROFILES)
INK = '#303438'
NS = old.NS


def blend(a,b,t):
    aa=[int(a[n:n+2],16) for n in [1,3,5]];bb=[int(b[n:n+2],16) for n in [1,3,5]]
    return '#'+''.join(f'{round(x+(y-x)*t):02x}' for x,y in zip(aa,bb))


def defs():
    s=['<defs>']
    for i,p in enumerate(PEOPLE):
        s.append(f'<linearGradient id="hair-{i}" x1="0" y1="0" x2=".8" y2="1"><stop stop-color="{blend(p["hair"],p["light"],.3)}"/><stop offset=".42" stop-color="{p["hair"]}"/><stop offset="1" stop-color="{blend(p["hair"],"#17272b",.3)}"/></linearGradient>')
        s.append(f'<linearGradient id="skin-{i}" x1=".15" y1="0" x2=".9" y2="1"><stop stop-color="{blend(p["skin"],"#fff9ef",.27)}"/><stop offset=".62" stop-color="{p["skin"]}"/><stop offset="1" stop-color="{blend(p["skin"],"#b98877",.2)}"/></linearGradient>')
        s.append(f'<clipPath id="faceclip-{i}"><path d="{p["face"]}"/></clipPath>')
    s += ['<linearGradient id="coat" x1="0" y1="0" x2="1" y2=".5"><stop stop-color="#879b8c"/><stop offset=".28" stop-color="#a5b29b"/><stop offset=".7" stop-color="#7c9385"/><stop offset="1" stop-color="#536e67"/></linearGradient>',
          '<linearGradient id="lining" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="#e5e0c9"/><stop offset="1" stop-color="#99a795"/></linearGradient>',
          '<linearGradient id="shirt" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="#efe5cd"/><stop offset=".5" stop-color="#d7cdb5"/><stop offset="1" stop-color="#b2ad98"/></linearGradient>',
          '<linearGradient id="trousers" x1="0" y1="0" x2="1" y2=".3"><stop stop-color="#35424b"/><stop offset=".3" stop-color="#59676d"/><stop offset=".67" stop-color="#455159"/><stop offset="1" stop-color="#2a343e"/></linearGradient>',
          '<linearGradient id="boot" x1="0" y1="0" x2=".2" y2="1"><stop stop-color="#645f58"/><stop offset=".5" stop-color="#454744"/><stop offset="1" stop-color="#303838"/></linearGradient>',
          '<linearGradient id="helmet" x1="0" y1="0" x2=".6" y2="1"><stop stop-color="#c0c9ae"/><stop offset=".54" stop-color="#899d86"/><stop offset="1" stop-color="#617e73"/></linearGradient>',
          '<radialGradient id="cheek"><stop stop-color="#d57e75" stop-opacity=".24"/><stop offset="1" stop-color="#d57e75" stop-opacity="0"/></radialGradient>',
          '</defs>']
    return ''.join(s)


def body(index,skin):
    b=BODIES[index];n=b['neck_y'];s=b['shoulder'];w=b['waist'];h=b['hip'];hem=n+b['torso'];lower=h*.66;foot=lower*.83
    silhouette=f'M{32-s} {n+3}Q{32-s+1} {n+1} 28.5 {n+1}H35.5Q{32+s-1} {n+1} {32+s} {n+3}Q{32+s+.8} {n+11} {32+w} {hem-7}L{32+h} {hem+1}Q32 {hem+4} {32-h} {hem+1}L{32-w} {hem-7}Q{32-s-.8} {n+11} {32-s} {n+3}Z'
    out=[f'<g id="body-{index}" stroke="{INK}" stroke-width=".54" stroke-linejoin="round" stroke-linecap="round">',
        f'<path id="joined-trousers" d="M{32-lower} {hem-3}Q32 {hem-5} {32+lower} {hem-3}L{32+foot} 90Q32 91 {32-foot} 90Z" fill="url(#trousers)"/>',
        f'<path d="M{32-lower+.8} {hem}L{32-foot+.7} 88L30.7 87.3L30.3 {hem+4}Z" fill="#8b9691" opacity=".16" stroke="none"/>',
        f'<path d="M32.2 {hem+3}L33.3 88.6M{32-foot+.3} 87.2L30.8 86.8M33.2 86.9L{32+foot-.3} 87.4" fill="none" stroke="#a0aaa1" stroke-width=".3" opacity=".36"/>',
        f'<path d="M32 {hem+6}V89" fill="none" stroke="#26363d" stroke-width=".24" opacity=".32"/>',
        f'<path id="joined-boots" d="M{32-foot} 88.5Q32 87.6 {32+foot} 88.5L{32+foot+.7} 93Q{32+foot*.5} 95 32 94.4Q{32-foot*.5} 95 {32-foot-.7} 93Z" fill="url(#boot)"/>',
        f'<path d="M{32-foot+.5} 91.4Q{32-foot*.5} 90.2 31.4 91.1M32.6 91.1Q{32+foot*.5} 90.2 {32+foot-.5} 91.4" stroke="#b8b1a0" stroke-width=".4" opacity=".44" fill="none"/>',
        f'<path d="M{32-foot-.5} 93Q32 94.1 {32+foot+.5} 93" fill="none" stroke="#202b2d" stroke-width=".6"/>',
        '<path d="M32 90.6V93.6" fill="none" stroke="#9c9c8d" stroke-width=".22" opacity=".4"/>',
        f'<path d="{silhouette}" fill="url(#coat)"/>',
        f'<clipPath id="bodyclip-{index}"><path d="{silhouette}"/></clipPath>',
        f'<g clip-path="url(#bodyclip-{index})" stroke="none"><path d="M{32+s-2} {n+3}Q{32+s-4} {n+14} {32+w-1.3} {hem-8}L{32+h-2.2} {hem+3}H48V{n}Z" fill="#334f48" opacity=".24"/><path d="M{32-s+1} {n+5}L{32-s+2} {n+13}L{32-w+1} {hem-7}L{32-h+1} {hem+1}L{32-h+2} {hem+1}L{32-w+2} {hem-6}L{32-s+2.8} {n+6}Z" fill="#d3d7bc" opacity=".3"/><path d="M{32-h} {hem-.7}Q32 {hem+1.8} {32+h} {hem-.7}V{hem+4}H15Z" fill="#344d47" opacity=".25"/></g>',
        f'<path d="M28.8 {n-.5}H35.2L35 {n+5}Q32 {n+7} 29 {n+5}Z" fill="{skin}" stroke-width=".4"/>',
        f'<path d="M29 {n+1}Q32 {n+3} 35 {n+1}V{n+3.7}Q32 {n+5.1} 29 {n+3.7}Z" fill="#976d5e" opacity=".21" stroke="none"/>',
        f'<path d="M29 {n+4}Q32 {n+7} 35 {n+4}L36.3 {hem-.2}Q32 {hem+1} 27.7 {hem-.2}Z" fill="url(#shirt)" stroke-width=".45"/>',
        f'<path d="M30 {n+5.2}Q32 {n+6.9} 34 {n+5.2}" fill="none" stroke="#fff4da" stroke-width=".54"/>',
        f'<path d="M30.5 {n+9}L29.7 {hem-3}L31 {hem-1}M33.2 {n+11}L34.6 {hem-7}L33.7 {hem-3}" fill="none" stroke="#9b9e8b" stroke-width=".4" opacity=".55"/>',
        f'<path d="M28.8 {hem-1.2}Q32 {hem-.1} 35.2 {hem-1.2}" fill="none" stroke="#f1e9d1" stroke-width=".45"/>']
    for sign in [-1,1]:
        x=lambda a:32+sign*a
        # Folded collar, inner seam, pocket flap and seam form one readable clothing structure.
        out += [f'<path d="M{x(s-1.5)} {n+3}L{x(3)} {n+2.2}L{x(1.3)} {n+11}L{x(4.5)} {n+8.7}Z" fill="url(#lining)" stroke-width=".45"/>',
                f'<path d="M{x(3.2)} {n+3}L{x(2)} {n+8.9}L{x(3.9)} {n+8.4}" fill="none" stroke="#f1eed7" stroke-width=".4" opacity=".65"/>',
                f'<path d="M{x(3.3)} {n+11.7}L{x(4.4)} {hem-1}" fill="none" stroke="#c4cfb4" stroke-width=".33" opacity=".68"/>',
                f'<path d="M{x(w-1.2)} {hem-9.8}L{x(w-2.2)} {hem-12.3}L{x(4.7)} {hem-11.6}" fill="none" stroke="#455f55" stroke-width=".38" opacity=".65"/>',
                f'<path d="M{x(w-1.4)} {hem-4.1}L{x(w-2.6)} {hem-5.9}L{x(4.7)} {hem-4.8}" fill="none" stroke="#d2d7bd" stroke-width=".3" opacity=".55"/>']
        px=x(max(4.6,w*.7));pw=min(3.7,w*.54)
        out += [f'<path d="M{px-pw/2} {hem-9}H{px+pw/2}L{px+pw/2-.3} {hem-4.7}Q{px} {hem-4.3} {px-pw/2+.3} {hem-4.7}Z" fill="#627d6e" stroke-width=".4"/>',
                f'<path d="M{px-pw/2-.15} {hem-9.3}H{px+pw/2+.15}L{px+pw/2-.2} {hem-7.6}Q{px} {hem-7.1} {px-pw/2+.2} {hem-7.6}Z" fill="#9caa91" stroke-width=".34"/>',
                f'<path d="M{px-pw/2+.5} {hem-6.8}L{px-pw/2+.6} {hem-5.3}H{px+pw/2-.6}" fill="none" stroke="#bfcaab" stroke-width=".22" opacity=".64"/>',
                f'<circle cx="{px}" cy="{hem-8.3}" r=".24" fill="#d1c7a6" stroke-width=".18"/>']
    out += [f'<path d="M{32-h+.8} {hem+.6}Q32 {hem+2.8} {32+h-.8} {hem+.6}" fill="none" stroke="#b7c2a7" stroke-width=".35" opacity=".75"/>','</g>']
    return ''.join(out)


def face(index):
    p=PEOPLE[index]
    out=[f'<g id="face-{index}" stroke="{INK}" stroke-width=".6" stroke-linejoin="round">']
    for x in [20.8,43.2]:
        out += [f'<ellipse cx="{x}" cy="24.8" rx="1.35" ry="2" fill="{p["skin"]}" stroke-width=".4"/>',f'<path d="M{x} 24Q{x-.45} 24.8 {x} 25.7" stroke="#aa8171" stroke-width=".28" fill="none"/>']
    out += [f'<path d="{p["face"]}" fill="url(#skin-{index})"/>',f'<g clip-path="url(#faceclip-{index})" stroke="none">',
            '<path d="M19 12H45V23Q32 18.8 19 23Z" fill="#ad8270" opacity=".17"/>',
            '<ellipse cx="24.6" cy="29.6" rx="3.8" ry="2.8" fill="url(#cheek)"/><ellipse cx="39.4" cy="29.6" rx="3.8" ry="2.8" fill="url(#cheek)"/>',
            '<path d="M23 28Q26 33 31 34.6Q26 34.8 22.4 30.5Z" fill="#fff8e9" opacity=".2"/>','</g></g>']
    return ''.join(out)


def features(index):
    # Preserve the accepted 0.87 eye scale and vary the six original feature sets.
    xml=old.features(index)
    # Add secondary iris reflections within each original eye clipping region.
    xml=xml.replace('<rect x="26"', '<path d="M24.8 28.2Q26.5 29.05 28.1 28.1" fill="none" stroke="#ffedc5" stroke-width=".33" opacity=".48"/><circle cx="27.7" cy="27.3" r=".22" fill="#fffcf3" opacity=".8"/><rect x="26"')
    return xml


# Broad locks provide the material structure, the small strokes merely support it.
LOCKS = [
    ['M20.5 29Q18.8 45 20.2 60L22.4 62L23.6 32Z','M42.6 28Q45.5 43 44.2 60L46 58.5L44.4 27Z','M22 14.7Q29 9.9 36.8 11.1Q32.6 16.7 23 18.6Z'],
    ['M21 15.6L25.7 11.7L28.3 12.6L31 11L34 12.1L37 11.8L41.5 15.1L38.8 14.4L36 15.3L33 14.6L29.8 15.7L26.9 14.8L24 16.1Z'],
    ['M21 28Q18 34 21.8 37Q25 41 21.8 45Q18.3 50 22.7 53L21 57Q17.1 54 19.6 50Q21 47 18.8 43Q17 40 19.7 36Q17.9 32 21 28Z','M43 28Q46 34 42.2 37Q39 41 42.2 45Q45.7 50 41.3 53L43 57Q46.9 54 44.4 50Q43 47 45.2 43Q47 40 44.3 36Q46.1 32 43 28Z','M22.5 14Q31 9.7 41.8 14.2L40.6 16.6Q32 13.6 24 17Z'],
    ['M22 14L28 9L25.1 14.7Z','M28 13.8L35.7 7.7L32.4 13.8Z','M35.7 14.4L40.8 9.5L40.7 15.5Z'],
    ['M20.5 17Q20 13.7 24.4 14.4Q25 10.9 28.4 12.9Q31.2 10.2 34.5 13.1Q37.6 10.8 39.5 14.8Q42.6 14.4 42.6 17.1L41.3 18.3Q38.4 15.8 36.6 17Q33.5 14.8 30.4 16.7Q27 14.4 24.2 17.6Z'],
    ['M43.7 28Q46.9 31.3 44.7 36.8Q42 42.3 45 46.8Q48.4 51.9 44.8 57.1L45.5 61L46.9 58.8Q49 54.5 46.7 50.4Q44.4 45.6 46.3 41.6Q48.3 37.4 46.4 33Z','M22.1 14.4Q28.3 10.1 36.6 11.2Q33.8 17.1 23.8 19.1Z']
]


def hair(index,front=False,helmet=False):
    p=PEOPLE[index]
    raw=old.hair(index,front,helmet)
    tree=ET.fromstring(f'<svg xmlns="{NS}">{raw}</svg>')
    original=tree[0][0].get('d')
    which='front' if front else 'back';key=f'hairclip-{index}-{which}-{int(helmet)}'
    out=[f'<g id="hair-{which}-{index}" stroke="{INK}" stroke-linejoin="round" stroke-linecap="round"><path d="{original}" fill="url(#hair-{index})" stroke-width=".58"/>',f'<clipPath id="{key}"><path d="{original}"/></clipPath>',f'<g clip-path="url(#{key})" stroke="none">']
    out.append(f'<path d="M17 18Q32 13 47 19L47 27Q32 21.7 17 25Z" fill="#15272a" opacity=".19"/>')
    # Shadows from the separate lock groups.
    for j,d in enumerate(LOCKS[index]):
        out.append(f'<path d="{d}" fill="{p["light"]}" opacity="{.18 if j<2 and index in [0,2,5] else .26}"/>')
    if front:
        out.append(f'<path d="M20 13Q30 7.4 44 13L43.4 14.7Q31 10.7 20.8 15Z" fill="{p["light"]}" opacity=".31"/>')
        # Controlled strand bundles, not independent hairline noise.
        paths=[
          'M23.3 17.8Q30.9 15.9 35.9 11.9M25.1 18.7Q32.1 17.2 37.2 12.7M40 14.7L41.4 22.3',
          'M23.8 14.2L25.4 13.2M28.2 13.6L30.6 12.7M33.6 13.3L35.6 12.7M38.2 14.2L39.9 15.2',
          'M23.6 16.7L24.3 20.3M28 14.9L28.7 19.6M33 14.6L33 19.9M37.9 15.6L38.8 19.5M41 17L41.9 22.8',
          'M23.6 14.3L28.4 10.4M29.7 12.6L34.4 9M35.2 13.7L39.2 10.6M39.5 15L41.7 16.5',
          'M21.7 17.1Q22.8 15.6 24.2 16.7M26.4 14.3Q28 13.5 29.1 15.2M32 13.6Q33.5 13.5 34.2 15.5M37 15.2Q38.6 13.8 40 16.6',
          'M23.4 17.6Q30 16 35.5 12.1M25.6 19.1Q31.3 18 37.4 12.9M40.5 15.5L41.5 22.8'
        ][index]
        if not helmet:
            out.append(f'<path d="{paths}" fill="none" stroke="{p["light"]}" stroke-width=".26" opacity=".7"/>')
    else:
        if index in [0,2]:
            for side in [-1,1]:
                for j in range(3):
                    x=32+side*(10+j*.9)
                    d=f'M{x} 30Q{x+side*.6} 44 {x} 59' if index==0 else f'M{x} 29Q{x+side*2.3} 34 {x} 38Q{x-side*1.8} 43 {x+side*.2} 47Q{x+side*2} 52 {x} 56'
                    out.append(f'<path d="{d}" fill="none" stroke="{p["light"]}" stroke-width=".27" opacity=".48"/>')
        if index==5:
            out.append(f'<path d="M45.5 30Q47.8 34 45.5 39Q43.9 43 46 48Q47.8 53 45.3 58" fill="none" stroke="{p["light"]}" stroke-width=".33" opacity=".72"/>')
    out += ['</g>']
    if index==5 and not front:
        out.append('<path d="M43.3 25.3L46.4 26" stroke="#6a9e95" stroke-width="1.2"/><path d="M43.7 25.3L45.9 25.8" stroke="#b5caba" stroke-width=".3"/>')
    out.append('</g>')
    return ''.join(out)


def helmet():
    return '''<g id="helmet-equipment" stroke="#303d3a" stroke-linejoin="round" stroke-linecap="round">
    <path d="M18.8 21.1L18.9 15.8Q18.7 7 31.7 7Q45.2 6.7 45.1 16L45.2 21.1Q32 18.6 18.8 21.1Z" fill="url(#helmet)" stroke-width=".64"/>
    <path d="M20.6 15.2Q21.4 8.9 31.8 8.7Q39 8.3 42.7 12.7" stroke="#e0dfbf" stroke-width=".5" fill="none" opacity=".6"/>
    <path d="M21 17.8Q32 15.7 43.1 17.8L44 20.3Q32 18.3 20 20.3Z" fill="#4d6b5d" stroke-width=".3"/>
    <path d="M22 18.2Q31.7 16.9 42.3 18.2" stroke="#bac8a4" stroke-width=".25" fill="none" opacity=".7"/>
    <path d="M29.7 9.1Q30 12.6 29.8 16.6" stroke="#607f6d" stroke-width=".28" fill="none"/>
    <path d="M19.8 20.6L20.5 23.8L21.8 24.6M44.1 20.6L43.5 23.8L42.2 24.6" stroke="#617564" stroke-width=".7" fill="none"/>
    <rect x="21" y="17.7" width="1" height="1.8" rx=".2" fill="#c3c5a4" stroke-width=".2"/>
    <rect x="42" y="17.7" width="1" height="1.8" rx=".2" fill="#c3c5a4" stroke-width=".2"/>
    <path d="M34.8 11.4L38.2 11.7M35.1 12.3L37.2 12.4" stroke="#e2dec2" opacity=".25" stroke-width=".3"/>
    </g>'''


def document(profile,part=None,helmet_on=False,portrait=False):
    fi,fa,ha,bi=[profile[k] for k in ['features','face','hair','body']];dy=BODIES[bi]['neck_y']-34
    parts={'features':features(fi),'face':face(fa),'hair-back':hair(ha,helmet=helmet_on),'hair-front':hair(ha,True,helmet_on),'body':body(bi,PEOPLE[fa]['skin']),'helmet':helmet()}
    if part:
        content=parts[part]
    else:
        content=f'<g transform="translate(0 {dy})">{parts["hair-back"]}</g>'+parts['body']+f'<g transform="translate(0 {dy})">'+parts['face']+parts['features']+parts['hair-front']+(parts['helmet'] if helmet_on else '')+'</g>'
    view=f'13 {dy+3} 38 38' if portrait and not part else '0 0 64 104'
    size=(608,608) if portrait else (512,832)
    return f'<svg xmlns="{NS}" width="{size[0]}" height="{size[1]}" viewBox="{view}">{defs()}{content}</svg>'


def generate():
    (HERE/'svg').mkdir(parents=True,exist_ok=True)
    for p in PROFILES:
        for label,kw in [('bare',{}),('helmet',{'helmet_on':True}),('portrait',{'portrait':True}),('helmet-detail',{'portrait':True,'helmet_on':True})]+[(k+'-layer',{'part':k}) for k in ['features','face','hair-back','hair-front','body']]+[(k+'-helmet-layer',{'part':k,'helmet_on':True}) for k in ['hair-back','hair-front']]:
            (HERE/f'svg/{p["id"]}-{label}.svg').write_text(document(p,**kw),encoding='utf-8')
    (HERE/'svg/helmet-equipment-layer.svg').write_text(document(PROFILES[0],part='helmet'),encoding='utf-8')
    mixes=[]
    for j,(fi,fa,ha,bi) in enumerate([(0,5,2,2),(4,2,0,4),(2,0,5,3)]):
        p=dict(id=f'mix{j+1}',features=fi,face=fa,hair=ha,body=bi);mixes.append(p)
        (HERE/f'svg/mix-{j+1}.svg').write_text(document(p),encoding='utf-8')
    for i in range(6):
        p=dict(features=1,face=1,hair=1,body=i)
        (HERE/f'svg/body-study-{i+1}.svg').write_text(document(p),encoding='utf-8')
    manifest={'component_axes':['features','face','hair','body'],'profiles':PROFILES,'mixes':mixes,'bodies':BODIES,'head_local_socket':[32,34],'foot_anchor':[32,94],'head_transform':'translate(0, body.neck_y - 34)','draw_order':['hair-back','body','head: face','head: features','head: hair-front','head: helmet-equipment'],'structural_constraints':{'arms':False,'hands':False,'leg_gap':'continuous silhouette, faint seam'},'view':'front','runtime_modified':False,'approval':'pending','source_sha256':hashlib.sha256((ROOT/'assets/art/vector/friendly_atlas.svg').read_bytes()).hexdigest()}
    (HERE/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    for f in (HERE/'svg').glob('*.svg'): ET.fromstring(f.read_text(encoding='utf-8'))
    print('REFINED_SVG_OK',len(list((HERE/'svg').glob('*.svg'))))


if __name__=='__main__': generate()
