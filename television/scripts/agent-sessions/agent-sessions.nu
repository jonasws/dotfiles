#!/usr/bin/env -S nu -n --no-std-lib

# Agent sessions across every repository and harness, for the `agent-sessions`
# television channel, a Raycast script command, or anything else that wants
# them as JSON. Sessions come from the adapters in ./adapters (see README.md);
# tuios says which of them run in a pane right now.
#
#   agent-sessions.nu list [scope] [--json]   scope: all | live | here | <harness>
#   agent-sessions.nu info <key> [--json]
#   agent-sessions.nu find [words...] [--json]  the newest session matching every word
#   agent-sessions.nu get <key> <field>       id | cwd | transcript | resume | pane | key | title
#   agent-sessions.nu copy <key> <field>      the same, onto the clipboard
#   agent-sessions.nu preview <key> [mode]    chat | pane | reply | activity
#   agent-sessions.nu open <key> [--fork] [--dry-run]
#
# A key is `<harness>:<session id>`, such as claude-code:e638e16e-…. Harness
# ids are tuios's, so a key matches a pane's harness_id and agent_session_id.

const ADAPTERS = path self ./adapters
const SCRIPTS = path self ..

const HARNESS_COLORS = {
    claude-code: "#D97757"
    codex: "#10A37F"
    gemini-cli: "#4285F4"
    cursor-agent: "#A78BFA"
    opencode: "#38BDF8"
    pi: "#9B8AFB"
}
const SHORT = {claude-code: "claude", gemini-cli: "gemini", cursor-agent: "cursor"}

def paint [color: string]: string -> string { $"(ansi $color)($in)(ansi reset)" }

def clip [width: int]: string -> string {
    let s = ($in | str replace --all --regex '\s+' ' ')
    if ($s | str length) > $width {
        ($s | str substring 0..<($width - 1)) + "…"
    } else {
        $s | fill --alignment left --width $width
    }
}

def tilde []: string -> string { str replace --regex $"^($env.HOME | str replace --all '/' '\/')" "~" }

def short [harness: string]: nothing -> string { $SHORT | get -o $harness | default $harness }

def ms-to-date []: any -> any { if $in == null { null } else { $in * 1_000_000 | into datetime } }

def stamp []: any -> string {
    if $in == null { "?" } else { $in | ms-to-date | format date "%Y-%m-%d %H:%M" }
}

def humanize []: any -> string {
    if $in == null { "?" } else {
        let d = ($in | ms-to-date)
        if ((date now) - $d) < 1min { "just now" } else { $d | date humanize }
    }
}

# --- adapters --------------------------------------------------------------

def adapters []: nothing -> list<record> {
    ls $ADAPTERS | where type == file | get name
    | where {|p| not ($p | path basename | str starts-with ".") }
    | each {|p| {harness: ($p | path parse | get stem), path: $p} }
}

def adapter [harness: string]: nothing -> string {
    let hit = (adapters | where harness == $harness)
    if ($hit | is-empty) { error make {msg: $"no adapter for harness ($harness)"} }
    $hit.0.path
}

def ndjson []: string -> list<record> {
    lines | where {|l| $l starts-with "{" } | each {|l| $l | from json }
}

def parse-key [key: string]: nothing -> record {
    let k = ($key | str trim)
    let i = ($k | str index-of ":")
    if $i < 1 { error make {msg: $"not a session key: ($key)"} }
    {harness: ($k | str substring 0..<$i), id: ($k | str substring ($i + 1)..)}
}

