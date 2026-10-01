#!/usr/bin/env bash
# Full render inside the Higgsfield cloud sandbox (8 cores, internet, ffmpeg, faster-whisper).
# Usage (run in background):
#   EPISODE=episodes/<dir>/tiktok.json AUDIO_URLS="url0 url1 ..." HOOK_URL=<optional mp4 url> \
#   UPLOAD_URL=<presigned PUT url for the final mp4> bash tools/hf_render.sh
# Writes progress to /home/user/hf_render.log and a small QA sheet to /home/user/qa.jpg.
set -euo pipefail
cd "$(dirname "$0")/.."
log() { echo "[$(date +%H:%M:%S)] $*"; }

SLUG=$(python3 -c "import json;print(json.load(open('$EPISODE'))['slug'])")
VOICE_DIR=/home/user/voice/$SLUG
mkdir -p "$VOICE_DIR" "public/ep/$SLUG"

log "deps"
pip install -q numpy >/dev/null 2>&1 || true
[ -d node_modules ] || npm ci --silent --no-audit --no-fund

log "sound effects + music bed"
python3 tools/make_audio_assets.py

log "voice: download + tighten pauses + slight speed-up"
i=0
for u in $AUDIO_URLS; do
  n=$(printf "%02d" $i)
  curl -sSfL -o "$VOICE_DIR/raw_$n.mp3" "$u"
  ffmpeg -y -loglevel error -i "$VOICE_DIR/raw_$n.mp3" \
    -af "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=-1:stop_duration=0.3:stop_threshold=-45dB:stop_silence=0.18,atempo=${VOICE_TEMPO:-1.07},aresample=24000" \
    -ac 1 -sample_fmt s16 "$VOICE_DIR/seg_$n.wav"
  i=$((i+1))
done

if [ -n "${HOOK_URL:-}" ]; then
  log "hook clip"
  curl -sSfL -o "public/ep/$SLUG/hook_raw.mp4" "$HOOK_URL"
  ffmpeg -y -loglevel error -i "public/ep/$SLUG/hook_raw.mp4" -an \
    -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30" \
    -c:v libx264 -crf 18 -pix_fmt yuv420p "public/ep/$SLUG/hook.mp4"
fi

log "build + render"
REMOTION_BROWSER=/nonexistent AUDIO_DIR="$VOICE_DIR" bash tools/render.sh "$EPISODE"

log "qa sheet"
python3 - <<EOF
from PIL import Image
im = Image.open("out/$SLUG/contact.png").convert("RGB")
im = im.resize((im.width * 2 // 3, im.height * 2 // 3))
im.save("/home/user/qa.jpg", quality=55)
EOF

if [ -n "${UPLOAD_URL:-}" ]; then
  log "upload"
  curl -sSf -X PUT -H "Content-Type: video/mp4" -H "If-None-Match: *" \
    --upload-file "out/$SLUG/$SLUG.mp4" "$UPLOAD_URL" -o /dev/null -w "upload http %{http_code}\n"
fi
log "DONE $SLUG"
