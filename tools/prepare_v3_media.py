"""Encode actual Godot Movie Maker output and inspect its recorded media."""
from pathlib import Path
import hashlib
import json
import subprocess
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FFMPEG = ROOT / '.tools/video_runtime/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
OUT = ROOT / 'build/v3_evidence'


def run(*args):
    subprocess.run([str(FFMPEG), '-y', '-hide_banner', '-loglevel', 'error', *map(str, args)], check=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    original = OUT / 'motion.avi'
    movie = ROOT / 'build/Rimgate-demo-v0.3.0-motion.mp4'
    report = json.loads((ROOT / 'build/reports/v3_final_motion.json').read_text(encoding='utf-8-sig'))
    actual_pck = ROOT / 'build/release_v0.3_windows/Rimgate.pck'
    if report.get('failures') != [] or report.get('pck_sha256') != sha(actual_pck):
        raise RuntimeError('Actual final-package motion capture is missing or failed.')
    run('-i', original, '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', movie)
    run('-i', movie, '-f', 'null', '-')
    for second in (14.5, 15.5):
        run('-ss', second, '-i', original, '-frames:v', '1', OUT / f'motion_{second}.png')
    paused = (OUT / 'motion_14.5.png').read_bytes() == (OUT / 'motion_15.5.png').read_bytes()
    if not paused:
        raise RuntimeError('Recorded pause frames differ; inspect the actual game before release.')
    sound = OUT / 'recorded_audio.wav'
    run('-i', movie, '-vn', '-ac', '2', '-ar', '48000', '-c:a', 'pcm_s16le', sound)
    with wave.open(str(sound), 'rb') as reader:
        channels = reader.getnchannels()
        seconds = reader.getnframes() / reader.getframerate()
        samples = np.frombuffer(reader.readframes(reader.getnframes()), dtype='<i2').astype(np.float64) / 32768.0
    paired = samples.reshape(-1, channels)
    peak = float(np.max(np.abs(samples)))
    clipped = int(np.count_nonzero(np.abs(samples) >= 0.9999))
    stereo = float(np.sqrt(np.mean((paired[:, 0] - paired[:, 1]) ** 2)))
    audio = {'channels': channels, 'seconds': seconds, 'peak': peak, 'clipped_samples': clipped, 'stereo_difference_rms': stereo,
             'passed': channels == 2 and seconds >= 20 and peak > 0 and clipped == 0 and stereo > 0,
             'method': 'PCM decoded from the actual exported-game MP4; no added or replacement audio.',
             'media_sha256': sha(movie), 'pck_sha256': sha(actual_pck)}
    (OUT / 'motion_audio_report.json').write_text(json.dumps(audio, indent=2) + '\n', encoding='utf-8')
    if not audio['passed']:
        raise RuntimeError('Actual recorded audio failed its gate.')
    graph = 'fps=12,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=sierra2_4a'
    run('-ss', '5.5', '-t', '7', '-i', original, '-filter_complex', graph, '-loop', '0', OUT / 'v3_gameplay.gif')
    summary = {'original_avi_sha256': sha(original), 'mp4_sha256': sha(movie), 'pck_sha256': sha(actual_pck),
               'pause_frames_identical': paused, 'audio': audio, 'full_decode_passed': True,
               'capture_method': 'Actual final EXE Godot Movie Maker at fixed 60 FPS, offline; not a realtime performance benchmark.'}
    (OUT / 'media_summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__':
    main()
