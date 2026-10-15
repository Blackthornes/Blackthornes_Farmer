"""Make the addon's own sounds, Media/Sounds/*.ogg.

    python -m pip install numpy soundfile
    python tools/make_sounds.py

They are built from sine waves here rather than taken from a sound library, so
they belong to this addon and can ship on CurseForge with it. The owner picked
these two on 2026-09-26: rare-drop (a green-or-better item drops) and
drop-rates-unlocked (a mob's 20th kill); rank-up (2026-10-13) when a mob climbs
your top 15; xp-tick (2026-10-13) for each tenth of a level on the XP bar;
top-farm (2026-10-14) when an auction scan puts a new mob first on your board;
cute, laurel, slayer, beast and fear (2026-10-15) for kill milestones.
Run it again only to change them (name files to write only those:
python tools/make_sounds.py top-farm.ogg);
the game needs a full restart to pick up a changed file.
"""

import os
import sys

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


def sweep(f0, f1, sec, decay=0.12):
    """A sine sliding from f0 to f1: a soft little boop."""
    x = t(sec)
    freq = f0 + (f1 - f0) * (x / sec)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-x / decay) * np.clip(x / 0.004, 0, 1)


def drum(freq, sec, decay=0.35):
    """A deep drum: a thump whose pitch falls as it rings, and a slap."""
    x = t(sec)
    pitch = freq * (1 + 1.6 * np.exp(-x * 28))
    body = np.sin(2 * np.pi * np.cumsum(pitch) / SR) * np.exp(-x / decay)
    rng = np.random.default_rng(int(freq))
    slap = rng.standard_normal(len(x)) * np.exp(-x * 45)
    slap = np.convolve(slap, np.ones(24) / 24, mode="same")
    return body + 0.6 * slap


def drone(freq, sec, attack=0.3, release=0.8):
    """A low, dark hum, two voices a little apart so it wavers."""
    x = t(sec)
    out = np.zeros_like(x)
    for detune in (1.0, 1.012):
        for h in range(1, 7):
            out += np.sin(2 * np.pi * freq * detune * h * x) / h ** 1.6
    shiver = 0.75 + 0.25 * np.sin(2 * np.pi * 5.5 * x)
    a = np.clip(x / attack, 0, 1)
    r = np.clip((sec - x) / release, 0, 1)
    return out * shiver * a * r


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


ONLY = set(sys.argv[1:])


def finish(x, name, peak_db):
    if ONLY and name not in ONLY:
        return
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

# Rank up (2026-10-13): a mob climbs your top 15. Two soft bell notes, E6 up
# to B6, quieter than the others, since it can come every few kills.
buf = np.zeros(int(SR * 0.9))
soft = ((1, 1), (2.76, .35), (5.4, .18))
place(buf, 0.7 * bell(1318.5, 0.8, 0.28, soft), 0.0)
place(buf, bell(1975.5, 0.8, 0.28, soft), 0.09)
finish(reverb(buf, 0.2), "rank-up.ogg", -9)

# XP tick (2026-10-13): a tenth of a level crossed on the XP bar. One soft
# bell, G6 with a faint D7 over it, the quietest of all, since it comes
# ten times a level.
buf = np.zeros(int(SR * 0.8))
place(buf, bell(1568.0, 0.7, 0.22, soft), 0.0)
place(buf, 0.35 * bell(2349.3, 0.6, 0.2, soft), 0.03)
finish(reverb(buf, 0.15), "xp-tick.ogg", -14)

# Top farm (2026-10-14): an auction scan put a new mob first on your board.
# A run of coin bells climbing to a held chord, brighter than a rank-up,
# since it comes once a scan at most.
buf = np.zeros(int(SR * 2.2))
for i, f in enumerate((1318.5, 1568.0, 1975.5, 2637.0)):
    place(buf, (0.55 + 0.08 * i) * bell(f, 0.9, 0.25, soft), i * 0.07)
for f in (659.25, 783.99, 987.77, 1318.5):
    place(buf, 0.22 * brass(f, 1.1, 0.03, 0.7), 0.3)
place(buf, 0.45 * bell(3136.0, 1.0, 0.3), 0.34)
finish(reverb(buf, 0.3), "top-farm.ogg", -6)

# Milestones (2026-10-15). Cute: two soft boops, up then up again, for a
# moment of baby talk.
buf = np.zeros(int(SR * 0.9))
place(buf, sweep(880, 1320, 0.22), 0.0)
place(buf, 0.9 * sweep(1100, 1760, 0.26), 0.17)
place(buf, 0.35 * bell(2637.0, 0.6, 0.2, soft), 0.36)
finish(reverb(buf, 0.25), "cute.ogg", -8)

# Laurel: a gentle silver chime, three high bells falling into place.
buf = np.zeros(int(SR * 1.8))
for i, f in enumerate((2349.3, 1975.5, 2637.0)):
    place(buf, (0.7 + 0.1 * i) * bell(f, 1.4, 0.45, soft), i * 0.12)
place(buf, 0.2 * brass(1174.7, 1.0, 0.1, 0.8), 0.24)
finish(reverb(buf, 0.45), "laurel.ogg", -7)

# Slayer: a heavy war drum, two beats and a big one, and a horn on top.
buf = np.zeros(int(SR * 3.0))
place(buf, 0.7 * drum(62, 0.9), 0.0)
place(buf, 0.7 * drum(62, 0.9), 0.32)
place(buf, drum(55, 1.6, 0.6), 0.64)
for f in (196.0, 293.66, 392.0):
    place(buf, 0.18 * brass(f, 1.6, 0.06, 1.0), 0.66)
finish(reverb(buf, 0.35), "slayer.ogg", -3)

# Beast: a low, dark swell with a deep drum under it (played when the
# game's own voice line will not).
buf = np.zeros(int(SR * 2.2))
place(buf, drone(55.0, 2.0, 0.4, 1.0), 0.0)
place(buf, 0.6 * drum(45, 1.4, 0.7), 0.05)
finish(reverb(buf, 0.3), "beast.ogg", -5)

# Fear: a slow heartbeat, two pairs of thumps, under a quiet hum.
buf = np.zeros(int(SR * 2.4))
for at in (0.0, 0.22, 1.0, 1.22):
    place(buf, (0.9 if at in (0.0, 1.0) else 0.65) * drum(48, 0.5, 0.15), at)
place(buf, 0.25 * drone(73.4, 2.2, 0.5, 1.0), 0.0)
finish(reverb(buf, 0.2), "fear.ogg", -7)
