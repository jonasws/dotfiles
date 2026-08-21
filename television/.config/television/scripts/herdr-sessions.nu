#!/usr/bin/env nu

# Emit one line per Herdr pane for the `herdr-sessions` television channel.
#
# Ordered as an attention queue: blocked first, then done (finished but unseen),
# then idle, working, unclassified agents, then panes running some other command,
# and finally idle shells. Television preserves this order until you start typing.
#
# Colour requires `ansi = true`, which the channel spec lists as incompatible with
# a `display` template, so the whole line renders and the pane id has to survive
# as visible text. It leads the row, dimmed, and is recovered with
# `{strip_ansi|split: :0}`. Deriving the pane from the rest of the row instead is
# not an option -- two shells split inside one workspace render an identical
# label/state/title row.
#
# The pane the picker was launched from is omitted, since focusing it is a no-op.
# Popup commands get HERDR_ACTIVE_PANE_ID (the tiled pane underneath the popup);
# a picker run directly in a pane gets HERDR_PANE_ID instead.
#
# Output is one ANSI-coloured line per pane, starting with the pane id.

const LABEL_MIN = 18
const LABEL_MAX = 24
const STATE_MIN = 14

# Workspaces cycle through these so rows belonging together read as a block, and
# so two workspaces sharing a label (herdr defaults it to the directory name) stay
# tellable apart. Deliberately not the state colours' saturated variants.
const GROUP_COLORS = [light_blue light_magenta light_cyan light_green light_yellow light_purple]

# rank drives sort order, colour marks the group boundaries.
def attention [status: string]: nothing -> record {
    match $status {
        "blocked" => {rank: 0, color: "light_red_bold"}
        "done" => {rank: 1, color: "green"}
        "idle" => {rank: 2, color: "yellow"}
        "working" => {rank: 3, color: "cyan"}
        _ => {rank: 4, color: "magenta"}
    }
}

# A shell titles itself "<command line> <abbreviated cwd>" while something runs
# and just "<abbreviated cwd>" when idle, so the trailing path-looking token is
# the cwd and anything before it is the command. A title with no path token at all
# is a TUI naming itself, which is also something running.
def foreground []: string -> any {
    let words = ($in | split row " " | where {|it| $it != ""})
    if ($words | is-empty) {
        null
    } else if ($words | length) == 1 and (($words | first) =~ '^[~/]') {
        null
    } else {
        $words | first
    }
}

# Pads to width, or truncates with an ellipsis so a clipped label reads as clipped
# rather than as a different workspace. `fill` only pads, hence the explicit clip.
def clip [width: int]: string -> string {
    if ($in | str length) > $width {
        ($in | str substring 0..<($width - 1)) + "…"
    } else {
        $in | fill --alignment left --width $width
    }
}

def paint [color: string]: string -> string {
    $"(ansi $color)($in)(ansi reset)"
}

def main [] {
    let snapshot = (herdr api snapshot | from json | get result.snapshot)

    # Outside a managed pane neither variable is set, so fall back to whatever the
    # server currently reports as focused.
    let from_env = [$env.HERDR_ACTIVE_PANE_ID? $env.HERDR_PANE_ID?] | compact
    let exclude = if ($from_env | is-empty) { [$snapshot.focused_pane_id] } else { $from_env }

    let workspaces = (
        $snapshot.workspaces
        | select workspace_id label number
        | rename workspace_id label wsnum
    )

    let rows = (
        $snapshot.panes
        | where {|pane| $pane.pane_id not-in $exclude }
        | each {|pane|
            let title = ($pane.terminal_title_stripped? | default $pane.terminal_title? | default "" | str trim)
            let fg = ($title | foreground)
            let agent = ($pane.agent? | default "")
            let att = if $agent != "" {
                attention ($pane.agent_status? | default "unknown")
            } else if $fg != null {
                {rank: 5, color: "blue"}
            } else {
                {rank: 6, color: "light_gray"}
            }
            let workspace = ($workspaces | where workspace_id == $pane.workspace_id | first)

            {
                pane_id: $pane.pane_id
                rank: $att.rank
                color: $att.color
                wsnum: ($workspace.wsnum? | default 999)
                label: ($workspace.label? | default $pane.workspace_id)
                state: (if $agent != "" { $"($agent) ($pane.agent_status? | default 'unknown')" } else { $fg | default "shell" })
                title: $title
            }
        }
        | sort-by rank wsnum pane_id
    )

    if ($rows | is-empty) { return }

    # Group labels so every pane of a workspace carries the same colour, keyed on
    # the workspace number rather than the label, which is not unique.
    let group_color = (
        $rows
        | get wsnum
        | uniq
        | enumerate
        | reduce --fold {} {|it, acc|
            $acc | insert $"($it.item)" ($GROUP_COLORS | get ($it.index mod ($GROUP_COLORS | length)))
        }
    )

    # Columns size to the widest value actually present, then clamp: the minimum
    # keeps a list of short labels from collapsing into a cramped strip, the
    # maximum keeps one very long workspace name from pushing titles off-screen.
    let label_width = ([($rows | get label | each {|it| $it | str length} | math max) $LABEL_MIN] | math max | [$in $LABEL_MAX] | math min)
    let state_width = ([($rows | get state | each {|it| $it | str length} | math max) $STATE_MIN] | math max)
    let id_width = ($rows | get pane_id | each {|it| $it | str length} | math max)

    # Upstream channels separate fields with two or three spaces rather than a
    # single one (see opencode-sessions, tmux-windows, gh-prs); the same gap reads
    # much better here than the tight single space.
    $rows | each {|row|
        [
            ($row.pane_id | clip $id_width | paint "light_gray")
            ($row.label | clip $label_width | paint ($group_color | get $"($row.wsnum)"))
            ($row.state | clip $state_width | paint $row.color)
            $row.title
        ] | str join "  "
    } | to text
}
