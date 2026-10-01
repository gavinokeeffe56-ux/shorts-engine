#!/usr/bin/env bash
# Build narration + timeline, render, normalize loudness, extract QA frames.
# Usage: tools/render.sh episodes/<slug>
set -e
cd "$(dirname "$0")/.."
EP="$1"
if [ -d "$EP" ]; then EPF="$EP/episode.json"; else EPF="$EP"; fi
SLUG=$(python3 -c "import json;print(json.load(open('$EPF'))['slug'])")
BROWSER=${REMOTION_BROWSER:-/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell}
mkdir -p out/$SLUG
python3 tools/build_episode.py "$EP"
python3 -c "import json,sys; t=json.load(open('public/ep/$SLUG/timeline.json')); json.dump({'timeline':t},open('out/$SLUG/props.json','w'))"
CORES=$(nproc); CONC=$(( CORES < 4 ? CORES : 4 ))
npx remotion render src/index.ts Short out/$SLUG/raw.mp4 --props=out/$SLUG/props.json \
  --browser-executable="$BROWSER" --concurrency=$CONC --crf=18 --log=error
ffmpeg -y -loglevel error -i out/$SLUG/raw.mp4 -c:v copy -af loudnorm=I=-14:TP=-1.5:LRA=11 -ar 48000 \
  -c:a aac -b:a 192k -movflags +faststart out/$SLUG/$SLUG.mp4
python3 tools/qa_frames.py "$SLUG"
echo "rendered out/$SLUG/$SLUG.mp4"
