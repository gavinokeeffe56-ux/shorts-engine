#!/usr/bin/env bash
# Higgsfield faceless-video Phase 6 + 7 + 9 for this episode, run inside the Higgsfield sandbox.
# Usage: COMMIT=<sha> CLIP1..CLIP7=<block file names> UPLOAD_URL='<presigned put url>' [HOOK_URL='<presigned put url for the 15 s hook clip>'] bash finish.sh
# All-AI episode (tech topic): no real-footage blocks.
set -euo pipefail
cd /home/user
REPO=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/${COMMIT:-main}/episodes/ai-tokens-strawberry/faceless
B=https://d8j0ntlcm91z4.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
S=https://d2ol7oe51mr4n9.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
rm -rf work/blocks work/voices work/output; mkdir -p work/blocks work/voices work/output
curl -fsSL "$REPO/${MANIFEST:-script_manifest.json}" -o script_manifest.json
cat > clips.txt <<EOT
$B/${CLIP1:?}
$B/${CLIP2:?}
$B/${CLIP3:?}
$B/${CLIP4:?}
$B/${CLIP5:?}
$B/${CLIP6:?}
$B/${CLIP7:?}
EOT
# voices (Holden). Long pauses are shortened to 0.25 s and silent head/tail removed (silence only); a take still over
# 9.3 s gets a mild tempo lift (max 1.12) and one under 8.1 s a mild slow-down (min 0.90), because the assembler
# needs 7.8-9.5 s of speech per block.
i=1
for f in hf_20261006_040845_04ca4007-23eb-439e-b2b0-47f31fcc0bc0 hf_20261006_040845_dece25d9-ff5a-4ec9-8220-32898eaf55f4 hf_20261006_040845_aff89515-8f37-4647-9f10-6f8fea5f74d2 hf_20261006_043426_b20db1a5-52c5-4c43-9c00-3020d8e27c9b hf_20261006_043426_b79d4a6c-dcc2-4afd-a02d-5674a1d31318 hf_20261006_040845_6ded1485-6f9f-40bc-9952-50d6a51b3c52 hf_20261006_043426_8a407743-954c-4d54-b5f1-f33407e1f914; do
  curl -fsSL "$B/$f.mp3" -o /home/user/src$i.mp3
  ffmpeg -nostdin -loglevel error -y -i /home/user/src$i.mp3 -af "silenceremove=start_periods=1:start_threshold=-38dB:start_silence=0.03:stop_periods=-1:stop_duration=0.3:stop_silence=0.25:stop_threshold=-38dB" -ar 44100 /home/user/t$i.wav
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 /home/user/t$i.wav)
  af=$(python3 -c "d=$d; t=d/9.3 if d>9.3 else (d/8.1 if d<8.1 else 1.0); t=min(1.12,max(0.90,t)); print('atempo=%.4f'%t)")
  ffmpeg -nostdin -loglevel error -y -i /home/user/t$i.wav -af "$af" -c:a libmp3lame -q:a 2 /home/user/v$i.mp3
  echo "VOICE $i trimmed=$d filter=$af final=$(ffprobe -v error -show_entries format=duration -of csv=p=0 /home/user/v$i.mp3)"
  i=$((i+1))
done
for i in 1 2 3 4 5 6 7; do echo /home/user/v$i.mp3; done > voices.txt
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
  --script script_manifest.json --language en ${SOFT:+--accept-soft-blocks $SOFT} --music /home/user/bed.wav --out work/output/final_clean.mp4
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
H2DEF="MISCOUNTS R'S"
bash se/tools/hook_title.sh work/output/final_caps.mp4 work/output/final.mp4 "${HOOK1:-WRITES ESSAYS}" "${HOOK2:-$H2DEF}"
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
