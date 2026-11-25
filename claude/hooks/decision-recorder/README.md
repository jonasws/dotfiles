# Decision log: the permission prompts you answered

A local record of every permission prompt you answered for an AI agent:
approved, approved "always", declined, cancelled, or answered from the tuios
Inbox. Each entry keeps the context you answered in: when, which session and
folder, the repo, worktree, branch and commit, and what the command targeted
(for a git push, where it was going).

atuin answers "how did I do this before". This log answers "did I approve this,
or something like it, before, and where".

Calls that ran or were refused **without** asking you are not recorded: rules,
hooks, the permission mode and auto mode decide about 96% of calls, and none
of those are your decisions.

Status: Phases 0 and 1 are built and self-tested. Nothing is registered yet.
The design and its reasoning are in [DESIGN.md](DESIGN.md).

## How it works

    you are asked ──► PermissionRequest ──► capture    pending row + git context
    you answer
    the call runs ──► PostToolUse(Failure) ─► post      marks a pending row as ran (async)
    turn ends ──────► Stop / SubagentStop ──► reconcile reads your answer from the transcript (async)
    session starts ─► SessionStart ─────────► sweep     expires old rows (async, every 6 h at most)

No hook event reports your answer, but the session transcript does: each tool
result carries a permissionDecision whose source says whether you approved
(user_temporary, user_permanent), declined (user_reject) or cancelled
(user_abort), and a reasonCode saying why you were asked. The reconciler reads
that after each turn. The post hook is the fallback if the transcript ever
stops carrying it. The field is undocumented, so agent-decisions doctor warns
when it hasn't been seen.

A call that doesn't prompt runs no recording code at all, except the async
post hook, which looks for a pending row and exits.

The recorder prints nothing and always exits 0, so it can never change what a
call does. Without a database it does nothing.

### Pushes to main and master

