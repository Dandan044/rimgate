"""Reproducible original sound effects and repo-native SVG UI icons.

No bitmap artwork is generated or edited here. Character and prop PNGs are
unaltered outputs of the built-in image generation tool.
"""
from pathlib import Path
import math
import random
import struct
import wave

BASE = Path(__file__).resolve().parent
RATE = 48000


def sound(name, duration, kind, pitch=1.0):
    rng = random.Random(7201 + sum(map(ord, name)))
    values = []
    filtered = 0.0
    for index in range(int(duration * RATE)):
        t = index / RATE
        noise = rng.uniform(-1, 1)
        filtered = filtered * 0.84 + noise * 0.16
        if kind == "shot":
            value = 0.65 * noise * math.exp(-t * 65) + 0.40 * filtered * math.exp(-t * 18)
            value += 0.35 * math.sin(2 * math.pi * (140 * pitch * t - 160 * t * t)) * math.exp(-t * 26)
        elif kind == "blast":
            attack = min(1, t * 130)
            value = attack * (filtered * 1.9 + 0.4 * math.sin(2 * math.pi * 42 * pitch * t)) * math.exp(-t * 3.8)
        elif kind == "mortar":
            value = (filtered * 1.5 + math.sin(2 * math.pi * (95 * t - 35 * t * t)) * 0.4) * math.exp(-t * 9)
        elif kind == "impact":
            value = (noise * 0.35 + math.sin(2 * math.pi * 1200 * t) * 0.35) * math.exp(-t * 60)
        elif kind == "hit":
            value = (filtered + math.sin(2 * math.pi * 120 * t) * 0.2) * math.exp(-t * 34)
        elif kind == "reload":
            pulse = math.exp(-t * 100) + (math.exp(-(t - 0.13) * 90) if t > 0.13 else 0)
            value = (noise * 0.3 + math.sin(2 * math.pi * 1700 * t) * 0.25) * pulse
        else:
            frequencies = {"order": [690, 940], "alert": [520, 390, 520], "victory": [440, 554.37, 659.25, 880], "defeat": [392, 329.63, 261.63]}[kind]
            note_length = duration / len(frequencies)
            note = min(len(frequencies) - 1, int(t / note_length))
            local = t - note * note_length
            envelope = min(1, local * 70) * min(1, (note_length - local) * 35) * math.exp(-local * 2)
            value = (math.sin(2 * math.pi * frequencies[note] * t) + 0.17 * math.sin(4 * math.pi * frequencies[note] * t)) * envelope * 0.4
        value *= min(1, t * 1800, (duration - t) * 200)
        values.append(value)
    peak = max(max(map(abs, values)), 0.001)
    data = b"".join(struct.pack("<h", int(max(-1, min(1, sample / peak * 0.76)) * 32767)) for sample in values)
    with wave.open(str(BASE / "audio" / f"{name}.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(data)


def main():
    (BASE / "audio").mkdir(exist_ok=True)
    (BASE / "icons").mkdir(exist_ok=True)
    specs = [
        ("rifle_1", .22, "shot", 1), ("rifle_2", .25, "shot", 1.13),
        ("mg_1", .20, "shot", .7), ("mg_2", .23, "shot", .76),
        ("mortar", .65, "mortar", 1),
        ("explosion_1", 1.5, "blast", 1), ("explosion_2", 1.75, "blast", .86),
        ("impact", .12, "impact", 1), ("hit", .18, "hit", 1),
        ("reload", .3, "reload", 1), ("order", .16, "order", 1),
        ("alert", .75, "alert", 1), ("victory", 1.25, "victory", 1),
        ("defeat", 1.2, "defeat", 1),
    ]
    for spec in specs:
        sound(*spec)
    drawings = {
        "move": '<path d="M7 24h31M25 10l14 14-14 14"/>',
        "attack": '<circle cx="24" cy="24" r="13"/><path d="M24 3v10m0 22v10M3 24h10m22 0h10"/>',
        "stop": '<rect x="12" y="12" width="24" height="24" rx="2"/>',
        "operate": '<circle cx="24" cy="24" r="9"/><path d="M24 5v7m0 24v7M5 24h7m24 0h7M10 10l5 5m18 18 5 5M10 38l5-5m18-18 5-5"/>',
        "rescue": '<path d="M6 15v24m36-24v24M6 29h36M12 22h24M20 9h8m-4-4v8"/>',
        "treat": '<path d="M19 7h10v12h12v10H29v12H19V29H7V19h12Z"/>',
        "stand": '<circle cx="24" cy="9" r="4"/><path d="M24 15v15m-11-9 11-6 11 6M24 30l-9 12m9-12 9 12"/>',
        "crouch": '<circle cx="25" cy="10" r="4"/><path d="m24 16-4 12 15 3-9 11M20 28l-8 12m10-21 13 5"/>',
        "prone": '<circle cx="38" cy="23" r="4"/><path d="M32 26H18L7 34m11-8L7 21m20 5 6 8h11"/>',
        "suppress": '<path d="M7 13h24m-24 11h34M7 35h24m4-27 7 5-7 5m0 12 7 5-7 5"/>',
        "normal": '<path d="M8 17h25M8 31h25m-4-19 7 5-7 5m0 4 7 5-7 5"/>',
        "cautious": '<circle cx="24" cy="24" r="15"/><circle cx="24" cy="24" r="3"/><path d="M24 4v9m0 22v9M4 24h9m22 0h9"/>',
        "bleed": '<path d="M24 5c0 0-12 17-12 24a12 12 0 0 0 24 0C36 22 24 5 24 5Z"/>',
        "downed": '<path d="M8 30h30M15 23h16m-7-16v10m-5-5h10"/><circle cx="38" cy="26" r="4"/>',
        "rout": '<path d="M5 24h24m-9-9 9 9-9 9M37 8v32m-6-32h10m-10 32h10"/>',
        "blocked": '<path d="M9 9l30 30M39 9 9 39"/><circle cx="24" cy="24" r="19"/>',
        "pause": '<path d="M16 8v32m16-32v32"/>',
    }
    for name, drawing in drawings.items():
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 48 48"><g fill="none" stroke="#d4ebd6" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">{drawing}</g></svg>\n'
        (BASE / "icons" / f"{name}.svg").write_text(svg, encoding="utf-8")
    print(f"Generated {len(specs)} original WAV effects and {len(drawings)} original SVG UI icons")


if __name__ == "__main__":
    main()