# Panes by conversation id, from tuios. Empty when tuios is missing or not
# running.
#
# `list-agents --all` lists every window, and a pane keeps the conversation
# id its agent reported after that agent exits. Such a pane is dormant: a
# shell (or a pane a daemon restart brought back) that `tuios resume-agent`
# can bring the conversation back in, with the flags it was started with.
# Its harness_id is empty then, so panes are keyed by the id alone; a
# conversation id is a UUID, unique across harnesses.
def live []: nothing -> record {
    if (in-herdr) { return (herdr-live) }
    if (which tuios | is-empty) { return {} }
    let r = (do -i { ^tuios list-agents --all-sessions --all --json } | complete)
    if $r.exit_code != 0 { return {} }
    $r.stdout | from json | get -o agents | default []
    | where {|a| ($a.agent_session_id? | default "") != "" }
    | reduce --fold {} {|a, acc|
        let dormant = (($a.harness_id? | default "") == "" or $a.state == "none")
        let pane = {
            session: $a.session
            window_id: $a.window_id
            token: $"($a.session)/($a.window_id | str substring 0..<8)"
            name: ($a.name? | default "")
            state: (if $dormant { "dormant" } else { $a.state })
            dormant: $dormant
            needs_you: (not $dormant and ($a.needs_you or $a.state == "needs_input"))
            finished_unread: (not $dormant and $a.finished_unread)
            now: ($a.meta?.now? | default "")
        }
        # A running pane wins over a dormant one holding the same conversation.
        let have = ($acc | get -o $a.agent_session_id)
        if $have == null or ($have.dormant and not $dormant) {
            $acc | upsert $a.agent_session_id $pane
        } else { $acc }
    }
}

# Agent panes by conversation id, from herdr. herdr reports the id its
# integration (or a harness hook) gave it as agent_session.value.
def herdr-live []: nothing -> record {
    let r = (do -i { ^herdr agent list } | complete)
    if $r.exit_code != 0 { return {} }
    $r.stdout | from json | get -o result.agents | default []
    | where {|a| ($a.agent_session?.value? | default "") != "" }
    | reduce --fold {} {|a, acc|
        $acc | upsert $a.agent_session.value {
            herdr: true
            session: $a.workspace_id
            window_id: $a.pane_id
            token: $a.pane_id
            name: ($a.name? | default "")
            state: $a.agent_status
            dormant: false
            needs_you: ($a.agent_status == "blocked")
            finished_unread: false
            now: ""
        }
    }
}

def with-live [panes: record]: record -> record {
    let s = $in
    $s | insert key $"($s.harness):($s.id)" | insert pane ($panes | get -o $s.id)
}

def sessions []: nothing -> list<record> {
    let panes = (live)
    adapters
    | par-each {|a|
        let r = (do -i { ^$a.path list } | complete)
        if $r.exit_code != 0 { [] } else { $r.stdout | ndjson }
    }
    | flatten
    | each {|s| $s | with-live $panes }
    | sort-by -r updated
}

def lookup [key: string]: nothing -> record {
    let k = (parse-key $key)
    let r = (do -i { ^(adapter $k.harness) info $k.id } | complete)
    if $r.exit_code != 0 { error make {msg: $"no session ($key)"} }
    $r.stdout | from json | with-live (live)
}

def messages [s: record]: nothing -> list<record> {
    let r = (do -i { ^(adapter $s.harness) messages $s.id } | complete)
    if $r.exit_code != 0 { [] } else { $r.stdout | ndjson }
}

# --- list ------------------------------------------------------------------

# The main checkout and every worktree of the repository the picker runs in.
def here-roots []: nothing -> list<string> {
    let r = (do -i { ^git worktree list --porcelain } | complete)
    if $r.exit_code != 0 { return [($env.PWD | str lowercase)] }
    $r.stdout | lines | where {|l| $l starts-with "worktree " }
    | each {|l| $l | str substring 9.. | str lowercase }
}

def in-scope [scope: string]: list<record> -> list<record> {
    match $scope {
        "all" => $in
        "live" => ($in | where pane != null)
        "here" => {
            let roots = (here-roots)
            $in | where {|s|
                let c = ($s.cwd | str lowercase)
                $roots | any {|r| $c == $r or ($c | str starts-with $"($r)/") }
            }
        }
        _ => ($in | where harness == $scope)
    }
}

