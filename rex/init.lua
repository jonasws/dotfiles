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

-- Ctrl+hjkl moves and Ctrl+Shift+hjkl resizes across Rex panes and Neovim
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
    if nvim_owns_keys(ctx) then
      return false
    end
    rex.session.focus_direction({ direction = direction })
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

-- Next/previous agent, after herdr's next_agent/previous_agent. An agent is a
-- terminal whose program reported a status record with an app (Claude Code
-- does). Order follows the sidebar: sessions, then tabs, then pane layout order.
-- Like herdr it wraps, and from a non-agent pane it lands on the first (next)
-- or last (previous) agent.
local TERMINAL = "com.superlogical.terminal"

local function is_agent(session_id, block_id)
  local res = rex.call("block.method", {
    session_id = session_id,
    block_id = block_id,
    method = "program_status",
  })
  for _, record in ipairs(res and res.result and res.result.records or res and res.records or {}) do
    if record.effective_app or record.app then
      return true
    end
  end
  return false
end

local function agents()
  local found = {}
  local listed = rex.call("session.list")
  for _, session in ipairs(listed and listed.sessions or {}) do
    local view = rex.session.view({ session_id = session.session_id })
    for _, window in ipairs(view and view.windows or {}) do
      for _, layer in ipairs(window.layers or {}) do
        if layer.kind == "tiled" then
          for _, block in ipairs(layer.blocks or {}) do
            if block.creator_name == TERMINAL and is_agent(session.session_id, block.block_id) then
              found[#found + 1] = {
                session_id = session.session_id,
                window_id = window.window_id,
                block_id = block.block_id,
              }
            end
          end
        end
      end
    end
  end
  return found
end

local function cycle_agent(ctx, step)
  local list = agents()
  if #list == 0 then
    return
  end
  local current
  for i, agent in ipairs(list) do
    if agent.block_id == ctx.block_id then
      current = i
    end
  end
  local target
  if current then
    target = list[(current - 1 + step) % #list + 1]
  else
    target = step > 0 and list[1] or list[#list]
  end
  if target.block_id == ctx.block_id then
    return
  end
  rex.session.focus_block({ session_id = target.session_id, block_id = target.block_id })
  -- focus_block only changes the server's idea of the active window; the app
  -- needs session.select to show that tab, and the session if it differs.
  rex.client.queue("session.select", {
    session_id = target.session_id,
    window_id = target.window_id,
  })
end

rex.action({
  name = "next_agent",
  title = "Focus Next Agent",
  run = function(ctx) cycle_agent(ctx, 1) end,
})

rex.action({
  name = "previous_agent",
  title = "Focus Previous Agent",
  run = function(ctx) cycle_agent(ctx, -1) end,
})

rex.bind("ctrl+cmd+]", "next_agent")
rex.bind("ctrl+cmd+[", "previous_agent")

-- herdr's prefix, with its agent keys. Ctrl+B no longer reaches the terminal on
-- its own, so Ctrl+B twice sends one through.
rex.bind("ctrl+b>a", "next_agent")
rex.bind("ctrl+b>shift+a", "previous_agent")
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })

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
