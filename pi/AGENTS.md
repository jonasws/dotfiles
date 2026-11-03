## Where you run

You run inside a nono sandbox (profile `pi-agent`, `AGENT_SANDBOX=nono`). It is
enforced by the kernel, not by asking you, so a denial is final: report it and
say what the user would have to change, do not look for a way around it.

- Writable: the directory you started in, `~/CX`, `~/CNOPS`, `~/CN-TERMINAL`,
  `~/dotfiles`, `~/.herdr/worktrees`, `~/.m2/repository`. Everything else in
  `$HOME` is read-only or invisible.
- Read-only even there: your own configuration and containment
  (`~/dotfiles/{claude,fish,fnox,herdr,nono,pi,git,mise-global}`,
  `~/dotfiles/mise.toml`, `~/.pi/agent`), every `.git/hooks` and `.git/config`.
  Describe the change for the user instead.
- Unreadable: `.env` files, `~/.ssh`, `~/.aws`, keychains, 1Password.
- Network goes through a proxy that allows LLM APIs, package registries,
  GitHub, sigstore and a few documentation sites. Anything else fails to
  connect. There is no SSH, so `git push` and SSH remotes do not work; the user
  pushes.
- No credentials exist in here. `gh`, `op`, `fnox` and `twg` are refused. For
  GitHub use the `github` MCP tools: read-only and public repositories only, so
  search private repos in the local clones under `~/CX`, `~/CNOPS` and
  `~/CN-TERMINAL`. `mvn` runs `--offline` against `~/.m2/repository`.
- Commits come out unsigned. Do not pass `-S`. After committing, tell the user
  how many unsigned commits there are and to run `resign-commits`.

## Other agents

There are no subagents. Use these, in this order of preference:

1. Context gathering is its own session. If a task needs a survey first, do the
   survey, write it to a file (`/scout` does this), and suggest a fresh
   session that starts from that file instead of carrying the tool output.
2. One-shot work you only need the answer of, such as a review: run yourself
   with `pi -p --no-session "<prompt>"` through bash (`/review` does this). It
   inherits this sandbox.
3. Work the user should be able to watch and steer: a pi in a herdr pane next
   to yours (`/delegate` does this).

herdr panes start outside any sandbox, so you can read herdr but not drive it.
`herdr agent read|wait|list|get` and `herdr pane read|list` work directly.
Everything that creates panes or sends input goes through `pi-herdr`, which
starts only sandboxed pi children and only touches agents named `pi-*`:

```bash
pi-herdr spawn pi-tests -- --model sonnet          # split right, start pi there
pi-herdr prompt --wait --timeout 600000 pi-tests "Fix the failing test in ..."
herdr agent read pi-tests --source recent-unwrapped --lines 120
pi-herdr interrupt pi-tests                        # Esc
pi-herdr stop pi-tests                             # close its pane
```

The `herdr` skill describes the full CLI; its `pane run`, `send-text`,
`agent start` and layout commands are refused here.

## Commit messages

Indent the body with 2 spaces (from line 2 and below). No session links and no
`Co-Authored-By` trailer: the message describes the change, not the tool.

## Code comments

Comment the non-obvious why. No comments that restate the code, and none about
detours taken while getting there.
