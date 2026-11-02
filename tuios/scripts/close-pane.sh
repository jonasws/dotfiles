#!/usr/bin/env bash
# Close the focused pane, as prefix+x does by default. On the session's last
# pane, show the next session in the shared order and kill this one, rather
# than leave it empty on its splash screen. With no other session, it only
# closes the pane. Bound to prefix+x in config.toml.

session=${TUIOS_SESSION:-}
pane=${TUIOS_ACTIVE_PANE_ID:-}
[[ -n $session && -n $pane ]] || exit 0

# Command keys run without the shell's aliases.
tuios=$(command -v tuios) || tuios=$HOME/.local/share/tuios-nightly/bin/tuios
[[ -x $tuios ]] || exit 0

sessions=$("$tuios" ls --json 2>/dev/null) || sessions=
{ read -r count; read -r next; } < <(jq -r --arg s "$session" '
  (map(.name) | index($s)) as $i
  | if $i == null or length < 2 then empty
    else .[$i].window_count, .[($i + 1) % length].name
    end' <<<"$sessions" 2>/dev/null)

if [[ $count == 1 && -n $next ]]; then
  "$tuios" switch-session -s "$session" "$next" && exec "$tuios" kill-session "$session"
fi
exec "$tuios" close-window -s "$session" "$pane"