def glyph [pane: any]: nothing -> string {
    if $pane == null { return ("·" | paint "dark_gray") }
    if $pane.dormant { return ("○" | paint "light_blue") }
    if $pane.state == "errored" { return ("×" | paint "light_red_bold") }
    if $pane.needs_you { return ("◉" | paint "light_red_bold") }
    if $pane.finished_unread { return ("●" | paint "light_cyan") }
    if $pane.state == "working" { return ("◐" | paint "#c78a1f") }
    "√" | paint "light_green"
}

# The repository a session belongs to: a worktree under `<...>/worktrees/<repo>/`
# or `<repo>/.claude/worktrees/` names its repository, anything else its folder.
def repo-name [cwd: string]: nothing -> string {
    let parts = ($cwd | path split)
    let wt = ($parts | enumerate | where {|p| $p.item in ["worktrees" ".worktrees"] } | last | default null)
    if $wt == null { return ($cwd | path basename) }
    let before = ($parts | get -o ($wt.index - 1) | default "")
    if $before in [".claude" ".git"] { $parts | get -o ($wt.index - 2) | default ($cwd | path basename) } else {
        $parts | get -o ($wt.index + 1) | default ($cwd | path basename)
    }
}

def row [s: record]: nothing -> string {
    let color = ($HARNESS_COLORS | get -o $s.harness | default "default")
    let branch = if $s.branch in ["" "main" "master" "HEAD"] { "" } else { $" ($s.branch)" | paint "magenta" }
    let where_ = if $s.pane == null { "" } else { $"  ($s.pane.token)" | paint "light_blue" }
    [
        (glyph $s.pane)
        ($s.updated | humanize | clip 15 | paint "yellow")
        (short $s.harness | clip 6 | paint $color)
        (repo-name $s.cwd | clip 24 | paint "cyan")
        (($s.title | clip 64) + $branch + $where_)
        ($s.key | paint "dark_gray")
    ] | str join " "
}

# --- preview ---------------------------------------------------------------

def header [s: record]: nothing -> list<string> {
    let k = {|label| $label | fill --width 9 | paint "dark_gray" }
    let size = if ($s.size? | default null) == null { "" } else { $" \(($s.size | into filesize))" | paint "dark_gray" }
    [
        ($s.title | paint "white_bold")
        $"(do $k 'harness')(short $s.harness | paint ($HARNESS_COLORS | get -o $s.harness | default 'default'))"
        (if $s.pane != null {
            let p = $s.pane
            $"(do $k 'pane')(glyph $p) ($p.state) in ($p.token | paint 'light_blue')(if $p.name != '' { $'  "($p.name)"' } else { '' })"
        } else { $"(do $k 'pane')(('not open' | paint 'dark_gray'))" })
        $"(do $k 'dir')($s.cwd | tilde)(if $s.branch != '' { ' on ' + ($s.branch | paint 'magenta') } else { '' })(if not ($s.cwd | path exists) { ' (gone)' | paint 'light_red' } else { '' })"
        $"(do $k 'started')($s.created | stamp)   ('last' | paint 'dark_gray') ($s.updated | stamp) \(($s.updated | humanize)\)"
        $"(do $k 'file')($s.transcript | tilde)($size)"
        $"(do $k 'key')($s.key | paint 'dark_gray')"
    ]
}

def turn [m: record]: nothing -> string {
    let who = if $m.role == "user" { "❯ you" | paint "magenta_bold" } else { "● agent" | paint "cyan_bold" }
    let tools = ($m.tools? | default [] | each {|t| $"→ ($t.name) ($t.hint)" | paint "dark_gray" })
    [$who] ++ (if $m.text != "" { [$m.text] } else { [] }) ++ $tools | str join "\n"
}

# Consecutive agent turns merge, so a run of tool calls reads as one turn.
def merge-turns []: list<record> -> list<record> {
    reduce --fold [] {|m, acc|
        let last = ($acc | last | default null)
        if $last != null and $last.role == "assistant" and $m.role == "assistant" {
            let text = ([$last.text $m.text] | where {|t| $t != "" } | str join "\n\n")
            $acc | drop | append ($last | merge {text: $text, tools: ($last.tools ++ ($m.tools? | default []))})
        } else {
            $acc | append ($m | upsert tools ($m.tools? | default []))
        }
    }
}

