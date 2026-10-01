"""Generate original sound effects and a placeholder music bed (no licensing issues).
Replace public/music/bed.wav with YouTube Audio Library tracks when available."""
import os, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 44100
rng = np.random.default_rng(7)


def save(path, x, stereo=True):
    x = x / max(1e-9, np.abs(x).max()) * 0.9
    pcm = (x * 32767).astype(np.int16)
    if stereo and pcm.ndim == 1:
        pcm = np.stack([pcm, pcm], 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo else 1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def lowpass(x, a):
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc); y[i] = acc
    return y


def whoosh(d=0.55):
    n = int(d * SR); t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    env = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 2
    cut = 0.02 + 0.25 * np.sin(np.pi * t / d)          # sweeping filter
    y = np.zeros(n); acc = 0.0
    for i in range(n):
        acc += cut[i] * (noise[i] - acc); y[i] = acc
    return y * env


def pop():
    d = 0.14; t = np.arange(int(d * SR)) / SR
    f = 950 * np.exp(-t * 9) + 380
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 32)


def tick():
    d = 0.05; t = np.arange(int(d * SR)) / SR
    return (np.sin(2 * np.pi * 2400 * t) + 0.5 * rng.standard_normal(len(t)) * 0.3) * np.exp(-t * 120)


def impact():
    d = 1.2; t = np.arange(int(d * SR)) / SR
    boom = np.sin(2 * np.pi * (48 + 40 * np.exp(-t * 8)) * t) * np.exp(-t * 3.2)
    hit = lowpass(rng.standard_normal(len(t)), 0.08) * np.exp(-t * 18) * 2
    return boom + hit


def bed(seconds=64, bpm=96):
    n = int(seconds * SR); t = np.arange(n) / SR
    beat = 60 / bpm; bar = beat * 4
    chords = [(57, 60, 64), (53, 57, 60), (48, 52, 55), (55, 59, 62)]  # Am F C G (midi)
    mid = lambda m: 440 * 2 ** ((m - 69) / 12)
    out = np.zeros(n)
    for i in range(int(seconds / (bar * 2)) + 1):
        c = chords[i % 4]; s0 = int(i * bar * 2 * SR); L = int(bar * 2 * SR)
        if s0 >= n: break
        tt = np.arange(min(L, n - s0)) / SR
        env = np.minimum(1, tt / 0.8) * np.minimum(1, (bar * 2 - tt) / 0.8)
        seg = np.zeros(len(tt))
        for m in c:
            f = mid(m - 12)
            seg += np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt + 0.5)
        seg += 0.6 * np.sin(2 * np.pi * mid(c[0] - 24) * tt)
        out[s0:s0 + len(tt)] += seg * env * 0.25
    # soft pulse: kick on 1 and 3, shaker on off-beats
    for k in range(int(seconds / beat)):
        s0 = int(k * beat * SR)
        if s0 >= n: break
        L = min(int(0.35 * SR), n - s0); tt = np.arange(L) / SR
        if k % 2 == 0:
            out[s0:s0 + L] += 0.9 * np.sin(2 * np.pi * (50 + 60 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 9)
        s1 = int((k + 0.5) * beat * SR); L2 = min(int(0.06 * SR), n - s1)
        if L2 > 0:
            out[s1:s1 + L2] += 0.12 * rng.standard_normal(L2) * np.exp(-np.arange(L2) / SR * 60)
    # arpeggio sparkle
    for k in range(int(seconds / (beat / 2))):
        c = chords[int(k * beat / 2 / (bar * 2)) % 4]
        s0 = int(k * beat / 2 * SR); L = min(int(0.3 * SR), n - s0)
        if L <= 0: break
        tt = np.arange(L) / SR
        out[s0:s0 + L] += 0.08 * np.sin(2 * np.pi * mid(c[k % 3] + 12) * tt) * np.exp(-tt * 10)
    return out


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "public", "sfx"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "public", "music"), exist_ok=True)
    for name, fn in [("whoosh", whoosh), ("pop", pop), ("tick", tick), ("impact", impact)]:
        save(os.path.join(ROOT, "public", "sfx", f"{name}.wav"), fn())
    save(os.path.join(ROOT, "public", "music", "bed.wav"), bed())
    print("audio assets written")
