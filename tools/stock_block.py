#!/usr/bin/env python3
"""Build a 10 s, 9:16, five-hard-cut block from REAL public-domain footage (NASA Image and Video Library).

Runs inside the Higgsfield sandbox (it has internet). No API key needed.
Usage:
  python3 tools/stock_block.py --query "rocket launch" [--query "launch pad"] --out work/stock/block03.mp4 \
      [--shots 5] [--shot-seconds 2] [--width 1440] [--height 2560] [--fps 24] [--exclude-credit spacex] \
      [--avoid-file stock_used.txt] [--seed 2026-10-02]
Writes <out> plus <out>.json with the clips used (nasa_id, title, center, date) for the credit line.
--avoid-file: nasa_ids already used on the channel (one per line); they are skipped and the new ones are appended,
so the same launch doesn't show up every day. --seed shuffles the candidate order (use the episode date).

Rules baked in:
- Skips items whose metadata mentions copyright, (c), courtesy of a third party, or an excluded credit.
- Strips original audio (NASA clips often carry commentary that would fight the narration) and adds a silent track.
- Centre-crops 16:9 footage to 9:16 (which also drops most corner graphics).
- Picks shots from the middle of each clip and rejects near-black / flat frames.
"""
import argparse, json, os, random, subprocess, sys, tempfile, urllib.parse, urllib.request

API = "https://images-api.nasa.gov"
BAD_WORDS = ("copyright", "©", "(c)", "courtesy of", "all rights reserved")
# talking heads, news packages and visualisations rarely fit a narrated b-roll beat
BAD_TITLE = ("administrator", "interview", "briefing", "conference", "remarks", "speaks", "talks", "discusses",
             "explains", "highlights", "podcast", "panel", "ceremony", "award", "students", "livestream", "replay",
             "this week @nasa", "what's up", "social", "q&a", "event", "visualiz", "animation", "graphic", "_ntv_",
             "videofile", "sound bite", "soundbite", "message", "greeting", "hangout", "chat", "town hall")
GOOD = ("b-roll", "broll", "footage", "time-lapse", "timelapse", "view")
STOP = {"the", "a", "an", "of", "from", "in", "on", "at", "to", "and", "with", "for"}


def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def search(query, n=60):
    q = urllib.parse.urlencode({"q": query, "media_type": "video", "page_size": n})
    items = get(f"{API}/search?{q}")["collection"]["items"]
    out = []
    for it in items:
        d = it["data"][0]
        text = " ".join(str(d.get(k, "")) for k in ("description", "title", "photographer", "secondary_creator")).lower()
        title = (d.get("title", "") + " " + d["nasa_id"]).lower()
        terms = [w for w in query.lower().split() if w not in STOP]
        hit_t = sum(w.rstrip("s") in title for w in terms)
        hit_a = sum(w.rstrip("s") in text for w in terms)
        out.append({"nasa_id": d["nasa_id"], "title": d.get("title", ""), "center": d.get("center", ""),
                    "date": d.get("date_created", "")[:10], "text": text, "ttl": title,
                    "ok": hit_a * 3 >= len(terms) * 2,  # at least two thirds of the query words present
                    "score": 2 * hit_t + hit_a + sum(g in text for g in GOOD)})
    return out


def fix(u):
    u = u.replace("http://", "https://")
    p = urllib.parse.urlsplit(u)
    return urllib.parse.urlunsplit(p._replace(path=urllib.parse.quote(urllib.parse.unquote(p.path))))


def pick_mp4(nasa_id):
    hrefs = [h["href"] for h in get(f"{API}/asset/{urllib.parse.quote(nasa_id)}")["collection"]["items"]]
    mp4 = [h for h in hrefs if h.lower().endswith(".mp4")]
    for tag in ("~medium.mp4", "~large.mp4", "~mobile.mp4", "~orig.mp4"):
        for h in mp4:
            if h.endswith(tag):
                return fix(h)
    return fix(mp4[0]) if mp4 else None


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height:format=duration", "-of", "json", path],
                         capture_output=True, text=True).stdout
    j = json.loads(out)
    s = j["streams"][0]
    return float(j["format"]["duration"]), int(s["width"]), int(s["height"])


try:
    import cv2
    _FACE = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
except Exception:  # opencv missing: stock_blocks.sh installs opencv-python-headless
    cv2 = _FACE = None


def has_face(path, t):
    """Real people on camera (officials, astronauts talking) are skipped: no faces in our b-roll."""
    if _FACE is None:
        return False
    tmp = path + f".f{t:.1f}.png"
    subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-ss", f"{t:.2f}", "-i", path, "-frames:v", "1",
                    "-vf", "scale=480:-2", tmp])
    img = cv2.imread(tmp, cv2.IMREAD_GRAYSCALE) if os.path.exists(tmp) else None
    if img is None:
        return False
    return len(_FACE.detectMultiScale(img, 1.1, 6, minSize=(24, 24))) > 0


