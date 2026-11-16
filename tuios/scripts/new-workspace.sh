#!/usr/bin/env bash
# Show a workspace, opening its first pane before the switch so the empty
# workspace's splash never draws. With a number, that workspace (past the last
# one in use it is the one after); with none, the first workspace with no pane.
# The new pane starts in the focused pane's folder. Bound to super+t, super+n,
# super+1..9, prefix+c and prefix+1..9 in config.toml.
#
# tuios's own switch shows the empty workspace first and asks the daemon for
# the pane after, so the splash draws until the pane arrives.

session=${TUIOS_SESSION:-}
[[ -n $session ]] || exit 0

# Command keys run without the shell's aliases.
tuios=$(command -v tuios) || tuios=$HOME/.local/share/tuios-nightly/bin/tuios
[[ -x $tuios ]] || exit 0

state=$("$tuios" list-windows -s "$session" --json 2>/dev/null) || exit 0
{ read -r target; read -r has; read -r cwd; } < <(jq -r --arg want "${1:-}" '
  . as $s
  | ([.windows[] | select(.workspace >= 1 and .workspace <= 9) | .workspace] | unique) as $used
  | (if $want == ""
     then ([range(1; 10)] | map(select(. as $w | $used | index($w) | not)) | first // 0)
     else ([($want | tonumber), (($used | max // 0) + 1)] | min) end) as $target
  | $target, (if ($used | index($target)) != null then "yes" else "no" end),
    ([$s.windows[] | select(.window_id == $s.focused_window_id) | .cwd][0] // "")
' <<<"$state" 2>/dev/null)

[[ $target =~ ^[1-9]$ ]] || exit 0

if [[ $has == no ]]; then
  "$tuios" new-window -s "$session" --workspace "$target" ${cwd:+--cwd "$cwd"} >/dev/null || exit 0
fi
exec "$tuios" select-workspace -s "$session" "$target"
