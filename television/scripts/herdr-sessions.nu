#!/usr/bin/env -S nu -n --no-std-lib

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
# The pane the picker was launched from sorts last: focusing it is a no-op, but
# it stays findable. Popup commands get HERDR_ACTIVE_PANE_ID (the tiled pane
# underneath the popup); a picker run directly in a pane gets HERDR_PANE_ID.
#
# The scope argument narrows the list the way herdr-bar's tab-cycled filters do;
# the channel lists one source per scope so Tab steps through them. Widths and
# workspace colours are computed over every pane before narrowing, so a row keeps
# its colour and columns stay put while cycling.
#
# Output is one ANSI-coloured line per pane, starting with the pane id.

const LABEL_MIN = 18
const LABEL_MAX = 24
const STATE_MIN = 14

# Workspaces cycle through these so rows belonging together read as a block, and
# so two workspaces sharing a label (herdr defaults it to the directory name) stay
# tellable apart. Kept clear of the status colours (cyan, green, red, amber) so a
# label never reads as a state; the hex values are Catppuccin lavender, pink
# and peach.
const GROUP_COLORS = [light_blue light_magenta light_yellow "#b4befe" "#f5c2e7" "#fab387"]

# rank drives sort order. Glyphs and colours are herdr-bar's, which in turn
# mirror Herdr's own sidebar, so the picker reads the same as the sidebar --
# except idle: tv renders anything above U+0700 outside the ranges it trusts
# (U+2000-U+25FF, Nerd Font, emoji) as ␀, which takes Herdr's ✓ (U+2713), so
# √ stands in for it.
def attention [status: string]: nothing -> record {
    match $status {
        "blocked" => {rank: 0, glyph: "◉", color: "light_red_bold"}
        "done" => {rank: 1, glyph: "●", color: "light_cyan"}
        "idle" => {rank: 2, glyph: "√", color: "light_green"}
        "working" => {rank: 3, glyph: "◐", color: "#c78a1f"}
        _ => {rank: 4, glyph: "○", color: "dark_gray"}
    }
}

# Vendor colours from herdr-bar, so a mixed team of agents scans by colour.
const AGENT_COLORS = {
    claude: "#D97757"
    codex: "#10A37F"
    gemini: "#4285F4"
    cursor: "#A78BFA"
    opencode: "#38BDF8"
    kimi: "#9B8AFB"
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

# A row's name followed by dimmed context, with the context dropped when the
# name already contains it. Agents lead with the tab name, since that is what
# the work was named, and trail the agent's own summary. Other panes lead with
# their terminal title and trail the tab name, so a shell split into an agent's
# tab does not pass itself off as the agent.
def heading [name: string, context: string]: nothing -> string {
    if $name == "" {
        $context
    } else if $context == "" or ($name | str lowercase | str contains ($context | str lowercase)) {
        $name
    } else {
        $"($name)  (ansi dark_gray)($context)(ansi reset)"
    }
}

# Glyph and status in the attention colour, the agent in its vendor colour.
# State text is never wider than the column, which sizes to the widest row, so
# padding the plain text length is enough and nothing needs clipping.
def state-cell [row: record, width: int]: nothing -> string {
    let pad = ("" | fill --width ($width - ($row.state | str length)))
    let agent = if $row.agent == "" {
        ""
    } else {
        ($row.agent | paint ($AGENT_COLORS | get -o $row.agent | default "default")) + " "
    }
    $"($row.glyph | paint $row.color) ($agent)($row.status | paint $row.color)($pad)"
}

def paint [color: string]: string -> string {
    $"(ansi $color)($in)(ansi reset)"
}

def in-scope [scope: string, rank: int]: nothing -> bool {
    match $scope {
        "agents" => ($rank <= 4)
        "commands" => ($rank == 5)
        "shells" => ($rank == 6)
        "attention" => ($rank <= 1)
        _ => true
    }
}

# Typed sigils, after herdr-bar's: a row carries the sigil of every scope it
# belongs to, so typing one first narrows the list by fuzzy match alone. tv's
# query syntax reserves `!` and a trailing `$`, so herdr-bar's `$ shells` and
# `! needs you` become `#` and `?` here.
def sigils [rank: int]: nothing -> string {
    if $rank <= 1 { "@?" } else if $rank <= 4 { "@" } else if $rank == 5 { "%" } else { "#" }
}

# scope: all, agents, commands (panes running something else), shells, or
# attention (blocked and done agents).
def main [scope: string = "all"] {
    let snapshot = (herdr api snapshot | from json | get result.snapshot)

    # Outside a managed pane neither variable is set, so fall back to whatever the
    # server currently reports as focused.
    let from_env = [$env.HERDR_ACTIVE_PANE_ID? $env.HERDR_PANE_ID?] | compact
    let current = if ($from_env | is-empty) { [$snapshot.focused_pane_id] } else { $from_env }

    let workspaces = (
        $snapshot.workspaces
        | select workspace_id label number
        | rename workspace_id label wsnum
    )

    let tab_labels = (
        $snapshot.tabs
        | reduce --fold {} {|tab, acc| $acc | insert $tab.tab_id ($tab.label? | default "" | str trim) }
    )

    let rows = (
        $snapshot.panes
        | each {|pane|
            let title = ($pane.terminal_title_stripped? | default $pane.terminal_title? | default "" | str trim)
            let fg = ($title | foreground)
            let agent = ($pane.agent? | default "")
            let status = ($pane.agent_status? | default "unknown")
            let att = if $agent != "" {
                attention $status
            } else if $fg != null {
                {rank: 5, glyph: "▸", color: "blue"}
            } else {
                {rank: 6, glyph: "·", color: "light_gray"}
            }
            let workspace = ($workspaces | where workspace_id == $pane.workspace_id | first)

            {
                pane_id: $pane.pane_id
                current: ($pane.pane_id in $current)
                rank: $att.rank
                color: $att.color
                glyph: $att.glyph
                agent: $agent
                status: (if $agent != "" { $status } else { $fg | default "shell" })
                wsnum: ($workspace.wsnum? | default 999)
                label: ($workspace.label? | default $pane.workspace_id)
                state: ([$att.glyph $agent (if $agent != "" { $status } else { $fg | default "shell" })] | where {|it| $it != "" } | str join " ")
                title: (if $agent != "" {
                    heading ($tab_labels | get -o $pane.tab_id | default "") ($pane.label? | default $title | str trim)
                } else {
                    let cwd = ($pane.foreground_cwd? | default $pane.cwd? | default "" | str replace $env.HOME "~")
                    heading (if $title != "" { $title } else { $cwd }) ($tab_labels | get -o $pane.tab_id | default "")
                })
            }
        }
        | sort-by current rank wsnum pane_id
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
    let shown = ($rows | where {|row| in-scope $scope $row.rank })

    # An empty source makes tv list its own "Command produced no output" line
    # and preview it as a pane called "Command". A single blank line counts as
    # output, so the list stays visibly empty; the blank entry is not a pane id,
    # which the preview and focus scripts both check before acting.
    if ($shown | is-empty) {
        return ""
    }

    $shown | each {|row|
        [
            ($row.pane_id | clip $id_width | paint "dark_gray")
            (sigils $row.rank | clip 2 | paint "dark_gray")
            ($row.label | clip $label_width | paint ($group_color | get $"($row.wsnum)"))
            (state-cell $row $state_width)
            $row.title
        ] | str join "  "
    } | to text
}
