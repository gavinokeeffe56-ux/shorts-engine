#!/usr/bin/env bash
# Higgsfield faceless-video Phase 6 + 7 + 9 for this episode, run inside the Higgsfield sandbox.
# Usage: UPLOAD_URL='<presigned put url>' bash finish.sh
set -euo pipefail
cd /home/user
REPO=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/main/episodes/starship-v3-starlink/faceless
B=https://d8j0ntlcm91z4.cloudfront.net/user_3IcIh3SFQBb0AyeqhfSzBumbxwv
mkdir -p work/blocks work/voices work/output
curl -fsSL "$REPO/script_manifest.json" -o script_manifest.json
cat > clips.txt <<EOF
$B/hf_20261001_035228_2ab21010-ef08-4e4b-beed-c8c8e89e5c5c.mp4
$B/hf_20261001_035228_15db8ae8-34b1-42fb-9919-f991d8204a87.mp4
$B/hf_20261001_035228_7437de72-98c3-408b-969a-6640d06f7202.mp4
$B/hf_20261001_035228_61509083-769a-4047-a65a-164c1271bf1f.mp4
$B/hf_20261001_035228_df5b9956-158f-4f66-a9dc-c0b8f309cc2f.mp4
$B/hf_20261001_035228_c2a28a05-4a6d-47ad-b5e6-0a50512f6072.mp4
$B/hf_20261001_035228_4f312948-9cd0-4ad9-a1a1-0468f18b99f0.mp4
$B/hf_20261001_035228_a00b31d5-f0f1-4a37-aa56-072060602657.mp4
EOF
cat > voices.txt <<EOF
$B/hf_20261001_035234_d2610558-bb0d-4d11-a9ae-233ab3660336.mp3
$B/hf_20261001_035409_84ba4812-db72-4ff6-b5b6-3507c720c4f4.mp3
$B/hf_20261001_035409_8ea19204-fad7-4fa4-b781-ae0b44ad8591.mp3
$B/hf_20261001_035235_2108f321-097d-43a6-9937-c272ad41465c.mp3
$B/hf_20261001_035537_9fc1a6a3-3395-4e16-b30d-b00fdc93556a.mp3
$B/hf_20261001_035234_e5ee9482-d4c9-48ec-a01c-e67839292ded.mp3
$B/hf_20261001_035248_587aec3f-6db1-4859-a9c0-79c7f66c95f2.mp3
$B/hf_20261001_035408_d68d7185-b07a-43f9-ad23-829d07fe6d04.mp3
EOF
# light instrumental bed (our own synthesized track), ducked under the voice by the assembler
if [ ! -s bed.wav ]; then
  rm -rf se && git clone -q --depth 1 https://github.com/gavinokeeffe56-ux/shorts-engine se
  pip install -q numpy >/dev/null 2>&1 || true
  (cd se && python3 tools/make_audio_assets.py >/dev/null) && cp se/public/music/bed.wav bed.wav
fi
python3 ${HF_WORKFLOWS}/faceless-video/scripts/validate_motion_script.py --script script_manifest.json \
  --duration-seconds 80 --duration-retry-blocks 2,5,8
chmod +x ${HF_WORKFLOWS}/faceless-video/scripts/*.sh ${HF_WORKFLOWS}/subtitles/scripts/*.sh 2>/dev/null || true
bash ${HF_WORKFLOWS}/faceless-video/scripts/finish_video.sh --blocks 8 --clips-file clips.txt --voices-file voices.txt \
  --script script_manifest.json --language en --music bed.wav --out work/output/final_clean.mp4
python3 -c "import json; d=json.load(open('work/output/final_clean.mp4.assembly.json')); print('SIDECAR', d['blocks'], len(d['per_block']))"
# Phase 7: captions (bold look keeps clear of the platform UI)
CAPTION_LANGUAGE='en'; CAPTION_LOOK='bold'
bash ${HF_WORKFLOWS}/subtitles/scripts/fetch_fonts.sh
python3 ${HF_WORKFLOWS}/subtitles/scripts/audio_to_captions.py work/output/final_clean.mp4 --srt work/output/final.srt \
  --per-block work/output/final_clean.mp4.assembly.json --voice-dir work/voices --script script_manifest.json --language "$CAPTION_LANGUAGE"
python3 ${HF_WORKFLOWS}/subtitles/scripts/subtitle_paper_burn.py --in work/output/final_clean.mp4 --srt work/output/final.srt \
  --out work/output/final.mp4 --style "$CAPTION_LOOK"
ffprobe -v error -show_entries stream=codec_type,duration,width,height -of csv=p=0 work/output/final.mp4
# small QA strip for the workspace
for t in 1 13 25 37 49 61 73; do ffmpeg -nostdin -loglevel error -y -ss $t -i work/output/final.mp4 -frames:v 1 -vf scale=90:160 /tmp/q$t.png; done
python3 -c "
from PIL import Image
ts=[1,13,25,37,49,61,73]; ims=[Image.open(f'/tmp/q{t}.png') for t in ts]
s=Image.new('RGB',(90*len(ims),160)); [s.paste(im,(i*90,0)) for i,im in enumerate(ims)]; s.save('/home/user/qa_strip.jpg',quality=35)"
# Phase 9: upload
[ -s work/output/final.mp4 ] || { echo "final.mp4 missing"; exit 1; }
code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: video/mp4" -H "If-None-Match: *" --upload-file work/output/final.mp4 "$UPLOAD_URL")
echo "PUT -> $code"; [ "$code" = "200" ]
echo FINISH_DONE
