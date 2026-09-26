#!/usr/bin/env python3
"""Procedurally synthesizes original sound effects for Neon Rift.

All sounds generated here are original works created for this project
(no samples are used). Output: game/assets/audio/sfx/gen_*.ogg

Usage: python3 tools/synth_sfx.py
Requires: numpy, scipy, ffmpeg (with libvorbis)
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio", "sfx")
rng = np.random.default_rng(1234)


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def env_adsr(n, a=0.01, d=0.1, s=0.6, r=0.2, dur=None):
    """Simple ADSR envelope with times in seconds; sustain fills the remainder."""
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, a_n, endpoint=False),
        np.linspace(1, s, d_n, endpoint=False),
        np.full(s_n, s),
        np.linspace(s, 0, r_n),
    ])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def env_exp(n, attack=0.005, decay=6.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t * decay)


def sweep_bandpass(noise, f0, f1, q=2.0, steps=48):
    """Band-pass filter noise with a centre frequency sweeping from f0 to f1."""
    n = len(noise)
    out = np.zeros(n)
    seg = n // steps + 1
    zi = None
    for i in range(steps):
        s, e = i * seg, min(n, (i + 1) * seg)
        if s >= n:
            break
        frac = i / max(steps - 1, 1)
        fc = f0 * (f1 / f0) ** frac
        bw = fc / q
        lo, hi = max(20, fc - bw / 2), min(SR / 2 - 100, fc + bw / 2)
        sos = signal.butter(2, [lo, hi], btype="band", fs=SR, output="sos")
        if zi is None:
            zi = signal.sosfilt_zi(sos) * 0
        chunk, zi = signal.sosfilt(sos, noise[s:e], zi=zi)
        out[s:e] = chunk
    return out


def lowpass(x, fc, order=2):
    sos = signal.butter(order, fc, btype="low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, fc, order=2):
    sos = signal.butter(order, fc, btype="high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def chirp(dur, f0, f1, kind="exp", wave="sine"):
    t = t_axis(dur)
    if kind == "exp":
        k = np.log(f1 / f0) / dur
        phase = 2 * np.pi * f0 * (np.exp(k * t) - 1) / k
    else:
        phase = 2 * np.pi * (f0 * t + (f1 - f0) * t * t / (2 * dur))
    if wave == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    if wave == "square":
        return np.sign(np.sin(phase))
    return np.sin(phase)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def save(name, x, peak=0.89):
    x = normalize(x, peak)
    fade = min(len(x), int(0.004 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wavfile.write(tmp.name, SR, (x * 32767).astype(np.int16))
        dst = os.path.join(OUT, f"gen_{name}.ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    os.unlink(tmp.name)
    print("wrote", dst, f"{len(x) / SR:.2f}s")


def whoosh(dur, f0, f1, q=1.6, bright=0.0):
    n = int(SR * dur)
    noise = rng.standard_normal(n)
    x = sweep_bandpass(noise, f0, f1, q=q)
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.6
    x *= e
    if bright > 0:
        x += bright * highpass(noise, 5000) * e ** 3
    return x


def blade_swing(dur, hum_f0, hum_f1, seed_shift=0.0):
    n = int(SR * dur)
    w = whoosh(dur, 500 + seed_shift, 2600 + seed_shift, q=1.3, bright=0.15)
    hum = chirp(dur, hum_f0, hum_f1, wave="saw") * 0.35 + chirp(dur, hum_f0 * 2.01, hum_f1 * 2.0) * 0.25
    hum = lowpass(hum, 2500)
    e = np.sin(np.linspace(0, np.pi, n)) ** 1.2
    # A bit of "electric" amplitude flutter.
    flutter = 1.0 + 0.25 * np.sin(2 * np.pi * 38 * t_axis(dur))
    return w * 1.0 + hum * e * flutter


def main():
    # --- Movement ---------------------------------------------------------
    save("jump", whoosh(0.28, 300, 1800, q=1.2) + 0.3 * whoosh(0.28, 150, 400, q=1.0), peak=0.7)
    dash = whoosh(0.38, 250, 3200, q=1.1, bright=0.25)
    thr = lowpass(rng.standard_normal(len(dash)), 900) * env_exp(len(dash), 0.01, 9) * 1.6
    save("dash", dash + thr, peak=0.8)
    save("air_dash", whoosh(0.32, 600, 4200, q=1.3, bright=0.35) + 0.6 * thr[: int(0.32 * SR)], peak=0.75)
    n = int(0.3 * SR)
    thud = np.sin(2 * np.pi * np.cumsum(np.linspace(95, 42, n)) / SR) * env_exp(n, 0.002, 18)
    thud += 0.35 * lowpass(rng.standard_normal(n), 1200) * env_exp(n, 0.001, 30)
    save("land", thud, peak=0.8)
    n = int(0.3 * SR)
    kick = 0.8 * lowpass(rng.standard_normal(n), 3000) * env_exp(n, 0.001, 35)
    kick += np.sin(2 * np.pi * np.cumsum(np.linspace(180, 70, n)) / SR) * env_exp(n, 0.001, 20)
    save("wall_kick", kick + 0.5 * whoosh(0.3, 500, 3000, q=1.3), peak=0.8)
    # Jump pad: rising resonant sweep with vibrato.
    dur = 0.6
    t = t_axis(dur)
    f = 180 * (6.0 ** (t / dur)) * (1 + 0.03 * np.sin(2 * np.pi * 14 * t))
    pad = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    pad *= env_adsr(len(t), 0.005, 0.1, 0.7, 0.3)
    save("jump_pad", pad + 0.4 * whoosh(dur, 200, 5000, q=1.0), peak=0.75)

    # --- Blade -----------------------------------------------------------
    save("blade_swing_1", blade_swing(0.30, 220, 140, 0), peak=0.75)
    save("blade_swing_2", blade_swing(0.28, 260, 160, 250), peak=0.75)
    save("blade_swing_3", blade_swing(0.42, 180, 90, -150), peak=0.8)
    save("blade_heavy", blade_swing(0.6, 150, 60, -250) + 0.5 * whoosh(0.6, 120, 900, q=1.0), peak=0.85)
    dur = 0.45
    ign = chirp(dur, 90, 420, wave="saw") * env_adsr(int(dur * SR), 0.01, 0.1, 0.6, 0.2)
    save("blade_ignite", lowpass(ign, 3000) + 0.3 * whoosh(dur, 400, 3000), peak=0.6)
    # Blade impact: sharp transient + electric crackle + low body.
    n = int(0.35 * SR)
    crack = highpass(rng.standard_normal(n), 2000) * env_exp(n, 0.0005, 25)
    zap = np.sign(np.sin(2 * np.pi * 1200 * t_axis(0.35) + 3 * np.sin(2 * np.pi * 90 * t_axis(0.35)))) * env_exp(n, 0.001, 22) * 0.35
    body = np.sin(2 * np.pi * np.cumsum(np.linspace(160, 60, n)) / SR) * env_exp(n, 0.001, 14)
    save("blade_hit", crack + zap + body, peak=0.9)
    body2 = np.sin(2 * np.pi * np.cumsum(np.linspace(120, 40, n)) / SR) * env_exp(n, 0.001, 9)
    save("heavy_hit", 1.2 * crack + zap + 1.3 * body2, peak=0.95)

    # --- Abilities / UI ---------------------------------------------------
    dur = 1.3
    t = t_axis(dur)
    chord = sum(np.sin(2 * np.pi * np.cumsum(fr * (1 + 1.5 * t / dur)) / SR) for fr in (110, 165, 220, 277))
    chord *= env_adsr(len(t), 0.05, 0.3, 0.8, 0.5)
    save("overdrive", lowpass(chord, 4000) * 0.5 + whoosh(dur, 100, 6000, q=0.9, bright=0.3), peak=0.85)
    n = int(0.06 * SR)
    blip = np.sin(2 * np.pi * 1800 * t_axis(0.06)) * env_exp(n, 0.001, 60)
    save("ui_hover", blip, peak=0.4)
    n = int(0.9 * SR)
    boom = np.sin(2 * np.pi * np.cumsum(np.linspace(70, 30, n)) / SR) * env_exp(n, 0.002, 5)
    boom += 0.6 * lowpass(rng.standard_normal(n), 600) * env_exp(n, 0.002, 7)
    save("shockwave", boom, peak=0.9)
    # Spawn materialize: shimmering rising arpeggio.
    dur = 0.8
    t = t_axis(dur)
    arp = np.zeros_like(t)
    for i, fr in enumerate((440, 554, 659, 880, 1108)):
        start = int(i * 0.08 * SR)
        seg = len(t) - start
        arp[start:] += np.sin(2 * np.pi * fr * t[:seg]) * env_exp(seg, 0.003, 7)
    save("spawn", arp + 0.4 * whoosh(dur, 2000, 8000, q=1.2), peak=0.6)
    # Low-health heartbeat pulse.
    n = int(0.5 * SR)
    hb = np.zeros(n)
    for off in (0.0, 0.18):
        s = int(off * SR)
        m = n - s
        hb[s:] += np.sin(2 * np.pi * 55 * t_axis(m / SR)) * env_exp(m, 0.004, 22)
    save("heartbeat", hb, peak=0.8)


if __name__ == "__main__":
    main()
