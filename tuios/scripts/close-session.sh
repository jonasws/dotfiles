#!/usr/bin/env bash
# Close the session the way herdr's prefix+D closes a workspace: ask first,
# then show the session that takes its place in the list (the next one, or the
# previous one when it was last) and kill it. A client cannot stay attached to
# no session, so closing the only one quits the client.
#
# Runs in a popup from tuios/scripts/toggle-popup.sh; bound to prefix+D in
# config.toml.

session=${TUIOS_SESSION:-}
[[ -n $session ]] || exit 0

# Command keys run without the shell's aliases.
tuios=$(command -v tuios) || tuios=$HOME/.local/share/tuios-nightly/bin/tuios
[[ -x $tuios ]] || exit 0

sessions=$("$tuios" ls --json 2>/dev/null) || sessions='[]'
{ read -r count; read -r next; } < <(jq -r --arg s "$session" '
  (map(.name) | index($s)) as $i
  | if $i == null then empty
    else (.[$i].window_count // 0),
         (if length < 2 then ""
          elif $i + 1 < length then .[$i + 1].name
          else .[$i - 1].name end)
    end' <<<"$sessions" 2>/dev/null)

printf '\n  Close session \e[1m%s\e[0m and its %s pane(s)?\n' "$session" "${count:-?}"
if [[ -n $next ]]; then
  printf '  Then show \e[1m%s\e[0m.\n' "$next"
else
  printf '  It is the only session, so tuios quits.\n'
fi
printf '\n  [y] close   [any other key] cancel '
read -rsn1 answer
[[ $answer == [yY] ]] || exit 0

if [[ -n $next ]]; then
  "$tuios" switch-session -s "$session" "$next" || exit 1
fi
exec "$tuios" kill-session "$session"
