# Sourced by the tsk popup scripts. Reads the tsk task the board shows as
# selected. The board has no API for its selection, so the task number is read
# off the screen: a board row carries the `▸` cursor marker, and a task page
# opens with its `T<n>` header.

# tsk_selected_task PANE: print the T<n> under the cursor of the board in PANE.
tsk_selected_task() {
  local screen header task
  screen=$(tuios capture-pane -w "$1") || return 0
  task=$(rg -m1 -o '▸.*?\b(T\d+)\b' -r '$1' <<<"$screen" || true)
  if [[ -z $task ]]; then
    header=$(awk 'NF { print; exit }' <<<"$screen")
    task=$(rg -o '^\s*\S+\s+(T\d+)\b' -r '$1' <<<"$header" || true)
  fi
  printf '%s' "$task"
}

# tsk_find_task: the task under the cursor of the board in the pane the key was
# pressed in (TUIOS_ACTIVE_PANE_ID, from toggle-popup.sh or the command key),
# else of the first tsk board in the session.
tsk_find_task() {
  local pane=${TUIOS_ACTIVE_PANE_ID:-${TUIOS_PANE_ID:-}} task=
  [[ -n $pane ]] && task=$(tsk_selected_task "$pane")
  if [[ -z $task ]]; then
    pane=$(tuios list-windows --json |
      jq -r 'first(.windows[] | select(.foreground_cmd == "tsk") | .window_id) // empty')
    [[ -n $pane ]] && task=$(tsk_selected_task "$pane")
  fi
  printf '%s' "$task"
}
