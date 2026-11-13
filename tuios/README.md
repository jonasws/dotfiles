# tuios

The terminal multiplexer, hosted in Ghostty. This directory is linked as a whole
to `~/.config/tuios` (the `tuios` dotfile group), because `tuios config` and the
keybind manager write back into `config.toml`. Docs:
[tuios.dev/docs/configuration](https://tuios.dev/docs/configuration).

- [Installing](#installing)
- [How it is used](#how-it-is-used)
- [Keys](#keys)
- [Plugins](#plugins)
- [Agents](#agents)
- [Known issues](#known-issues)

| Command | Does |
| ------- | ---- |
| `tuios config apply` | Reloads the config. Run it from a terminal outside tuios. |
| `tuios keybinds doctor` | Lists keys that clash or that something else has taken. |
| `tuios restart-server` | Needed after a `[hooks]` change on an older daemon. |

## Installing

tuios runs from main, not from a release. `mise run update:tuios-nightly`:

- clones it into `~/.local/share/tuios-nightly/src`;
- builds it with the libghostty-vt emulator (the `ghostty` backend, with go and
  zig 0.17 from mise);
- links the binary as `~/.local/bin/tuios`;
- syncs the same commit to the hosts in `[hosts]` (`pi`).

`built-commit` in that folder records which commit is installed.

The task leaves a running daemon on its old build (`--keep-server`).
`tuios kill-server` switches over once the panes can be spared. tuios isn't a
mise tool on purpose: `restart-server` starts the newer of two binaries, and it
ranks a dev build below any release.

The daemon is started by the first `tuios` in Ghostty, which makes it count as
Ghostty for macOS privacy grants (`op`, the local network). There's no
LaunchAgent.

## How it is used

- **One session per repository.** `prefix+r` opens `tv git-repos`. Enter runs
  `television/scripts/tuios-session.sh`, which switches to the repo's session
  or creates one named after the repo's directory. A name that's already taken
  gets the parent directory in front (`CNOPS-<repo>`). `prefix+R` opens
  `tv git-worktrees` for the focused pane's repo. A linked worktree gets its
  own session, `<repo>-<branch>`, and `group_main` puts those sessions under
  the main checkout on the rail.
- **herdr vocabulary.** The setup came over from herdr. A herdr workspace is a
  tuios session, a herdr tab is a tuios workspace, and a herdr pane is a tuios
  window. tuios also answers herdr's socket API (on its socket plus `.herdr`)
  and sets `HERDR_ENV=1` in its panes. That is what lets herdr plugins and
  `herdr-splits.nvim` run unchanged
  ([herdr compatibility](https://tuios.dev/docs/herdr-compatibility)).
- **Tiled, terminal mode.** BSP layout with `smart_split`. Keys go to the pane,
  and only the prefix and the command keys are taken. The rail is on the right.
- **Theme.** `mocha-ghostty` (`themes/`), the same sixteen colours as Ghostty,
  with `catppuccin_latte` when the host turns light. Selection and the
  copy-mode cursor are rosewater, as in Ghostty.
- **Naming.** A shell pane shows the title fish sets
  (`fish/functions/fish_title.fish`), and Claude Code names its own pane.
  `scripts/workspace-names.py`, run by the `[hooks]` on focus, pane, command
  and agent events, names each workspace after an agent's topic, else a shell
  pane's title. A name given by hand (`prefix+T`, the CLI or MCP) marks the
  workspace manual, and the script leaves it alone until the name is cleared
  (`tuios set-workspace-name N` with no name). tuios itself has no automatic
  workspace names: an unnamed one shows its number.
- **Worktrees.** These go to `../.worktrees/<repo>/<branch>` beside the repo,
  so a worktree under `~/CX` still loads `~/CX/CLAUDE.md`. The
  `after-new-worktree` hook (`scripts/new-worktree.sh`) runs `mise install`
  there, after `mise trust` when the main checkout is trusted. The hook gets
  one minute.

## Keys

The prefix is `ctrl+b`. `prefix+H` opens the hotkey sheet
(`television/hotkeys/tuios.tsv`).

**Without the prefix.** Ghostty passes these through; see
[ghostty/README.md](../ghostty/README.md).

| Key | Does |
| --- | ---- |
| Ctrl+hjkl / Ctrl+Shift+hjkl | Move / resize across panes and Neovim windows (herdr-splits). |
| Cmd+K | Pane navigator: every pane in every session, searchable, with a preview. |
| Cmd+O | Agent sessions in every repo (`tv agent-sessions`): jump to one or resume it. |
| Cmd+, | Go-to picker: agents, sessions, workspaces, panes. |
| Cmd+P | Command palette. |
| Cmd+T / Cmd+N, Cmd+1..9, Ctrl+(Shift+)Tab | New workspace, pick one, step through them. |
| Cmd+R / Cmd+D / Cmd+W | Split right / split down / close the pane. |
| Cmd+[ / Cmd+] | Jump list back / forward over workspaces (the `jumplist` plugin). |
| Cmd+. | Label the panes and focus one by its label. |
| Ctrl+Shift+Space | Text hints on every pane. |

**Prefix keys that differ from tuios's defaults.** Most of them follow herdr.

| Key | Does | tuios default moved to |
| --- | ---- | ---------------------- |
| `v`, `c` | Split right, new workspace | |
| `1`..`9`, `n` / `p` | Pick, next, previous workspace | |
| `w`, `ctrl+n` / `ctrl+p` | Session switcher, next / previous session | |
| `g`, `/` | Pane navigator | |
| `G` | Scratch pane | go-to picker → Cmd+, |
| `a` / `A`, `J` / `K` | Next / previous agent, across sessions | |
| `o`, `ctrl+k` | Oldest item that needs you, newest finished turn | |
| `T`, `W`, `N`, `X` | Rename workspace, rename session, new session, close workspace | window prefix → `ctrl+x`, workspace switcher → `ctrl+g`, last message → `ctrl+y` |
| `x` / `D` | Close the pane / the session, then show the next session | |
| `e` | Pane screen and scrollback in `$EDITOR` | rail focus → `E` |
| `ctrl+r` | Rename pane | |
| `ctrl+o` | Layout prefix (`space` cycles layouts, `t` BSP schemes) | |
| `ctrl+u` / `alt+u` | Text hints in this pane / all panes | |
| `ctrl+d` | Debug prefix | |

**Command keys** (popups through `scripts/toggle-popup.sh`, which open in the
folder of the pane you pressed them in):

| Key | Opens |
| --- | ----- |
| `prefix+f` | tv pane picker |
| `prefix+r` / `prefix+R` | Repo picker / worktree picker |
| `prefix+l` / `prefix+L` | lazygit status / log |
| `prefix+y` / `prefix+Y` | yazi / yazi picking files into the pane |
| `prefix+O` | AWS profiles |
| `prefix+H` | Hotkeys |
| `prefix+F` | F1 dashboard (herdr-f1) |
| `prefix+t` / `prefix+ctrl+t` | tsk board / tsk quick capture |
| `prefix+ctrl+e` | tsk notes in nvim |
| `prefix+ctrl+s` / `prefix+S` | Start an agent on the tsk task under the board cursor, here / in a worktree |
| `prefix+p` | Preview the AWS `run_script` that is waiting for approval. This one is broken; see [Known issues](#known-issues). |

## Plugins

`tuios plugins list` shows what is installed. Three are enabled in `[plugins]`:

- `herdr-splits`: Ctrl+hjkl across panes and Neovim windows.
- `dev.minung.herdr-f1`: the F1 dashboard. Installed with `herdr plugin install`.
  tuios reads herdr's plugin registry.
- `jonasws.jumplist`: [`plugins/jumplist/`](plugins/jumplist/), which records
  workspace visits for Cmd+[ / Cmd+].

Installed but off: `herdr-automatic-rename`, `dan.pane-topic-sync`,
`herdr-bar` and `herdr-tsk` (the tsk keys above replace it).

## Agents

The agents view (`prefix+i`) is where work starts. Its Working group stays
folded (`fold_working`), so Needs you and Ready for review come first.

- **Approvals in the Inbox.** `[agents.approvals]` holds Claude Code's
  permission prompts and plans for 120 s, so they can be answered from the
  agents view or the phone. The hook that waits is the PermissionRequest
  entry in `claude/settings.json`; `tuios integration status claude-code`
  checks it. In auto mode only calls that still prompt reach the Inbox, which
  includes every `aws` and `fnox exec`. Extra risk rules mark the
  destructive ones, so allowing one takes two presses: `cdk
  deploy`/`destroy`/`import`, CloudFormation stack changes, `aws … delete-*`
  and `aws s3 rm`/`rb`/`mv`/`sync --delete`, also behind `--profile` or
  `fnox exec`. They slow you down; they don't sandbox anything.
- **Push notifications.** `[notify]` lives in `config.d/notify.toml`. The file
  is gitignored because the ntfy topic is a secret. Copy
  `config.d/notify.toml.example`, then run `tuios config apply` and
  `tuios notify test` from outside tuios.
- **Return notes and ask-human.** `claude/CLAUDE.md` tells Claude to leave a
  `tuios note set` when it stops with work left, and to use `tuios ask-human`
  before a deploy.
- **tsk.** tsk is the backlog across repos; a tuios task card follows one run.
  `prefix+ctrl+s` creates a card `T<n>: <title>` and starts
  `tuios start-agent claude --task` in the repo. `prefix+S` starts the tsk
  task and runs `tuios fan` on branch `tsk/t<n>-<slug>` instead. The card
  then moves itself through plan, verify, review and shipped (`b` in the
  agents view). Both keys act only on a tsk board (`scripts/tsk-board.sh` reads
  the task under its cursor off the screen). The board's own `ctrl+s` also
  runs `tsk dispatch` for an assigned task, which launches through herdr, so
  leave tasks unassigned.

## Known issues

- **`prefix+p` is dead.** `prev_workspace` already holds `p`, so the AWS
  `run_script` preview never runs (`tuios keybinds doctor`). It needs another
  key.
- **Ctrl+hjkl in a tv popup** may move panes instead of moving through the
  picker's list. tuios resolves command keys before the pane sees them, and
  has no per-popup exception. The arrow keys and `ctrl+n` / `ctrl+p` work.
