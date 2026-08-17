#!/usr/bin/env nu

# Emit the entries of the `herdr-sessions` television channel: every Herdr pane
# first, then every git repository that has no pane open on it.
#
# Panes come ordered as an attention queue: blocked first, then done (finished
# but unseen), then idle, working, unclassified agents, then panes running some
# other command, and finally idle shells. Repos follow, zoxide-frecency first.
# Television preserves this order until you start typing.
#
# The two halves answer the same question -- "take me to the thing I want to work
# in" -- and differ only in whether that thing is already running. So a repo the
# panes above already cover is dropped: its workspace exists, and the pane rows
# are the richer way to reach it.
#
# Colour requires `ansi = true`, which the channel spec lists as incompatible with
# a `display` template, so the whole line renders and the key of the row has to
# survive as visible text: the pane id for a pane, the path for a repo. It leads
# the row and is recovered with `{strip_ansi|split: :0}`, which is also what tells
# the two kinds apart downstream -- a key starting with `~` is a repo. Deriving
# the key from the rest of the row instead is not an option -- two shells split
# inside one workspace render an identical label/state/title row.
#
# The pane the picker was launched from is omitted, since focusing it is a no-op.
# Popup commands get HERDR_ACTIVE_PANE_ID (the tiled pane underneath the popup);
# a picker run directly in a pane gets HERDR_PANE_ID instead.
#
# Output is one ANSI-coloured line per entry, starting with that entry's key.

const LABEL_MIN = 18
const LABEL_MAX = 24
const STATE_MIN = 14
const REPO_MAX = 60

const REPO_SOURCE = "~/.config/television/scripts/git-repos.sh"

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

# `~` rather than the absolute path: the key column is the widest thing in the
# repo block, and every path in it starts with the same 15 characters otherwise.
def tildify []: string -> string {
    let path = $in
    let home = ($nu.home-dir | str trim --right --char "/")
    if ($path | str starts-with $"($home)/") {
        $"~($path | str substring ($home | str length)..)"
    } else {
        $path
    }
}

# Repos that have no workspace on them yet.
#
# "Has a workspace" is asked two ways, because herdr tracks no cwd per workspace
# -- only per pane, and a pane's cwd is wherever it was last `cd`ed to. So a pane
# sitting in the repo (root or below) counts, and so does a workspace *labelled*
# after the repo, which is how herdr-workspace.sh names the ones it opens. The
# label test alone would be too eager: two repos can share a basename, and only
# one of them is the one that is open, so it is skipped for those.
#
# A path containing a space is skipped entirely: the channel recovers the key as
# the row's first space-separated field, so such a path would come back truncated
# and the jump would land nowhere.
def repos [open_cwds: list<string>, open_labels: list<string>]: nothing -> list<string> {
    let candidates = (
        ^($REPO_SOURCE | path expand)
        | lines
        | where {|repo| $repo != "" and not ($repo | str contains " ") }
    )
    let ambiguous = ($candidates | each {|repo| $repo | path basename} | uniq --repeated)

    $candidates | where {|repo|
        let base = ($repo | path basename)
        not (
            ($open_cwds | any {|cwd| $cwd == $repo or ($cwd | str starts-with $"($repo)/") }) or
            ($base in $open_labels and $base not-in $ambiguous)
        )
    }
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

    # A pane counts as covering its repo whether it sits in the repo root or in a
    # subdirectory of it, and whether that is the shell's cwd or the cwd of what
    # the shell is running.
    let open_cwds = (
        $snapshot.panes
        | each {|pane| [($pane.cwd? | default "") ($pane.foreground_cwd? | default "")] }
        | flatten
        | where {|cwd| $cwd != "" }
        | uniq
    )
    let open_labels = ($snapshot.workspaces | get label | uniq)
    let repo_paths = (repos ($open_cwds | each {|cwd| $cwd | path expand}) $open_labels)
    let repo_width = ([
        ($repo_paths | each {|repo| $repo | tildify | str length} | append 0 | math max)
        $REPO_MAX
    ] | math min)

    # `fill`, not `clip`: an over-long path may push its tag out of line, but it
    # must never be truncated -- it is the key the jump action is handed.
    let repo_lines = (
        $repo_paths | each {|repo|
            [
                ($repo | tildify | fill --alignment left --width $repo_width)
                ("repo" | paint "light_gray")
            ] | str join "  "
        }
    )

    if ($rows | is-empty) { return ($repo_lines | to text) }

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
    let pane_lines = (
        $rows | each {|row|
            [
                ($row.pane_id | clip $id_width | paint "light_gray")
                ($row.label | clip $label_width | paint ($group_color | get $"($row.wsnum)"))
                ($row.state | clip $state_width | paint $row.color)
                $row.title
            ] | str join "  "
        }
    )

    # Two blocks, each aligned to its own widths. Sharing one key column would
    # mean padding every pane id out to the width of the longest repo path.
    $pane_lines | append $repo_lines | to text
}