def frame_ok(path, t):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", path, "-frames:v", "1",
                          "-vf", "scale=32:18", "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
    if len(raw) < 100:
        return False
    mean = sum(raw) / len(raw)
    sd = (sum((b - mean) ** 2 for b in raw) / len(raw)) ** 0.5
    return 25 < mean < 225 and sd > 12  # not black, not blown out, not flat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", action="append", default=[])
    ap.add_argument("--id", action="append", default=[], help="use these nasa_ids directly (hand-picked)")
    ap.add_argument("--avoid-id", action="append", default=[])
    ap.add_argument("--out", required=True)
    ap.add_argument("--shots", type=int, default=5)
    ap.add_argument("--shot-seconds", type=float, default=2.0)
    ap.add_argument("--width", type=int, default=1440)
    ap.add_argument("--height", type=int, default=2560)
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--exclude-credit", action="append", default=["spacex"])
    ap.add_argument("--avoid-file")
    ap.add_argument("--seed")
    a = ap.parse_args()
    avoid = set()
    if a.avoid_file and os.path.exists(a.avoid_file):
        avoid = {l.strip() for l in open(a.avoid_file) if l.strip()}
    avoid |= set(a.avoid_id)
    if not a.query and not a.id:
        ap.error("give --query or --id")

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    tmp = tempfile.mkdtemp()
    cands, seen = [], set()
    for i in a.id:  # hand-picked: still checked for copyright / excluded credits
        seen.add(i)
        try:
            d = get(f"{API}/search?" + urllib.parse.urlencode({"nasa_id": i}))["collection"]["items"][0]["data"][0]
        except Exception:
            print(f"skip {i}: not found", file=sys.stderr); continue
        text = " ".join(str(d.get(k, "")) for k in ("description", "title", "photographer", "secondary_creator")).lower()
        if any(w in text for w in BAD_WORDS) or any(x.lower() in text for x in a.exclude_credit):
            print(f"skip {i}: rights/credit", file=sys.stderr); continue
        cands.append({"nasa_id": i, "title": d.get("title", ""), "center": d.get("center", ""),
                      "date": d.get("date_created", "")[:10], "score": 99})
    for q in a.query:
        for c in search(q):
            if c["nasa_id"] in seen or c["nasa_id"] in avoid:
                continue
            seen.add(c["nasa_id"])
            if any(w in c["text"] for w in BAD_WORDS) or any(x.lower() in c["text"] for x in a.exclude_credit):
                continue
            if not c["ok"] or any(b in c["ttl"] for b in BAD_TITLE):
                continue
            cands.append(c)
    if a.seed:
        random.Random(a.seed).shuffle(cands)
    cands.sort(key=lambda c: -c["score"])  # stable: random order kept within equal relevance

    shots, used = [], []
    for c in cands:
        if len(shots) >= a.shots:
            break
        url = pick_mp4(c["nasa_id"])
        if not url:
            continue
        src = os.path.join(tmp, f"src{len(used)}.mp4")
        if subprocess.run(["curl", "-fsSL", "--max-time", "90", "-o", src, url]).returncode != 0:
            continue
        try:
            dur, w, h = probe(src)
        except Exception:
            continue
        if dur < 6 or w < 640:
            continue
        # up to 2 shots per source clip, from the middle 70% of it
        per = min(2, a.shots - len(shots))
        took = 0
        for k in range(6):
            if took >= per:
                break
            t = dur * (0.15 + 0.7 * (k + 0.5) / 6)
            if t + a.shot_seconds > dur or not frame_ok(src, t + a.shot_seconds / 2):
                continue
            if any(has_face(src, t + f * a.shot_seconds) for f in (0.1, 0.5, 0.9)):
                continue
            seg = os.path.join(tmp, f"shot{len(shots)}.mp4")
            vf = (f"scale={a.width}:{a.height}:force_original_aspect_ratio=increase,"
                  f"crop={a.width}:{a.height},fps={a.fps},setsar=1")
            r = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-ss", f"{t:.2f}", "-i", src,
                                "-t", f"{a.shot_seconds}", "-an", "-vf", vf, "-c:v", "libx264", "-crf", "18",
                                "-pix_fmt", "yuv420p", seg])
            if r.returncode == 0:
                shots.append(seg)
                took += 1
        if took:
            used.append({k: c[k] for k in ("nasa_id", "title", "center", "date")})

    if len(shots) < a.shots:
        print(f"ERROR: only {len(shots)} usable shots for {a.query}", file=sys.stderr)
        sys.exit(1)
    lst = os.path.join(tmp, "list.txt")
    with open(lst, "w") as f:
        for s in shots[:a.shots]:
            f.write(f"file '{s}'\n")
    total = a.shots * a.shot_seconds
    subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
                    "-f", "lavfi", "-t", f"{total}", "-i", "anullsrc=r=48000:cl=stereo",
                    "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-shortest", a.out], check=True)
    json.dump({"source": "NASA Image and Video Library (public domain)", "clips": used}, open(a.out + ".json", "w"), indent=1)
    if a.avoid_file:
        with open(a.avoid_file, "a") as f:
            for u in used:
                f.write(u["nasa_id"] + "\n")
    print(f"OK {a.out} shots={a.shots} sources={len(used)}")


if __name__ == "__main__":
    main()