def chat [s: record, keep: int = 10]: nothing -> string {
    let turns = (messages $s | merge-turns)
    let body = if ($turns | length) > ($keep + 1) {
        let skipped = ($"… (($turns | length) - $keep - 1) earlier turns …" | paint "dark_gray")
        [(turn ($turns | first)) $skipped] ++ ($turns | last $keep | each {|m| turn $m })
    } else { $turns | each {|m| turn $m } }
    $body | str join "\n\n"
}

def markdown []: string -> string {
    let text = $in
    let cols = ($env.FZF_PREVIEW_COLUMNS? | default ($env.COLUMNS? | default "100") | into int)
    if (which glow | is-not-empty) {
        $text | ^glow --style dark --width ([($cols - 2) 40] | math max) - | complete | get stdout
    } else if (which bat | is-not-empty) {
        $text | ^bat --language md --color always --style plain | complete | get stdout
    } else { $text }
}

def reply [s: record]: nothing -> string {
    let last = (messages $s | where role == "assistant" and text != "" | last | default null)
    let recap = if $s.pane != null {
        do -i { ^tuios agent-log -s $s.pane.session -w $s.pane.window_id --recap } | complete | get stdout | str trim
    } else { "" }
    [
        (if $recap != "" { ("recap" | paint "dark_gray") + "\n" + $recap + "\n" } else { "" })
        (if $last == null { "No reply yet" | paint "dark_gray" } else {
            $"("last reply" | paint 'dark_gray') ($last.at? | default '' | if $in == '' { '' } else { $in | into datetime | date humanize })\n" + ($last.text | markdown)
        })
    ] | where {|x| $x != "" } | str join "\n"
}

def activity [s: record]: nothing -> string {
    let ms = (messages $s)
    let tools = ($ms | get -o tools | default [] | flatten | where {|t| $t != null })
    let by_tool = ($tools | group-by name | items {|k, v| {tool: $k, n: ($v | length)} } | sort-by -r n)
    let files = ($tools | where {|t| ($t.file? | default "") != "" } | group-by file
        | items {|f, v| {file: $f, edits: ($v | where {|t| ($t.name | str lowercase) in [edit write multiedit notebookedit] } | length), reads: ($v | where {|t| ($t.name | str lowercase) == read } | length)} }
        | sort-by -r edits reads)
    let width = ($by_tool | get -o n | default [] | append 1 | math max)
    let bars = ($by_tool | first 12 | each {|t|
        let n = ([((($t.n * 30) / $width) | math ceil) 1] | math max)
        $"($t.tool | str replace 'mcp__' '' | clip 20) ('' | fill --character '▇' --width $n | paint 'cyan') ($t.n)"
    })
    let user_turns = ($ms | where role == "user" and text != "" | length)
    let pane_log = if $s.pane != null {
        let r = (do -i { ^tuios agent-log -s $s.pane.session -w $s.pane.window_id --limit 12 } | complete)
        if $r.exit_code == 0 and ($r.stdout | str trim) != "" { $"\n('pane activity' | paint 'dark_gray')\n($r.stdout | str trim)" } else { "" }
    } else { "" }
    [
        $"($user_turns) prompts · ($tools | length) tool calls · ($files | where edits > 0 | length) files edited"
        ""
        ("tools" | paint "dark_gray")
        ...$bars
        ""
        ("files" | paint "dark_gray")
        ...($files | first 20 | each {|f|
            let mark = if $f.edits > 0 { $"✎($f.edits)" | paint "yellow" } else { $"r($f.reads)" | paint "dark_gray" }
            $"($mark | fill --width 4) ($f.file | str replace ($s.cwd + '/') '' | tilde)"
        })
        $pane_log
    ] | str join "\n"
}

