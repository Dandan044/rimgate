"""Review-only SVG facial overlays on the exact in-game friendly pawn."""
from pathlib import Path
from copy import deepcopy
import hashlib
import json
import math
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / 'assets/art/vector/friendly_atlas.svg'
NS = 'http://www.w3.org/2000/svg'
ET.register_namespace('', NS)
ORIGINAL = ET.parse(SOURCE).getroot()[0][0]
STYLES = ['A 柔和 · 蔷薇瞳', 'B 平静 · 翠绿瞳', 'C 锐利 · 紫罗兰瞳']
STATES = ['待命 · 自然眨眼', '专注 · 瞳孔跟随', '惊慌 · 汗滴与颤动', '受伤 · 闭眼忍痛']
INK = '#263b3b'


def eye(side, style, state, openness=1, look=0):
    """Wide half-lidded anime eye; mirror a shared shape for the right eye."""
    dark = '#141c20'
    transform = 'translate(64 0) scale(-1 1)' if side else ''
    if openness < .14:
        return f'<g transform="{transform}"><path d="M22.3 25.7Q26 27.1 30 25.7" fill="none" stroke="{dark}" stroke-width="1" stroke-linecap="round"/></g>'
    top = 24.4 if style < 2 else 24.9
    if state == 1:
        top += .55
    if state == 2:
        top -= .9
    path = f'M22.3 {top+.3}Q25.8 {top-1.4} 30.1 {top+.4}L29.3 28.8Q26.6 30 23.6 28.7Z'
    clip = f'eye-{side}-{style}-{state}'
    colors = [('#472d42','#b65674','#ffb5ad'),('#1c3a32','#379159','#a8e78b'),('#302843','#73529c','#c4a8ee')][style]
    pupil = 26.5 + (look if side == 0 else -look)
    return f'''<g transform="{transform}"><g transform="translate(0 26) scale(1 {openness}) translate(0 -26)">
    <defs><clipPath id="{clip}"><path d="{path}"/></clipPath>
    <linearGradient id="iris-{clip}" x1="0" y1="0" x2="0" y2="1"><stop stop-color="{colors[0]}"/><stop offset=".55" stop-color="{colors[1]}"/><stop offset="1" stop-color="{colors[2]}"/></linearGradient></defs>
    <path d="M22.1 {top-1}Q25.9 {top-2.1} 30.3 {top-.2}L30.1 {top+1.5}Q25.8 {top-.1} 22.3 {top+1.2}Z" fill="#6d6e63" opacity=".55"/>
    <path d="{path}" fill="#f7f5e9" stroke="{dark}" stroke-width=".65"/>
    <g clip-path="url(#{clip})"><ellipse cx="{pupil}" cy="26.3" rx="2.55" ry="3.2" fill="url(#iris-{clip})" stroke="{dark}" stroke-width=".65"/>
    <ellipse cx="{pupil}" cy="25.5" rx="1.05" ry="1.85" fill="{dark}" opacity=".83"/>
    <ellipse cx="{pupil+1.15}" cy="28.1" rx=".62" ry=".42" fill="{colors[2]}"/>
    <ellipse cx="{pupil-1.1}" cy="25.4" rx=".5" ry=".7" fill="#fffaf0" opacity=".9"/></g>
    <path d="M21.8 {top+.1}Q25.5 {top-2.2} 30.4 {top+.3}L29.8 {top+1.4}Q25.7 {top-.5} 22.8 {top+1.35}Z" fill="{dark}"/>
    <path d="M23.8 28.9Q26.2 29.8 28.7 29" fill="none" stroke="{dark}" stroke-width=".45"/>
    </g></g>'''


