#!/usr/bin/env bash
# Render a .cast to GIF (agg via mise exec) and MP4 (ffmpeg). Usage: render.sh IN.cast OUTDIR [font-size]
set -euo pipefail
cast=$1; out=$2; font=${3:-14}
mkdir -p "$out"
base=$(basename "$cast" .cast)
mise exec github:asciinema/agg@latest -- agg --font-size "$font" "$cast" "$out/$base.gif" >/dev/null 2>&1
ffmpeg -hide_banner -loglevel error -y -i "$out/$base.gif" -movflags +faststart -pix_fmt yuv420p \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "$out/$base.mp4"
printf 'duration %ss\n' "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/$base.gif")"
ls -la "$out/$base.gif" "$out/$base.mp4"