def pane-screen [s: record]: nothing -> string {
    if $s.pane == null {
        ("Not open in any pane. Enter resumes it." | paint "dark_gray") + "\n\n" + (chat $s 6)
    } else {
        # --trim only drops rows below the cursor. A TUI agent parks the
        # cursor in its prompt box and paints blank or space-filled rows
        # under it, so drop every trailing row that has no visible text.
        let rows = (do -i { ^tuios capture-pane -s $s.pane.session -w $s.pane.window_id --ansi --trim } | complete | get stdout | lines)
        let keep = ($rows | enumerate | where {|r| ($r.item | ansi strip | str trim) != "" } | last | default null)
        if $keep == null { "" } else { $rows | first ($keep.index + 1) | str join "\n" }
    }
}

# --- fields ----------------------------------------------------------------

def field [s: record, name: string]: nothing -> string {
    match $name {
        "id" => $s.id
        "key" => $s.key
        "cwd" => $s.cwd
        "title" => $s.title
        "transcript" => $s.transcript
        "resume" => ([cd $s.cwd "&&"] ++ $s.resume | each {|a| if $a == "&&" { $a } else { $a | sh-quote } } | str join " ")
        "pane" => {
            if $s.pane == null { error make {msg: "not open in a tuios pane"} }
            let p = $s.pane
            $"tuios pane ($p.window_id) \(session ($p.session), token ($p.token)(if $p.name != '' { $', named "($p.name)"' } else { '' })\)"
        }
        _ => (error make {msg: $"unknown field ($name)"})
    }
}

def sh-quote []: string -> string {
    if ($in =~ '^[A-Za-z0-9_./:@%+=-]+$') { $in } else { "'" + ($in | str replace --all "'" "'\\''") + "'" }
}

# An OSC 9 notification on the terminal: tuios shows it as a toast, Ghostty
# outside tuios as a desktop notification. Without a terminal it goes to stderr.
def toast [text: string] {
    let osc = $"\e]9;($text | str replace --all --regex '[\x00-\x1f]' ' ')\a"
    try { $osc | save --raw --append /dev/tty } catch { print --stderr $text }
}

# --- open ------------------------------------------------------------------

# Where a session's checkout is, and how to bring it back when it was removed:
# as a worktree of its branch, in the nearest existing ancestor that is a
# repository, or in the main checkout a `<...>/worktrees/<repo>/<slug>` path
# was made from.
def cwd-plan [s: record]: nothing -> record {
    if ($s.cwd | path exists) { return {dir: $s.cwd, restore: null} }
    if $s.branch in ["" "HEAD"] { error make {msg: $"($s.cwd | tilde) is gone and the session has no branch to restore it from"} }
    let parts = ($s.cwd | path split)
    let ancestors = (1..<($parts | length) | each {|n| $parts | first $n | path join } | reverse)
    let from_ancestor = ($ancestors
        | where {|d| ($d | path exists) and (do -i { ^git -C $d rev-parse --show-toplevel } | complete | get exit_code) == 0 }
        | first | default null)
    let repo = if $from_ancestor != null {
        do -i { ^git -C $from_ancestor rev-parse --show-toplevel } | complete | get stdout | str trim
    } else {
        let name = (repo-name $s.cwd)
        [~/CX ~/CNOPS ~/CN-TERMINAL ~ ~/src ~/code] | each {|r| $r | path expand | path join $name }
        | where {|d| ($d | path join .git | path exists) } | first | default null
    }
    if $repo == null { error make {msg: $"($s.cwd | tilde) is gone and no repository was found to restore it from"} }
    {dir: $s.cwd, restore: {repo: $repo, branch: $s.branch}}
}

def restore [plan: record] {
    if $plan.restore == null { return }
    let r = (^git -C $plan.restore.repo worktree add $plan.dir $plan.restore.branch | complete)
    if $r.exit_code != 0 {
        error make {msg: $"git worktree add ($plan.dir | tilde) ($plan.restore.branch) failed: ($r.stderr | str trim)"}
    }
    toast $"Restored worktree ($plan.dir | path basename) on ($plan.restore.branch)"
}

