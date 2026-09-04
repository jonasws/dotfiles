# git

Global git configuration, kept in `~/.config/git/` rather than `~/.gitconfig`
so it stays version-controlled. Git reads both; `~/.gitconfig` wins on
conflicts, so nothing here overrides what is already there.

```sh
stow git
```

## What it does

`template/hooks/post-checkout` links the main checkout's `.mise.local.toml`
into every new git worktree.

`.mise.local.toml` is gitignored, so a fresh worktree does not get one and mise
silently loses the local env, tools and tasks it defines. The hook links rather
than copies, so all worktrees share one file instead of copies that drift apart
as tokens rotate and hosts change.

Nothing to configure. Repos without a `.mise.local.toml` are untouched.

Works for every way a worktree gets created — `git worktree add`, `herdr
worktree create`, and Claude Code's `EnterWorktree` — because all of them shell
out to real git, which runs `post-checkout` inside the new worktree.

## Existing repos need one backfill

`init.templateDir` seeds `.git/hooks` at clone and init time, so repos cloned
before this package have no hook. Re-running `git init` in a repo copies in any
template hook it is missing, and does not touch hooks that already exist:

```fish
for d in ~/CNOPS/* ~/CX/*
    test -d $d/.git; and git -C $d init -q
end
```

Worktrees read hooks from the common git dir, so backfilling the main checkout
covers every worktree of that repo.

## Why not core.hooksPath

`core.hooksPath` looks like the obvious way to install a hook globally. It is a
trap here:

- It **shadows `.git/hooks` for every repo**, so nothing a repo installs itself
  runs unless the global hook explicitly chains to it.
- **pre-commit refuses to install while it is set**: `[ERROR] Cowardly refusing
  to install hooks with core.hooksPath set.`
- Setting it to the empty string per repo to dodge that error is worse:
  it disables hooks entirely, so `pre-commit install` reports success and the
  hook then never runs on commit.

`init.templateDir` has none of those problems. It seeds real files into
`.git/hooks`, leaves `core.hooksPath` unset, and coexists with pre-commit,
husky and lefthook.

## Things worth knowing

**The hook must not chain.** It *is* `.git/hooks/post-checkout`, so exec'ing the
repo-local hook would exec itself and loop forever. Nothing is shadowed, so
there is nothing to chain to. A tool that later claims this hook renames this
file (pre-commit uses `post-checkout.legacy`) and calls it.

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
