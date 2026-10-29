#!/usr/bin/env -S nu -n --no-std-lib

# Emit one line per tuios pane, in every session, for the `tuios-sessions`
# television channel.
#
# Reads tuios directly (`list-windows --all`, `list-agents --all-sessions`,
# `list-attention`), not herdr's compat API. That keeps what herdr has no field
# for: the agent's own needs_you / finished_unread flags, the kind of thing it
# waits on (approval, question, plan), what it is doing right now, context use,
# subagents, queued prompts, unread mail and how long it has been in this state.
#
# Ordered as an attention queue. Television keeps this order until you type:
#   0 errored, 1 needs you, 2 finished and unseen   (longest waiting first)
#   3 working, 4 other agents                       (newest first)
#   5 panes running a command, 6 idle shells
# The pane the picker was opened from sorts last.
#
# Colour needs `ansi = true`, which rules out a `display` template, so the row
# begins with a token, `<session>/<window id prefix>` (the session in its own
# colour, the id dim), that the preview and focus scripts read back with
# `{strip_ansi|split: :0}`.

const SESSION_COLORS = [light_blue light_magenta light_yellow "#b4befe" "#f5c2e7" "#fab387"]
const AGENT_COLORS = {
    claude-code: "#D97757"
    codex: "#10A37F"
    gemini-cli: "#4285F4"
    cursor-agent: "#A78BFA"
    opencode: "#38BDF8"
    pi: "#9B8AFB"
}
const SHELLS = [fish bash zsh sh nu dash tcsh ksh login]

# tv draws characters above U+0700 as a placeholder, so the glyphs stay in the
# ranges it trusts.
def attention [rank: int]: nothing -> record {
    match $rank {
        0 => {glyph: "×", color: "light_red_bold"}
        1 => {glyph: "◉", color: "light_red_bold"}
        2 => {glyph: "●", color: "light_cyan"}
        3 => {glyph: "◐", color: "#c78a1f"}
        4 => {glyph: "√", color: "light_green"}
        5 => {glyph: "▸", color: "blue"}
        _ => {glyph: "·", color: "light_gray"}
    }
}

def paint [color: string]: string -> string { $"(ansi $color)($in)(ansi reset)" }

def clip [width: int]: string -> string {
    if ($in | str length) > $width {
        ($in | str substring 0..<($width - 1)) + "…"
    } else {
        $in | fill --alignment left --width $width
    }
}

def ago [ns: any]: nothing -> string {
    if $ns == null { return "" }
    let secs = ((date now | into int) - $ns) // 1_000_000_000
    if $secs < 90 { $"($secs)s" } else if $secs < 5400 { $"($secs // 60)m" } else if $secs < 129600 { $"($secs // 3600)h" } else { $"($secs // 86400)d" }
}

def in-scope [scope: string, rank: int]: nothing -> bool {
    match $scope {
        "agents" => ($rank <= 4)
        "needs" => ($rank <= 2)
        "working" => ($rank == 3)
        "panes" => ($rank == 5)
        "shells" => ($rank == 6)
        _ => true
    }
}

def sigils [rank: int]: nothing -> string {
    if $rank <= 2 { "@?" } else if $rank <= 4 { "@" } else if $rank == 5 { "%" } else { "#" }
}

