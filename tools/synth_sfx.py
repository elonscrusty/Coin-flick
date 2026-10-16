"""Synthesize CRACK THE ROCKS' original sound effects (numpy + ffmpeg only) into art/sfx/<Name>.ogg.

    python3 tools/synth_sfx.py [--only A,B] [--wav]

Everything is generated from sines, noise and FFT filters, so the files are original and free
to upload. Deterministic (seeded per sound name). Loops use circular (FFT) filtering, whole
beats and wrap-around adds, so they repeat without a click. Needs ffmpeg for the .ogg step
(--wav writes plain 16-bit mono 44.1 kHz WAV instead).
Upload with tools/upload_audio.py; the catalog is in docs/AUDIO.md.
"""

import argparse
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "sfx")


def rng_for(name: str):
    return np.random.default_rng(sum(ord(c) * (i + 3) for i, c in enumerate(name)) % 100003)


# ---------------------------------------------------------------- building blocks

def T(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur, r):
    return r.standard_normal(int(dur * SR))


def filt(x, lo=None, hi=None, order=2):
    """FFT band filter: pass lo..hi Hz (None = open). Circular, so loops stay seamless."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g = g / (1 + (f / hi) ** (2 * order))
    if lo:
        g = g * (1 - 1 / (1 + (f / lo) ** (2 * order)))
    return np.fft.irfft(spec * g, len(x))


def lp(x, hi, order=2):
    return filt(x, None, hi, order)


def hp(x, lo, order=2):
    return filt(x, lo, None, order)


def bp(x, lo, hi):
    return filt(x, lo, hi)


def env(n, attack, decay):
    t = np.arange(n) / SR
    return np.clip(t / max(attack, 1e-4), 0, 1) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))


def glide(f0, f1, dur, shape=1.0):
    n = int(dur * SR)
    k = (np.arange(n) / max(n - 1, 1)) ** shape
    return np.sin(2 * np.pi * np.cumsum(f0 * (f1 / f0) ** k) / SR)


def fade(x, fin=0.002, fout=0.02):
    x = x.copy()
    i, o = int(fin * SR), int(fout * SR)
    if i:
        x[:i] *= np.linspace(0, 1, i)
    if o:
        x[-o:] *= np.linspace(1, 0, o)
    return x


def soft(x, drive=1.6):
    return np.tanh(x * drive) / np.tanh(drive)


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    if j > i:
        dst[i:j] += src[: j - i]
    return dst


def wrap_add(dst, src, at):
    """Add src at time `at`, wrapping past the end (keeps loops seamless)."""
    idx = (int(at * SR) + np.arange(len(src))) % len(dst)
    np.add.at(dst, idx, src)
    return dst


def bell(freq, dur, decay=0.4, ratios=(1, 2.0, 2.76, 4.07), bright=0.5):
    t = T(dur)
    out = np.zeros_like(t)
    for k, r in enumerate(ratios):
        out += (bright ** k) / (1 + k) * np.sin(2 * np.pi * freq * r * t + k) * np.exp(-t / (decay / (1 + 0.8 * k)))
    return out * np.clip(t / 0.002, 0, 1)


def note(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def thump(m, f0=170, f1=85, decay=0.014, grit=0.45, r=None):
    """One machine impact of m samples: low pitched knock plus a short bright tick."""
    body = soft(glide(f0, f1, m / SR, 0.5) * np.exp(-np.arange(m) / SR / decay), 2)
    tick = hp(r.standard_normal(m), 1500) * np.exp(-np.arange(m) / SR / 0.005) * grit
    return body + tick


# ---------------------------------------------------------------- one-shots

def hammer_hit(i):
    r = rng_for(f"hit{i}")
    base = (150, 175, 130)[i]
    n = int(0.16 * SR)
    body = soft(glide(base * 1.9, base, 0.16, 0.6) * env(n, 0.001, 0.035), 2.0)
    clack = bp(noise(0.16, r), 1200 + 500 * i, 4200) * env(n, 0.0005, 0.012)
    return fade(body * 0.8 + clack * 0.9, 0.0005, 0.03)


def stone_crack(i):
    r = rng_for(f"crack{i}")
    dur = (0.34, 0.42, 0.30)[i]
    n = int(dur * SR)
    snap = hp(noise(dur, r), 1800) * env(n, 0.0005, 0.02)
    ticks = np.zeros(n)
    for k in range(4 + i):
        at = int((0.04 + r.random() * (dur - 0.1)) * SR)
        m = min(int(0.02 * SR), n - at)
        ticks[at:at + m] += hp(r.standard_normal(m), 2500) * np.exp(-np.arange(m) / SR / 0.004) * (0.5 - k * 0.05)
    body = soft(glide(220, 90, dur, 0.5) * env(n, 0.001, 0.05), 1.8)
    return fade(snap * 0.7 + ticks * 0.6 + body * 0.6, 0.0005, 0.05)


def gravel_spill(i):
    r = rng_for(f"gravel{i}")
    dur = (0.7, 0.95)[i]
    n = int(dur * SR)
    x = np.zeros(n)
    for _ in range(26 + i * 12):
        at = int(r.random() ** 1.6 * (dur - 0.08) * SR)
        m = int(0.025 * SR)
        f = 1500 + r.random() * 3500
        x[at:at + m] += bp(r.standard_normal(m), f * 0.6, f * 1.4) * np.exp(-np.arange(m) / SR / 0.006) * (0.3 + r.random() * 0.7)
    bed = lp(noise(dur, r), 2400) * env(n, 0.02, dur * 0.4) * 0.25
    return fade(soft(x * 2.2 + bed, 1.3), 0.002, 0.15)


def press_descend():
    t = T(1.1)
    motor = glide(70, 110, 1.1) + 0.5 * glide(140, 220, 1.1)
    hiss = bp(noise(1.1, rng_for("pd")), 800, 3000) * 0.25
    return fade(soft(motor * 0.5 + hiss, 1.5) * np.clip(t / 0.1, 0, 1), 0.01, 0.1) * 0.8


def press_impact():
    r = rng_for("pi")
    n = int(0.9 * SR)
    sub = soft(glide(110, 38, 0.9, 0.4) * env(n, 0.002, 0.16), 2.0)
    clang = bell(240, 0.9, 0.35, (1, 2.4, 3.9)) * 0.35
    crunch = lp(noise(0.9, r), 3000) * env(n, 0.001, 0.05)
    return fade(sub + clang + crunch * 0.7, 0.0005, 0.12)


def press_retract():
    t = T(0.9)
    motor = glide(120, 75, 0.9) + 0.5 * glide(240, 150, 0.9)
    hiss = bp(noise(0.9, rng_for("pr")), 700, 2600) * env(len(t), 0.05, 0.3) * 0.5
    return fade(soft(motor * 0.45, 1.5) * np.clip(1 - t / 0.9, 0, 1) ** 0.5 * 0.8 + hiss, 0.01, 0.1)


def jackhammer_start():
    r = rng_for("jhs")
    dur = 0.7
    n = int(dur * SR)
    x = np.zeros(n)
    m = int(0.05 * SR)
    at, k = 0.0, 0
    while at < dur - 0.05:
        s = int(at * SR)
        e = min(n, s + m)
        x[s:e] += thump(m, r=r)[: e - s]
        at += 1 / min(4 + k * 0.5, 22)
        k += 1
    return fade(x * np.clip(T(dur) / 0.15, 0, 1), 0.002, 0.04)


def jackhammer_loop():
    # 16 impacts in exactly 1.0 s, tails wrap around: repeats without a seam
    r = rng_for("jhl")
    n = SR
    x = np.zeros(n)
    m = int(0.06 * SR)
    for b in range(16):
        wrap_add(x, thump(m, 170, 85, 0.014, 0.45, r), b / 16)
    return soft(x, 1.2) * 0.8


def jackhammer_stop():
    r = rng_for("jhx")
    dur = 0.5
    n = int(dur * SR)
    x = np.zeros(n)
    at, rate = 0.0, 16.0
    m = int(0.05 * SR)
    while at < dur - 0.05:
        s = int(at * SR)
        e = min(n, s + m)
        x[s:e] += thump(m, 160, 80, 0.012, 0.4, r)[: e - s] * (1 - at / dur)
        at += 1 / rate
        rate = max(3.0, rate * 0.9)
    return fade(x, 0.002, 0.05)


def conveyor_hum():
    dur = 2.0
    t = T(dur)
    hum = np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 110 * t) * 0.3 + np.sin(2 * np.pi * 165 * t) * 0.1
    rumble = lp(noise(dur, rng_for("cv")), 350) * 0.5
    tick = np.zeros(len(t))
    m = int(0.03 * SR)
    for b in range(8):
        tk = bp(rng_for(f"cvt{b}").standard_normal(m), 600, 2200) * np.exp(-np.arange(m) / SR / 0.008)
        wrap_add(tick, tk * 0.35, b * dur / 8)
    return soft(hum * 0.5 + rumble + tick, 1.2) * 0.7


def crusher_loop():
    dur = 2.0
    t = T(dur)
    grind = lp(noise(dur, rng_for("cr")), 1400) * (0.6 + 0.4 * np.sin(2 * np.pi * 4 * t))
    low = np.sin(2 * np.pi * 48 * t) * 0.4 + np.sin(2 * np.pi * 96 * t + 1) * 0.25
    knock = np.zeros(len(t))
    m = int(0.07 * SR)
    kn = soft(glide(140, 70, 0.07) * np.exp(-np.arange(m) / SR / 0.02), 2) * 0.6
    for b in range(6):
        wrap_add(knock, kn, b * dur / 6)
    return soft(grind * 0.8 + low + knock, 1.5) * 0.7


def geode_reveal():
    out = np.zeros(int(2.0 * SR))
    for n_, at in ((84, 0.0), (88, 0.12), (91, 0.24), (96, 0.38)):
        place(out, bell(note(n_), 1.6, 0.9), at)
    shimmer = hp(noise(2.0, rng_for("gr")), 5000) * env(len(out), 0.3, 0.5) * 0.06
    return fade(soft(out * 0.35 + shimmer, 1.2), 0.002, 0.3)


def rarity_accent():
    out = np.zeros(int(1.6 * SR))
    for k, n_ in enumerate((74, 81, 86, 93)):
        place(out, bell(note(n_), 1.1, 0.5, (1, 2.0, 3.0)), k * 0.08)
    return fade(soft(out * 0.35, 1.2), 0.002, 0.2)


def sale():
    out = np.zeros(int(0.6 * SR))
    place(out, bell(note(88), 0.3, 0.12, (1, 2.7)), 0.0)
    place(out, bell(note(95), 0.45, 0.16, (1, 2.7)), 0.07)
    place(out, hp(noise(0.05, rng_for("sale")), 4500) * np.exp(-T(0.05) / 0.01) * 0.3, 0.0)
    return fade(soft(out * 0.5, 1.2), 0.001, 0.1)


def pickup():
    """A rock lifted off the pile: a short scrape-and-lift, a dull stone knock, a tiny rattle of chips."""
    r = rng_for("pickup")
    n = int(0.28 * SR)
    scrape = bp(noise(0.28, r), 700, 3200) * env(n, 0.03, 0.05) * np.clip(1 - T(0.28) / 0.12, 0, 1) * 0.45
    knock = soft(glide(210, 120, 0.28, 0.5) * env(n, 0.001, 0.045), 2.0) * 0.8
    out = scrape + knock
    for at in (0.1, 0.15, 0.2):
        m = int(0.02 * SR)
        place(out, hp(r.standard_normal(m), 2600) * np.exp(-np.arange(m) / SR / 0.004) * 0.25, at)
    return fade(soft(out, 1.4), 0.001, 0.08)


def deposit():
    """A rock set down on the crushing table: a heavy low thud, a clatter, then chips settling."""
    r = rng_for("deposit")
    dur = 0.4
    n = int(dur * SR)
    thud = soft(glide(150, 62, dur, 0.4) * env(n, 0.001, 0.07), 2.4)
    clack = bp(noise(dur, r), 900, 4000) * env(n, 0.0005, 0.015) * 0.7
    out = thud * 0.9 + clack
    for at, g in ((0.07, 0.35), (0.12, 0.25), (0.19, 0.2), (0.26, 0.12)):
        m = int(0.022 * SR)
        place(out, bp(r.standard_normal(m), 1800, 5200) * np.exp(-np.arange(m) / SR / 0.005) * g, at)
    return fade(soft(out, 1.3), 0.0005, 0.1)


def material_found():
    """A new material discovered: a rising two-note glass chime over a soft sparkle."""
    out = np.zeros(int(1.0 * SR))
    place(out, bell(note(79), 0.8, 0.35, (1, 2.0, 3.0, 5.0)), 0.0)
    place(out, bell(note(86), 0.9, 0.45, (1, 2.0, 3.0, 5.0)), 0.12)
    place(out, bell(note(91), 0.8, 0.4, (1, 2.0, 4.0)) * 0.6, 0.24)
    spark = hp(noise(1.0, rng_for("mf")), 6000) * env(len(out), 0.15, 0.25) * 0.04
    return fade(soft(out * 0.38 + spark, 1.2), 0.001, 0.25)


def purchase():
    out = np.zeros(int(0.7 * SR))
    for n_, at, d in ((72, 0.0, 0.2), (79, 0.09, 0.25), (84, 0.18, 0.3)):
        place(out, bell(note(n_), 0.5, d, (1, 2.0, 3.0)), at)
    return fade(soft(out * 0.4, 1.2), 0.001, 0.15)


def button():
    n = int(0.07 * SR)
    return fade(soft(glide(520, 380, 0.07, 0.6) * env(n, 0.001, 0.02), 1.5) * 0.7, 0.0005, 0.02)


def countdown_tick():
    t = T(0.15)
    n = len(t)
    x = np.sin(2 * np.pi * 880 * t) * env(n, 0.001, 0.04) + 0.3 * np.sin(2 * np.pi * 1760 * t) * env(n, 0.001, 0.02)
    return fade(soft(x, 1.2) * 0.6, 0.0005, 0.03)


def match_win():
    out = np.zeros(int(2.0 * SR))
    for n_, at in ((67, 0.0), (72, 0.15), (76, 0.3), (79, 0.45), (84, 0.7)):
        place(out, bell(note(n_), 1.3, 0.6, (1, 2.0, 3.0, 4.0), 0.4), at)
    pad = np.zeros_like(out)
    for n_ in (60, 64, 67, 72):
        pad += np.sin(2 * np.pi * note(n_) * T(2.0))
    pad = lp(pad, 1200) * env(len(out), 0.25, 0.6) * 0.1
    return fade(soft(out * 0.3 + pad, 1.2), 0.002, 0.35)


# ---------------------------------------------------------------- ambience loops (8 s)

def _chirp(r, f0, f1, dur, wob=0.0):
    """One small bird call: a quick pitch sweep with a soft envelope and a little warble."""
    n = int(dur * SR)
    k = np.arange(n) / max(n - 1, 1)
    f = f0 * (f1 / f0) ** k * (1 + wob * np.sin(2 * np.pi * 28 * k * dur))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR)
    return x * np.sin(np.pi * k) ** 1.5


def lobby_ambience():
    """Quiet camp bed (12 s loop, Master 8 section 20): soft wind, the distant waterfall as a low steady
    rush, a few sparse bird calls. No tones or bells (nothing musical to grow tiresome on repeat)."""
    dur = 12.0
    t = T(dur)
    r = rng_for("camp")
    wind = lp(noise(dur, r), 520) * (0.65 + 0.35 * np.sin(2 * np.pi * t / dur * 2 + 0.7))
    water = bp(noise(dur, r), 280, 2400) * (0.92 + 0.08 * np.sin(2 * np.pi * t / dur * 3))
    out = wind * 0.34 + water * 0.06
    calls = ((1.3, 3300, 4300, 0.09), (1.48, 3500, 4600, 0.08), (5.2, 2600, 3900, 0.16), (8.4, 4100, 3200, 0.12),
             (8.58, 4000, 3300, 0.1), (10.9, 3000, 3600, 0.14))
    for at, f0, f1, d in calls:
        wrap_add(out, _chirp(r, f0, f1, d, 0.04) * 0.035, at)
    return out


def quarry_ambience():
    """Quiet quarry bed (12 s loop): wind over the cut faces, a low ground rumble, an occasional far gravel
    trickle and a very faint distant machine thrum. No tonal hits."""
    dur = 12.0
    t = T(dur)
    r = rng_for("quarry2")
    wind = bp(noise(dur, r), 140, 900) * (0.55 + 0.45 * np.sin(2 * np.pi * t / dur * 3 + 1))
    rumble = lp(noise(dur, r), 110) * 0.5
    thrum = (np.sin(2 * np.pi * 50 * t) + 0.4 * np.sin(2 * np.pi * 100 * t)) * (0.6 + 0.4 * np.sin(2 * np.pi * t / dur * 6)) * 0.035
    out = wind * 0.3 + rumble * 0.3 + thrum
    for k, at in enumerate((2.1, 6.8, 9.9)):
        m = int(0.5 * SR)
        trickle = bp(r.standard_normal(m), 900, 4000) * np.exp(-np.arange(m) / SR / 0.16) * (0.5 + 0.5 * (r.random(m) > 0.92))
        wrap_add(out, trickle * 0.045, at)
    return out


def machine_hum():
    """Gentle hum near a running machine (4 s loop): a soft 55 Hz motor with its harmonics, a little air,
    a slow swell. Positioned and quiet; Audio loops it while the machine works."""
    dur = 4.0
    t = T(dur)
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * t / dur)
    motor = np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 110 * t + 0.6) * 0.22 + np.sin(2 * np.pi * 165 * t + 1.1) * 0.08
    air = lp(noise(dur, rng_for("hum")), 420) * 0.25
    return soft((motor + air) * swell, 1.1) * 0.6


SOUNDS = {
    "HammerHit1": lambda: hammer_hit(0), "HammerHit2": lambda: hammer_hit(1), "HammerHit3": lambda: hammer_hit(2),
    "StoneCrack1": lambda: stone_crack(0), "StoneCrack2": lambda: stone_crack(1), "StoneCrack3": lambda: stone_crack(2),
    "GravelSpill1": lambda: gravel_spill(0), "GravelSpill2": lambda: gravel_spill(1),
    "JackhammerStart": jackhammer_start, "JackhammerLoop": jackhammer_loop, "JackhammerStop": jackhammer_stop,
    "ConveyorHum": conveyor_hum,
    "PressDescend": press_descend, "PressImpact": press_impact, "PressRetract": press_retract,
    "CrusherLoop": crusher_loop,
    "GeodeReveal": geode_reveal, "RarityAccent": rarity_accent,
    "Pickup": pickup, "Deposit": deposit, "MaterialFound": material_found,
    "Sale": sale, "Purchase": purchase, "Button": button, "CountdownTick": countdown_tick, "MatchWin": match_win,
    "LobbyAmbience": lobby_ambience, "QuarryAmbience": quarry_ambience, "MachineHum": machine_hum,
}


def write_wav(path, x):
    peak = float(np.max(np.abs(x))) or 1.0
    pcm = (np.clip(x / peak * 0.85, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--wav", action="store_true")
    args = ap.parse_args()
    only = {x for x in args.only.split(",") if x}
    os.makedirs(OUT, exist_ok=True)
    for name, fn in SOUNDS.items():
        if only and name not in only:
            continue
        x = fn()
        if args.wav:
            path = os.path.join(OUT, name + ".wav")
            write_wav(path, x)
        else:
            path = os.path.join(OUT, name + ".ogg")
            with tempfile.TemporaryDirectory() as d:
                tmp = os.path.join(d, name + ".wav")
                write_wav(tmp, x)
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-ac", "1", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", "3", path], check=True)
        print(f"{name:<18} {len(x) / SR:5.2f}s {os.path.getsize(path) // 1024:4d} KB")


if __name__ == "__main__":
    main()
