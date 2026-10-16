"""Synthesize Find The Pet's original short sound effects into art/sfx/<Name>.ogg.

    python3 tools/synth_pet_sfx.py [--only A,B] [--wav]

Same building blocks and output format as tools/synth_sfx.py (sines, noise, FFT filters; seeded,
so the files are original and free to upload). Upload with tools/upload_audio.py, which picks up
every art/sfx/*.ogg and regenerates src/shared/SoundIds.luau; src/shared/PetSoundIds.luau then
reads the new ids from there. Music is not made here (search list in docs/AUDIO.md). Pets never roar
(owner rule): there are no roar sounds; big hatches use HatchSparkle and HatchDrum instead.
Every file is peak-normalized to the same level (PEAK = -3 dBFS, so the .ogg step never clips).
"""

import argparse
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from synth_sfx import (  # noqa: E402
    OUT, SR, T, _chirp, bell, bp, env, fade, glide, hp, lp, noise, note, place, rng_for, soft,
)

PEAK = 0.708  # -3 dBFS: one level for every pet sound, with headroom so Vorbis overshoot never clips


def write_wav(path, x):
    """16-bit mono WAV, peak-normalized to PEAK (synth_sfx.write_wav uses 0.85, too hot for the .ogg step)."""
    peak = float(np.max(np.abs(x))) or 1.0
    pcm = (np.clip(x / peak * PEAK, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def _shell_ticks(r, out, count, start, spread, level, lo=2600):
    """Scatter tiny bright clicks (eggshell bits) over `spread` seconds from `start`."""
    for k in range(count):
        m = int(0.018 * SR)
        at = start + r.random() ** 1.3 * spread
        place(out, hp(r.standard_normal(m), lo) * np.exp(-np.arange(m) / SR / 0.0035) * level * (1 - k / (count + 2)), at)
    return out


def egg_tap():
    """One tap on an egg: a hollow little knock with a dry shell crunch. Short so fast tapping stays clean."""
    r = rng_for("eggtap")
    dur = 0.16
    n = int(dur * SR)
    knock = soft(glide(620, 380, dur, 0.5) * env(n, 0.0008, 0.02), 1.8) * 0.6
    crunch = bp(noise(dur, r), 2200, 7000) * env(n, 0.0005, 0.012) * 0.7
    out = knock + crunch
    _shell_ticks(r, out, 3, 0.012, 0.05, 0.35)
    return fade(out, 0.0005, 0.03)


def egg_break():
    """An empty egg breaks: a bright pop, a crack, then shell bits falling and a soft puff."""
    r = rng_for("eggbreak")
    dur = 0.6
    n = int(dur * SR)
    pop = soft(glide(900, 260, 0.12, 0.4) * env(int(0.12 * SR), 0.0008, 0.03), 2.0)
    out = np.zeros(n)
    place(out, pop * 0.8, 0.0)
    place(out, hp(noise(0.08, r), 1800) * env(int(0.08 * SR), 0.0005, 0.015) * 0.8, 0.0)
    puff = lp(noise(dur, r), 1500) * env(n, 0.01, 0.08) * 0.25
    out += puff
    _shell_ticks(r, out, 14, 0.06, 0.42, 0.45, 3000)
    return fade(soft(out, 1.3), 0.0005, 0.1)


def egg_chirp():
    """Hint from the pet egg when you are close: two tiny high chirps, like a chick inside."""
    r = rng_for("eggchirp")
    out = np.zeros(int(0.42 * SR))
    place(out, _chirp(r, 2600, 3900, 0.09, 0.05), 0.0)
    place(out, _chirp(r, 2800, 4200, 0.11, 0.05), 0.16)
    return fade(out * 0.8, 0.001, 0.05)


def coin_pickup():
    """Coins collected: a bright two-note ding (B5 then E6) with a little shimmer."""
    out = np.zeros(int(0.7 * SR))
    place(out, bell(note(83), 0.5, 0.18, (1, 2.0, 3.0), 0.35), 0.0)
    place(out, bell(note(88), 0.6, 0.28, (1, 2.0, 3.0), 0.35), 0.075)
    shimmer = hp(noise(0.7, rng_for("coin")), 6000) * env(len(out), 0.005, 0.12) * 0.05
    return fade(soft(out * 0.6 + shimmer, 1.2), 0.0005, 0.12)


def speed_boots():
    """Speed boots switch on: a rising air whoosh with a light zip on top."""
    r = rng_for("boots")
    dur = 0.55
    t = T(dur)
    n = len(t)
    shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    lo_band = bp(noise(dur, r), 500, 1800) * shape
    hi_band = bp(noise(dur, r), 2500, 7000) * shape * np.clip(t / dur, 0, 1)
    zip_ = glide(500, 1600, dur, 1.4) * env(n, 0.05, 0.25) * 0.18
    return fade(soft(lo_band * 0.6 + hi_band * 0.5 + zip_, 1.3), 0.005, 0.08)


def tower_hit():
    """A pet attack lands in the tower: a punchy low thump with a snappy slap on top."""
    r = rng_for("towerhit")
    dur = 0.3
    n = int(dur * SR)
    body = soft(glide(160, 55, dur, 0.4) * env(n, 0.001, 0.06), 2.4)
    slap = bp(noise(dur, r), 1500, 6000) * env(n, 0.0005, 0.018) * 0.9
    return fade(body * 0.9 + slap, 0.0005, 0.06)


def tower_special():
    """A pet's special move: a charging zap that rises for half a second, then a big bright boom."""
    r = rng_for("special")
    out = np.zeros(int(1.4 * SR))
    charge_t = T(0.55)
    charge = glide(220, 1400, 0.55, 1.6) * np.clip(charge_t / 0.55, 0, 1) ** 1.5
    charge = charge + 0.4 * glide(330, 2100, 0.55, 1.6) * np.clip(charge_t / 0.55, 0, 1) ** 2
    place(out, soft(charge, 1.5) * 0.35, 0.0)
    m = int(0.85 * SR)
    boom = soft(glide(130, 40, 0.85, 0.4) * env(m, 0.001, 0.18), 2.2)
    blast = lp(noise(0.85, r), 5000) * env(m, 0.001, 0.09) * 0.7
    sparkle = bell(note(84), 0.85, 0.3, (1, 2.0, 3.0, 4.0), 0.4) * 0.25
    place(out, boom + blast + sparkle, 0.55)
    return fade(soft(out, 1.3), 0.002, 0.2)


# ---------------------------------------------------------------- Find The Pet moments (Item 20)
# Bright cartoon one-shots for the find -> train -> fight loop. No voices, no roars (owner rule).


def _arp(notes, step, dur, decay=0.25, ratios=(1, 2.0, 3.0), bright=0.4, gain=0.5):
    """Bell notes (MIDI numbers) placed `step` seconds apart."""
    out = np.zeros(int((step * (len(notes) - 1) + dur) * SR))
    for k, m in enumerate(notes):
        place(out, bell(note(m), dur, decay, ratios, bright) * gain, k * step)
    return out


def _pad(x, seconds):
    return np.concatenate([x, np.zeros(int(seconds * SR))])


def _sparkles(r, out, count, start, spread, level, lo=5000):
    """Tiny high bell glints scattered over `spread` seconds, over a faint air shimmer."""
    for _ in range(count):
        at = start + r.random() * spread
        f = 2400 + r.random() * 2600
        place(out, bell(f, 0.18, 0.05, (1, 2.4), 0.3) * level * (0.6 + 0.4 * r.random()), at)
    m = int((spread + 0.2) * SR)
    place(out, hp(r.standard_normal(m), lo) * env(m, spread * 0.5, 0.15) * level * 0.15, start)
    return out


def _stab(m, dur, gain=0.25):
    """A bright major triad hit on MIDI root m."""
    return sum(bell(note(m + i), dur, dur * 0.45, (1, 2.0, 3.0), 0.45) for i in (0, 4, 7)) * gain


def hatch_sparkle():
    """Epic and better hatch: a rising sparkle swell (bell glissando over a shimmer) ending on a bright chord."""
    r = rng_for("hatchsparkle")
    out = np.zeros(int(1.5 * SR))
    place(out, _arp([72, 76, 79, 83, 84, 88, 91, 96], 0.07, 0.4, 0.18, gain=0.35), 0.0)
    sw = T(0.6)
    place(out, hp(noise(0.6, r), 4000) * (sw / 0.6) ** 2 * 0.25, 0.0)
    place(out, sum(bell(note(m), 0.9, 0.35, (1, 2.0, 3.0), 0.35) for m in (84, 88, 91)) * 0.3, 0.56)
    _sparkles(r, out, 10, 0.55, 0.6, 0.25)
    return fade(soft(out, 1.2), 0.002, 0.15)


def hatch_drum():
    """Legendary and Void hatch: one big friendly drum hit (low boom + snare snap) with a cymbal-like wash."""
    r = rng_for("hatchdrum")
    dur = 1.2
    n = int(dur * SR)
    out = np.zeros(n)
    place(out, soft(glide(110, 48, 0.6, 0.5) * env(int(0.6 * SR), 0.001, 0.22), 2.2), 0.0)
    place(out, bp(noise(0.25, r), 900, 5000) * env(int(0.25 * SR), 0.0005, 0.05) * 0.6, 0.0)
    out += hp(noise(dur, r), 6000) * env(n, 0.002, 0.35) * 0.35
    return fade(soft(out, 1.4), 0.0005, 0.2)


def pet_found():
    """Someone found the pet egg: a quick happy three-note pop (C6 E6 G6) with a soft sparkle."""
    r = rng_for("petfound")
    out = _pad(_arp([84, 88, 91], 0.09, 0.4, 0.2, gain=0.55), 0.2)
    _sparkles(r, out, 5, 0.2, 0.3, 0.2)
    return fade(soft(out, 1.2), 0.001, 0.12)


def egg_grab():
    """An egg goes into the basket: a round little rising 'bloop' with a tiny shell tick."""
    r = rng_for("egggrab")
    dur = 0.22
    out = glide(300, 760, dur, 0.6) * env(int(dur * SR), 0.004, 0.06) * 0.8
    place(out, hp(noise(0.02, r), 3000) * env(int(0.02 * SR), 0.0005, 0.004) * 0.3, 0.0)
    return fade(out, 0.001, 0.04)


def egg_drop():
    """Eggs set down in the nest: a soft straw 'fwump' and a low wooden knock."""
    r = rng_for("eggdrop")
    dur = 0.35
    out = bp(noise(dur, r), 400, 3000) * env(int(dur * SR), 0.004, 0.05) * 0.6
    place(out, soft(glide(240, 150, 0.15, 0.5) * env(int(0.15 * SR), 0.001, 0.03), 1.8) * 0.8, 0.01)
    return fade(out, 0.001, 0.06)


def battle_matched():
    """A Pet Battle rival is found: a quick whoosh into two bright 'versus' stabs."""
    r = rng_for("matched")
    out = np.zeros(int(0.9 * SR))
    w = T(0.3)
    place(out, bp(noise(0.3, r), 800, 5000) * (w / 0.3) ** 2 * 0.5, 0.0)
    place(out, _stab(72, 0.45), 0.3)
    place(out, _stab(79, 0.45), 0.45)
    return fade(soft(out, 1.3), 0.002, 0.1)


def pet_crit():
    """A critical hit: a sharp bright 'tchak' with a high ping on top."""
    r = rng_for("crit")
    dur = 0.4
    n = int(dur * SR)
    out = hp(noise(dur, r), 2500) * env(n, 0.0005, 0.02) + bell(note(96), dur, 0.12, (1, 2.0, 3.0), 0.4) * 0.5
    place(out, soft(glide(400, 120, 0.12, 0.4) * env(int(0.12 * SR), 0.0008, 0.03), 2.0) * 0.6, 0.0)
    return fade(soft(out, 1.3), 0.0005, 0.06)


def pet_ko():
    """A pet is knocked out: a cartoon slide-whistle down and a soft puff (no voice)."""
    r = rng_for("ko")
    out = np.zeros(int(0.8 * SR))
    place(out, glide(1400, 300, 0.55, 0.8) * env(int(0.55 * SR), 0.01, 0.4) * 0.45, 0.0)
    place(out, lp(noise(0.3, r), 1800) * env(int(0.3 * SR), 0.005, 0.07) * 0.6, 0.5)
    return fade(soft(out, 1.2), 0.002, 0.1)


def battle_win():
    """A Pet Battle won: a short bright fanfare (G5 C6 E6, then a held chord)."""
    r = rng_for("battlewin")
    out = _pad(_arp([79, 84, 88], 0.11, 0.35, 0.18, gain=0.5), 1.0)
    place(out, sum(bell(note(m), 0.9, 0.45, (1, 2.0, 3.0), 0.35) for m in (84, 88, 91)) * 0.3, 0.33)
    _sparkles(r, out, 8, 0.35, 0.6, 0.2)
    return fade(soft(out, 1.2), 0.002, 0.15)


def battle_lose():
    """A Pet Battle or tower run lost: a gentle, friendly 'aww' of three falling soft notes."""
    out = np.zeros(int(1.1 * SR))
    for k, m in enumerate((67, 64, 60)):
        place(out, bell(note(m), 0.5, 0.25, (1, 2.0), 0.25) * (0.5 if k < 2 else 0.6), k * 0.18)
    return fade(soft(out, 1.1), 0.002, 0.12)


def train_tap():
    """One training tap: a tiny soft 'plink' (the code raises the pitch while tapping fast)."""
    dur = 0.14
    out = bell(note(86), dur, 0.05, (1, 2.0), 0.3) * 0.6 + glide(500, 900, dur, 0.5) * env(int(dur * SR), 0.001, 0.02) * 0.3
    return fade(out, 0.0005, 0.03)


def level_up():
    """Level up: a quick rising arpeggio (C E G C) with a sparkle tail."""
    r = rng_for("levelup")
    out = _pad(_arp([72, 76, 79, 84], 0.07, 0.45, 0.22, gain=0.5), 0.25)
    _sparkles(r, out, 6, 0.25, 0.4, 0.2)
    return fade(soft(out, 1.2), 0.001, 0.12)


def evolve():
    """A pet evolves: a magic shimmer that swells for a second, then a warm major chord bloom."""
    r = rng_for("evolve")
    out = np.zeros(int(1.9 * SR))
    sw = T(1.0)
    place(out, glide(300, 1200, 1.0, 1.4) * sw ** 1.5 * 0.2, 0.0)
    place(out, hp(noise(1.0, r), 3500) * sw ** 2 * 0.2, 0.0)
    place(out, sum(bell(note(m), 0.9, 0.5, (1, 2.0, 3.0), 0.3) for m in (72, 76, 79, 84)) * 0.25, 1.0)
    _sparkles(r, out, 10, 1.0, 0.7, 0.22)
    return fade(soft(out, 1.2), 0.004, 0.2)


def floor_clear():
    """A tower floor cleared: a short 'ta-da' (two stabs, the second higher and held)."""
    out = np.zeros(int(1.0 * SR))
    place(out, _stab(72, 0.25), 0.0)
    place(out, _stab(77, 0.75), 0.14)
    return fade(soft(out, 1.2), 0.001, 0.15)


def daily_claim():
    """Daily gift claimed: a gift-box pop, a little coin cascade and a bright bell."""
    r = rng_for("daily")
    out = np.zeros(int(1.1 * SR))
    place(out, soft(glide(500, 900, 0.08, 0.5) * env(int(0.08 * SR), 0.001, 0.02), 1.6) * 0.5, 0.0)
    for k in range(6):
        place(out, bell(note(88 + (k % 3) * 2), 0.25, 0.08, (1, 2.0, 3.0), 0.35) * 0.3, 0.08 + k * 0.06)
    place(out, bell(note(96), 0.6, 0.3, (1, 2.0, 3.0), 0.3) * 0.35, 0.46)
    _sparkles(r, out, 4, 0.46, 0.3, 0.15)
    return fade(soft(out, 1.2), 0.001, 0.12)


def gift_open():
    """A gift opens: paper rustle, a pop, then a small confetti crackle and a chime."""
    r = rng_for("gift")
    out = np.zeros(int(1.0 * SR))
    place(out, bp(noise(0.18, r), 1500, 6000) * env(int(0.18 * SR), 0.03, 0.05) * 0.4, 0.0)
    place(out, soft(glide(700, 260, 0.1, 0.4) * env(int(0.1 * SR), 0.0008, 0.025), 2.0) * 0.6, 0.18)
    _shell_ticks(r, out, 12, 0.22, 0.4, 0.25, 4000)
    place(out, _arp([84, 91], 0.08, 0.5, 0.25, gain=0.4), 0.24)
    return fade(soft(out, 1.2), 0.001, 0.12)


def quest_done():
    """A quest reward claimed: a crisp two-note 'ding-ding' (E6 then A6)."""
    return fade(soft(_arp([88, 93], 0.1, 0.45, 0.2, gain=0.55), 1.1), 0.001, 0.1)


def lucky_meter():
    """The Lucky Meter is full: a sweeping harp-like glissando up to a shining high note."""
    r = rng_for("lucky")
    out = _pad(_arp([72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96], 0.035, 0.35, 0.16, gain=0.3), 0.6)
    place(out, bell(note(96), 0.7, 0.35, (1, 2.0, 3.0), 0.4) * 0.4, 0.38)
    _sparkles(r, out, 6, 0.38, 0.5, 0.18)
    return fade(soft(out, 1.2), 0.001, 0.15)


def denied():
    """Not allowed / error: a soft, friendly low double 'bonk' (not a harsh buzzer)."""
    out = np.zeros(int(0.32 * SR))
    m = int(0.12 * SR)
    for k, f in enumerate((330, 262)):
        place(out, soft(np.sin(2 * np.pi * f * np.arange(m) / SR) * env(m, 0.002, 0.04), 1.6) * 0.5, k * 0.13)
    return fade(lp(out, 2500), 0.001, 0.04)


SOUNDS = {
    "EggTap": egg_tap, "EggBreak": egg_break, "EggChirp": egg_chirp, "CoinPickup": coin_pickup,
    "SpeedBoots": speed_boots, "TowerHit": tower_hit, "TowerSpecial": tower_special,
    # Find The Pet moments (Item 20); every name here is a key in src/shared/PetSoundIds.luau
    "HatchSparkle": hatch_sparkle, "HatchDrum": hatch_drum, "PetFound": pet_found, "EggGrab": egg_grab,
    "EggDrop": egg_drop, "BattleMatched": battle_matched, "PetCrit": pet_crit, "PetKO": pet_ko,
    "BattleWin": battle_win, "BattleLose": battle_lose, "TrainTap": train_tap, "LevelUp": level_up,
    "Evolve": evolve, "FloorClear": floor_clear, "DailyClaim": daily_claim, "GiftOpen": gift_open,
    "QuestDone": quest_done, "LuckyMeter": lucky_meter, "Denied": denied,
}


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
        x = lp(fn(), 11000)  # gentle top cut: very bright noise makes Vorbis overshoot the peak
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
