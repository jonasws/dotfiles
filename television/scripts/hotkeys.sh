#!/usr/bin/env bash
# Rows for the hotkeys channel, read from ../hotkeys/<tool>.tsv.
#
#   hotkeys.sh list [tool]   one aligned row per binding; no tool means all of them
#   hotkeys.sh preview ROW   the row's section, with the row highlighted
#
# Rows are coloured with Catppuccin Mocha truecolor escapes, one colour per tool.
# Kept to bash 3.2 and BSD awk.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hotkeys" && pwd)"
order="herdr rex lazygit yazi tuicr hunk television fx lnav tabiew wezterm"

# "r;g;b" for a 38;2 foreground escape.
color() {
  case "$1" in
    herdr) echo "203;166;247" ;;      # mauve
    rex) echo "243;139;168" ;;        # red
    lazygit) echo "250;179;135" ;;    # peach
    yazi) echo "249;226;175" ;;       # yellow
    tuicr) echo "166;227;161" ;;      # green
    hunk) echo "148;226;213" ;;       # teal
    television) echo "137;220;235" ;; # sky
    fx) echo "116;199;236" ;;         # sapphire
    lnav) echo "137;180;250" ;;       # blue
    tabiew) echo "180;190;254" ;;     # lavender
    wezterm) echo "245;194;231" ;;    # pink
    *) echo "205;214;244" ;;          # text
  esac
}

# plain=1 leaves the escapes out, so preview can compare against tv's stripped row.
rows() {
  awk -F'\t' -v tool="$1" -v c="$(color "$1")" -v plain="${2:-0}" '
    BEGIN {
      e = "\033["; r = e "0m"
      if (plain) { ct = ""; cs = ""; ck = ""; cx = ""; r = "" }
      else {
        ct = e "1;38;2;" c "m"          # tool: bold, tool colour
        cs = e "38;2;147;153;178m"      # section: overlay1
        ck = e "38;2;" c "m"            # key: tool colour
        cx = e "1;38;2;249;226;175m"    # star: bold yellow
      }
    }
    /^#/ || NF < 3 { next }
    {
      star = ($4 == "" ? "" : "  " cx $4 r)
      printf "%s%-10s%s %s%-10s%s %s%-30s%s %s%s\n", ct, tool, r, cs, $1, r, ck, $2, r, $3, star
    }
  ' "$dir/$1.tsv"
}

case "${1:-}" in
  list)
    if [ -n "${2:-}" ]; then
      rows "$2"
    else
      for tool in $order; do rows "$tool"; done
    fi
    ;;
  preview)
    row="$2"
    tool="$(printf '%s' "$row" | awk '{print $1}')"
    section="$(printf '%s' "$row" | awk '{print $2}')"
    c="$(color "$tool")"
    printf '\033[1;38;2;%sm%s\033[0m \033[38;2;147;153;178m›\033[0m \033[1m%s\033[0m\n\n' "$c" "$tool" "$section"
    rows "$tool" 1 | awk -v sec="$section" -v row="$row" -v c="$c" '
      BEGIN { e = "\033["; r = e "0m" }
      $2 != sec { next }
      {
        key = substr($0, 23, 30); rest = substr($0, 54)
        sub(/  ★$/, "  " e "1;38;2;249;226;175m★" r, rest)
      }
      $0 == row {
        k = key; sub(/ +$/, "", k)
        printf "%s▶%s %s%s%s%*s %s%s%s\n", e "1;38;2;" c "m", r, e "1;4;38;2;" c "m", k, r, length(key) - length(k), "", e "1m", rest, r
        next
      }
      { printf "  %s%s%s %s\n", e "38;2;" c "m", key, r, rest }
    '
    comments="$(sed -n 's/^# \{0,1\}//p' "$dir/$tool.tsv" | sed 1d)"
    [ -n "$comments" ] && printf '\n\033[2m%s\033[0m\n' "$comments"
    ;;
  *)
    echo "usage: hotkeys.sh list [tool] | preview ROW" >&2
    exit 2
    ;;
esac
