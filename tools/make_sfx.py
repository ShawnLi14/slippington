"""Synthesize the game's sound effects into godot/assets/audio/*.wav.

Chiptune-adjacent SFX built from sine/square/noise primitives — no external
assets or licenses. Run: python tools/make_sfx.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "audio")


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples
        )
        w.writeframes(frames)
    print("wrote", path)


def env(i, n, attack=0.01, release=0.3):
    t = i / n
    a = min(1.0, (i / RATE) / max(attack, 1e-6))
    r = min(1.0, (1.0 - t) / max(release, 1e-6))
    return a * min(1.0, r)


def tone(freq_fn, dur, wave_fn=math.sin, attack=0.01, release=0.3, vol=0.8):
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        f = freq_fn(i / n)
        phase += 2 * math.pi * f / RATE
        out.append(wave_fn(phase) * env(i, n, attack, release) * vol)
    return out


def square(p):
    return 0.6 if math.sin(p) >= 0 else -0.6


def noise(_p):
    return random.uniform(-0.7, 0.7)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    peak = max(1.0, max(abs(s) for s in out))
    return [s / peak for s in out]


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


random.seed(7)

# Movement / objects
write_wav("jump", tone(lambda t: 240 + 260 * t, 0.12, square, release=0.5, vol=0.45))
write_wav("spring", tone(lambda t: 180 + 520 * t + 30 * math.sin(t * 40), 0.28, release=0.35, vol=0.7))
write_wav("portal", tone(lambda t: 500 + 250 * math.sin(t * 18), 0.32, release=0.3, vol=0.6))

# Tag: noise thump + falling chirp
write_wav("tag", mix(
    tone(lambda t: 90, 0.16, noise, release=0.9, vol=0.7),
    tone(lambda t: 900 - 500 * t, 0.18, release=0.5, vol=0.6),
))

# Abilities
write_wav("blink", tone(lambda t: 600 + 900 * t, 0.18, release=0.4, vol=0.6))
write_wav("swap", seq(
    tone(lambda t: 880, 0.09, release=0.4, vol=0.55),
    tone(lambda t: 440, 0.12, release=0.5, vol=0.55),
))
write_wav("stun", tone(lambda t: 110 - 30 * t, 0.34, square, release=0.4, vol=0.5))

# Round flow
write_wav("tick", tone(lambda t: 1250, 0.05, release=0.8, vol=0.5))
write_wav("caught", seq(
    tone(lambda t: 392, 0.16, release=0.4, vol=0.6),
    tone(lambda t: 311, 0.16, release=0.4, vol=0.6),
    tone(lambda t: 233, 0.30, release=0.5, vol=0.6),
))
write_wav("survived", seq(
    tone(lambda t: 392, 0.13, release=0.4, vol=0.6),
    tone(lambda t: 494, 0.13, release=0.4, vol=0.6),
    tone(lambda t: 587, 0.13, release=0.4, vol=0.6),
    tone(lambda t: 784, 0.30, release=0.5, vol=0.6),
))

# Ambient music loop: two soft chords (Am, F) with gentle detune shimmer.
def pad_chord(freqs, dur):
    n = int(RATE * dur)
    out = [0.0] * n
    for f in freqs:
        for det in (0.0, 0.7):
            phase = random.uniform(0, math.tau)
            for i in range(n):
                t = i / n
                fade = min(1.0, t / 0.18, (1.0 - t) / 0.18)
                trem = 0.85 + 0.15 * math.sin(2 * math.pi * 0.6 * i / RATE + phase)
                out[i] += math.sin(phase + 2 * math.pi * (f + det) * i / RATE) * fade * trem
        # soft octave sparkle
    peak = max(abs(s) for s in out)
    return [s / peak * 0.30 for s in out]


loop = seq(
    pad_chord([220.0, 261.63, 329.63], 4.8),   # Am
    pad_chord([174.61, 220.0, 261.63], 4.8),   # F
)
write_wav("music_loop", loop)
