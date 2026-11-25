# Decision log for agent tool calls: design

Status: design only. Nothing here is implemented or registered.
Written 2026-11-20. Revised the same day to record answered prompts only.

## 0. Summary

The log records **the permission prompts you answered**, and nothing else:
approved once, approved always, declined, cancelled, and Inbox answers.
Calls that a rule, a hook, the permission mode or the auto-mode classifier
allowed or denied without asking you are not stored. That is about 96% of
calls (1,239 a day over the last 31 days). What remains is about 47 rows a day.

Each row keeps the context the answer was given in: time, session, folder,
repo, worktree, branch, commit, and the command's target, such as the
destination of a git push. Recall then answers "did I approve this exact
command, or one like it, in the same kind of context, and when".

Three pieces, none of which run on a call that doesn't prompt:

1. **Prompt capture**: a PermissionRequest hook. It fires only when a prompt
   is about to be shown, and records the call and its git context.
2. **Reconciler**: an async Stop/SubagentStop hook. It reads the new part of
   the session transcript and fills in your answer, which the transcript
   records.
3. **Post fallback**: an async PostToolUse/PostToolUseFailure hook. It looks
   for a pending prompt for the call and exits when there is none. If the
   transcript stops carrying the answer, this still marks prompts that ran.

Guards that ask (pane-control, slackcli, run-script, git-push, help-allow's
twg/atuin asks) write one small row naming themselves, so the log can say
which hook asked.

Claims about hook events were checked against the raw
https://code.claude.com/docs/en/hooks.md on 2026-11-20 and are marked
**[docs]**. Facts read from local transcripts are marked **[observed]**: they
are internal and undocumented. Anything not confirmed is marked
**[unverified]**.

---

## 1. What the harness exposes

### 1.1 Hook events [docs]

| Event | Fires when | tool_use_id | Role here |
|---|---|---|---|
| PreToolUse | before every tool call | yes | guards only; no recording |
| PermissionRequest | when the harness is about to show a permission prompt | **no** | **prompt capture** |
| PostToolUse | after a tool completes successfully | yes | fallback: a prompted call ran |
| PostToolUseFailure | after a tool fails; is_interrupt for aborts | yes | fallback: it ran and failed |
| Stop, SubagentStop | end of a turn, end of a subagent | n/a | **reconciler** trigger |
| SessionStart | session start, resume, clear, compact, fork | n/a | sweep |
| PermissionDenied | auto mode denies a call | yes | not used (denials are left out) |

- No event carries your answer. A manual deny fires no event: PermissionDenied
  "doesn't run when you manually deny a permission dialog", and a permission
  denial fires neither Post event.
- Matching hooks run in parallel. PreToolUse verdicts merge deny > defer > ask > allow.
- A command hook that fails or times out doesn't block the call unless it has
  "onFailure": "block". None of these hooks set it.
- Common input fields: session_id, prompt_id, transcript_path, cwd,
  permission_mode, effort, hook_event_name, plus agent_id and agent_type
  inside subagents.
- PermissionRequest doesn't run for a sandboxed command's network request.
  That prompt isn't a tool call and isn't recorded.

### 1.2 The transcript records your answer [observed]

Every tool_result record in ~/.claude/projects/<cwd>/<session>.jsonl carries a
permissionDecision object, next to cwd, gitBranch, promptId, sessionId and
timestamp. For calls you answered, source starts with user_. Counted over all
transcripts on 2026-11-20 (31 days):

| source | count | meaning |
|---|---|---|
| user_temporary | ~1,410 | you approved, grantScope once |
| user_reject | ~68 | you declined |
| user_permanent | 3 | you approved and added a rule ("always") |
| user_abort | 1 | you cancelled the prompt |

reasonCode says **why you were prompted**:

