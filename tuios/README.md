# tuios

Configuration for [tuios](https://tuios.dev/docs/configuration), linked to
`~/.config/tuios` by the `tuios` dotfile group in `mise.toml`. `tuios config
apply` reloads it, and `tuios keybinds doctor` lists keys that something else
has taken.

**This config targets tuios built from main, not the 0.11.1 release.** It uses
`next_agent`, `prev_agent` and `edit_scrollback`, which main has and the
releases through 0.11.1 do not. Expect config warnings for them on 0.11.1; the
rest of the config does not depend on them. `mise run update:tuios-nightly`
builds main into `~/.local/share/tuios-nightly`, and the `tuios` shell alias
(`mise-global/config.toml`) points at that build. An alias only reaches an
interactive shell, so nothing here calls `tuios` from a script. The task leaves a
running daemon on its old build (`--keep-server`); `tuios kill-server` switches
it over when the panes can be spared, and until then the daemon does not know
the new actions.

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
| `herdr.lua` command keys | `[[keybindings.command]]` entries: popups through `scripts/toggle-popup.sh`, the tsk board on `prefix+t` among them. herdr's subagent viewer key (`prefix+S`) is not ported: the rail already shows a row per subagent under its pane. |
| Ctrl+hjkl that unzooms and wraps | The `herdr-splits` plugin, enabled in `[plugins]`. |
| Neovim marker file for Ctrl+hjkl | Not needed. Panes have `HERDR_ENV=1`, so `herdr-splits.nvim` loads. |
| Prefix chords for tabs, panes and sessions | `[keybindings.prefix_mode]`. |
| `ctrl+b e`, scrollback in `$EDITOR` | The `edit_scrollback` action, on `prefix+e`. |
| `ctrl+b a` / `shift+a` | The `next_agent` and `prev_agent` actions. |
| Git repo picker opens a session | Enter and `ctrl-w` both run `television/scripts/tuios-session.sh`, which opens or switches to a session named after the repo. |
| Hotkeys sheet | `herdr.tsv`, `prefix+shift+h`: the keys follow herdr's, and the differences are listed below. |
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
installed off until it is listed in `[plugins]`, and four are: `herdr-splits`,
`herdr-f1`, and `dan.pane-topic-sync` with `herdr-automatic-rename`, which name
agent panes after their topic and workspaces after the pane running in them
(settings in `~/.config/herdr/plugins/config/`). `scripts/auto-name.sh` also
names agent panes, from the `after-agent-state` hook. `herdr-tsk` is off: the
tsk board and quick capture are popups on `prefix+t` and `prefix+ctrl+t`. The
other installed plugins, `herdr-bar` among them, are off.

Where tuios's keys differ from `herdr.tsv`: `o` goes to the oldest item that
needs you, `ctrl+k` to the newest finished turn, `J` / `K` also step through
agents, `prefix+g` and `prefix+/` both open the pane navigator, and
`prefix+shift+s` (subagent viewers) is not bound, since the rail lists each
pane's subagents.

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