def git-root [dir: string]: nothing -> string {
    let top = (do -i { ^git -C $dir rev-parse --show-toplevel } | complete)
    if $top.exit_code == 0 { $top.stdout | str trim } else { $dir }
}

# The tuios session already open on a checkout, if any.
def session-on [root: string]: nothing -> any {
    ^tuios ls --json | from json
    | where {|x| ($x.worktree?.path? | default "" | str lowercase) == ($root | str lowercase) }
    | get -o 0.name
}

def focus [p: record] {
    if ($p.herdr? | default false) {
        ^($SCRIPTS | path join herdr-focus.sh) $p.window_id
        return
    }
    ^tuios focus-window -s $p.session $p.window_id | ignore
    if $p.session != ($env.TUIOS_SESSION? | default "") {
        ^tuios switch-session $p.session | ignore
    }
}

def in-tuios []: nothing -> bool {
    (($env.TUIOS_ENV? | default "") == "1" or ($env.AGENT_SESSIONS_TUIOS? | default "") == "1") and (which tuios | is-not-empty)
}

# Focus the pane running the session; otherwise resume it in a new pane of the
# tuios session for its checkout (tuios-session.sh opens or creates that one,
# and names a worktree's session as tuios does), or in place outside tuios.
# Inside herdr and not tuios. tuios panes set HERDR_ENV too, since tuios
# answers herdr's API, so tuios is checked first.
def in-herdr []: nothing -> bool {
    ($env.HERDR_ENV? | default "") == "1" and not (in-tuios) and (which herdr | is-not-empty)
}

# The herdr workspace a pane of which sits in the checkout, if any.
def herdr-workspace-on [root: string]: nothing -> any {
    let r = (do -i { ^herdr pane list } | complete)
    if $r.exit_code != 0 { return null }
    let p = ($root | str lowercase)
    $r.stdout | from json | get -o result.panes | default []
    | where {|x| ([$x.cwd? $x.foreground_cwd?] | compact | each {|c| $c | str lowercase }) | any {|c| $c == $p } }
    | get -o 0.workspace_id
}

# A new tab in the checkout's workspace, or a new workspace, whose shell runs
# the resume command: the pane outlives the agent, as in tuios.
def herdr-open [dir: string, title: string, argv: list<string>] {
    let root = (git-root $dir)
    let ws = (herdr-workspace-on $root)
    let label = ($title | str substring 0..<40)
    let created = if $ws == null {
        ^herdr workspace create --cwd $dir --label ($root | path basename) --focus | from json
    } else {
        ^herdr tab create --workspace $ws --cwd $dir --label $label --focus | from json
    }
    let pane = ($created | get -o result.root_pane.pane_id)
    if $pane == null { error make {msg: $"herdr gave no pane for ($dir | tilde)"} }
    let workspace = ($ws | default ($created | get -o result.workspace.workspace_id))
    if $workspace != null { ^herdr workspace focus $workspace | ignore }
    ^herdr pane run $pane ($argv | each {|a| $a | sh-quote } | str join " ") | ignore
}

