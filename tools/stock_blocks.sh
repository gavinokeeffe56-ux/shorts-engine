#!/usr/bin/env bash
# Build an episode's REAL-FOOTAGE blocks (NASA public domain) inside the Higgsfield sandbox and PUT each one
# to its presigned upload URL, so they can go into clips.txt like any AI block.
# Usage (sandbox, background):
#   COMMIT=<sha> EP=<episode dir> SEED=<yyyy-mm-dd> UPLOADS='3=<put url> 6=<put url>' bash stock_blocks.sh
#   (UPLOADS value "skip" builds without uploading; STOCK_URL overrides the stock.json location)
# Reads episodes/<EP>/faceless/stock.json:
#   {"blocks": {"3": {"queries": ["..."], "ids": [optional hand-picked nasa_ids], "avoid_ids": [rejected ones],
#                     "shows": "...", "line": "..."}}}
# Prints per block: "BLOCK n OK|FAILED", the PUT status, the credits json, then STOCK_QA_B64=<small strip>.
set -uo pipefail
cd /home/user
RAW=https://raw.githubusercontent.com/gavinokeeffe56-ux/shorts-engine/$COMMIT
curl -fsSL "$RAW/tools/stock_block.py" -o stock_block.py || { echo "no stock_block.py"; exit 1; }
curl -fsSL "${STOCK_URL:-$RAW/episodes/$EP/faceless/stock.json}" -o stock.json || { echo "no stock.json"; exit 1; }
curl -fsSL "$RAW/stock_used.txt" -o stock_used.txt 2>/dev/null || : > stock_used.txt
pip install -q "opencv-python-headless<5" >/dev/null 2>&1 || echo "WARN no opencv: face filter off"
mkdir -p work/stock && rm -f /tmp/sq_*.png
built=()
for pair in $UPLOADS; do
  n=${pair%%=*}; url=${pair#*=}; nn=$(printf %02d "$n"); out=work/stock/block$nn.mp4
  mapfile -t qs < <(python3 -c "
import json; b=json.load(open('stock.json'))['blocks']['$n']
for k,f in (('queries','--query'),('ids','--id'),('avoid_ids','--avoid-id')):
    for v in b.get(k,[]): print(f); print(v)")
  args=("${qs[@]}")
  if ! python3 stock_block.py "${args[@]}" --out "$out" --avoid-file stock_used.txt --seed "${SEED:-0}"; then
    echo "BLOCK $n FAILED"; continue
  fi
  echo "BLOCK $n OK"; cat "$out.json"; echo
  if [ "$url" != "skip" ]; then
    code=$(curl -sS -o /dev/null -w '%{http_code}' -X PUT -H "Content-Type: video/mp4" --upload-file "$out" "$url")
    echo "BLOCK $n PUT $code"
  fi
  for t in 1 3 5 7 9; do
    ffmpeg -nostdin -loglevel error -y -ss $t -i "$out" -frames:v 1 -vf scale=54:96 "/tmp/sq_${nn}_$t.png"
  done
  built+=("$nn")
done
python3 - "${built[@]}" <<'PY'
import sys, base64, io
from PIL import Image
rows = sys.argv[1:]
if rows:
    s = Image.new('RGB', (54 * 5, 96 * len(rows)))
    for r, nn in enumerate(rows):
        for i, t in enumerate([1, 3, 5, 7, 9]):
            s.paste(Image.open(f'/tmp/sq_{nn}_{t}.png'), (i * 54, r * 96))
    b = io.BytesIO(); s.save(b, 'JPEG', quality=35)
    print('STOCK_QA_B64=' + base64.b64encode(b.getvalue()).decode())
PY
echo STOCK_DONE
