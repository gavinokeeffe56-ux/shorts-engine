"""Build narration audio + timeline JSON for one episode.

Usage: python3 tools/build_episode.py episodes/<slug>
Writes public/ep/<slug>/narration.wav and public/ep/<slug>/timeline.json
Script syntax inside segment text:
  {display|spoken}  -> caption shows `display`, voice says `spoken`
  ^word             -> emphasized word in captions
"""
import csv, json, os, re, sys, wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL = os.path.join(ROOT, "models", "kokoro-v1.1.int8.onnx")
VOICES = os.path.join(ROOT, "models", "voices-v1.0.bin")
SR = 24000
PUNCT = set(",.;:!?—–-…\"'()")

TOKEN_RE = re.compile(r"\{([^|}]*)\|([^}]*)\}(\S*)|(\S+)")


def parse_tokens(text):
    toks = []
    for m in TOKEN_RE.finditer(text):
        if m.group(4) is not None:
            raw = m.group(4)
            emph = raw.startswith("^")
            raw = raw.lstrip("^").replace("~", " ")
            toks.append({"display": raw, "speak": raw, "emph": emph})
        else:
            disp, speak, tail = m.group(1), m.group(2), m.group(3)
            toks.append({"display": disp + tail, "speak": speak + tail, "emph": True})
    for t in toks:
        if re.search(r"[\d$%]", t["display"]):
            t["emph"] = True
    return toks


def word_groups(timings):
    """Split phoneme timings into spoken-word groups (drop pure punctuation)."""
    groups, cur = [], []
    for tm in timings:
        if tm.phoneme == " ":
            if cur: groups.append(cur); cur = []
            continue
        cur.append(tm)
    if cur: groups.append(cur)
    out = []
    for g in groups:
        chars = [x for x in g if x.phoneme not in PUNCT]
        if not chars:
            continue
        out.append((chars[0].start, chars[-1].end))
    return out


def synth_segment(k, toks, voice, speed):
    # phonemize token-by-token so spoken-word groups line up with caption tokens exactly
    ph_toks, counts = [], []
    for t in toks:
        ph = k.tokenizer.phonemize(t["speak"], "en-us").strip()
        n = len([w for w in ph.split() if any(c not in PUNCT for c in w)])
        ph_toks.append(ph)
        counts.append(n)
    audio, sr, timings = k.create_timed(" ".join(p for p in ph_toks if p), voice=voice,
                                        speed=speed, lang="en-us", is_phonemes=True)
    assert sr == SR
    groups = word_groups(timings)
    words = []
    if sum(counts) == len(groups):
        gi = 0
        for t, n in zip(toks, counts):
            if n == 0:
                if words: words[-1]["text"] += " " + t["display"]
                continue
            s, e = groups[gi][0], groups[gi + n - 1][1]
            gi += n
            words.append({"text": t["display"], "start": s, "end": e, "emph": t["emph"]})
        mode = "exact"
    else:  # fallback: proportional over speech span
        s0 = groups[0][0] if groups else 0.0
        e0 = groups[-1][1] if groups else len(audio) / SR
        w = np.array([max(len(t["speak"]), 1) for t in toks], float)
        edges = s0 + (e0 - s0) * np.concatenate([[0], np.cumsum(w) / w.sum()])
        for i, t in enumerate(toks):
            words.append({"text": t["display"], "start": float(edges[i]), "end": float(edges[i + 1]), "emph": t["emph"]})
        mode = f"proportional ({sum(counts)} vs {len(groups)})"
    return np.asarray(audio, np.float32), words, mode


# ---------- external voice (e.g. ElevenLabs via Higgsfield) ----------
def _norm(w):
    return re.sub(r"[^a-z0-9]", "", w.lower())


def load_wav(path):
    with wave.open(path) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1, "expect 24 kHz mono wav"
        return np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32768


def external_segment(whisper, path, toks):
    """Use a pre-made narration file; word timings from faster-whisper, aligned to script tokens."""
    import difflib
    audio = load_wav(path)
    segs, _ = whisper.transcribe(path, word_timestamps=True, language="en")
    ww = [(w.word.strip(), w.start, w.end) for s in segs for w in s.words]
    # expand script tokens into spoken words, remembering which token each came from
    sp, owner = [], []
    for ti, t in enumerate(toks):
        for w in re.split(r"[\s-]+", t["speak"]):
            if _norm(w):
                sp.append(_norm(w)); owner.append(ti)
    wn = [_norm(w[0]) for w in ww]
    times = [None] * len(sp)
    sm = difflib.SequenceMatcher(a=sp, b=wn, autojunk=False)
    for a, b, n in sm.get_matching_blocks():
        for k_ in range(n):
            times[a + k_] = (ww[b + k_][1], ww[b + k_][2])
    # fill unmatched spoken words by interpolating between known neighbours
    total = len(audio) / SR
    i = 0
    while i < len(sp):
        if times[i] is not None:
            i += 1; continue
        j = i
        while j < len(sp) and times[j] is None:
            j += 1
        t0 = times[i - 1][1] if i > 0 else (ww[0][1] if ww else 0.0)
        t1 = times[j][0] if j < len(sp) else (ww[-1][2] if ww else total)
        step = max(t1 - t0, 0.05) / (j - i)
        for k_ in range(i, j):
            times[k_] = (t0 + (k_ - i) * step, t0 + (k_ - i + 1) * step)
        i = j
    words = []
    for ti, t in enumerate(toks):
        idx = [k_ for k_, o in enumerate(owner) if o == ti]
        if not idx:
            if words: words[-1]["text"] += " " + t["display"]
            continue
        words.append({"text": t["display"], "start": float(times[idx[0]][0]),
                      "end": float(times[idx[-1]][1]), "emph": t["emph"]})
    matched = sum(n for _, _, n in sm.get_matching_blocks())
    return audio, words, f"whisper-aligned ({matched}/{len(sp)} words matched)"


