#!/usr/bin/env bash
# Burn a big two-line text hook over the first seconds of a finished video (the on-screen hook TikTok viewers
# read before the voice lands). Runs in the Higgsfield sandbox after captions are burned.
# Usage: hook_title.sh in.mp4 out.mp4 "LINE ONE" ["LINE TWO"] [seconds=2.8]
#   Line one is white, line two is yellow. Keep each line to about 16 characters; longer lines shrink to fit.
set -euo pipefail
in=$1; out=$2; l1=$3; l2=${4:-}; d=${5:-2.8}
font=$(fc-list | grep -iE 'Montserrat.*(ExtraBold|Black)' | head -1 | cut -d: -f1)
[ -n "$font" ] || font=$(fc-list | grep -iE 'Montserrat.*Bold|Metropolis.*(Black|Bold)' | head -1 | cut -d: -f1)
[ -n "$font" ] || font=$(fc-list | grep -i bold | head -1 | cut -d: -f1)
IFS=, read -r W H < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$in")
n1=${#l1}; n2=${#l2}; n=$(( n1 > n2 ? n1 : n2 ))
fs=$(( H * 50 / 1000 )); fit=$(python3 -c "print(int($W*0.90/(0.64*max($n,1))))")
[ "$fit" -lt "$fs" ] && fs=$fit
printf '%s' "$l1" > /tmp/ht1.txt; printf '%s' "$l2" > /tmp/ht2.txt
common="fontfile=$font:fontsize=$fs:borderw=$(( fs / 7 )):bordercolor=black:x=(w-text_w)/2:enable='lt(t,$d)':alpha='if(lt(t,$d-0.3),1,max(0,($d-t)/0.3))'"
vf="drawtext=textfile=/tmp/ht1.txt:fontcolor=white:y=h*0.15:$common"
[ -n "$l2" ] && vf="$vf,drawtext=textfile=/tmp/ht2.txt:fontcolor=0xFFE14A:y=h*0.15+$(( fs * 125 / 100 )):$common"
ffmpeg -nostdin -loglevel error -y -i "$in" -vf "$vf" -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a copy -movflags +faststart "$out"
echo "HOOK_TITLE_OK font=$font size=$fs"