An approved push to a protected branch is never kept: main, master, the repo's
default branch, release/*, prod*, production and hotfix/*. Declines are kept.
Phase 2 adds ask rules and git-push-guard.py so every push to main or master
prompts.

## Files

All in claude/hooks/decision-recorder/, linked as one folder to
~/.claude/hooks/decision-recorder, except the two shared files at the end.

| File | What it is |
|---|---|
| decision-recorder.py | the hook: modes capture, post, reconcile, sweep |
| decision_log.py | storage, schema, HMAC, redaction, command normalisation, git push target |
| gitctx.py | git context read from .git files, without running git |
| ../cmdshape.py | shell command splitting, shared with the other hooks |
| agent_decisions.py | the CLI: init, log, show, why, doctor |
| ../help_only.py, ../help-allow.py | also allow \`<cmd> --skill [name]\` reference queries |

Data, outside the repo:

| Path | What |
|---|---|
| ~/.local/share/agent-decisions/decisions.sqlite3 | the log (SQLite, WAL) |
| ~/.local/share/agent-decisions/hmac.key | key for hashing command input, 0600 |

Set AGENT_DECISIONS_DB to use another database, for tests.

## Setting it up

1. Link the folder into ~/.claude (mise.toml has the entry
   "~/.claude/hooks/decision-recorder" = { mode = "symlink" }):

       mise dot apply

   Do this before registering: a registered Python hook whose file is missing
   blocks calls.

2. Create the database and key:

       python3 -I ~/.claude/hooks/decision-recorder/agent_decisions.py init

   (agent-decisions on PATH once mise.toml links it; see "Not done yet".)

3. Register the hooks in claude/settings.json, next to the existing entries:

       "PermissionRequest": [ …, { "hooks": [{ "type": "command", "timeout": 5,
           "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" capture" }] } ],
       "PostToolUse": [ …, { "matcher": "^(?!(Read|Glob|Grep|LSP|TodoWrite|TaskOutput|ToolSearch|Poll)$).*",
           "hooks": [{ "type": "command", "async": true, "timeout": 5,
           "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" post" }] } ],
       "PostToolUseFailure": [ …, same as PostToolUse ],
       "Stop":         [ …, { "hooks": [{ "type": "command", "async": true, "timeout": 30,
           "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" reconcile" }] } ],
       "SubagentStop": [ …, same as Stop ],
       "SessionStart": [ …, { "matcher": "^(startup|clear)$", "hooks": [{ "type": "command",
           "async": true, "timeout": 30,
           "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" sweep" }] } ]

   And two deny rules, so the agent can't edit the log or read the key:

       "Edit(~/.local/share/agent-decisions/**)",
       "Read(~/.local/share/agent-decisions/hmac.key)"

   None of these hooks set onFailure: a failure lets the call through.

4. Check it after a session or two:

       python3 -I ~/.claude/hooks/decision-recorder/agent_decisions.py doctor

## Using it

    agent-decisions log                        # newest prompts first
    agent-decisions log --outcome declined --since 14d
    agent-decisions log --repo . --branch main # this repo, one branch
    agent-decisions log --tool Edit
    agent-decisions show 812                   # one prompt: context, reason, outcome
    agent-decisions why --since 30d            # which rules and hooks cost you the most prompts
    agent-decisions doctor                     # schema, key, counts, stale pending rows
    agent-decisions rebuild                    # drop transcript-only rows; the next Stop reads them again

log prints one line per prompt:

    812  2026-11-20 13:37  approved   Bash  git push --force origin feat/x  [github.com/jonasws/dotfiles feat/x]

Outcomes:

| Outcome | Meaning |
|---|---|
| approved | you approved once |
| approved_always | you approved and added a permission rule |
| declined | you declined |
| cancelled | you cancelled the prompt (Esc) |
| inbox_approved, inbox_declined | answered from the tuios Inbox |
| pending | asked, answer not read yet (until the turn ends) |
| unresolved | no answer found after a day: interrupted, or the transcript format changed |

## Retention

| Outcome | Counts in recall | Command text kept | Row kept |
|---|---|---|---|
| approved, approved_always, inbox_approved | 90 days | 30 days | 1 year |
| declined, inbox_declined | 60 days | 30 days | 1 year |
| cancelled, unresolved | 14 days | 7 days | 90 days |

The sweep applies these at session start. At about 45 prompts a day the
database stays at a few MB. The values came from 31 days of transcripts; check
them again after a few months.

## What is stored, and privacy

- The command or tool input, redacted (tokens, secrets, passwords, auth
  headers, URL credentials, long high-entropy strings, heredoc bodies), and
  dropped after the "text kept" period. For Edit and Write, only the path.
- A shape of the command for matching: program, subcommand, flag names, with
  values masked.
- Git context: repo remote (credentials stripped), worktree, branch, commit,
  upstream, and for git push the destination.
- A keyed HMAC of the input, so a copy of the database can't be brute-forced
  back into short commands.
- Never tool output.

Nothing leaves the machine. The file is not in the dotfiles repo.

## Who can change it

- The agent's Bash runs in the sandbox, which can't read or write
  ~/.local/share/agent-decisions.
- The two deny rules above cover the Edit, Write and Read tools.
- The hooks themselves live in ~/dotfiles/claude, which the sandbox can't write
  and where edits ask.
- Only you run init, and later forget and ttl.

## Testing

    python3 -I ~/.claude/hooks/cmdshape.py --self-test
    python3 -I ~/.claude/hooks/decision-recorder/gitctx.py --self-test
    python3 -I ~/.claude/hooks/decision-recorder/decision_log.py --self-test
    python3 -I ~/.claude/hooks/decision-recorder/decision-recorder.py --self-test
    python3 -I ~/.claude/hooks/help-allow.py --self-test        # covers help_only.py
    python3 -I ~/.claude/hooks/pane-control-guard.py --self-test

Try the recorder against a throwaway database:

    export AGENT_DECISIONS_DB=/tmp/decisions-test/decisions.sqlite3
    python3 -I ~/.claude/hooks/decision-recorder/agent_decisions.py init
    echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"git push"},"cwd":"'"$PWD"'"}' \
      | python3 -I ~/.claude/hooks/decision-recorder/decision-recorder.py capture
    python3 -I ~/.claude/hooks/decision-recorder/agent_decisions.py log

## Not done yet

| Phase | Adds |
|---|---|
| 2 | git-push-guard.py and the main/master ask rules; guards record which hook asked (record_ask); agent-decisions recall and top; ~/.local/bin/agent-decisions link in mise.toml; letting the sandbox read the log |
| 3 | import-transcripts; "seen before: approved 3×" in guard prompts; the decisions-recall skill; a History tab in overview.tml |

Target context is recorded for git push, branch-changing git commands, Edit,
Write and WebFetch. aws, cdk, kubectl, slackcli, tuios and the AWS run_script
tool record only the repo for now.

Auto-allowing from history was considered and dropped: most approvals never
recur outside their session, so it would rarely help, and hints give the same
memory without widening what runs unprompted.
