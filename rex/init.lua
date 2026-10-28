-- Rex configuration, linked to ~/.config/rex/init.lua. Reload with
-- `rex config reload`; `rex config check` validates without applying.
--
-- Rex is the multiplexer here, so the pane chords are direct Cmd shortcuts
-- rather than herdr's prefix keys. Splits keep WezTerm's meaning (see
-- wezterm/dot-wezterm.lua). Font and theme live in the app's Settings, not in
-- this file: Rex has no Lua option for them yet.

-- Cmd+D stacks a pane below, Cmd+R adds one to the right, as in WezTerm.
rex.bind("cmd+d", "pane.split", { direction = "down" })
rex.bind("cmd+r", "pane.split", { direction = "right" })

-- Ctrl+hjkl moves (unzooming a zoomed pane, wrapping at the edge) and
-- Ctrl+Shift+hjkl resizes across Rex panes and Neovim
-- windows as one grid. Neovim side: lazyvim/lua/plugins/smart-splits.lua, whose
-- Rex backend calls back into the `rex` CLI at a Neovim edge. While Neovim runs
-- in a pane the keys belong to it. Rex can't see that from the foreground
-- process (the shell sits behind atuin's PTY proxy), so lazyvim/lua/config/
-- autocmds.lua leaves a marker file holding Neovim's pid, named after the block.
local MARKERS = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/nvim/rex-nvim/"

local function nvim_owns_keys(ctx)
  local path = MARKERS .. tostring(ctx.block_id):gsub("[^%w%-]", "_")
  local file = io.open(path, "r")
  if not file then
    return false
  end
  local pid = file:read("*l")
  file:close()
  local alive = pid and rex.exec({ "/bin/kill", "-0", pid })
  if alive and alive.ok then
    return true
  end
  os.remove(path) -- Neovim died without cleaning up
  return false
end

-- Pickers use Ctrl+hjkl themselves (tv: help, layout, and walking its list), so
-- while one runs in the foreground it gets the moves. They don't use
-- Ctrl+Shift+hjkl, so resizing ignores this. Same list as wezterm/dot-wezterm.lua.
local PICKERS = { tv = true, fzf = true }

-- Ctrl+hjkl moves between the tiled panes, which a floating layer (a picker,
-- the scrollback editor) sits on top of, so the layer gets the keys. A tv or
-- fzf started by hand in a tiled pane is found by its foreground process; the
-- layers' own commands run without job control, which hides the program behind
-- `login`, so the process name can't be used there.
local function in_floating_layer(ctx, view)
  for _, window in ipairs(view and view.windows or {}) do
    for _, layer in ipairs(window.layers or {}) do
      if layer.kind == "floating" then
        for _, block in ipairs(layer.blocks or {}) do
          if block.block_id == ctx.block_id then
            return true
          end
        end
      end
    end
  end
  return false
end

local function picker_wants_keys(ctx, view)
  if in_floating_layer(ctx, view) then
    return true
  end
  local res = rex.call("block.method", {
    session_id = ctx.session_id,
    block_id = ctx.block_id,
    method = "process",
  })
  local info = res and res.result or res
  local fg = info and info.foreground
  return fg ~= nil and PICKERS[fg.name] == true
end

rex.action({
  name = "smart_splits_resize",
  title = "Smart Splits: Resize Pane",
  args = { key = "string", direction = "string" },
  run = function(ctx, args)
    -- Functions bound with rex.bind can't queue client actions, so this is an
    -- action: it forwards the chord to Neovim or resizes the Rex pane itself.
    if nvim_owns_keys(ctx) then
      rex.client.queue("pane.send_key", { key = args.key })
    else
      rex.client.queue("pane.resize", { direction = args.direction, amount = 3 })
    end
  end,
})

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex.bind("ctrl+" .. key, function(ctx)
    local view = rex.session.view({ session_id = ctx.session_id })
    if nvim_owns_keys(ctx) or picker_wants_keys(ctx, view) then
      return false
    end
    -- A zoomed block reports every direction as an edge, so unzoom first, then
    -- move, wrapping to the opposite side at an edge. Same as herdr-splits.
    for _, window in ipairs(view and view.windows or {}) do
      if window.zoomed_block_id and window.focused_block_id == ctx.block_id then
        rex.session.zoom_block({ session_id = ctx.session_id, block_id = ctx.block_id, zoom = false })
      end
    end
    rex.session.focus_direction({ direction = direction, wrap = true })
    return true
  end)
  rex.bind("ctrl+shift+" .. key, "smart_splits_resize", {
    key = "ctrl+shift+" .. key,
    direction = direction,
  })
end

-- Option is the us-altgr-intl compose layer, so no chord here uses it.
rex.bind("cmd+ctrl+=", "pane.balance")

rex.bind("cmd+shift+enter", "pane.zoom")
rex.bind("cmd+p", "client.palette.toggle")

-- Bound explicitly: the default Cmd+Plus does not fire (Rex Beta feedback
-- "cmd+`+` not working"), and `=` is the unshifted key on this layout.
rex.bind("cmd+=", "client.font.increase")
rex.bind("cmd+-", "client.font.decrease")
rex.bind("cmd+0", "client.font.reset")

-- Next/previous agent: the next_agent and previous_agent actions are defined in
-- herdr.lua, which steps through herdr's agents across sessions.
rex.bind("ctrl+cmd+]", "next_agent")
rex.bind("ctrl+cmd+[", "previous_agent")

-- herdr's prefix (its keys are in herdr.lua). Ctrl+B no longer reaches the terminal on
-- its own, so Ctrl+B twice sends one through.
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

-- herdr's default prefix keys for tabs, panes and workspaces (sessions here).
-- Left out: prefix+h/j/k/l, which Ctrl+hjkl cover (and l is lazygit), and detach.
for key, action in pairs({
  ["c"] = "client.tab.new",
  ["shift+x"] = "client.tab.close",
  ["shift+t"] = "client.tab.rename",
  ["n"] = "client.tab.next",
  ["p"] = "client.tab.previous",
  ["x"] = "pane.close",
  ["z"] = "pane.zoom",
  ["v"] = "pane.split.right",
  ["-"] = "pane.split.down",
  ["shift+n"] = "session.new",
  ["shift+d"] = "session.close",
  ["shift+w"] = "session.rename",
  ["ctrl+n"] = "session.next",
  ["ctrl+p"] = "session.previous",
}) do
  rex.bind("ctrl+b>" .. key, action)
end

-- prefix+1..9 jumps to that tab; Rex counts tabs from 1.
for i = 1, 9 do
  rex.bind("ctrl+b>" .. i, "client.tab.goto", { index = i })
end

-- Rex has no copy mode yet, so Ctrl+B e stands in for herdr's edit_scrollback.
-- It snapshots the pane's screen and scrollback into a floating $EDITOR (Neovim
-- by default) with the cursor on the last line. buftype=nofile keeps the buffer
-- editable but refuses :w and never counts as modified, so you can reshape text
-- before yanking it and :q closes without a warning. A full-screen program has
-- no scrollback, so inside one the snapshot is just its screen.
rex.action({
  name = "edit_scrollback",
  title = "Edit Scrollback in $EDITOR",
  run = function()
    local shot = rex.block.call("com.superlogical.terminal", "format", {
      format = "text",
      trim = true,
      unwrap = true,
    })
    if not shot or not shot.content then
      return
    end
    local path = os.tmpname()
    local file = io.open(path, "w")
    if not file then
      return
    end
    file:write(shot.content)
    file:close()
    rex.session.new_layer({
      bounds = { 0.04, 0.04, 0.92, 0.92 },
      focus = true,
      layout = {
        block = {
          flavor = "com.superlogical.terminal.shell",
          label = "scrollback",
          options = {
            command = {
              "sh", "-c",
              'f=$1; "${EDITOR:-nvim}" -n -c "setlocal buftype=nofile" + "$f"; rm -f "$f"',
              "sh", path,
            },
          },
        },
      },
    })
  end,
})

rex.bind("ctrl+b>e", "edit_scrollback")

-- herdr's command keys (herdr.lua), behind herdr's ctrl+b prefix: ctrl+b then
-- shift+f for herdr-f1, f or Cmd+K for the pane picker. The table is
-- television/hotkeys/rex.tsv.
require("herdr").bind()
