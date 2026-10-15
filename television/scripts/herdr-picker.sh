#!/usr/bin/env bash
# Open the `herdr-sessions` channel with a preview sized to the popup.
#
# tv sizes the preview as a fixed percentage, which starves the list in a
# narrow popup. This reserves LIST_COLS for the list -- enough for the pane id,
# sigil, workspace and state columns plus the start of a title -- and gives the
# preview the rest, up to half the width. When that leaves too little for a
# readable preview, the preview moves below the list instead, and the list is
# sized to the panes it will show rather than to half the height: a session
# has a handful of panes, so the rest goes to the preview.
#
# The popup's size comes from Herdr, not from the popup's own terminal: a popup
# command starts before its terminal has been sized, so `tput` reads 0x0 there.
# Herdr reports the focused tab's area, and the popup is a fixed share of it,
# set by width/height on the binding in herdr/config.toml. Keep POPUP_*_PCT in
# step with those.
set -euo pipefail

POPUP_WIDTH_PCT=90
POPUP_HEIGHT_PCT=80

LIST_COLS=100
PREVIEW_MIN_COLS=40
PREVIEW_MAX_PCT=50
# Input box (3), list borders (2), status bar (1), and spare rows for panes
# opened while the picker is up.
LIST_CHROME_LINES=6
LIST_SPARE_ROWS=2
STACKED_PREVIEW_MAX_PCT=85

# Prints "<tab width> <tab height> <pane count>", or nothing if Herdr is
# unreachable, in which case the popup's own (possibly unsized) terminal is
# the only thing left to ask.
read -r tab_cols tab_lines panes < <(
  herdr api snapshot 2>/dev/null | jq -r '.result.snapshot as $s
    | ($s.layouts[] | select(.tab_id == $s.focused_tab_id) | .area) as $a
    | "\($a.width) \($a.height) \($s.panes | length)"' 2>/dev/null
) || true

if [[ -n "${tab_cols:-}" ]]; then
  # Less the popup's own border on each side.
  cols=$((tab_cols * POPUP_WIDTH_PCT / 100 - 2))
  lines=$((tab_lines * POPUP_HEIGHT_PCT / 100 - 2))
else
  cols=$(tput cols 2>/dev/null || echo 0)
  lines=$(tput lines 2>/dev/null || echo 0)
  panes=0
fi
preview_cols=$((cols - LIST_COLS))

if ((preview_cols >= PREVIEW_MIN_COLS)); then
  pct=$((preview_cols * 100 / cols))
  ((pct > PREVIEW_MAX_PCT)) && pct=$PREVIEW_MAX_PCT
  exec tv herdr-sessions --layout landscape --preview-size "$pct" "$@"
fi

list_lines=$((panes + LIST_SPARE_ROWS + LIST_CHROME_LINES))
pct=$PREVIEW_MAX_PCT

if ((lines > list_lines)); then
  pct=$(((lines - list_lines) * 100 / lines))
  ((pct > STACKED_PREVIEW_MAX_PCT)) && pct=$STACKED_PREVIEW_MAX_PCT
  ((pct < PREVIEW_MAX_PCT)) && pct=$PREVIEW_MAX_PCT
fi

exec tv herdr-sessions --layout portrait --preview-size "$pct" "$@"
