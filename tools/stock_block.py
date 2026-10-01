#!/usr/bin/env python3
"""Build a 10 s, 9:16, five-hard-cut block from REAL public-domain footage (NASA Image and Video Library).

Runs inside the Higgsfield sandbox (it has internet). No API key needed.
Usage:
  python3 tools/stock_block.py --query "rocket launch" [--query "launch pad"] --out work/stock/block03.mp4 \
      [--shots 5] [--shot-seconds 2] [--width 1440] [--height 2560] [--fps 24] [--exclude-credit spacex]
Writes <out> plus <out>.json with the clips used (nasa_id, title, center, date) for the credit line.

Rules baked in:
- Skips items whose metadata mentions copyright, (c), courtesy of a third party, or an excluded credit.
- Strips original audio (NASA clips often carry commentary that would fight the narration) and adds a silent track.
- Centre-crops 16:9 footage to 9:16 (which also drops most corner graphics).
- Picks shots from the middle of each clip and rejects near-black / flat frames.
"""
import argparse, json, os, subprocess, sys, tempfile, urllib.parse, urllib.request

API = "https://images-api.nasa.gov"
BAD_WORDS = ("copyright", "©", "(c)", "courtesy of", "all rights reserved")


def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.load(r)


def search(query, n=25):
    q = urllib.parse.urlencode({"q": query, "media_type": "video", "page_size": n})
    items = get(f"{API}/search?{q}")["collection"]["items"]
    out = []
    for it in items:
        d = it["data"][0]
        text = " ".join(str(d.get(k, "")) for k in ("description", "title", "photographer", "secondary_creator")).lower()
        out.append({"nasa_id": d["nasa_id"], "title": d.get("title", ""), "center": d.get("center", ""),
                    "date": d.get("date_created", "")[:10], "text": text})
    return out


def pick_mp4(nasa_id):
    hrefs = [h["href"] for h in get(f"{API}/asset/{urllib.parse.quote(nasa_id)}")["collection"]["items"]]
    mp4 = [h for h in hrefs if h.lower().endswith(".mp4")]
    for tag in ("~medium.mp4", "~large.mp4", "~mobile.mp4", "~orig.mp4"):
        for h in mp4:
            if h.endswith(tag):
                return h.replace("http://", "https://")
    return mp4[0].replace("http://", "https://") if mp4 else None


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height:format=duration", "-of", "json", path],
                         capture_output=True, text=True).stdout
    j = json.loads(out)
    s = j["streams"][0]
    return float(j["format"]["duration"]), int(s["width"]), int(s["height"])


def frame_ok(path, t):
    raw = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", path, "-frames:v", "1",
                          "-vf", "scale=32:18", "-f", "rawvideo", "-pix_fmt", "gray", "-"], capture_output=True).stdout
    if len(raw) < 100:
        return False
    mean = sum(raw) / len(raw)
    sd = (sum((b - mean) ** 2 for b in raw) / len(raw)) ** 0.5
    return mean > 25 and sd > 12


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", action="append", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--shots", type=int, default=5)
    ap.add_argument("--shot-seconds", type=float, default=2.0)
    ap.add_argument("--width", type=int, default=1440)
    ap.add_argument("--height", type=int, default=2560)
    ap.add_argument("--fps", type=int, default=24)
    ap.add_argument("--exclude-credit", action="append", default=["spacex"])
    a = ap.parse_args()

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    tmp = tempfile.mkdtemp()
    cands, seen = [], set()
    for q in a.query:
        for c in search(q):
            if c["nasa_id"] in seen:
                continue
            seen.add(c["nasa_id"])
            if any(w in c["text"] for w in BAD_WORDS) or any(x.lower() in c["text"] for x in a.exclude_credit):
                continue
            cands.append(c)

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
    print(f"OK {a.out} shots={a.shots} sources={len(used)}")


if __name__ == "__main__":
    main()
