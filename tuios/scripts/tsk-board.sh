# Sourced by the tsk popup scripts. Reads the tsk task the board shows as
# selected. The board has no API for its selection, so the task number is read
# off the screen: a board row carries the `▸` cursor marker, and a task page
# opens with its `T<n>` header.
#
# A board is the `tsk-board` popup (toggle-popup.sh names it) or a pane running
# tsk in the foreground. Only a board's screen is read, so a `▸ T12` in an
# agent's output is never taken for a selection.

tsk_board_filter='.windows[] | select(.custom_name == "tsk-board" or .foreground_cmd == "tsk")'

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

# tsk_focused_task: the task under the cursor of the board the key was pressed
# in (TUIOS_ACTIVE_PANE_ID, set for a command key and passed on by
# toggle-popup.sh). Returns 2 when that pane is not a board.
tsk_focused_task() {
  local pane=${TUIOS_ACTIVE_PANE_ID:-${TUIOS_PANE_ID:-}}
  [[ -n $pane ]] || return 2
  tuios list-windows --json |
    jq -e --arg id "$pane" "any($tsk_board_filter; .window_id == \$id)" >/dev/null ||
    return 2
  tsk_selected_task "$pane"
}

# tsk_find_task: the focused board's task, else the first board's in the
# session. Returns 2 when the session has no board.
tsk_find_task() {
  local pane
  tsk_focused_task && return 0
  pane=$(tuios list-windows --json | jq -r "first($tsk_board_filter | .window_id) // empty")
  [[ -n $pane ]] || return 2
  tsk_selected_task "$pane"
}
