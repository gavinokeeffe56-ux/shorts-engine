"""Extract one frame per beat + a contact sheet, and print technical checks."""
import json, subprocess, sys
from PIL import Image
slug = sys.argv[1]
t = json.load(open(f"public/ep/{slug}/timeline.json"))
mp4 = f"out/{slug}/{slug}.mp4"
dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", mp4],
                           capture_output=True, text=True).stdout.strip() or 0)
times = [b["t"] + 0.9 for s in t["segments"] for b in s["beats"]]
times += [s["start"] + 0.6 for s in t.get("shots", [])][::3]  # every third AI shot
times.append((t.get("endCard") or {}).get("start", 1e9) + 1.0)
times = sorted({round(x, 2) for x in times if x < dur - 0.1})  # loop mode has no end card
thumbs = []
for i, x in enumerate(times):
    p = f"out/{slug}/qa_{i:02d}.png"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{x:.2f}", "-i", mp4, "-frames:v", "1",
                    "-vf", "scale=360:640", p], check=True)
    thumbs.append(Image.open(p))
cols = 6; rows = (len(thumbs) + cols - 1) // cols
sheet = Image.new("RGB", (360 * cols, 640 * rows))
for i, im in enumerate(thumbs):
    sheet.paste(im, ((i % cols) * 360, (i // cols) * 640))
sheet.save(f"out/{slug}/contact.png")
probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height,r_frame_rate:format=duration",
                        "-of", "compact", mp4], capture_output=True, text=True).stdout
loud = subprocess.run(["ffmpeg", "-i", mp4, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
I = [l.strip() for l in loud.splitlines() if l.strip().startswith("I:")]
print(probe.strip()); print("loudness", I[-1] if I else "?")
# dead-air gate: any stretch of 0.8 s+ where the picture does not change
fz = subprocess.run(["ffmpeg", "-hide_banner", "-i", mp4, "-vf", "scale=270:480,freezedetect=n=0.003:d=0.8",
                     "-map", "0:v", "-f", "null", "-"], capture_output=True, text=True).stderr
starts = [l.split("freeze_start:")[1].strip() for l in fz.splitlines() if "freeze_start:" in l]
print("freezes:", ", ".join(starts) if starts else "none")
print(f"contact sheet: out/{slug}/contact.png  (LOOK AT IT before sending)")