def open-session [s: record, fork: bool, dry: bool] {
    if $s.pane != null and not $fork {
        # A dormant pane gets its conversation back from tuios, which builds
        # the command from the harness manifest and the flags the agent was
        # started with, and types it into the pane's shell.
        if $dry {
            return ({action: (if $s.pane.dormant { "resume-agent" } else { "focus" })} | merge $s.pane | to json)
        }
        focus $s.pane
        if $s.pane.dormant {
            ^tuios resume-agent -s $s.pane.session -w $s.pane.window_id | ignore
        }
        return
    }
    let argv = if $fork { $s.fork? | default null } else { $s.resume }
    if $argv == null { error make {msg: $"($s.harness) cannot fork a session"} }
    let plan = (cwd-plan $s)
    let tuios = (in-tuios)
    let herdr = (in-herdr)
    if $dry {
        let root = if $plan.restore == null { git-root $plan.dir } else { $plan.dir }
        return ({
            action: (if $fork { "fork" } else { "resume" })
            via: (if $tuios { "tuios new-window + fish -C" } else if $herdr { "herdr tab + pane run" } else { "exec" })
            herdr_workspace: (if $herdr { herdr-workspace-on $root | default $"new workspace for ($root | tilde)" } else { null })
            cwd: $plan.dir
            restore_worktree: $plan.restore
            tuios_session: (if $tuios { session-on $root | default $"new session for ($root | tilde)" } else { null })
            argv: $argv
        } | to json)
    }
    restore $plan
    if $tuios {
        let root = (git-root $plan.dir)
        ^($SCRIPTS | path join tuios-session.sh) $root
        let session = (session-on $root | default ($root | path basename))
        let name = ($s.title | str substring 0..<40)
        # A shell that runs the resume command first: the pane outlives the
        # agent, shows why a resume failed, and the agent reports its own
        # conversation id through its hooks, which needs no grant over another
        # pane. new-window returns once the window exists, so the picker's
        # popup closes before the agent has started.
        let cmd = ($argv | each {|a| $a | sh-quote } | str join " ")
        ^tuios new-window $name -s $session --cwd $plan.dir -- fish -C $cmd | ignore
    } else if $herdr {
        herdr-open $plan.dir $s.title $argv
    } else {
        cd $plan.dir
        exec ($argv | first) ...($argv | skip 1)
    }
}

# --- commands --------------------------------------------------------------

def main [] {
    print "usage: agent-sessions.nu list [all|live|here|<harness>] [--json] | info <key> [--json] | get <key> <field> | copy <key> <field> | preview <key> [chat|pane|reply|activity] | open <key> [--fork] [--dry-run]"
}

# Sessions, newest first.
def "main list" [scope: string = "all", --json] {
    let rows = (sessions | in-scope $scope)
    if $json { return ($rows | to json) }
    if ($rows | is-empty) { return "" }
    $rows | each {|s| row $s } | to text
}

# One session with its live pane.
def "main info" [key: string, --json] {
    let s = (lookup $key)
    if $json { $s | to json } else { header $s | str join "\n" }
}

# The newest session whose title, repository, branch or directory holds every
# word, or the newest of all with no words. Prints its key.
def "main find" [...words: string, --json] {
    let ws = ($words | each {|w| $w | str lowercase })
    let hit = (sessions | where {|s|
        let hay = ([$s.title (repo-name $s.cwd) $s.branch $s.cwd] | str join " " | str lowercase)
        $ws | all {|w| $hay | str contains $w }
    } | first | default null)
    if $hit == null {
        print --stderr $"no session matches: ($words | str join ' ')"
        exit 1
    }
    if $json { $hit | to json } else { $hit.key }
}

def "main get" [key: string, name: string] { field (lookup $key) $name }

def "main copy" [key: string, name: string] {
    let s = (lookup $key)
    let text = (try { field $s $name } catch {|e| toast $e.msg; error make {msg: $e.msg} })
    $text | ^pbcopy
    toast $"Copied ($name): ($text | str substring 0..<60)"
}

def "main preview" [key: string, mode: string = "chat"] {
    let s = (try { lookup $key } catch { return "No sessions in this scope" })
    match $mode {
        "chat" => ((header $s) ++ ["" (chat $s)] | str join "\n")
        "pane" => (pane-screen $s)
        "reply" => ((header $s | first 4) ++ ["" (reply $s)] | str join "\n")
        "activity" => ((header $s | first 4) ++ ["" (activity $s)] | str join "\n")
        _ => (error make {msg: $"unknown preview mode ($mode)"})
    }
}

# Jump to the pane running the session, or resume it.
def "main open" [key: string, --fork, --dry-run] {
    try { open-session (lookup $key) $fork $dry_run } catch {|e| toast $e.msg; error make {msg: $e.msg} }
}
