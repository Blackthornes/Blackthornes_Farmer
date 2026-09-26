"""Make the addon's own sounds, Media/Sounds/*.ogg.

    python -m pip install numpy soundfile
    python tools/make_sounds.py

Both are built from sine waves here rather than taken from a sound library, so
they belong to this addon and can ship on CurseForge with it. Trent picked
these two on 2026-09-26: rare-drop (a green-or-better item drops) and
drop-rates-unlocked (a mob's 20th kill). Run it again only to change them;
the game needs a full restart to pick up a changed file.
"""

import os

import numpy as np
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media", "Sounds")
os.makedirs(OUT, exist_ok=True)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def bell(freq, sec, decay, partials=((1, 1), (2.76, .45), (5.4, .25), (8.93, .12))):
    x = t(sec)
    out = np.zeros_like(x)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-x * ratio / decay)
    return out * np.clip(x / 0.002, 0, 1)


def brass(freq, sec, attack=0.04, release=0.35):
    x = t(sec)
    out = np.zeros_like(x)
    for h in range(1, 12):
        out += np.sin(2 * np.pi * freq * h * x * (1 + 0.0015 * np.sin(2 * np.pi * 5 * x))) / h ** 1.3
    a = np.clip(x / attack, 0, 1)
    r = np.clip((sec - x) / release, 0, 1)
    return out * a * r


def place(buf, clip, at):
    i = int(at * SR)
    end = min(len(buf), i + len(clip))
    buf[i:end] += clip[:end - i]


def reverb(x, mix=0.25):
    out = x.copy()
    for d, g in ((0.029, .5), (0.037, .45), (0.043, .4), (0.051, .35), (0.067, .3), (0.089, .25)):
        k = int(d * SR)
        y = np.zeros(len(x) + k * 12)
        y[:len(x)] = x
        # cheap feedback comb, vectorised in blocks of k
        z = np.zeros_like(y)
        z[:len(x)] = x
        for s in range(k, len(y), k):
            z[s:s + k] += g * z[s - k:s][:len(z[s:s + k])]
        out = np.pad(out, (0, len(z) - len(out)))
        out += mix / 6 * z
    return out


def finish(x, name, peak_db):
    x = x - np.mean(x)
    # trim trailing silence
    thresh = np.max(np.abs(x)) * 10 ** (-60 / 20)
    last = np.max(np.nonzero(np.abs(x) > thresh)) + 1
    x = x[:last]
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / np.max(np.abs(x)) * 10 ** (peak_db / 20)
    sf.write(os.path.join(OUT, name), x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    print(name, round(len(x) / SR, 2), "s")


# Rare drop: a quick bright arpeggio sparkle (C6 E6 G6 C7 E7).
buf = np.zeros(int(SR * 1.6))
for i, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0, 2637.0)):
    place(buf, (0.8 + 0.05 * i) * bell(f, 1.2, 0.35), i * 0.055)
finish(reverb(buf, 0.35), "rare-drop.ogg", -4)

# Drop rates unlocked: short brass fanfare with a sparkle on top.
buf = np.zeros(int(SR * 2.6))
notes = ((0.00, 392.0, 0.14), (0.14, 523.25, 0.14), (0.28, 659.25, 0.14))
for at, f, d in notes:
    place(buf, 0.5 * brass(f, d + 0.05, 0.015, 0.05), at)
for f in (523.25, 659.25, 783.99, 1046.5):
    place(buf, 0.33 * brass(f, 1.2, 0.03, 0.8), 0.44)
for i, f in enumerate((2093.0, 2637.0, 3136.0, 4186.0)):
    place(buf, 0.35 * bell(f, 1.0, 0.3), 0.46 + i * 0.07)
finish(reverb(buf, 0.4), "drop-rates-unlocked.ogg", -3)
