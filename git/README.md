# git

Global git configuration, kept in `~/.config/git/` rather than `~/.gitconfig`
so it stays version-controlled. Git reads both; `~/.gitconfig` wins on
conflicts, so nothing here overrides what is already there.

```sh
stow git
```

## What it does

`hooks/post-checkout` links the main checkout's `.mise.local.toml` into every
new git worktree.

`.mise.local.toml` is gitignored, so a fresh worktree does not get one and mise
silently loses the local env, tools and tasks it defines. The hook links rather
than copies, so all worktrees share one file instead of copies that drift apart
as tokens rotate and hosts change.

Nothing to configure. Repos without a `.mise.local.toml` are untouched.

Works for every way a worktree gets created — `git worktree add`, `herdr
worktree create`, and Claude Code's `EnterWorktree` — because all of them shell
out to real git, which runs `post-checkout` inside the new worktree.

## Things worth knowing

**`core.hooksPath` shadows `.git/hooks` everywhere.** Setting it globally means
no repo's own hooks run unless something chains to them. `post-checkout` ends by
exec'ing the repo-local hook so husky, lefthook, pre-commit and mise keep
working. Any hook added here must do the same.

**Repos that set their own `core.hooksPath` opt out entirely.** husky v9 points
it at `.husky`, and a repo-level value overrides the global one, so these hooks
do not run there at all.

**The main working tree is never modified.** `post-checkout` also fires on
ordinary `git checkout`, so the hook only acts when git-dir differs from
git-common-dir, which is true only in a linked worktree.

**Real files are never replaced.** A worktree that has its own real
`.mise.local.toml` — say one pinning a port just for that worktree — keeps it,
and the hook says so on stderr. Only a symlink or nothing is ever overwritten.

**mise trust is already shared across worktrees.** A config trusted in the main
checkout is trusted in linked worktrees regardless of where they live on disk,
so agents do not hit a trust prompt or a silently broken env. Setting
`paranoid = true` in mise would disable that sharing.

## What this deliberately does not solve

Config that names a singleton resource does not survive being shared. A task
pinning `localPortNumber=54321`, or `TESTCONTAINERS_REUSE_ENABLE` pointing at
one container, will collide when several worktrees run agents at once. Those
values need deriving per worktree, which is a change to the repo's own config,
not something a link can fix.
