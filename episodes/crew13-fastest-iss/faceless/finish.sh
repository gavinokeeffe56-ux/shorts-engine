#!/usr/bin/env bash
# Higgsfield faceless-video Phase 6 + 7 + 9 for this episode, run inside the Higgsfield sandbox.
# Usage: COMMIT=<sha> UPLOAD_URL='<presigned put url>' [HOOK_URL='<presigned put url for the 15 s hook clip>'] bash finish.sh
# Blocks 3 and 5 are real NASA public-domain footage built with tools/stock_blocks.sh (see stock.json / clip_credits.json).
set -euo pipefail
cd /home/user
REPO=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/${COMMIT:-main}/episodes/crew13-fastest-iss/faceless
B=https://d8j0ntlcm91z4.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
S=https://d2ol7oe51mr4n9.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
rm -rf work/blocks work/voices work/output; mkdir -p work/blocks work/voices work/output
curl -fsSL "$REPO/script_manifest.json" -o script_manifest.json
cat > clips.txt <<EOT
$B/hf_20261002_042611_3b41ce6c-d683-4776-897e-306a0f86c3ca.mp4
$B/hf_20261002_042611_3b6bfefc-7261-4195-b912-c83b3204e43f.mp4
$S/920a1cec-be65-4e9f-b4c8-8310414ae620.mp4
$B/hf_20261002_042611_5cf63ed7-b8a3-4de8-98f0-2b91db33ea65.mp4
$S/455c0423-91b1-410a-aa78-3502bf8bca89.mp4
$B/hf_20261002_042611_7d4e2dbf-d823-4d8f-8646-803c4f02497f.mp4
$B/hf_20261002_042611_37f1c79e-04bb-439c-9796-4553facab51c.mp4
EOT
cat > voices.txt <<EOT
$B/hf_20261002_043534_4e138864-de06-4188-bc6f-4d1d5ab7f544.mp3
$B/hf_20261002_042510_b41c9378-642e-459e-a685-2023b27cb2b9.mp3
$B/hf_20261002_043438_a9b71980-9de8-4b97-b185-64fa809c2d19.mp3
$B/hf_20261002_043935_432ba6f5-1186-4e06-ad40-b76b63ced8ea.mp3
$B/hf_20261002_043534_8c65c1a5-68a7-48d5-9cb4-93d14d5d4ba9.mp3
$B/hf_20261002_043438_51d661bf-8c49-40a4-9bfb-86d54e73c088.mp3
$B/hf_20261002_042408_7bd86fd0-8a52-4dfd-8948-16d1018c5047.mp3
EOT
# light instrumental bed (our own synthesized track), ducked under the voice by the assembler
if [ ! -s bed.wav ]; then
  rm -rf se && git clone -q --depth 1 https://github.com/gavinokeeffe56-ux/shorts-engine se
  pip install -q numpy >/dev/null 2>&1 || true
  (cd se && python3 tools/make_audio_assets.py >/dev/null) && cp se/public/music/bed.wav bed.wav
fi
python3 ${HF_WORKFLOWS}/faceless-video/scripts/validate_motion_script.py --script script_manifest.json \
  --duration-seconds 70 --duration-retry-blocks 4
chmod +x ${HF_WORKFLOWS}/faceless-video/scripts/*.sh ${HF_WORKFLOWS}/subtitles/scripts/*.sh 2>/dev/null || true
bash ${HF_WORKFLOWS}/faceless-video/scripts/finish_video.sh --blocks 7 --clips-file clips.txt --voices-file voices.txt \
  --script script_manifest.json --language en --music /home/user/bed.wav --out work/output/final_clean.mp4
python3 -c "import json; d=json.load(open('work/output/final_clean.mp4.assembly.json')); print('SIDECAR', d['blocks'], len(d['per_block']))"
# captions look for v_00N.wav; the assembler writes voiceNN.wav
for i in 0 1 2 3 4 5 6; do n=$(printf %02d $((i+1))); [ -e work/voices/v_00$i.wav ] || { [ -e work/voices/voice$n.wav ] && ln -s voice$n.wav work/voices/v_00$i.wav; } || true; done
# Phase 7: captions (bold look keeps clear of the platform UI)
CAPTION_LANGUAGE='en'; CAPTION_LOOK='bold'
bash ${HF_WORKFLOWS}/subtitles/scripts/fetch_fonts.sh
python3 ${HF_WORKFLOWS}/subtitles/scripts/audio_to_captions.py work/output/final_clean.mp4 --srt work/output/final.srt \
  --per-block work/output/final_clean.mp4.assembly.json --voice-dir work/voices --script script_manifest.json --language "$CAPTION_LANGUAGE" ${MIN_SIM:+--minimum-similarity $MIN_SIM}
python3 ${HF_WORKFLOWS}/subtitles/scripts/subtitle_paper_burn.py --in work/output/final_clean.mp4 --srt work/output/final.srt \
  --out work/output/final.mp4 --style "$CAPTION_LOOK"
ffprobe -v error -show_entries stream=codec_type,duration,width,height -of csv=p=0 work/output/final.mp4
# small QA strips for the workspace: one frame per block, then a second frame of each block
mk() { # name t1..t7
  name=$1; shift; i=0
  for t in "$@"; do ffmpeg -nostdin -loglevel error -y -ss $t -i work/output/final.mp4 -frames:v 1 -vf scale=90:160 /tmp/q_${name}_$i.png; i=$((i+1)); done
  python3 -c "
from PIL import Image
ims=[Image.open(f'/tmp/q_${name}_{i}.png') for i in range($#)]
s=Image.new('RGB',(90*len(ims),160)); [s.paste(im,(i*90,0)) for i,im in enumerate(ims)]; s.save('/home/user/qa_${name}.jpg',quality=32)"
}
mk a 1 13 25 37 49 61 69.5
mk b 5 17 21 33 41 55 65
cp /home/user/qa_a.jpg /home/user/qa_strip.jpg
# Phase 9: upload
[ -s work/output/final.mp4 ] || { echo "final.mp4 missing"; exit 1; }
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: video/mp4" -H "If-None-Match: *" --upload-file work/output/final.mp4 "$UPLOAD_URL")
echo "PUT -> $code"; [ "$code" = "200" ]
if [ -n "${HOOK_URL:-}" ]; then
  ffmpeg -nostdin -loglevel error -y -i work/output/final.mp4 -t 15 -c:v libx264 -crf 20 -c:a aac work/output/hook15.mp4
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: video/mp4" -H "If-None-Match: *" --upload-file work/output/hook15.mp4 "$HOOK_URL")
  echo "HOOK PUT -> $code"
fi
echo FINISH_DONE
