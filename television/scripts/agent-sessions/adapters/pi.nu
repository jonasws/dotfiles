#!/usr/bin/env -S nu -n --no-std-lib

# agent-sessions adapter for pi (the pi-coding-agent). See ../README.md.
#
# Not yet run against real sessions: there were none on this machine when it
# was written. It reads the layout pi documents, one JSONL file per session
# under ~/.pi/agent/sessions/<encoded cwd>/, whose first line is a `session`
# header (id, timestamp, cwd) and whose `message` lines carry the turns. It
# lists nothing while that folder is missing, so it is safe to keep enabled.

def root []: nothing -> string {
    $env.AGENT_SESSIONS_PI_DIR? | default "~/.pi/agent/sessions" | path expand
}

def files []: nothing -> list<record> {
    let dir = (root)
    if not ($dir | path exists) { return [] }
    glob $"($dir)/**/*.jsonl" | each {|f| ls $f | first }
}

def entries [file: string]: nothing -> list<record> {
    open --raw $file | lines | where {|l| $l starts-with "{" } | each {|l| try { $l | from json } catch { null } } | compact
}

def text-of [content: any]: nothing -> string {
    if ($content | describe | str starts-with "string") { return $content }
    $content | default [] | where {|b| ($b.type? | default "") == "text" } | get -o text | default [] | str join "\n"
}

def ms [ts: any]: nothing -> any {
    if $ts == null { null } else if ($ts | describe) == "int" { $ts } else { $ts | into datetime | into int | $in // 1_000_000 }
}

def record-of [f: record]: nothing -> record {
    let es = (entries $f.name)
    let head = ($es | where {|e| ($e.type? | default "") == "session" } | first | default {})
    let msgs = ($es | where {|e| ($e.type? | default "") == "message" })
    let first_user = ($msgs | where {|e| $e.message?.role? == "user" } | first | default null)
    let prompt = if $first_user == null { "" } else { text-of $first_user.message.content | str replace --all --regex '\s+' ' ' | str trim }
    let named = ($es | where {|e| ($e.type? | default "") == "session_info" } | last | default {} | get -o name | default "")
    let id = ($head.id? | default ($f.name | path parse | get stem))
    {
        harness: "pi"
        id: $id
        title: (if $named != "" { $named } else { $prompt | str substring 0..<80 })
        first_prompt: $prompt
        cwd: ($head.cwd? | default "")
        branch: ""
        created: (ms ($head.timestamp? | default null))
        updated: ($f.modified | into int | $in // 1_000_000)
        size: ($f.size | into int)
        transcript: $f.name
        resume: [pi --session $f.name]
        fork: null
    }
}

def find-file [id: string]: nothing -> record {
    let hit = (files | where {|f| ($f.name | str contains $id) })
    if ($hit | is-empty) {
        print --stderr $"pi: no session ($id)"
        exit 1
    }
    $hit.0
}

def main [] { print "usage: pi.nu list | info <id> | messages <id>" }

def "main list" [] {
    files | each {|f| record-of $f | to json --raw } | to text
}

def "main info" [id: string] { record-of (find-file $id) | to json --raw }

def "main messages" [id: string] {
    entries (find-file $id).name
    | where {|e| ($e.type? | default "") == "message" and $e.message?.role? in [user assistant] }
    | each {|e|
        let content = ($e.message.content? | default [])
        let tools = if ($content | describe) =~ '^(list|table)' {
            $content | where {|b| ($b.type? | default "") in [toolCall tool_use] }
            | each {|b|
                let args = ($b.arguments? | default ($b.input? | default {}))
                let file = ($args.path? | default ($args.file_path? | default null))
                {name: $b.name, hint: ($args.command? | default ($file | default "") | into string | str substring 0..<120)}
                | if $file == null { $in } else { $in | insert file $file }
            }
        } else { [] }
        {role: $e.message.role, text: (text-of $content), tools: $tools, at: ($e.timestamp? | default null)}
        | to json --raw
    } | to text
}
