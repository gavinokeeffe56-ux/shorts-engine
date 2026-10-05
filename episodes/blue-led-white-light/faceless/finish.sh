#!/usr/bin/env bash
# Higgsfield faceless-video Phase 6 + 7 + 9 for this episode, run inside the Higgsfield sandbox.
# Usage: COMMIT=<sha> UPLOAD_URL='<presigned put url>' [HOOK_URL='<presigned put url for the 15 s hook clip>'] bash finish.sh
# All-AI episode (tech topic): no real-footage blocks.
set -euo pipefail
cd /home/user
REPO=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/${COMMIT:-main}/episodes/blue-led-white-light/faceless
B=https://d8j0ntlcm91z4.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
S=https://d2ol7oe51mr4n9.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
rm -rf work/blocks work/voices work/output; mkdir -p work/blocks work/voices work/output
curl -fsSL "$REPO/${MANIFEST:-script_manifest.json}" -o script_manifest.json
cat > clips.txt <<EOT
$B/hf_20261005_040850_469f0694-8de4-4737-8575-1d55700f7bc7.mp4
$B/hf_20261005_040850_477d6734-8fc7-4d86-ad05-13709a699762.mp4
$B/hf_20261005_040850_715ce456-1019-4fd9-b17f-1e0afe0b2d55.mp4
$B/hf_20261005_040850_76f006a2-2cd2-452d-a220-83cd301080b4.mp4
$B/hf_20261005_040850_381879c2-dd4f-454d-9bb4-8246d2e506bb.mp4
$B/hf_20261005_040850_a479853c-2d7f-4c2c-86a1-694454d36b84.mp4
$B/${CLIP7:?set CLIP7 to the block 7 file name}
EOT
# block 1 voice: the take runs 9.56 s with ~0.2 s of decay after the last word; trim the tail to 9.46 s (silence only) so the speech fits the 9.5 s window and starts early
curl -fsSL "$B/${VOICE1SRC:-hf_20261005_041242_485af415-b94c-4b94-990a-aaa8ec9bb248.mp3}" -o /home/user/v1_src.mp3
ffmpeg -nostdin -loglevel error -y -i /home/user/v1_src.mp3 -af "atrim=end=${V1END:-9.46},afade=t=out:st=${V1FADE:-9.40}:d=0.06" -c:a libmp3lame -q:a 2 /home/user/v1.mp3
cat > voices.txt <<EOT
/home/user/v1.mp3
$B/hf_20261005_041242_8dc27741-e636-48a3-9c55-f818ba3669b6.mp3
$B/hf_20261005_040939_9e2b49d5-2a21-41aa-b7a6-a9febe8355d3.mp3
$B/hf_20261005_040939_6822dc41-338d-4056-844f-39cd1806ea55.mp3
$B/hf_20261005_040939_60aa1cea-101d-4d0d-80c8-9856cc774fa2.mp3
$B/hf_20261005_040939_1d6575a3-d029-4d77-bc00-ba218e91d1b8.mp3
$B/hf_20261005_040939_f8808531-f0e8-4ad6-86a5-e89e34749418.mp3
EOT
# optional alternate block 1 (hook retry): CLIP1 / VOICE1 are file names under $B
[ -n "${CLIP1:-}" ] && sed -i "1s#.*#$B/$CLIP1#" clips.txt
# QC of the AI blocks: size, audio stream, scene cuts
for u in $(grep '^http' clips.txt); do f=/tmp/qc.mp4; curl -fsSL "$u" -o $f; echo "QC ${u: -12} $(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=p=0 $f) audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_name,sample_rate -of csv=p=0 $f | tr '\n' ' ') cuts=$(ffprobe -v error -select_streams v:0 -show_entries frame=pkt_pts_time -of csv=p=0 -f lavfi "movie=$f,select=gt(scene\,0.3)" | wc -l)"; done
# light instrumental bed (our own synthesized track), ducked under the voice by the assembler
[ -d se ] || git clone -q --depth 1 https://github.com/gavinokeeffe56-ux/shorts-engine se
if [ ! -s bed.wav ]; then
  true
  pip install -q numpy >/dev/null 2>&1 || true
  (cd se && python3 tools/make_audio_assets.py >/dev/null) && cp se/public/music/bed.wav bed.wav
fi
python3 ${HF_WORKFLOWS}/faceless-video/scripts/validate_motion_script.py --script script_manifest.json \
  --duration-seconds 70 --words-min 20 --words-max 28${RETRY:+ --duration-retry-blocks $RETRY}
chmod +x ${HF_WORKFLOWS}/faceless-video/scripts/*.sh ${HF_WORKFLOWS}/video-montage/scripts/*.sh 2>/dev/null || true
bash ${HF_WORKFLOWS}/faceless-video/scripts/finish_video.sh --blocks 7 --clips-file clips.txt --voices-file voices.txt \
  --script script_manifest.json --language en --music /home/user/bed.wav --out work/output/final_clean.mp4
python3 -c "import json; d=json.load(open('work/output/final_clean.mp4.assembly.json')); print('SIDECAR', d['blocks'], len(d['per_block']))"
# captions look for v_00N.wav; the assembler writes voiceNN.wav
for i in 0 1 2 3 4 5 6; do n=$(printf %02d $((i+1))); [ -e work/voices/v_00$i.wav ] || { [ -e work/voices/voice$n.wav ] && ln -s voice$n.wav work/voices/v_00$i.wav; } || true; done
# Phase 7: captions (bold look keeps clear of the platform UI)
CAPTION_LANGUAGE='en'; CAPTION_LOOK='bold'
bash ${HF_WORKFLOWS}/video-montage/scripts/fetch_fonts.sh
A2C="python3 ${HF_WORKFLOWS}/video-montage/scripts/audio_to_captions.py work/output/final_clean.mp4 --srt work/output/final.srt --script script_manifest.json --language $CAPTION_LANGUAGE ${MIN_SIM:+--minimum-similarity $MIN_SIM}"
$A2C --per-block work/output/final_clean.mp4.assembly.json --voice-dir work/voices || { echo "CAPTIONS: per-block failed, using --mixed"; $A2C --mixed; }
python3 ${HF_WORKFLOWS}/video-montage/scripts/subtitle_paper_burn.py --in work/output/final_clean.mp4 --srt work/output/final.srt \
  --out work/output/final.mp4 --style "$CAPTION_LOOK" --no-caps --font-key montserrat --stroke-frac 0.045 --profile faceless
echo "CUES $(grep -c -- '-->' work/output/final.srt)"
mv work/output/final.mp4 work/output/final_caps.mp4
bash se/tools/hook_title.sh work/output/final_caps.mp4 work/output/final.mp4 "${HOOK1:-30 YEARS}" "${HOOK2:-FOR ONE COLOR}"
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
ffmpeg -nostdin -loglevel error -y -ss 1 -i work/output/final.mp4 -frames:v 1 -vf scale=360:640 /home/user/qa_hook.jpg
ffmpeg -nostdin -loglevel error -y -ss 0.2 -i work/output/final.mp4 -frames:v 1 -vf scale=360:640 /home/user/qa_first.jpg
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