def main [scope: string = "all"] {
    # The picker runs in a popup of its own, which is noise in its own list.
    let self = ($env.TUIOS_PANE_ID? | default "")
    let windows = (tuios list-windows --all --json | from json | get panes | where window_id != $self)
    let agents = (
        tuios list-agents --all-sessions --json | from json | get agents
        | reduce --fold {} {|a, acc| $acc | insert $a.window_id $a }
    )
    let waiting = (
        tuios list-attention --json | from json | get items
        | where {|it| ($it.window? | default "") != "" and $it.kind != "finished" }
        | reduce --fold {} {|it, acc| $acc | insert $it.window $it.kind }
    )

    let current = ($env.TUIOS_ACTIVE_PANE_ID? | default "")

    let rows = (
        $windows | each {|w|
            let a = ($agents | get -o $w.window_id)
            let folder = ($w.cwd? | default "" | path basename)
            let rank = if $a != null {
                if $a.state == "errored" { 0 } else if ($a.needs_you or $a.state == "needs_input") { 1 } else if $a.finished_unread { 2 } else if $a.state == "working" { 3 } else { 4 }
            } else if ($w.command? | default "" | path basename) in $SHELLS or ($w.command? | default "") == "" {
                6
            } else { 5 }
            let name = ($w.name? | default "" | str trim)
            let title = ($w.title? | default "" | str trim)
            let kind = ($waiting | get -o $w.window_id | default "")
            let meta = ($a.meta? | default {})
            let tags = (
                [
                    (if $kind != "" { $kind | paint "light_red" })
                    (if ($meta.ctx? | default "") != "" { $"($meta.ctx)%" | paint "dark_gray" })
                    (if ($a.subagents? | default 0) > 0 { $"⌥($a.subagents)" | paint "dark_gray" })
                    (if ($a.queued? | default 0) > 0 { $"↳($a.queued)" | paint "dark_gray" })
                    (if ($a.unread? | default 0) > 0 { $"✉($a.unread)" | paint "light_yellow" })
                    (if $a != null and $rank != 4 and $rank != 0 { ago $a.agent_state_at | paint "dark_gray" })
                ] | compact | str join " "
            )
            let activity = if $a != null and $a.state == "working" { $meta.now? | default "" } else { "" }
            let heading = if $a != null {
                if $name == "" { $folder } else { $name }
            } else if $title != "" { $title } else { $folder }
            {
                token: $"($w.session)/($w.window_id | str substring 0..<8)"
                session: $w.session
                current: ($w.window_id == $current)
                rank: $rank
                since: ($a.agent_state_at? | default 0)
                heading: $heading
                folder: (if $a != null { $folder } else { ($w.command? | default "") })
                harness: ($a.harness_id? | default "")
                state: ($a.state? | default "")
                tags: $tags
                activity: ($activity | str replace --all "\n" " " | str substring 0..<([($activity | str length) 48] | math min))
            }
        }
        | sort-by current rank since
    )

    let shown = ($rows | where {|r| in-scope $scope $r.rank })
    if ($shown | is-empty) { return "" }

    let sessions = ($rows | get session | uniq)
    let token_w = ($rows | get token | each {|t| $t | str length } | math max)
    let state_w = ($rows | each {|r| ($"x ($r.harness | str replace 'claude-code' 'claude') ($r.state)" | str trim | str length) } | math max)

    $shown | each {|r|
        let att = (attention $r.rank)
        let agent = if $r.harness == "" { "" } else {
            ($r.harness | str replace "claude-code" "claude" | paint ($AGENT_COLORS | get -o $r.harness | default "default")) + " "
        }
        let status = if $r.state == "" { "" } else { $r.state }
        let plain = ([$att.glyph ($r.harness | str replace "claude-code" "claude") $status] | where {|x| $x != "" } | str join " ")
        let pad = ("" | fill --width ([($state_w - ($plain | str length)) 0] | math max))
        let state_cell = $"($att.glyph | paint $att.color) ($agent)($status | paint $att.color)($pad)"
        let session_color = ($SESSION_COLORS | get (($sessions | enumerate | where item == $r.session | first | get index) mod ($SESSION_COLORS | length)))
        [
            (($r.session | paint $session_color) + ($"/($r.token | split row '/' | last)" | clip ($token_w - ($r.session | str length)) | paint "dark_gray"))
            (sigils $r.rank | clip 2 | paint "dark_gray")
            $state_cell
            ($r.heading | str replace --all "\n" " ")
            (if $r.folder != "" { $r.folder | paint "dark_gray" } else { "" })
            (if $r.activity != "" { $r.activity | paint "#c78a1f" } else { "" })
            $r.tags
        ] | where {|x| $x != "" } | str join "  "
    } | to text
}
