#!/usr/bin/env bash
# Open the draft the agent in the focused pane wrote, in leaf beside it, where
# Ctrl+E edits it in Neovim. Bound to a command key.
#
# An agent in nono holds only the read and write grants, so it cannot split
# its own pane; the draft-pane skill then writes the draft to
# $XDG_CACHE_HOME/drafts/<its pane id>/ and asks you for this key. The pane is
# yours: it runs outside the sandbox, so only a file that is the agent's own
# work is opened. Anything that resolves outside the drafts directory, or a
# file with another name (a hard link), is refused: the agent can read the pane
# back, and the pane could otherwise show a file the sandbox denies it.
set -euo pipefail

pane=${TUIOS_ACTIVE_PANE_ID:-}
say() {
  exec ~/.config/tuios/scripts/toggle-popup.sh agent-draft 70 7 -- \
    bash -c 'printf "\n  %s\n\n  Press any key to close." "$1"; read -rsn1' _ "$1"
}

[[ -n $pane ]] || say "No focused pane."

file=
for root in "$HOME/.cache/agents/drafts" "$HOME/.cache/drafts"; do
  [[ -d $root/$pane ]] || continue
  file=$(ls -t "$root/$pane"/*.md 2>/dev/null | head -n 1 || true)
  [[ -n $file ]] && break
done
[[ -n $file ]] || say "This pane's agent has published no draft."

real=$(realpath "$file")
case $real in
"$(realpath "$root")/$pane"/*.md) ;;
*) say "Refused: $file resolves outside the drafts directory." ;;
esac
[[ -f $real && ! -L $file && $(stat -f %l "$real") -eq 1 ]] ||
  say "Refused: $file is not a plain file of its own."

name="draft $(basename "$real")"
if tuios list-windows ${TUIOS_SESSION:+-s "$TUIOS_SESSION"} --json |
  jq -e --arg n "$name" '.windows[] | select(.display_name == $n)' >/dev/null; then
  exec tuios focus-window ${TUIOS_SESSION:+-s "$TUIOS_SESSION"} "$name"
fi
exec tuios split-window right ${TUIOS_SESSION:+-s "$TUIOS_SESSION"} -w "$pane" \
  --name "$name" --cwd "$(dirname "$real")" -- leaf -w "$real"
