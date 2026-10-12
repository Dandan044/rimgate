"""Prepare selected licensed audio from the downloaded archives, without extracting paths.

Downloads live in .tools/audio_v2. Sources are converted to mono PCM for an
offline, deterministic mixer. Requires FFmpeg; never executes archive contents.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TEMP = ROOT / '.tools/audio_v2'
DEST = ROOT / 'assets/audio/source'
FFMPEG = ROOT / '.tools/video_runtime/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    raw = TEMP / 'selected'
    raw.mkdir(exist_ok=True)
    selected = {}
    with zipfile.ZipFile(TEMP / 'tabasco.zip') as archive:
        for name in ['sks', 'mosin', 'shotty']:
            path = raw / (name + '.wav')
            path.write_bytes(archive.read('sounds/' + name + '.wav'))
            selected['tabasco_' + name] = path
        (DEST / 'Tabasco-original-license.txt').write_bytes(archive.read('sounds/creativecommons.txt'))
    with zipfile.ZipFile(TEMP / 'kenney.zip') as archive:
        names = ['footstep_grass_000', 'footstep_grass_001', 'footstep_concrete_000',
                 'impactMetal_light_000', 'impactMetal_medium_001', 'impactMining_000',
                 'impactSoft_medium_000', 'impactSoft_heavy_001', 'impactWood_medium_000',
                 'impactPlate_light_000', 'impactTin_medium_000']
        for name in names:
            path = raw / (name + '.ogg')
            path.write_bytes(archive.read('Audio/' + name + '.ogg'))
            selected['kenney_' + name] = path
        (DEST / 'Kenney-original-license.txt').write_bytes(archive.read('License.txt'))
    for name in ['reload', 'cock', 'boom']:
        selected['springy_' + name if name != 'boom' else 'nenad_boom'] = TEMP / (name + '.wav')
    metadata = []
    for name, path in selected.items():
        target = DEST / (name + '.wav')
        subprocess.run([str(FFMPEG), '-hide_banner', '-loglevel', 'error', '-y', '-i', str(path),
                        '-ac', '1', '-ar', '48000', '-c:a', 'pcm_s16le', str(target)], check=True)
        with wave.open(str(target)) as clip:
            seconds = clip.getnframes() / clip.getframerate()
        metadata.append({'file': target.name, 'seconds': seconds,
                         'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                         'pcm_sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
        print(name, round(seconds, 3))
    (DEST / 'MANIFEST.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
