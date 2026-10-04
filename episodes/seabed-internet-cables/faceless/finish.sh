#!/usr/bin/env bash
# Higgsfield faceless-video Phase 6 + 7 + 9 for this episode, run inside the Higgsfield sandbox.
# Usage: COMMIT=<sha> UPLOAD_URL='<presigned put url>' [HOOK_URL='<presigned put url for the 15 s hook clip>'] bash finish.sh
# All-AI episode (tech topic): no real-footage blocks.
set -euo pipefail
cd /home/user
REPO=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/${COMMIT:-main}/episodes/seabed-internet-cables/faceless
B=https://d8j0ntlcm91z4.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
S=https://d2ol7oe51mr4n9.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
rm -rf work/blocks work/voices work/output; mkdir -p work/blocks work/voices work/output
curl -fsSL "$REPO/script_manifest.json" -o script_manifest.json
cat > clips.txt <<EOT
$B/hf_20261004_042544_beb73ce8-a07f-4345-99ac-81056f57c8b8.mp4
$B/hf_20261004_042415_f2a2d4d0-753d-41ea-9577-3f971675b5e9.mp4
$B/hf_20261004_042415_9a33449a-3c8b-4a52-8948-9da5489c60ba.mp4
$B/hf_20261004_042415_55de9bf6-f08f-433b-a20f-3ddedad67a37.mp4
$B/hf_20261004_042415_19fbb540-d323-4129-837f-f3a36f0a92ea.mp4
$B/hf_20261004_042415_c14c61c0-53ac-464d-a8c3-be5a478e37e1.mp4
$B/hf_20261004_042544_8394fb44-55db-4516-a1a3-1e6a6ee77cc2.mp4
EOT
cat > voices.txt <<EOT
$B/hf_20261004_043642_d79b633c-8e24-4ce5-98eb-4eff52582fd9.mp3
$B/hf_20261004_043642_9ce6019e-516d-4b97-b6b7-eaeb141c2f58.mp3
$B/hf_20261004_042427_a0bf60ca-df69-4d66-9645-02ccb8b12631.mp3
$B/hf_20261004_042427_71648c56-9d6d-4289-a57f-cdb1af7e5e8e.mp3
$B/hf_20261004_044219_31faaca3-0523-4553-b06b-c7b7d455650f.mp3
$B/hf_20261004_042427_5c7b640e-4501-43ff-a282-86f7146943c8.mp3
$B/hf_20261004_044759_f15c652e-5d17-4c27-94dd-1c2ba3e61804.mp3
EOT
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
  --duration-seconds 70${RETRY:+ --duration-retry-blocks $RETRY}
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
bash se/tools/hook_title.sh work/output/final_caps.mp4 work/output/final.mp4 "${HOOK1:-NOT SATELLITES}" "${HOOK2:-THE SEA FLOOR}"
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
