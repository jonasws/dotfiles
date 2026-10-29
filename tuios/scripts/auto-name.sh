#!/usr/bin/env bash
# Name an agent pane after its topic, so the rail stops showing "claude 1" and
# "claude 2". Run it from the `after-agent-state` hook (see config.toml).
#
# The rail ranks a name set with `tuios set-window` above the running command,
# and the topic Claude Code sets is only the window title. A name this script
# wrote is remembered in a marker file, so a later turn renames the pane again,
# while a name you gave it by hand is left alone. `tuios set-window --name ""`
# hands a pane back.
#
# Outside tuios, or with the daemon out of reach, it exits 0 without output.

[[ -n ${TUIOS_WINDOW_ID:-} && -n ${TUIOS_AGENT_HARNESS:-} ]] || exit 0

# The daemon runs hooks with its own environment, where the `tuios` shell alias
# does not exist.
tuios=$(command -v tuios) || tuios=$HOME/.local/share/tuios-nightly/bin/tuios
[[ -x $tuios ]] || exit 0
command -v jq >/dev/null || exit 0

session=${TUIOS_SESSION_ID:-}
win=$("$tuios" list-windows ${session:+-s "$session"} --json 2>/dev/null |
  jq -c --arg id "$TUIOS_WINDOW_ID" '
    first(.windows[]? | .window_id as $w | select(($w | startswith($id)) or ($id | startswith($w)))) // empty
  ' 2>/dev/null) || exit 0
[[ -n $win ]] || exit 0

id=$(jq -r .window_id <<<"$win")
custom=$(jq -r '.custom_name // ""' <<<"$win")
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/tuios-auto-name
marker=$state_dir/$id

last=
[[ -f $marker ]] && last=$(<"$marker")
[[ -z $custom || $custom == "$last" ]] || exit 0

# Drop the status glyph Claude Code puts ahead of a topic, and cap the length.
topic=$(jq -r '.title // "" | sub("^[^[:alnum:]]+"; "") | .[0:40]' <<<"$win")
cwd_base=$(basename "$(jq -r '.cwd // ""' <<<"$win")")

# A shell title ("~/dotfiles"), the command, or tuios's "Terminal <id>" default
# is not a topic.
case $topic in
  '' | "$cwd_base" | claude | shell | "Terminal "*) exit 0 ;;
esac
[[ $topic == "$custom" ]] && exit 0

"$tuios" set-window -w "$id" ${session:+-s "$session"} --name "$topic" >/dev/null 2>&1 || exit 0
mkdir -p "$state_dir" && printf '%s' "$topic" >"$marker"
