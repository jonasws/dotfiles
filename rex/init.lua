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