MOTIONS = ["push", "panL", "pull", "panR", "drift"]


def build_shots(ep, ep_dir, segs, out_dir, slug, total, max_len=2.8):
    """Background shot timeline: each segment's listed assets split its time; long holds are
    re-cut with a different camera move so the picture changes every ~2-3 s."""
    apath = os.path.join(ep_dir, ep.get("assets_file", "assets.json"))
    if not os.path.exists(apath) or not any(s_.get("shots") for s_ in ep["segments"]):
        return []
    assets = json.load(open(apath))["assets"]
    shots, mi = [], 0
    for si, seg in enumerate(ep["segments"]):
        ids = seg.get("shots") or []
        if not ids:
            continue
        t0 = 0.0 if si == 0 else segs[si]["start"]
        t1 = segs[si + 1]["start"] if si + 1 < len(segs) else total
        span = t1 - t0
        n = max(len(ids), int(np.ceil(span / max_len)))
        # each asset gets consecutive shots (a re-cut with a new camera move); spare shots go to clips first
        k = [n // len(ids)] * len(ids)
        extra = n - sum(k)
        order = sorted(range(len(ids)), key=lambda i: assets[ids[i]]["kind"] != "video")
        for i in order[:extra]:
            k[i] += 1
        seq = [aid for aid, kk in zip(ids, k) for _ in range(kk)]
        dur = span / len(seq)
        used, cnt = {}, {a_: seq.count(a_) for a_ in set(seq)}
        for j, aid in enumerate(seq):
            a = assets[aid]
            ext = "mp4" if a["kind"] == "video" else "jpg"
            rel = f"ep/{slug}/assets/{aid}.{ext}"
            occ = used.get(aid, 0)
            used[aid] = occ + 1
            offset = occ * dur
            if a["kind"] == "video":
                room = max(a.get("seconds", 5.0) - dur, 0.0)
                offset = room * occ / (cnt[aid] - 1) if cnt[aid] > 1 else 0.0
                motion = ["push", "pull", "drift"][mi % 3]
            else:
                motion = a.get("motion") or MOTIONS[mi % len(MOTIONS)]
            shots.append({"start": t0 + j * dur, "end": t0 + (j + 1) * dur, "src": rel, "kind": a["kind"],
                          "motion": motion, "offset": round(offset, 3),
                          "missing": not os.path.exists(os.path.join(out_dir, "assets", f"{aid}.{ext}"))})
            mi += 1
    return shots


def make_captions(words, max_words=3, max_chars=18):
    caps, cur = [], []
    def flush():
        if cur:
            caps.append({"words": list(cur)})
            cur.clear()
    for w in words:
        txt = w["text"]
        chars = sum(len(x["text"]) + 1 for x in cur) + len(txt)
        if cur and (len(cur) >= max_words or chars > max_chars):
            flush()
        cur.append(w)
        if txt[-1] in ".,;:!?—" or (re.search(r"[\d$%]", txt) and len(cur) > 1):
            flush()
    flush()
    for i, c in enumerate(caps):
        c["start"] = c["words"][0]["start"] - 0.05
        nxt = caps[i + 1]["words"][0]["start"] if i + 1 < len(caps) else None
        end = c["words"][-1]["end"] + 0.25
        if nxt is not None and nxt - c["words"][-1]["end"] < 0.45:
            end = nxt - 0.05
        c["end"] = end
    return caps


def resolve_beats(beats, words, toks):
    out, last = [], -1
    for b in beats:
        b = dict(b)
        if "atWord" in b:
            key = b.pop("atWord").lower()
            idx = next((i for i in range(max(last, 0), len(toks))
                        if toks[i]["display"].lower().lstrip("{").startswith(key)), None)
            if idx is None:
                raise ValueError(f"beat word not found: {key}")
        else:
            idx = b.pop("at", 0)
        last = idx + 1
        b["t"] = max(0.0, words[min(idx, len(words) - 1)]["start"] - 0.12)
        out.append(b)
    return out


def write_wav(path, audio):
    pcm = (np.clip(audio, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main(ep_path, audio_dir=None):
    if os.path.isdir(ep_path):
        ep_dir, ep_file = ep_path, os.path.join(ep_path, "episode.json")
    else:
        ep_dir, ep_file = os.path.dirname(ep_path), ep_path
    ep = json.load(open(ep_file))
    slug = ep["slug"]
    out_dir = os.path.join(ROOT, "public", "ep", slug)
    os.makedirs(out_dir, exist_ok=True)
    if audio_dir:
        from faster_whisper import WhisperModel
        whisper = WhisperModel("base.en", device="cpu", compute_type="int8")
    else:
        from kokoro_onnx import Kokoro
        k = Kokoro(MODEL, VOICES)

    lead, gap = 0.35, 0.32
    t = lead
    pieces = [np.zeros(int(lead * SR), np.float32)]
    segs, all_words, speech, sfx = [], [], [], []
    for si, seg in enumerate(ep["segments"]):
        toks = parse_tokens(seg["text"])
        if audio_dir:
            audio, words, mode = external_segment(whisper, os.path.join(audio_dir, f"seg_{si:02d}.wav"), toks)
        else:
            audio, words, mode = synth_segment(k, toks, ep.get("voice", "am_michael"), ep.get("speed", 1.05))
        print(f"segment {si}: {len(audio)/SR:.2f}s, timing {mode}")
        for w in words:
            w["start"] += t; w["end"] += t
        beats = resolve_beats(seg.get("beats", []), words, toks)
        if si == 0 and beats:
            beats[0]["t"] = 0.0  # hook visuals on screen from frame 0
        dur = len(audio) / SR
        segs.append({"start": t, "end": t + dur, "words": words, "beats": beats})
        speech.append([words[0]["start"], words[-1]["end"]])
        all_words += words
        pieces.append(audio)
        t += dur
        g = 0.55 if si == len(ep["segments"]) - 2 else gap
        pieces.append(np.zeros(int(g * SR), np.float32))
        t += g

    end_start = t
    end_len = ep.get("endCard", {}).get("seconds", 2.5) if ep.get("endCard") else 0.25
    total = end_start + end_len
    pieces.append(np.zeros(int(end_len * SR), np.float32))
    narration = np.concatenate(pieces)
    narration = narration / max(1e-6, np.abs(narration).max()) * 0.89
    write_wav(os.path.join(out_dir, "narration.wav"), narration)

    # sound effects from beats
    seen = set()
    for s in segs:
        for b in s["beats"]:
            if any(k_ in b for k_ in ("target", "pan", "overview", "card")):
                sfx.append({"t": max(0, b["t"] - 0.15), "name": "whoosh", "vol": 0.35})
            if b.get("target") and b["target"] not in seen:
                seen.add(b["target"])
                sfx.append({"t": b["t"] + 0.12, "name": "pop", "vol": 0.5})
            if "counter" in b:
                sfx.append({"t": b["t"] + 0.1, "name": "tick", "vol": 0.35})
            if "big" in b or "cardAccent" in b:
                sfx.append({"t": b["t"] + 0.25, "name": "impact", "vol": 0.6})
    sfx.append({"t": end_start - 0.1, "name": "whoosh", "vol": 0.3})

    pts = []
    with open(os.path.join(ep_dir, ep["dataset"]["file"])) as f:
        for r in csv.DictReader(f):
            if ep["chart"].get("type") == "bars":
                pts.append({"name": r["name"], "year": 0, "cost": 1, "value": float(r["value"])})
            else:
                pts.append({"name": r["Entity"], "year": int(r["Year"]), "cost": float(r["Cost"])})

    timeline = {
        "slug": slug, "series": ep.get("series", ""), "layout": ep.get("layout", "youtube"), "fps": 30,
        "width": 1080, "height": 1920,
        "duration": total,
        "narration": f"ep/{slug}/narration.wav",
        "music": "music/bed.wav",
        "chart": ep["chart"], "dataset": ep["dataset"], "points": pts,
        "segments": segs, "captions": make_captions(all_words),
        "speech": speech, "sfx": sfx,
        "endCard": {**(ep.get("endCard") or {}), "start": end_start if ep.get("endCard") else total + 99},
        "shots": build_shots(ep, ep_dir, segs, out_dir, slug, total),
        **({"hookClip": {"src": f"ep/{slug}/hook.mp4", "end": segs[0]["end"] + 0.2}}
           if os.path.exists(os.path.join(out_dir, "hook.mp4")) else {}),
    }
    json.dump(timeline, open(os.path.join(out_dir, "timeline.json"), "w"), indent=1)
    print(f"total {total:.2f}s, {len(all_words)} words, {len(timeline['captions'])} caption groups")


if __name__ == "__main__":
    args = sys.argv[1:]
    audio_dir = None
    if "--audio-dir" in args:
        i = args.index("--audio-dir"); audio_dir = args[i + 1]; del args[i:i + 2]
    main(args[0], audio_dir)