def face(style, state, frame=0):
    openness = 1
    if state == 0 and frame in (5, 6, 7):
        openness = [.5, .06, .65][frame-5]
    look = .25*math.sin(frame/11*math.tau) if state == 1 else 0
    parts = []
    if state == 3:
        parts.append('<path d="M22.8 26.4Q26.3 25.1 29.8 26.8M34.2 26.8Q37.7 25.1 41.2 26.4" fill="none" stroke="#141c20" stroke-width="1.05" stroke-linecap="round"/>')
    else:
        parts += [eye(0, style, state, openness, look), eye(1, style, state, openness, look)]
    if state in (1, 3) or style == 2 and state == 0:
        parts.append('<path d="M22.1 21.5Q26.3 22.3 30 23.7L29.7 24.3Q25.3 23.5 22.1 22.2ZM41.9 21.5Q37.7 22.3 34 23.7L34.3 24.3Q38.7 23.5 41.9 22.2Z" fill="#141c20"/>')
    elif state == 2:
        parts.append('<path d="M22.1 21.9Q25.7 20.2 29.7 21.9L29.7 22.5Q25.7 21.6 22.1 22.5ZM41.9 21.9Q38.3 20.2 34.3 21.9L34.3 22.5Q38.3 21.6 41.9 22.5Z" fill="#141c20"/>')
    else:
        parts.append('<path d="M22.1 22.4Q25.8 20.7 29.7 22.5L29.7 23.1Q25.7 22.1 22.1 23.1ZM41.9 22.4Q38.2 20.7 34.3 22.5L34.3 23.1Q38.3 22.1 41.9 23.1Z" fill="#141c20"/>')
    parts.append('<path d="M31.6 29.5Q32 29.2 32.4 29.5L32 30.3Z" fill="#665f54" opacity=".75"/>')
    if state == 0:
        parts.append('<path d="M31.1 32.2Q32 31.1 32.9 32.2" fill="none" stroke="#66564e" stroke-width=".5"/>' if style == 0 else '<path d="M31.1 32.1H32.9" fill="none" stroke="#66564e" stroke-width=".5"/>')
    elif state == 1:
        parts.append('<path d="M31.1 32.1H32.9" fill="none" stroke="#66564e" stroke-width=".55"/>')
    elif state == 2:
        parts.append('<ellipse cx="32" cy="32.1" rx=".8" ry=".85" fill="#76584b"/>')
        drop_y = 24 + 1.6*(frame/11)
        parts.append(f'<path d="M42 {drop_y-1.5}Q39.6 {drop_y+1.5} 42 {drop_y+2}Q44.4 {drop_y+1.5} 42 {drop_y-1.5}Z" fill="#bce0dc" stroke="#628c89" stroke-width=".35"/>')
    else:
        parts.append('<path d="M30.9 32.2Q32 31.4 33.1 32.2" fill="none" stroke="#795e4d" stroke-width=".6"/>')
    offset = .12*math.sin(frame*2.8) if state in (2, 3) else 0
    return f'<g id="face-overlay" transform="translate({offset} 0)">'+''.join(parts)+'</g>'


def svg_document(overlay=''):
    base = ET.tostring(deepcopy(ORIGINAL), encoding='unicode')
    return f'''<svg xmlns="{NS}" width="256" height="256" viewBox="0 0 64 64">
    <g stroke="{INK}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round">{base}</g>
    {overlay}</svg>'''


def generate():
    (HERE/'svg').mkdir(parents=True, exist_ok=True)
    (HERE/'svg/original.svg').write_text(svg_document(), encoding='utf-8')
    for style in range(3):
        for state in range(4):
            (HERE/f'svg/{style}-{state}.svg').write_text(svg_document(face(style, state)), encoding='utf-8')
            # Independent transparent overlays; the body/helmet are never redrawn.
            (HERE/f'svg/{style}-{state}-face.svg').write_text(f'<svg xmlns="{NS}" width="256" height="256" viewBox="0 0 64 64">{face(style,state)}</svg>', encoding='utf-8')
    animation = []
    for frame in range(48):
        state, local = divmod(frame, 12)
        entries = []
        for style in range(3):
            entries.append(svg_document(face(style, state, local)))
        animation.append(entries)
    (HERE/'animation.json').write_text(json.dumps(animation), encoding='utf-8')
    (HERE/'source.json').write_text(json.dumps({'source':'assets/art/vector/friendly_atlas.svg','sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'styles':STYLES,'states':STATES,'review_only':True}, ensure_ascii=False, indent=2), encoding='utf-8')
    print('FACE_SVG_OK: 3 eye styles, 4 states, original pawn preserved')


if __name__ == '__main__':
    generate()
