# tuios

Configuration for [tuios](https://tuios.dev/docs/configuration), linked to
`~/.config/tuios` by the `tuios` dotfile group in `mise.toml`. `tuios config
apply` reloads it, and `tuios keybinds doctor` lists keys that something else
has taken.

**This config runs on tuios built from main.** What it needs is in the 0.12.0
release too: `next_agent`, `prev_agent` and `edit_scrollback`, the task board,
Settled shelf, return notes, `[agents.approvals]`, `group_main` and the
`after-new-worktree` hook.
`mise run update:tuios-nightly` builds main into `~/.local/share/tuios-nightly`
and links the binary as `~/.local/bin/tuios`, so `tuios` on PATH is the nightly
build in every shell and script. Hooks run in the daemon's environment, so
`scripts/auto-name.sh` falls back to the nightly path when `tuios` is not on its
PATH. The task leaves a running daemon on its old build (`--keep-server`);
`tuios kill-server` switches it over when the panes can be spared, and until
then the daemon does not know the new actions.

The command keys and scripts here use tuios's own commands (`tuios --skill`,
`tuios <cmd> --help`); the herdr scripts in `herdr/scripts` stay herdr's. tuios
also answers herdr's socket API on its own socket plus `.herdr`
([herdr Compatibility](https://tuios.dev/docs/herdr-compatibility)), which is
what lets it run herdr plugins as they are ([Plugins](https://tuios.dev/docs/plugins)).
A herdr workspace is a tuios session, a tab a tuios workspace, and a pane a
tuios window. `config.toml`
follows `herdr/config.toml` key for key where tuios has a match.

## What Rex got, and where it is here

The same herdr setup was ported to Rex (`rex/`). tuios ships most of that as
built-ins:

| In Rex | In tuios |
| ------ | -------- |
| `rex/herdr/` socket server, bridge and LaunchAgent | Built in. The daemon serves the herdr socket and starts when a session does. |
| `fish/conf.d/45-rex-herdr.fish` | tuios sets `HERDR_SOCKET_PATH`, `HERDR_PANE_ID` and `HERDR_ENV` in its panes. |
| `herdr.lua` command keys | `[[keybindings.command]]` entries: popups through `scripts/toggle-popup.sh`, the tsk board on `prefix+t` among them. herdr's subagent viewer key is not ported: the rail already shows a row per subagent under its pane, and `prefix+S` starts a tsk task in a worktree instead. |
| Ctrl+hjkl that unzooms and wraps | The `herdr-splits` plugin, enabled in `[plugins]`. |
| Neovim marker file for Ctrl+hjkl | Not needed. Panes have `HERDR_ENV=1`, so `herdr-splits.nvim` loads. |
| Prefix chords for tabs, panes and sessions | `[keybindings.prefix_mode]`. |
| `ctrl+b e`, scrollback in `$EDITOR` | The `edit_scrollback` action, on `prefix+e`. |
| `ctrl+b a` / `shift+a` | The `next_agent` and `prev_agent` actions. |
| Git repo picker opens a session | Enter and `ctrl-w` both run `television/scripts/tuios-session.sh`, which opens or switches to a session named after the repo. |
| Hotkeys sheet | `television/hotkeys/tuios.tsv`, first in `prefix+shift+h`: tuios's own keys and these. `herdr.tsv` stays for herdr. |
| `herdr_f1`, the F1 dashboard | The `herdr-f1` plugin from herdr's registry, enabled in `[plugins]`, on `prefix+F`. |
| Pickers in floating layers | Popups. The `tv` pickers run through `scripts/close-on-leave.sh`, which closes the popup when focus, the workspace or the session moves away from it. |
| Cmd+D / Cmd+R, `ctrl+cmd+]` / `[`, font keys, theme import | The host terminal's job (WezTerm, `wezterm/dot-wezterm.lua`). Rex's prefix-free agent chords are not ported. |
| LaunchAgent that keeps the server up | Not needed. On macOS, `tuios daemon-app install --login` runs the daemon as an app so panes keep local network access. |

### Keys

herdr's capital-letter chords: `shift+x` closes a tab, `shift+t` renames it,
`shift+n` makes a session, `shift+d` closes it and `shift+w` renames it. tuios
used those keys for other things, which moved:

| Action | Was | Now |
| ------ | --- | --- |
| Debug prefix | `D` | `ctrl+d` |
| Window prefix | `T` | `ctrl+x` |
| Last message | `N` | `ctrl+y` |
| Workspace switcher | `W` | `ctrl+g` |
| Rail focus | `e` | `E` |
| Newest finished turn | `A` | `ctrl+k` |
| Text hints | `F` | `ctrl+u` |

`a` and `A` step through the agents like herdr's `next_agent` and
`previous_agent`, in the order of the rail's agents section, switching session
as needed. tuios's own `J` and `K` keep doing the same. The attention queue
keeps tuios's `o`, and `ctrl+k` takes the newest finished turn from `A`, since
`O` opens the AWS profiles.

`prefix+F` opens the F1 dashboard, as in herdr. tuios leaves a plugin herdr
installed off until it is listed in `[plugins]`, and three are: `herdr-splits`,
`herdr-f1`, and `herdr-automatic-rename`, which names workspaces after the pane
running in them (settings in `~/.config/herdr/plugins/config/`). Agent panes are
named by `scripts/auto-name.sh` alone, from the `after-agent-state` hook;
`dan.pane-topic-sync` is off here so two namers do not fight over one label.
Since 0.12.1 tuios also shows a name the agent set itself (`claude -n`,
`/rename`), and a name set by the script or by hand comes before it.
`herdr-tsk` is off: the tsk board and quick capture are popups on `prefix+t`
and `prefix+ctrl+t`. The other installed plugins, `herdr-bar` among them, are
off.

Where tuios's keys differ from `herdr.tsv`: `o` goes to the oldest item that
needs you, `ctrl+k` to the newest finished turn, `J` / `K` also step through
agents, `prefix+g` and `prefix+/` both open the pane navigator, and
`prefix+shift+s` starts the selected tsk task in a worktree (see Agents below)
instead of opening subagent viewers, since the rail lists each pane's
subagents.

`prefix+e` opens the pane's screen and scrollback as plain text in the File
editor setting, else `$EDITOR`, else `$VISUAL`, else `vi`. vi, vim and nvim open
at the top of the screen, not on the last line as Rex's did. Rex's version used
a `buftype=nofile` buffer so that `:q` never warned; tuios's file is a real one
in a private folder, removed when the editor exits.

### Git repos

`prefix+r` opens `tv git-repos` in a popup. Enter runs the picker's `open`
action, which in a tuios pane (`TUIOS_ENV=1`) runs
`television/scripts/tuios-session.sh`: it switches to the session whose
checkout is the repo, or creates one there with `tuios switch-session --create`.
The session is named after the repo's directory, so `-s <repo>`, `tuios attach
<repo>` and the `session:<repo>` selector reach it. A session tuios named
`session-<hex>` is renamed on the way, and a name another repo already holds
gets the parent directory in front (`CNOPS-<repo>`).

## Agents

The agents view (`prefix+i`) is the place to work from; `tuios.tsv` has its
keys.

- **Approvals in the Inbox.** `[agents.approvals]` holds Claude Code's
  permission prompts and plans there, so they are answered from the agents
  view or the phone. The hook that waits is the PermissionRequest entry of
  integration v3, already in `claude/settings.json`; `tuios integration
  status claude-code` says whether it is current. In auto mode the Inbox
  only sees calls that still prompt: the `ask` rules in
  `claude/settings.json`, which take every `aws` and `fnox exec` call so that
  Claude reaches for the AWS MCP server first. Risk rules on top of the
  shipped ones mark the destructive ones among them: `cdk
  deploy`/`destroy`/`import`, CloudFormation stack changes, `aws … delete-*`
  style calls and `aws s3 rm`/`rb`/`mv`/`sync --delete`, also behind global
  options such as `--profile` or inside `fnox exec`; allowing one takes a
  second press. They are a speed bump, not a sandbox.
- **Working folded.** `[agents] fold_working` keeps the Working group closed
  until it is opened, so Needs you and Ready for review lead.
- **Worktrees.** `group_main` puts a repo's worktree sessions under its main
  checkout on the rail. `scripts/new-worktree.sh`, the `after-new-worktree`
  hook, runs `mise install` in each new worktree before its first pane
  starts. It runs `mise trust` first only when the main checkout is trusted,
  so a worktree of a repo I never trusted stays untrusted. tuios gives the
  hook one minute: past that it is stopped, and the session still starts
  with the hook's error shown, so a first install of a large toolchain is
  finished with `mise install` in the pane.
  `[hooks]` changes need `tuios restart-server`.
- **Push notifications.** `[notify]` lives in `config.d/notify.toml`,
  gitignored because the ntfy topic is a secret; copy
  `config.d/notify.toml.example`, then run `tuios config apply` and
  `tuios notify test` from a terminal outside tuios.
- **Return notes and ask-human.** `claude/CLAUDE.md` asks Claude to leave
  `tuios note set` on the session when it stops with work left, and to ask
  `tuios ask-human` before a deploy or other step that needs a yes.

### tsk and tuios task cards

tsk stays the backlog: notes, steps, the desk across repos, and only I set
`done`. tuios task cards follow one run. These keys act only when pressed on a
tsk board (the `prefix+t` popup or a pane running `tsk`); anywhere else they
say so in a popup:

| Key | Does |
| --- | --- |
| `prefix+ctrl+s` | `scripts/tsk-dispatch.sh here`: a card `T<n>: <title>`, then `tuios start-agent claude --task` in the repo's folder. The agent moves the tsk task itself. |
| `prefix+S` | `scripts/tsk-dispatch.sh worktree`: a card, `tsk status T<n> start` on the main checkout, then `tuios fan 1 --task` on branch `tsk/t<n>-<slug>` with the task's notes in the prompt. |

The board's own `ctrl+s` (no prefix) is tsk's start. On a task with an
assignee it also runs `tsk dispatch`, which launches the agent through Herdr,
and tuios panes set `HERDR_ENV`; leave tasks unassigned to keep that to the
prefix keys.

The card then moves through plan, verify, review and shipped on its own as the
agent's plan, `fan verify` and pull request change (`b` in the agents view).
`scripts/tsk-board.sh` reads the task under the board's cursor off the screen,
for this and for `tsk-notes.sh`.

## Not yet checked

Written on Linux without a tuios binary, against the docs and the source on
main. Nothing here has run on the Mac.

- **Ctrl+hjkl in a tv popup.** Rex gives these keys to `tv` and `fzf` when one
  runs in the foreground or in a floating layer. A tuios command key is
  resolved before the key reaches any pane, and main has no per-program or
  per-popup exception (`internal/input/keyboard_terminal.go`), so `ctrl+j` and
  `ctrl+k` may move panes instead of walking a picker's list, and `ctrl+h` and
  `ctrl+l` may do the same instead of opening tv's help and layout. The arrow
  keys and `ctrl+n` / `ctrl+p` still work in `tv`.
- **Cross-session agent jumps.** `next_agent` switches session when the next
  agent is in another one, as choosing its row in the rail does.
- **Key conflicts.** Run `tuios keybinds doctor` after `mise dot apply`. A
  command key that a tuios action holds shows up there as dead. `G` is held by
  both `goto_picker` (a default) and `toggle_scratch` (this config), which
  predates the Rex port.
- **The dispatch keys pressed for real.** `tsk-dispatch.sh` has run against a
  scratch daemon with the variables a command key sets (`TUIOS_SESSION`,
  `TUIOS_ACTIVE_PANE_ID`, `TUIOS_ACTIVE_PANE_CWD`), with `start-agent` and
  `fan` stubbed, but not from the keys on an attached client, and the
  failure popup needs one to show.
