# Rex

Configuration for [Rex](https://www.superlogical.com/rex/docs), linked to
`~/.config/rex` by the `rex` dotfile group in `mise.toml`. Reload after
changes with `rex config reload`.

## herdr in Rex

Rex answers herdr's socket API, the way tuios does
([`internal/session/herdr_api.go`](https://github.com/Gaurav-Gosain/tuios)), so
herdr tools work in Rex unchanged: the `herdr` CLI, herdr-f1 and other herdr
plugins, and this repo's herdr scripts and tv channels. A herdr workspace is a
Rex session, a tab a window, and a pane a terminal block.

```
herdr client ──unix socket──▶ herdr/bridge.mjs ══stdin/stdout══▶ herdr/server.lua  (rex do … --all)
(herdr CLI, herdr-f1,          bytes only                         ├─ methods/*.lua: herdr method → Rex API
 tv channels, scripts)                                            ├─ model.lua: Rex as herdr objects
                                                                  └─ events.lua: Rex events → herdr events
```

`herdr/server.lua` is a Rex Lua script. It answers each request against
Rex's live state through the script's own connection to the server, and
turns Rex's events into herdr's. Lua in Rex can't open sockets, so
`bridge.mjs` owns the socket and passes lines; it knows nothing about herdr.

| File | Role |
| ---- | ---- |
| `herdr.lua` | The configuration side: starts the server with Rex, the command keys, `open_repo`, next/previous agent. |
| `herdr/server.lua` | The server: transport, dispatch, shared helpers. |
| `herdr/methods/*.lua` | One table per herdr namespace: `session`, `workspace`, `tab`, `pane`, `agent`, `events`, `plugin`. |
| `herdr/model.lua` | Reads Rex and builds herdr's WorkspaceInfo, TabInfo, PaneInfo, AgentInfo and layouts, cached until an event says what changed. |
| `herdr/events.lua` | Rex events → herdr events, subscriptions and waits. |
| `herdr/ids.lua` | herdr ids from Rex UUIDs: `w<12 hex>`, `w…:t<12 hex>`, `w…:p<12 hex>`. |
| `herdr/plugins.lua` | herdr plugins from `~/.config/herdr/plugins.json`: actions, panes, startup and event hooks. |
| `herdr/keys.lua`, `herdr/toml.lua` | Key names → bytes for `send_keys`; a small TOML reader. |
| `herdr/bridge.mjs` | The socket. |
| `herdr/ctl`, `herdr/ctl.mjs` | `ensure`, `stop`, `status`, `path`, `call METHOD [JSON]`, `dashboard`. |
| `herdr/test/` | End-to-end test: the real bridge and server, against a scripted Rex. `node rex/herdr/test/run.mjs`. |
| `../fish/conf.d/45-rex-herdr.fish` | Gives every Rex pane `HERDR_SOCKET_PATH`, `HERDR_PANE_ID`, `HERDR_WORKSPACE_ID` and `HERDR_ENV`, as herdr and tuios do for theirs. |

### Methods

| herdr | Rex |
| ----- | --- |
| `ping` | herdr protocol 22, version `0.9.5+rex` |
| `session.snapshot` | `session.list`, `session.view`, and the terminal methods `title`, `pwd`, `process`, `program_status` |
| `workspace.list/get/create/rename/focus/close/report_metadata` | sessions: `session.create`, `set_label`, `session.destroy` |
| `tab.list/get/create/rename/focus/move/close` | windows: `new_window`, `set_window_label`, `focus_window`, `move_window`, `close_window` |
| `pane.list/get/current/layout/neighbor/edges/process_info` | blocks and the view's split tree |
| `pane.read` | the terminal's `format`; `visible` keeps the last screenful (`size`) |
| `pane.send_text/send_keys/send_input` | the terminal's `write`; keys through `keys.lua` |
| `pane.split/close/focus/focus_direction/zoom/resize/swap/move/rename` | `new_split`, `block.close`, `focus_block`, `zoom_block`, `resize_pane`, `swap_blocks`, `move_block`, `set_block_label` |
| `pane.wait_for_output`, `events.wait`, `agent.wait` | answered later: on Rex events, or polled every half second for output |
| `pane.report_agent*`, `pane.report_metadata`, `pane.clear_agent_authority`, `pane.release_agent` | kept by the server and shown to herdr clients; Rex has no API to set a status record |
| `agent.list/get/read/focus/send_keys/prompt/rename/start/wait/explain` | blocks with an OSC 7501 record or a herdr report |
| `events.subscribe` | Rex events, below |
| `plugin.list`, `plugin.action.list/invoke`, `plugin.log.list`, `plugin.pane.open/focus/close`, `popup.close` | herdr's plugin registry |
| `layout.*`, `worktree.*`, `integration.*`, `server.*`, copy and selection, `plugin.link/enable/…` | `unsupported`. Anything herdr doesn't have is `invalid_request`. |

A program's OSC 7501 state becomes herdr's `agent_status`; herdr has no
`error`, so a failed program shows as `blocked`. Its message becomes the
state label. A pane's stripped title reads `<command> <cwd>` while a program
runs and `<cwd>` at a shell prompt, as herdr's picker expects.

### Events

In herdr's shape: lifecycle events snake_case with `data.type`, and
`pane.agent_status_changed` dotted, only for subscriptions naming the pane.

| Rex | herdr |
| --- | ----- |
| `session_created` / `session_destroyed` / `session_label_changed` | `workspace_created` / `workspace_closed` / `workspace_renamed` |
| `window_created` / `window_closed` / `window_label_changed` / `active_window_changed` | `tab_created` / `tab_closed` / `tab_renamed` / `tab_focused`, `workspace_focused` |
| `block_created` / `block_closed` / `terminal.child_exited` | `pane_created` / `pane_closed` / `pane_exited` |
| `terminal.title_changed`, `pwd_changed`, `process_changed` | `pane_updated`, when what herdr shows changed |
| `terminal.program_status_changed` / `_removed` | `pane_agent_status_changed` and `pane.agent_status_changed`; `pane_agent_detected` on a first record |
| `session_view_changed` | `pane_focused` when the focused block moved; `layout_updated` |

### herdr plugins

Plugins installed with `herdr plugin install` run in Rex: their actions,
panes, startup hooks and event hooks, with herdr's environment
(`HERDR_PLUGIN_*`, the socket, and the focused workspace, tab and pane) and
herdr's config and state directories. Installing, linking and enabling stay
with herdr. So herdr-tsk, herdr-f1 and herdr-automatic-rename work here, and
`herdr plugin action invoke …` reaches them from any Rex pane.

### `HERDR_ENV` in Rex panes

herdr sets `HERDR_ENV=1` in every pane, plugin and command it starts, and
documents it as "`1` inside Herdr" ([Add Herdr support](https://herdr.dev/docs/add-herdr-support/)).
Tools read it as "a herdr socket is here and I run in one of its panes": agent
integrations report state only when it is set, herdr's agent skill requires it,
and so do this repo's Claude hooks and skills (subagent viewers, markdown
preview, the status line's context token). Rex panes answer herdr's API, so
`fish/conf.d/45-rex-herdr.fish` sets it, as tuios does in its panes. Two
consequences:

- herdr's own TUI refuses to start inside a Rex pane, as it does inside
  herdr, unless `experimental.allow_nested` is on.
- Neovim's split navigation chooses its backend by multiplexer. A Rex pane
  has both `HERDR_ENV=1` and `REX_SESSION`, and `REX_SESSION` wins, so
  smart-splits' Rex backend keeps driving Ctrl+hjkl there
  (`lazyvim/lua/plugins/smart-splits.lua`, `herdr-splits.lua`,
  `config/keymaps.lua`).

### Lifecycle

`init.lua` starts the server when Rex loads it (`herdr/ctl ensure`, which
does nothing when the socket already answers, so reloads and `rex config
check` are harmless). The command keys run the same check, so a server that
died comes back on the next key. The bridge exits when the script does, and
the script when the bridge does, taking the socket with them.
**herdr: Restart the herdr Socket** restarts it.

The socket is `$TMPDIR/rex-herdr-<uid>.sock`, or `REX_HERDR_SOCKET`. From a
Rex pane, `herdr api snapshot` shows what herdr tools see.

### Keys

`herdr.lua` binds herdr/config.toml's command keys behind the same `ctrl+b`
prefix. Pane movement stays on `init.lua`'s Cmd chords and Ctrl+hjkl.
`television/hotkeys/rex.tsv` has the full table; `ctrl+b` `shift+h` shows it.

| Key | Does | Runs |
| --- | ---- | ---- |
| `ctrl+b f`, `cmd+k` | pane picker, attention first | `tv herdr-sessions` |
| `ctrl+b shift+f` | herdr-f1 in the browser | its herdr plugin, else the `herdr-f1` CLI |
| `ctrl+b l` / `shift+l` | lazygit status / log | `herdr/scripts/lazygit-popup.sh` |
| `ctrl+b y` / `shift+y` | yazi; or pick files into the pane | `herdr/scripts/yazi-popup.sh` |
| `ctrl+b r` | git repos; Enter opens or focuses a tab | `tv git-repos`, its `rex` action |
| `ctrl+b shift+h` / `shift+o` | hotkeys / AWS profiles | `tv hotkeys` / `tv aws-profiles` |
| `ctrl+b t` / `ctrl+t` / `ctrl+e` | tsk board / quick capture / edit notes | `tsk-toggle.sh`, the herdr-tsk plugin, `tsk-notes.sh` |
| `ctrl+b shift+s` | subagent viewers | `claude/hooks/subagent-viewer.sh` |
| `ctrl+b a` / `shift+a` | next / previous agent, across sessions | `next_agent` / `previous_agent` |

herdr's popup and pane keys open a zoomed split that closes with its command.
Floating layers didn't draw full-screen programs until Rex fixed that on
2026-10-27 ("Floating layers: no backdrop, and alternate-screen programs
aren't drawn", Rex Beta feedback); the popups can move to layers next. A key's command gets what
herdr hands its command keys: `HERDR_ENV`, the socket, and
`HERDR_ACTIVE_PANE_ID`, `_TAB_ID` and `_PANE_CWD` for the pane the key was
pressed in. It runs through `$SHELL -l -c`, so PATH has mise's tools.

### Not yet checked against a live server

The docs don't give every argument name or response shape. Where they leave
one open, the server tries the likeliest first and falls back
(`model.try`), and reads results defensively:

- **`session.view`'s shape.** Blocks, windows, labels, the focused block and
  the split tree are found by field names (`block_id`, `window_id`,
  `focused`/`active`, `children`/`a`,`b`, `direction`, `ratio`). Layout
  rectangles come from the tree's ratios on a 1000×1000 grid, so neighbours
  and edges are right while cell sizes are not.
- **Terminal methods:** `format` with `{ format, trim, unwrap }`, `write`
  with `{ data }` (then `text`, `bytes`), and the `process` result's
  `foreground`.
- **Session methods:** `new_split` with `block_id`, `direction` and `side`;
  `resize_pane`, `swap_blocks` and `move_block` arguments; `session.create`
  with a layout, and `session.destroy` for closing.
- **The bridge pipe:** `rex.exec.start` with `detach = true` and a `stdout`
  callback, kept running after the script's top level returns.
- **Switching the app to another session:** the client action
  `session.switch` with a `session_id` argument. From outside the app it
  needs Remote Control turned on.
- **Starting the server from Rex.** `herdr/ctl ensure` runs `rex do`, using
  `REX_BIN` or `rex` on `PATH`. Rex puts `rex` on the `PATH` of its terminals;
  whether the server's own environment has it isn't documented. If the keys
  report that `rex` can't be found, set `REX_BIN` in the server's environment.