| reasonCode | count | cause |
|---|---|---|
| rule:userSettings | 835 | an ask rule in settings.json |
| hook:PreToolUse | 286 | a hook returned ask (which hook isn't named) |
| subcommands… | 123 | a part of a compound command matched no allow rule, or an ask rule |
| bashMiss:no-rule-match | 81 | no allow rule matched |
| safetyCheck (circuitBreaker claudeSettingsFile, dangerousRemoval) | 41 | a built-in safety check |
| rule:localSettings | 40 | an ask rule in settings.local.json |
| unknown, none, workingDir | ~70 | |

Calls that ran without a prompt carry source config (classifier, mode,
rule, subcommandResults) or hook. The reconciler ignores them.

The field names the class of rule, not the rule itself. The hook it names is
"hook:PreToolUse", not which hook. The ask rows of 3.3 fill that gap for the
guards.

### 1.3 Still unverified

- That PermissionRequest's tool_input equals the transcript's tool_use input
  after canonical JSON (sorted keys). A PreToolUse hook returning updatedInput
  could make them differ. None of the guards do that today.
- How an Inbox answer from tuios looks in the transcript. tuios answers
  through its PermissionRequest hook, so the expected source is hook, and a
  deny's message is "The user denied this from the tuios Inbox." The 31 days
  held no Inbox answers.
- That SubagentStop gives the subagent's own transcript path.
- That PermissionRequest fires for every prompt in auto mode, including those
  a hook's ask caused. The reconciler doesn't depend on it: a prompt it finds
  in the transcript without a captured row gets a row of its own (3.2).

---

## 2. Hook survey

| Hook | Event / matcher | Returns | Role in this design |
|---|---|---|---|
| pane-control-guard.py | PreToolUse ^(Bash\|mcp__tuios__.*)$, onFailure block | ask | writes an ask row when it asks; history hint in its reason |
| slackcli-guard.py (unregistered) | PreToolUse ^Bash$, onFailure block planned | allow / ask | same |
| run-script-guard.py | PreToolUse ^mcp__aws__ | allow / ask | same |
| git-push-guard.py (new, 7) | PreToolUse ^Bash$, onFailure block | ask | same |
| help-allow.py | PreToolUse ^Bash$ | allow (help), ask (twg, atuin writes) | writes ask rows for its asks only. Help allows never prompt, so they never reach the log |
| inline-script-guard.py | PreToolUse ^Bash$ | deny | none (denials are left out) |
| repl-lint.sh | PreToolUse ^REPL$ | deny / ask | its warning asks are prompts and get recorded by the harness hooks. No ask row (bash, and rare) |
| researcher-bash-guard.py | PreToolUse, researcher agent | block (exit 2) | none |
| atuin hook | Pre/Post/PostFailure ^Bash$ | nothing | none |
| tuios agent-hook | all events. **On PermissionRequest it may answer from the Inbox** | the Inbox answer | its answers appear as Inbox outcomes (3.4) |
| atuin-recall, tuios-workspace-topic, context7-env, herdr-agent-state, rex | session and prompt events | context | none |
| settings rules | 59 allow, 51 ask, 40 deny; defaultMode auto | allow / ask / deny | ask rules cause 60% of prompts (reasonCode rule:*) |

---

## 3. Architecture

    PreToolUse ─ guards ─ ask? ─► decision_log.record_ask()         ─┐
    PermissionRequest ─► decision-recorder.py capture  (pending row) ─┤
    PostToolUse/Failure ─► decision-recorder.py post   (async)       ─┼─► decisions.sqlite3
    Stop/SubagentStop ─► decision-recorder.py reconcile (async)      ─┤
    SessionStart ─► decision-recorder.py sweep (async)               ─┘
    agent-decisions CLI, decisions-recall skill ─► read-only recall

### 3.1 Prompt capture (PermissionRequest, synchronous)

It computes the context of 5 (session, workspace, target) and inserts a
pending row keyed by (session_id, input_hmac). It prints nothing, so it never
answers the prompt, and exits 0. It runs beside tuios agent-hook, which may
answer. About 20 ms, only while a prompt is opening.

It runs synchronously so the row exists before you can answer. The git
context is read at the moment of the prompt, which is the moment of the
decision.

### 3.2 Reconciler (Stop and SubagentStop, async)

It reads transcript_path from its saved byte offset, going back 256 KB so a
tool_use split from its result by the offset is seen whole. For each
tool_result whose permissionDecision.source starts with user_, or whose call
has a pending row:

1. It hashes the matching tool_use input (canonical JSON, the same HMAC as
   capture).
2. It looks up the newest pending row with that session and hash, captured
   before the result's timestamp.
3. It sets tool_use_id, the outcome, grant_scope, reason_code,
   circuit_breaker, rule_source and ts_answer.
4. With no pending row, it creates one from the transcript's cwd, gitBranch
   and timestamp, with ctx_partial = 1 (no commit or target context).

tool_use_id is UNIQUE, so reading the same lines twice changes nothing.

### 3.3 Ask rows from guards

decision_log.record_ask(hook, payload, reason, detail) runs only when a guard
returns ask, after it has printed its decision. It writes (session_id,
input_hmac, hook, reason, detail, ts). The reconciler and the CLI join it to
the prompt, so a row reads "asked by pane-control-guard: types into a shell
outside the sandbox" rather than "hook:PreToolUse". detail carries the
guard's shape hint: slackcli's channel IDs, run-script's boto3 operations.

### 3.4 Outcomes

| Evidence | outcome | via |
|---|---|---|
| source user_temporary | approved | transcript |
| source user_permanent | approved_always (the rule it added is in permission_suggestions) | transcript |
| source user_reject | declined | transcript |
| source user_abort | cancelled | transcript |
| pending row, source hook, message is the Inbox deny text | inbox_declined | transcript |
| pending row, source hook, the call ran | inbox_approved **[unverified]** | transcript |
| pending row, no transcript answer yet, Post event seen | approved (provisional; the reconciler replaces it) | post |
| pending row, no answer and no Post event after a day | unresolved: declined, cancelled, or the transcript format changed | sweep |

Pushes to protected branches are a special case (7): an approval is never
kept.

### 3.5 Post fallback (PostToolUse and PostToolUseFailure, async)

It hashes tool_input and looks up a pending row in the session through a
partial index that only holds pending rows. No match, the usual case: it
exits without writing. A match: it sets tool_use_id, ran, exit_code (from the
"Exit code N" first line), and a provisional outcome of approved. Async hooks
add no latency [docs]. They cost one short Python process per call in the
background. Its matcher leaves out tools that never prompt:
^(?!(Read|Glob|Grep|LSP|TodoWrite|TaskOutput|ToolSearch|Poll)$).*

### 3.6 Inbox answers

tuios answers a prompt from the Inbox through its own PermissionRequest
hook. The capture row exists (both hooks run in parallel), and the
transcript gives source hook, so the outcome is an Inbox one (3.4). No
listener is needed for the answer itself.

A **tuios subscribe** listener would add only who answered. Inbox items
close with closed = answered, answer and answered_by
(internal/session/attention.go:124 and :211). tuios's [hooks] table has no
event for it (its 13 events are in docs/HOOKS.md). It is left as an option,
not a phase.

### 3.7 Alternatives rejected

| Alternative | Why not |
|---|---|
| Record every call and infer the class (the first draft) | 96% of rows are calls nobody decided. A PreToolUse hook on every call, daily folding, and inferred classes that the transcript now gives directly |
| PermissionRequest + Post only, no transcript | Can't tell a decline from a cancel, an approve-always from an approve-once, or why you were prompted. Kept as the fallback |
| Transcript only, no PermissionRequest hook | Loses the git context at the moment of the prompt: the commit, the upstream, the push target. The transcript has only cwd and gitBranch |
| PermissionDenied for classifier denials | You chose to leave denials out: they aren't your decisions |
| Fold the slackcli allowlist into this DB | Policy written by you and history written by hooks have different writers and trust |
| Parse the guards' stdout from a recorder | Parallel hooks can't see each other's output [docs] |

---

## 4. Storage

DB: ~/.local/share/agent-decisions/decisions.sqlite3 (directory 0700, file
0600). HMAC key: ~/.local/share/agent-decisions/hmac.key (32 random bytes,
0600, made by init). Tests override the path with $AGENT_DECISIONS_DB.

### 4.1 Schema

    PRAGMA journal_mode = WAL;        -- persistent, set once by init
    PRAGMA auto_vacuum = INCREMENTAL;  -- set by init before the first table
    PRAGMA user_version = 1;

    CREATE TABLE repos (
      id          INTEGER PRIMARY KEY,
      repo_key    TEXT NOT NULL UNIQUE,  -- 'github.com/nsbno/cn-cx-booking-service' or 'path:/abs/common-dir'
      remote_url  TEXT,                  -- origin, userinfo stripped
      main_path   TEXT,
      default_ref TEXT                   -- refs/remotes/origin/HEAD, last seen
    );

    CREATE TABLE prompts (
      id              INTEGER PRIMARY KEY,
      session_id      TEXT NOT NULL,
      agent_id        TEXT,               -- subagent, else null
      agent_type      TEXT,
      prompt_id       TEXT,               -- the user prompt this call served
      tool_use_id     TEXT UNIQUE,        -- set by the reconciler or the Post fallback
      input_hmac      BLOB NOT NULL,      -- HMAC(key, canonical tool_input): the join key
      ts_prompt       INTEGER,            -- unix ms at PermissionRequest; null if the reconciler made the row
      ts_answer       INTEGER,            -- the tool_result's timestamp
      permission_mode TEXT,
      tuios_session   TEXT,
      tuios_pane      TEXT,
      tool_name       TEXT NOT NULL,
      mcp_server      TEXT,
      cwd             TEXT NOT NULL,
      input_redacted  TEXT,               -- nulled by the sweep after text_days
      outcome         TEXT CHECK (outcome IN ('approved', 'approved_always', 'declined', 'cancelled',
                                              'inbox_approved', 'inbox_declined', 'unresolved')),
      outcome_via     TEXT CHECK (outcome_via IN ('transcript', 'post', 'sweep')),
      grant_scope     TEXT,               -- permissionDecision.grantScope
      reason_code     TEXT,               -- rule:userSettings, hook:PreToolUse, bashMiss, safetyCheck, ...
      circuit_breaker TEXT,
      rule_source     TEXT,
      ran             INTEGER,            -- 1 ran, 0 failed (Post fallback)
      exit_code       INTEGER,
      ctx_partial     INTEGER NOT NULL DEFAULT 0,   -- made from the transcript alone
      origin          TEXT NOT NULL DEFAULT 'live'  -- live | import
    );

    -- One row per non-trivial command segment: 'cd ~/CX/a && git push' is found as git push in repo a.
    CREATE TABLE prompt_segments (
      prompt      INTEGER NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
      seq         INTEGER NOT NULL,
      ts          INTEGER NOT NULL,       -- copy of the prompt time, so indexes cover recency
      outcome     TEXT,                   -- copy of prompts.outcome, so recall filters in the index
      family      TEXT NOT NULL,          -- 'git push'
      shape       TEXT NOT NULL,          -- 'git push --force <arg> <path>'
      args_shape  TEXT,                   -- 'git push --force origin feat/x'
      eff_dir     TEXT,
      repo_id     INTEGER REFERENCES repos(id),
      worktree    TEXT,                   -- linked worktree path, null in the main checkout
      branch      TEXT,
      head_sha    TEXT,
      upstream    TEXT,
      upstream_sha TEXT,                  -- as of the last fetch
      fetched_at  INTEGER,                -- FETCH_HEAD mtime
      branch_class TEXT,                  -- default | protected | feature | detached
      target      TEXT,                   -- JSON from the family resolver (5.3)
      scope_key   TEXT NOT NULL,
      ctx_uncertain INTEGER NOT NULL DEFAULT 0,
      ctx_input_hmac BLOB NOT NULL,       -- HMAC(key, segment input + scope_key): 'exact' in recall
      PRIMARY KEY (prompt, seq)
    ) WITHOUT ROWID;

    CREATE TABLE asks (                   -- written by guards that return ask
      session_id  TEXT NOT NULL,
      input_hmac  BLOB NOT NULL,
      hook        TEXT NOT NULL,
      ts          INTEGER NOT NULL,
      reason      TEXT,
      detail      TEXT,                   -- JSON shape hint
      PRIMARY KEY (session_id, input_hmac, hook, ts)
    ) WITHOUT ROWID;

    CREATE TABLE ttl (                    -- editable through the CLI
      outcome     TEXT PRIMARY KEY,
      recall_days INTEGER NOT NULL,       -- counted in recall and hints
      text_days   INTEGER NOT NULL,       -- input_redacted kept
      keep_days   INTEGER NOT NULL        -- row kept
    );

    CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID;  -- transcript offsets, last sweep

    CREATE UNIQUE INDEX prompts_tool_use ON prompts(tool_use_id);
    CREATE INDEX prompts_pending  ON prompts(session_id, input_hmac, ts_prompt DESC) WHERE outcome IS NULL;
    CREATE INDEX prompts_ts       ON prompts(ts_prompt);
    CREATE INDEX prompts_prompt   ON prompts(prompt_id);
    CREATE INDEX seg_exact        ON prompt_segments(ctx_input_hmac, ts DESC);
    CREATE INDEX seg_shape_scope  ON prompt_segments(shape, scope_key, ts DESC);
    CREATE INDEX seg_family_scope ON prompt_segments(family, scope_key, ts DESC);
    CREATE INDEX seg_family_repo  ON prompt_segments(family, repo_id, ts DESC);
    CREATE INDEX seg_repo_branch  ON prompt_segments(repo_id, branch, ts DESC);
    CREATE INDEX asks_join        ON asks(session_id, input_hmac, ts DESC);

Default TTLs:

| outcome | recall_days | text_days | keep_days |
|---|---|---|---|
| approved, approved_always, inbox_approved | 90 | 30 | 365 |
| declined, inbox_declined | 60 | 30 | 365 |
| cancelled, unresolved | 14 | 7 | 90 |

At about 47 rows a day, a year is about 17,000 rows and a few MB. Size no
longer drives retention; relevance does. Over 31 days of transcripts, an
approval that came back in a later session in the same repo did so within 7
days half the time and never after 22 days. Declines had a p90 of 6 days.
The 60 and 90 day windows can't be tested on one month: rerun the analysis
(scratchpad ttl/analyze.nu) after three months.

### 4.2 Hot paths

| Path | Statement | Index |
|---|---|---|
| PermissionRequest | INSERT prompts + segments; repos upsert | PK, repos UNIQUE |
| guard ask | INSERT asks | PK |
| Post fallback | SELECT id FROM prompts WHERE session_id=? AND input_hmac=? AND outcome IS NULL ORDER BY ts_prompt DESC LIMIT 1, then UPDATE on a hit | prompts_pending (partial: only pending rows) |
| reconciler | the same lookup per answered result, then UPDATE, or INSERT | prompts_pending, prompts_tool_use |
| recall exact | prompt_segments WHERE ctx_input_hmac=? | seg_exact |
| recall similar | WHERE shape=? AND scope_key=? AND ts>? | seg_shape_scope |
| hint in a guard's ask | the two above, LIMIT 50 | same |

### 4.3 Failure rules and latency

- Open with timeout=0.25, busy_timeout 250, synchronous NORMAL (safe with WAL).
  Hooks never create or migrate the schema; a missing DB means they do
  nothing. "agent-decisions init" and migrate do that.
- **A write never changes a decision.** Capture and Post print nothing. Guards
  print their decision first and call record_ask in try/except afterwards.
  No recording hook sets onFailure.
- Measured (Python 3.15.2, SQLite 3.54.1): python3 -I startup 17 ms; opening
  the WAL DB, inserting and an indexed select, 20 ms. Git context from .git
  files: 0.25 ms in a main checkout, 2 ms in a linked worktree. Capture runs
  only while a prompt opens; the reconciler and Post fallback are async. **No
  recording code runs synchronously on a call that doesn't prompt.**

---

## 5. Context per prompt

Read at PermissionRequest, the moment of the decision.

### 5.1 Session

ts_prompt (unix ms UTC), cwd, session_id, prompt_id (ties the prompt to the
request that led to it), agent_id and agent_type, permission_mode, and
TUIOS_SESSION / TUIOS_PANE_ID from the environment **[unverified that hooks
inherit them]**.

### 5.2 Workspace (per segment)

The effective directory is cwd, moved by cd segments before it and by -C
for git (and make, tar). An unresolvable cd ($VAR, cd -) keeps the last known
directory and sets ctx_uncertain.

Read from .git files, never by running git: walk up to .git (a .git file
means a linked worktree; follow gitdir: and commondir), HEAD for the branch or
detached sha, the loose ref or packed-refs for the sha, config for
branch.<b>.remote/merge, remote.origin.url and push.default,
refs/remotes/origin/HEAD for the default branch, refs/remotes/<r>/<b> for the
upstream sha, and FETCH_HEAD's mtime for its age. Dirty state and ahead/behind
counts need git and the index, and are not captured. git-push-guard may count
commits to push with a 150 ms budget for its own reason text.

- repo_key: the origin URL normalised to host/owner/name, shared by a clone and
  all its worktrees, else path:<common dir>.
- branch_class: default (origin/HEAD, else main or master), protected
  (main, master, release/*, prod*, production, hotfix/*, tags), detached,
  else feature.

### 5.3 Target (per segment, from a resolver per family)

| Family | target | scope_key |
|---|---|---|
| git push | remote; src and dst refs from the refspec, else push.default, else the upstream; dst class; force; delete; tags; dst sha before | repo · dst class · force · delete |
| git reset --hard, clean -f, rebase, branch -D | branch, branch class | repo · branch class |
| aws, fnox … aws, cdk | profile (--profile, else AWS_PROFILE= in the command, else default), account (sso_account_id in ~/.aws/config), region, cdk stacks | account · region · stacks |
| kubectl, helm | --context, --namespace | context · namespace |
| slackcli | workspace, channels (guard hint) | workspace · channels |
| tuios, herdr | target session, pane or --select; same session as the caller or not | same session · verb |
| Edit, Write | path relative to the repo | repo · branch class · top dir |
| mcp__aws__run_script | boto3 operations (guard hint) | sorted operations |
| WebFetch | host | host |
| any other | – | repo |

A compound command that changes context before the risky segment
(git checkout -b x && git push) is resolved against the state at the prompt.
The resolver follows checkout/switch -b. Anything else it can't follow sets
ctx_uncertain.

---

## 6. Similarity

### 6.1 Two axes

| Input axis | Context axis |
|---|---|
| exact: ctx_input_hmac, the input **and** scope_key | same target: scope plus the exact branch or dst ref |
| args: benign positionals kept, flag values masked | same scope: scope_key |
| shape: flag names, all positionals masked | same repo |
| family: program and subcommand | anywhere |

The exact level includes the scope, so a bare git push approved on a feature
branch never matches the same text on main.

### 6.2 Normalising Bash

The splitting is shared with the guards (cmdshape.py, Phase 0).

1. Split on ;, &&, ||, | and newlines, quoting respected; recurse into bash -c (depth 3).
2. Unwrap env, command, time, nice, nohup, mise exec --, fnox exec --, uv run and xargs, kept as via. VAR=value becomes VAR=<v>.
3. Drop trivial segments (cd, pwd, echo, true, date) and sinks (jq, head, tail, wc, sort) from family and shape.
4. Program: basename of argv[0].
5. Subcommand depth from a table, default 1: 0 for rg, fd, jq, curl, ssh, sd, python3; 2 for aws, gh, slackcli, twg, docker compose, cdk; npm run and mise run keep the task name.
6. Flags: names only (--format=%h becomes --format, -1 becomes -<n>), bundles split and sorted.
7. Positionals in shape: <path>, <url:host>, <s3:bucket>, <n>, <arg>. In args_shape, kept when at most 40 characters of [A-Za-z0-9._:@/#-] and not secret-shaped.
8. $VAR and $(...) become <expansion>.

| Command | family | shape | args_shape |
|---|---|---|---|
| git push --force origin feat/x | git push | git push --force <arg> <path> | git push --force origin feat/x |
| cd ~/CX/foo && git push -f | git push | git push -f | git push -f |
| fnox exec -- aws s3 cp s3://bkt/k ./f | aws s3 cp | aws s3 cp <s3:bkt> <path> | aws s3 cp <s3:bkt> ./f |
| tuios -s dotfiles send-text -w ab12 'ls' | tuios send-text | tuios -s <arg> send-text -w <arg> <arg> | tuios -s dotfiles send-text -w ab12 <arg> |
| twg jira workitem edit CX-812 --summary 'x' | twg jira workitem | twg jira workitem --summary <arg> <arg> <arg> | twg jira workitem --summary <arg> edit CX-812 |

Without a flag table the parser can't tell value flags from boolean ones, so
args_shape can attach a positional to a flag. Guards that know their program
pass a detail hint that replaces it.

MCP tools: family is the tool name, shape adds the sorted input keys,
args_shape adds the values of a per-tool key list. Edit and Write: the
repo-relative path. WebFetch: the host. REPL: never prompts as a whole; the
calls inside it prompt on their own.

### 6.3 Redaction of input_redacted

Applied before storing:
- Values of flags named like token, secret, password, key, auth, cookie, session or bearer.
- Env assignments with such names, and Authorization:, Cookie: and X-Api-Key: header values.
- Known token formats: xox?-, ghp_/github_pat_, AKIA/ASIA, sk-, JWTs, PEM blocks.
- URL userinfo, and query parameters named like the above.
- Runs of 32 or more high-entropy characters.
- Heredoc bodies, and anything past 2,000 characters.

Tool output is never stored. input_hmac is keyed, so a copy of the DB can't be
brute-forced back to short commands.

---

## 7. Pushes to main and master

**An approval to push to main or master is never stored and never used.**

- When the reconciler resolves a prompt whose git push segment has dst class
  protected to approved (any kind), it deletes the row. A decline is kept.
  Unprompted pushes aren't stored anyway.
- Hints and auto-allow therefore never see a protected approval.

**Belt and braces, settings.json ask rules**, which hold whatever the hooks do:

    "Bash(git push*main*)",
    "Bash(git push*master*)",
    "Bash(*&& git push*main*)",
    "Bash(*&& git push*master*)",
    "Bash(*; git push*master*)",
    "Bash(*; git push*main*)",
    "Bash(git -C * push*main*)",
    "Bash(git -C * push*master*)"

Ask, not deny: you push dotfiles to main yourself. They over-match on purpose
(feat/main-menu asks too). **[unverified]** that a mid-pattern * crosses
spaces and operators as your existing deny rules assume; test each with a dry
command.

**git-push-guard.py** (PreToolUse ^Bash$, onFailure block) catches what rules
can't: a bare git push or git push origin HEAD while on main. It resolves the
destination with 5.3 and asks when it is main, master or the default branch,
or when it can't be resolved and the current branch is one of them. Its
reason names the push: "pushes ba9fd4d to origin/main (3 commits since the
last fetch)".

Cost: over 31 days, 28 pushes from main or master ran, 27 without a prompt,
18 of them in dotfiles. Expect about one more prompt a day.

---

## 8. Recall

### 8.1 CLI: agent-decisions

claude/hooks/decision-recorder/agent_decisions.py, linked as ~/.local/bin/agent-decisions from
the [dotfiles] table in mise.toml.

| Command | Who | Does |
|---|---|---|
| recall <command…> / recall --tool T --input JSON | agent and you | the strictest match on both axes, with counts per outcome |
| log [--since 7d] [--outcome declined] [--repo .] [--branch B] [--tool T] | agent and you | prompts, newest first |
| top [--outcome approved] [--by shape\|reason] | agent and you | most repeated prompts: candidates for an allow rule |
| why [--since 30d] | agent and you | prompts by reason_code and asking hook: which rule or guard costs you the most prompts |
| show <id> | you | one prompt, its context, ask rows, transcript link |
| import-transcripts [--since] | you | rows from past transcripts, origin import |
| forget, ttl, init, migrate, sweep, doctor | you | maintenance |

    $ cd ~/CX/cn-cx-booking-service && agent-decisions recall git push --force
    context   github.com/nsbno/cn-cx-booking-service · feat/CX-812 (feature) · upstream fetched 2 h ago
    scope     git push → repo · dst feature · force · no delete
                              same target   same scope   same repo         anywhere
    exact     git push --force  —           approved 2   approved 2        approved 4
    shape     git push --force  —           approved 3   approved 3        approved 5, declined 1
    asked by  rule:userSettings (ask rule)            window: approved 90 d, declined 60 d

    $ agent-decisions why --since 30d
    rule:userSettings    835   Edit 179, twg jira workitem 71, tuios capture-pane 56 ...
    hook pane-control    240   tuios capture_pane 82, new-window 47, split-window 41
    hook run-script       95
    safetyCheck           41   claudeSettingsFile 36, dangerousRemoval 5

"why" is new with this design. It shows where prompts come from, which is
the input for tightening or loosening rules.

### 8.2 Skill: decisions-recall

When to look: before running something that will prompt, when you refer to an
earlier approval ("as before"), and before retrying a declined call. Report
"approved twice in this repo, last on 2026-11-18". **History is never
permission.** A past decline is a reason to ask, not to find a way round.

### 8.3 Hint in a guard's ask reason

Only in prompts a guard causes, in any permission mode that prompts (auto
included: a hook's ask outranks the classifier). The guard does one indexed
lookup and appends:

    pane-control-guard: types into a shell outside the sandbox. Seen before: approved 3× in dotfiles (last 2026-11-18), declined 0×.

Prompts from settings ask rules (60% of all prompts, Edit in dotfiles the
biggest) carry no hint: a hook can't add text to a prompt it didn't cause. To
give a family hints, move it from a rule into a guard, as 7 does for pushes.

### 8.4 Auto-allow from history (dropped 2026-11-20, kept for the reasoning)

A guard that would ask answers allow instead when all of these hold:
1. the family is on your opt-in list (empty by default);
2. an exact match on both axes;
3. at least 3 live approvals (origin live) within recall_days, from at least two sessions;
4. no decline at the exact or args level in the window, imported ones included;
5. ctx_uncertain = 0 and ctx_partial = 0;
6. not a protected push, not a pane-control family, not a run-script mutation.

The call then doesn't prompt, so it is not recorded. An auto-allow therefore
can never renew itself: approvals come only from you and expire with
recall_days. Settings ask and deny rules still apply on top [docs].

The data suggests it would rarely fire: 3 in 4 approved keys never recur
outside their session, and the most repeated prompts (aws run_script, tuios
capture) see about one decline per five approvals. Hints may be enough.

---

## 9. Expiry

SQLite has no timers, and correctness doesn't depend on deletion: recall
filters by recall_days. The sweep runs from SessionStart (async), at most
every 6 hours: it nulls input_redacted after text_days, deletes rows after
keep_days, marks pending rows older than a day as unresolved, and runs
incremental_vacuum. No LaunchAgent is needed.

---

## 10. Security and privacy

| Path | Guard | Status |
|---|---|---|
| Bash or REPL $ writing the DB | the OS sandbox: no allowRead or allowWrite for ~/.local/share/agent-decisions; failIfUnavailable true, allowUnsandboxedCommands false | blocked today |
| Edit, Write, NotebookEdit | deny Edit(~/.local/share/agent-decisions/**) | to add |
| Reading the HMAC key | deny Read(~/.local/share/agent-decisions/hmac.key) | to add |
| Editing the hooks or settings.json | sandbox denyWrite ~/dotfiles/claude; ask rules on Edit there | covered |
| A session without the sandbox | not guarded: one you start on purpose | accepted |
| Forged hook payloads | hook input comes from the harness | n/a |
| Prompt injection through stored text | printed as data by the CLI; never put into context by a hook | by convention |
| Forged transcript lines | the agent can't write ~/.claude/projects from the sandbox, and Edit there asks (Edit(~/.claude/**)) | covered |

Recall from the sandbox: the agent's CLI can't read the DB today. Add the
directory to sandbox allowRead (not allowWrite), keeping the key out of it,
so the agent's recall starts at the args level. **[unverified]** that a
read-only connection to a WAL database works from there; if not, open with
?immutable=1 or serve recall through a small MCP server.

Privacy: redacted inputs for 30 days, shapes and context for a year. Context
holds paths, branch names (ticket keys), commit shas, remote URLs (userinfo
stripped), AWS profiles and account IDs. Nothing leaves the machine, and
"forget --since all" wipes it.

---

## 11. Where it lives

| Item | Path |
|---|---|
| DB, key | ~/.local/share/agent-decisions/{decisions.sqlite3,hmac.key} |
| Recorder | claude/hooks/decision-recorder/decision-recorder.py (modes: capture, post, reconcile, sweep) |
| Library | claude/hooks/decision-recorder/decision_log.py, gitctx.py |
| Shared parsing | claude/hooks/cmdshape.py (also used by slackcli-guard.py) |
| New guard | claude/hooks/git-push-guard.py |
| CLI | claude/hooks/decision-recorder/agent_decisions.py → ~/.local/bin/agent-decisions |
| Skill | claude/skills/decisions-recall/SKILL.md |
| mise tasks | decisions:init, decisions:doctor |

settings.json additions:

    "PermissionRequest": [ …, { "hooks": [{ "type": "command", "timeout": 5,
        "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" capture" }] } ],
    "PostToolUse": [ …, { "matcher": "^(?!(Read|Glob|Grep|LSP|TodoWrite|TaskOutput|ToolSearch|Poll)$).*",
        "hooks": [{ "type": "command", "async": true, "timeout": 5,
        "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" post" }] } ],
    "PostToolUseFailure": [ …, same as PostToolUse ],
    "Stop":         [ …, { "hooks": [{ "type": "command", "async": true, "timeout": 30,
        "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" reconcile" }] } ],
    "SubagentStop": [ …, same as Stop ],
    "SessionStart": [ …, { "matcher": "^(startup|clear)$", "hooks": [{ "type": "command", "async": true,
        "timeout": 30, "command": "python3 -I \"$HOME/.claude/hooks/decision-recorder/decision-recorder.py\" sweep" }] } ],
    "PreToolUse": [ …, git-push-guard.py on ^Bash$ with "onFailure": "block" ],
    "permissions.ask":  [ …, the eight rules in 7 ],
    "permissions.deny": [ …, "Edit(~/.local/share/agent-decisions/**)",
                             "Read(~/.local/share/agent-decisions/hmac.key)" ]

Run mise dot apply before registering: a missing python hook file blocks
calls (see the memory on new hooks).

overview.tml: a decision-recorder row (events PermissionRequest, Post*, Stop;
returns none; fails open; "records prompts you answered"), a git-push-guard
row, the eight ask rules on the Ask tab, and a History tab with the outcome
table (3.4) and the CLI commands. Reformat as the comment in mise.toml says.

---

## 12. Consolidating the guards later

Five Python guards would run on each Bash call (pane-control, help-allow,
inline-script, slackcli, git-push), each tokenising again. A single policy
hook would parse once and run each guard as a module. This design doesn't
depend on it:
- record_ask has the same signature for a script or a module.
- With nothing recorded on PreToolUse, recording adds nothing to merge.
- The hard part is failure policy: pane-control and slackcli must fail
  closed, help-allow and inline-script open. One process needs onFailure
  block and a try/except per module mapping a crash to that module's policy.
- repl-lint, run-script-guard and researcher-bash-guard have other matchers
  and stay separate.

Phase 0 (cmdshape.py) is the first step either way.

---

## 13. Decisions

| # | Question | Decision (2026-11-20) |
|---|---|---|
| 1 | What to store | Only prompts you answered. No auto-allowed calls, no denials |
| 2 | Hints | In guard asks only. Rule asks get none; move a family into a guard to give it hints |
| 3 | Inbox | From the PermissionRequest row plus the transcript. A tuios subscribe listener is optional, for answered_by |
| 4 | TTLs | Table in 4.1, from 31 days of transcripts. Rerun after three months |
| 5 | help-allow | Its help allows never prompt, so they never appear. Its twg/atuin asks write ask rows |
| 6 | Backfill | import-transcripts. Imported approvals help hints and recall, never Phase 4. Imported declines count against it |
| 7 | Tamper check on Bash | Dropped: the sandbox covers it |
| 8, 9 | Protected branches, scope | main and master approvals never stored; ask rules plus git-push-guard. Repo is the narrowest scope |
| – | Robustness | Transcript reconciler plus the async Post fallback |

| – | Phase 4 | Dropped: hints only. 8.4 stays as the record of why |
| – | help-allow reference queries | <cmd> --skill [name] and <cmd> skill [name] are allowed like --help (help_only.is_reference_query) |
| – | main/master cost | Accepted: the eight ask rules plus git-push-guard, dotfiles included |
| – | Next | Phases 0 and 1 now, built by the implementer subagent; registration in settings.json stays with the user |

---

## 14. Phases

| Phase | Work | Done when |
|---|---|---|
| 0 | cmdshape.py from slackcli-guard and help_only, one self-test; both guards use it | Self-tests pass and guard verdicts are unchanged |
| 1 | gitctx.py with self-tests (main checkout, worktree, detached HEAD, packed-refs only). decision_log.py (hmac, redaction, normalisation, record_ask) with --self-test. decision-recorder.py capture, post, reconcile, sweep. agent-decisions init, log, show, why, doctor. Deny rules. Register after mise dot apply | A week of rows. Every prompt resolves through the transcript. Check the unverified items of 1.3 |
| 2 | git-push-guard.py and the main/master ask rules. record_ask in pane-control, slackcli, run-script and help-allow asks. recall, top. Sandbox allowRead test | A push to main asks in every form of 7. Prompts name the guard that asked |
| 3 | import-transcripts. history_hint in guard asks. decisions-recall skill. Overview History tab | Hints show in prompts |
| later | Consolidated policy hook (12) | When the guards on Bash become a problem |

Phases 0 to 2 are mechanical. Brief the implementer subagent with this doc,
the self-test cases, and: python3 -I claude/hooks/decision-recorder/decision_log.py --self-test;
mise dot apply && agent-decisions doctor.
