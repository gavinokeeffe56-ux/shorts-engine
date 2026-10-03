#!/usr/bin/env bash
# Higgsfield faceless-video Phase 6 + 7 + 9 for this episode, run inside the Higgsfield sandbox.
# Usage: COMMIT=<sha> UPLOAD_URL='<presigned put url>' [HOOK_URL='<presigned put url for the 15 s hook clip>'] bash finish.sh
# Block 4 is real NASA public-domain footage built with tools/stock_blocks.sh (see stock.json / clip_credits.json).
set -euo pipefail
cd /home/user
REPO=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/${COMMIT:-main}/episodes/roman-steady-aim/faceless
B=https://d8j0ntlcm91z4.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
S=https://d2ol7oe51mr4n9.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
rm -rf work/blocks work/voices work/output; mkdir -p work/blocks work/voices work/output
curl -fsSL "$REPO/script_manifest.json" -o script_manifest.json
# real-footage blocks carry 48 kHz silence, AI blocks 32 kHz audio: the concat needs one rate, so remux the silence at 32 kHz (video untouched)
mkdir -p stockfix
for p in 04=17e586bb-88a2-4acf-8454-40195804ebca; do
  curl -fsSL "$S/${p#*=}.mp4" -o stockfix/src${p%%=*}.mp4
  ffmpeg -nostdin -loglevel error -y -i stockfix/src${p%%=*}.mp4 -f lavfi -t 10 -i anullsrc=r=32000:cl=stereo -map 0:v -map 1:a -c:v copy -c:a aac -shortest stockfix/block${p%%=*}.mp4
done
cat > clips.txt <<EOT
$B/hf_20261003_044324_849ecca0-8555-4f6c-93e5-4929a7d129d3.mp4
$B/hf_20261003_044324_f009d296-df10-46fe-89bc-aeef93c98c3d.mp4
$B/hf_20261003_044324_2c26c8fb-c8ba-45ca-a2a7-34cd8daaf9aa.mp4
/home/user/stockfix/block04.mp4
$B/hf_20261003_044325_631ef7c9-bfe5-46c5-a3bc-a51f2ed081ea.mp4
$B/hf_20261003_044325_fb6df498-2d9f-4f9c-a2e4-cf9025bc60fc.mp4
$B/hf_20261003_044324_e727fa70-4a94-42a8-88f3-3169409ab166.mp4
EOT
cat > voices.txt <<EOT
$B/hf_20261003_044353_983651ed-da38-4676-8858-f1c10ca7fa3c.mp3
$B/hf_20261003_044818_e21c5961-d4de-411a-8143-3169cbf2db12.mp3
$B/hf_20261003_044353_337122e6-3cf5-4d06-a1a1-77b67eb170b2.mp3
$B/hf_20261003_044353_89050c0f-3763-4e10-96d6-6c83ba31151f.mp3
$B/hf_20261003_044353_a3a1c58b-b364-422a-8c55-67a7b81c86bc.mp3
$B/hf_20261003_044714_04900c8c-2286-4117-a631-526183586746.mp3
$B/hf_20261003_044714_55eda7e9-a367-41bf-877a-6c133fbc40e5.mp3
EOT
# QC of the AI blocks: size, audio stream, scene cuts
for u in $(grep '^http' clips.txt); do f=/tmp/qc.mp4; curl -fsSL "$u" -o $f; echo "QC ${u: -12} $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 $f) audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_name,sample_rate -of csv=p=0 $f | tr '\n' ' ') cuts=$(ffprobe -v error -select_streams v:0 -show_entries frame=pkt_pts_time -of csv=p=0 -f lavfi "movie=$f,select=gt(scene\,0.3)" | wc -l)"; done
# light instrumental bed (our own synthesized track), ducked under the voice by the assembler
if [ ! -s bed.wav ]; then
  rm -rf se && git clone -q --depth 1 https://github.com/gavinokeeffe56-ux/shorts-engine se
  pip install -q numpy >/dev/null 2>&1 || true
  (cd se && python3 tools/make_audio_assets.py >/dev/null) && cp se/public/music/bed.wav bed.wav
fi
python3 ${HF_WORKFLOWS}/faceless-video/scripts/validate_motion_script.py --script script_manifest.json \
  --duration-seconds 70 --duration-retry-blocks 6,7
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
  for t in "$@"; do ffmpeg -nostdin -loglevel error -y -ss $t -i work/output/final.mp4 -frames:v 1 -vf scale=64:114 /tmp/q_${name}_$i.png; i=$((i+1)); done
  python3 -c "
from PIL import Image
ims=[Image.open(f'/tmp/q_${name}_{i}.png') for i in range($#)]
s=Image.new('RGB',(64*len(ims),114)); [s.paste(im,(i*64,0)) for i,im in enumerate(ims)]; s.save('/home/user/qa_${name}.jpg',quality=28,optimize=True)"
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
