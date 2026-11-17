#!/usr/bin/env bash
# Tile frames of a GIF/MP4 at the given seconds into one PNG, two per row.
# Usage: contact_sheet.sh VIDEO OUT.png [--crop-top PX] T1 T2 ...
set -euo pipefail
video=$1; out=$2; shift 2
crop=""
if [[ ${1:-} == --crop-top ]]; then crop="crop=iw:$2:0:0,"; shift 2; fi
tmp=$(mktemp -d)
i=0
for t in "$@"; do
  ffmpeg -hide_banner -loglevel error -y -ss "$t" -i "$video" -frames:v 1 -vf "${crop}scale=800:-1" "$tmp/$(printf 'f%02d' "$i").png"
  i=$((i + 1))
done
cols=2; rows=$(( (i + 1) / 2 )); [[ $i -eq 1 ]] && cols=1
ffmpeg -hide_banner -loglevel error -y -framerate 1 -i "$tmp/f%02d.png" -vf "tile=${cols}x${rows}" -frames:v 1 "$out"
echo "$out"
