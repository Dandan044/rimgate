"""Deterministic sampled/foley audio mixer for Demo v0.2 (Python + NumPy).

Selected mono PCM sources and their licenses ship in audio/source. This script
works offline; it does not download or execute third-party code. See AUDIO_V2.md.
"""
from pathlib import Path
import json
import wave
import numpy as np

BASE = Path(__file__).resolve().parent / 'audio'
RATE = 48000


def read(name):
    with wave.open(str(BASE / 'source' / (name + '.wav')), 'rb') as source:
        assert source.getframerate() == RATE and source.getnchannels() == 1 and source.getsampwidth() == 2
        return np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(np.float64) / 32768.0


def pitch(data, factor):
    return np.interp(np.arange(0, len(data), factor), np.arange(len(data)), data)


def band(data, low=70, high=16000):
    spectrum = np.fft.rfft(data)
    frequencies = np.fft.rfftfreq(len(data), 1 / RATE)
    curve = np.minimum(1.0, (frequencies / max(low, 1)) ** 2)
    curve *= np.minimum(1.0, (high / np.maximum(frequencies, 1)) ** 3)
    return np.fft.irfft(spectrum * curve, n=len(data))


def shot(name, window, duration=.68, factor=1.0):
    data = read(name)
    begin, end = (int(value * RATE) for value in window)
    candidates = np.flatnonzero(np.abs(data[begin:end]) > .28)
    assert len(candidates), (name, window)
    onset = begin + int(candidates[0])
    clip = data[max(0, onset - 96):onset + int(duration * RATE)]
    clip = band(pitch(clip, factor), 110, 14000)
    # Retain the recorded crack/body/early reflections and gate the noisy field tail.
    t = np.arange(len(clip)) / RATE
    clip *= np.exp(-np.maximum(0, t - .10) * 5.5)
    clip[:48] *= np.linspace(0, 1, 48)
    return clip


def mix(duration, layers):
    output = np.zeros(int(duration * RATE))
    for data, offset, gain in layers:
        begin = int(offset * RATE)
        size = min(len(data), len(output) - begin)
        if size > 0:
            output[begin:begin + size] += data[:size] * gain
    return output


def save(name, data, peak=.72):
    data = data - np.mean(data)
    data = np.tanh(data * 1.2)
    data *= peak / max(.001, float(np.max(np.abs(data))))
    fade_in = min(48, len(data) // 4)
    fade_out = min(960, len(data) // 4)
    data[:fade_in] *= np.linspace(0, 1, fade_in)
    data[-fade_out:] *= np.linspace(1, 0, fade_out)
    pcm = (np.clip(data, -.99, .99) * 32767).astype('<i2')
    with wave.open(str(BASE / (name + '.wav')), 'wb') as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    return {'name': name, 'seconds': round(len(data) / RATE, 4),
            'peak': round(float(np.max(np.abs(data))), 4),
            'rms': round(float(np.sqrt(np.mean(data * data))), 5)}


def main():
    results = []
    metal = read('kenney_impactMetal_light_000')
    plate = read('kenney_impactPlate_light_000')
    soft = read('kenney_impactSoft_medium_000')
    grass = read('kenney_footstep_grass_000')
    boom = read('nenad_boom')
    for index, window in enumerate([(.28, .6), (2.25, 2.6)], 1):
        crack = shot('tabasco_sks', window)
        results.append(save('rifle_' + str(index), mix(.85, [
            (crack, 0, 1), (band(crack, 140, 5000), .075, .15), (metal[:3500], .035, .055)])))
    for index, window in enumerate([(.35, .8), (3.45, 3.9)], 1):
        crack = shot('tabasco_mosin', window, .50, 1.04 if index == 1 else .98)
        results.append(save('mg_' + str(index), mix(.72, [
            (crack, 0, 1.1), (band(crack, 75, 1800), .04, .25), (metal[:4800], .025, .12)]), .76))
    heavy = shot('tabasco_shotty', (.08, .25), .45, .70)
    results.append(save('mortar', mix(1.05, [(band(heavy, 45, 2200), 0, 1),
                                                   (band(boom[:48000], 35, 1100), .015, .45), (plate, .04, .14)]), .80))
    mining = read('kenney_impactMining_000')
    for index, factor in enumerate([1.0, .91], 1):
        tail = band(pitch(boom, factor), 30, 8500)
        results.append(save('explosion_' + str(index), mix(2.8, [
            (heavy, 0, .35), (tail, 0, 1), (mining, .07, .38),
            (pitch(mining, .75), .21, .15), (plate, .34, .10)]), .86))
    foley = {
        'impact': ('kenney_impactWood_medium_000', 1.0, .64),
        'impact_metal_01': ('kenney_impactMetal_medium_001', 1.0, .65),
        'impact_wall_01': ('kenney_impactMining_000', 1.0, .62),
        'impact_sand_01': ('kenney_footstep_grass_001', 1.2, .49),
        'hit': ('kenney_impactSoft_heavy_001', 1.05, .57),
        'reload': ('springy_reload', 1.0, .56),
        'reload_mg_01': ('springy_reload', .85, .59),
        'station_handle_01': ('springy_cock', 1.0, .49),
        'mortar_load_01': ('kenney_impactTin_medium_000', .80, .55),
        'step_01': ('kenney_footstep_grass_000', 1.0, .34),
        'step_02': ('kenney_footstep_grass_001', 1.0, .34),
        'step_concrete_01': ('kenney_footstep_concrete_000', 1.0, .32),
    }
    for name, (source, factor, peak) in foley.items():
        data = pitch(read(source), factor)
        if name == 'impact_wall_01': data = data[:18000]
        results.append(save(name, data, peak))
    # Cloth/soft handling assembled from recorded grass and soft impacts, not a beep.
    cloth = band(grass, 350, 7000)
    results.append(save('bandage_01', mix(1.15, [(cloth, 0, .50),
                                               (pitch(cloth, 1.12), .35, .30), (soft, .82, .13)]), .38))
    (BASE / 'MIX_REPORT.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
    print('Generated', len(results), 'sampled/foley WAV effects; licensed sources preserved.')


if __name__ == '__main__':
    main()
