-- herdr in Rex, the configuration side. Loaded by init.lua.
--
-- herdr/server.lua answers herdr's socket API from Rex (see its header), so
-- herdr tools work here unchanged: the herdr CLI, herdr-f1 and other herdr
-- plugins, and this repo's herdr scripts and tv channels. This file keeps that
-- server running, gives it herdr's command keys from herdr/config.toml behind
-- the same ctrl+b prefix, and hands each key's command what herdr would.
--
-- Panes learn the socket from fish/conf.d/45-rex-herdr.fish, so herdr tools
-- started by hand in any Rex pane work too.

local ids = require("herdr.ids")
local model = require("herdr.model")

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or
  ((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/")
local CTL = here .. "herdr/ctl"
local SHELL = "com.superlogical.terminal.shell"

local M = {}

-- Starts the server unless it answers, and returns its socket path. ctl
-- checks the socket first, so this is cheap when it is already up, and safe
-- on every reload and `rex config check`.
function M.socket()
  local r, err = rex.exec({ CTL, "ensure" }, { timeout = 15 })
  if r == nil then error(err, 0) end
  if not r.ok then error("herdr socket: " .. (r.stderr ~= "" and r.stderr or r.stdout), 0) end
  return (r.stdout:gsub("%s+$", ""))
end

-- With the server: at load, so it comes up with Rex, without waiting on it.
pcall(rex.exec.start, { CTL, "ensure" }, { detach = true })

-- The pane a key was pressed in, as herdr names it.
local function active(ctx)
  local view = model.view(ctx.session_id)
  local block = ctx.block_id and view.blocks[ctx.block_id]
  return {
    workspace = ids.workspace(ctx.session_id),
    tab = block and block.window_id and ids.tab(ctx.session_id, block.window_id) or nil,
    pane = ctx.block_id and ids.pane(ctx.session_id, ctx.block_id) or nil,
    cwd = ctx.block_id and model.block(ctx.session_id, ctx.block_id).cwd or os.getenv("HOME"),
  }
end

-- What herdr hands its command keys: HERDR_ENV, the socket, and the pane,
-- tab and directory the key was pressed in.
function M.env(ctx)
  local a = active(ctx)
  local env = { HERDR_ENV = "1", HERDR_SOCKET_PATH = M.socket(), HERDR_ACTIVE_PANE_CWD = a.cwd }
  if a.pane then env.HERDR_ACTIVE_PANE_ID = a.pane end
  if a.tab then env.HERDR_ACTIVE_TAB_ID = a.tab end
  return env
end

-- `command` through the login shell, as herdr runs command keys, so PATH has
-- mise's and Homebrew's tools.
local function argv(command, env)
  local out = { "env", "-u", "HERDR_PANE_ID", "-u", "HERDR_TAB_ID", "-u", "HERDR_WORKSPACE_ID" }
  for k, v in pairs(env) do out[#out + 1] = k .. "=" .. v end
  for _, word in ipairs({ os.getenv("SHELL") or "/bin/zsh", "-l", "-c", command }) do out[#out + 1] = word end
  return out
end

-- herdr's `type = "popup"` and `type = "pane"`: a zoomed split that closes
-- when its command exits. Rex's floating layers don't draw full-screen
-- programs yet (Rex Beta feedback "Floating layers: no backdrop, and
-- alternate-screen programs aren't drawn").
function M.popup(ctx, command)
  local split, err = rex.session.new_split{
    direction = "horizontal", side = "after", focus = true,
    layout = rex.layout.block{ flavor = SHELL, options = { command = argv(command, M.env(ctx)), shell = "none" } },
  }
  if err ~= nil then error(err, 0) end
  local id = split.block_ids and split.block_ids[1]
  if id then rex.session.zoom_block{ block_id = id, zoom = true } end
  return { block_id = id }
end

-- A popup as a floating layer, sized as herdr's width and height are (fractions
-- of the window, centred). The layer closes when its command exits. For the tv
-- pickers; Rex draws full-screen programs in layers since 2026-10-27.
function M.float(ctx, command, width, height)
  local _, err = rex.session.new_layer{
    bounds = { (1 - width) / 2, (1 - height) / 2, width, height },
    focus = true,
    layout = rex.layout.block{ flavor = SHELL, options = { command = argv(command, M.env(ctx)), shell = "none" } },
  }
  if err ~= nil then error(err, 0) end
end

-- herdr's `type = "shell"`: runs in the background with the same variables.
function M.shell(ctx, command)
  local h, err = rex.exec.start(argv(command, M.env(ctx)), { detach = true })
  if h == nil then error(err, 0) end
  return { pid = h.pid }
end

-- herdr's `type = "plugin_action"`: invokes a herdr plugin action on the
-- server, with the pane the key was pressed in as its context.
function M.plugin_action(ctx, action)
  local a = active(ctx)
  local params = rex.json.encode({ action_id = action, context = {
    workspace_id = a.workspace, tab_id = a.tab, focused_pane_id = a.pane, focused_pane_cwd = a.cwd,
    invocation_source = "keybinding",
  } })
  local r, err = rex.exec({ CTL, "call", "plugin.action.invoke", params }, { timeout = 15 })
  if r == nil then error(err, 0) end
  if not r.ok then error(r.stdout ~= "" and r.stdout or r.stderr, 0) end
end

local function command_key(name, title, kind, command, size)
  rex.action{
    name = name,
    title = title,
    category = "herdr",
    run = function(ctx)
      if kind == "popup" then return M.popup(ctx, command) end
      if kind == "float" then return M.float(ctx, command, size[1], size[2]) end
      if kind == "shell" then return M.shell(ctx, command) end
      return M.plugin_action(ctx, command)
    end,
  }
end

command_key("herdr_panes", "herdr: Pane Picker", "float", "tv herdr-sessions", { 0.9, 0.8 })
command_key("herdr_lazygit_status", "herdr: lazygit Status", "popup", "~/.config/herdr/scripts/lazygit-popup.sh status")
command_key("herdr_lazygit_log", "herdr: lazygit Log", "popup", "~/.config/herdr/scripts/lazygit-popup.sh log")
command_key("herdr_yazi", "herdr: yazi", "popup", "~/.config/herdr/scripts/yazi-popup.sh")
command_key("herdr_yazi_pick", "herdr: yazi Pick into Pane", "popup", "~/.config/herdr/scripts/yazi-popup.sh pick")
command_key("herdr_repos", "herdr: Git Repo Picker", "float", "tv git-repos -k 'enter=\"actions:rex\"'", { 0.9, 0.8 })
command_key("herdr_hotkeys", "herdr: Hotkeys", "float", "tv hotkeys", { 0.9, 0.8 })
command_key("herdr_aws", "herdr: AWS Profiles", "float", "tv aws-profiles", { 0.8, 0.8 })
command_key("herdr_tsk", "herdr: Toggle tsk Board", "shell", "~/.config/herdr/scripts/tsk-toggle.sh")
command_key("herdr_tsk_capture", "herdr: tsk Quick Capture", "plugin_action", "herdr-tsk.quick-capture")
command_key("herdr_tsk_notes", "herdr: Edit tsk Notes", "popup", "~/.config/herdr/scripts/tsk-notes.sh")
command_key("herdr_subagents", "herdr: Toggle Subagent Viewers", "shell", "bash ~/.claude/hooks/subagent-viewer.sh toggle")

rex.action{
  name = "herdr_plugin_action",
  title = "herdr: Run Plugin Action",
  category = "herdr",
  args = { action = "string" },
  run = function(ctx, args) return M.plugin_action(ctx, args.action) end,
}

-- herdr-f1: its herdr plugin when installed, else the herdr-f1 CLI. Detached,
-- since npx can take longer than an action may run.
rex.action{
  name = "herdr_f1",
  title = "Open herdr-f1 Dashboard",
  category = "F1",
  keywords = "race agents dashboard herdr browser",
  run = function()
    local h, err = rex.exec.start({ CTL, "dashboard" }, { detach = true })
    if h == nil then error(err, 0) end
    return { pid = h.pid }
  end,
}

rex.action{
  name = "herdr_f1_stop",
  title = "Stop herdr-f1 Dashboard",
  category = "F1",
  run = function() rex.exec({ CTL, "dashboard-stop" }, { timeout = 15 }) end,
}

rex.action{
  name = "herdr_restart",
  title = "herdr: Restart the herdr Socket",
  category = "herdr",
  run = function()
    rex.exec({ CTL, "stop" }, { timeout = 5 })
    return { socket = M.socket() }
  end,
}

-- A repo as a tab of this session, focused if one is already open: the Rex
-- side of television/cable/git-repos.toml's `rex` action.
rex.action{
  name = "open_repo",
  title = "Open Repo as Tab",
  category = "herdr",
  args = { path = "string" },
  run = function(ctx, args)
    local label = args.path:gsub("/+$", ""):match("([^/]+)$") or args.path
    local view = model.view(ctx.session_id)
    for _, wid in ipairs(view.window_order) do
      if view.windows[wid].label == label then
        rex.session.focus_window{ window_id = wid }
        return { window_id = wid, reused = true }
      end
    end
    local w, err = rex.session.new_window{
      layout = rex.layout.block{ flavor = SHELL, options = { cwd = args.path } },
    }
    if err ~= nil then error(err, 0) end
    rex.session.set_window_label{ window_id = w.window_id, label = label }
    return { window_id = w.window_id }
  end,
}

-- Focuses a terminal and shows its session. Moving the app to another session
-- is a client action, and from the CLI it needs Remote Control turned on in
-- the app's settings. The argument name is a guess: check `rex -C <client>
-- actions`.
local function jump(ctx, target)
  local _, err = rex.session.focus_block{ session_id = target.session_id, block_id = target.block_id }
  if err ~= nil then error(err, 0) end
  if target.session_id ~= ctx.session_id then
    local ok, queued = pcall(rex.client.queue, "session.switch", { session_id = target.session_id })
    if not ok then return { focused = true, switched = false, reason = tostring(queued) } end
  end
  return { focused = true }
end

-- herdr's next_agent and previous_agent: every agent, in session and layout
-- order, across sessions.
local function step_agent(ctx, by)
  local agents, current = {}, nil
  model.invalidate()
  model.each_pane(function(sid, bid)
    if model.agent_of(sid, bid) then
      agents[#agents + 1] = { session_id = sid, block_id = bid }
      if bid == ctx.block_id then current = #agents end
    end
  end)
  if #agents == 0 then return { agents = 0 } end
  local target = agents[current and ((current - 1 + by) % #agents) + 1 or (by > 0 and 1 or #agents)]
  return jump(ctx, target)
end

rex.action{ name = "next_agent", title = "herdr: Next Agent", category = "herdr", run = function(ctx) return step_agent(ctx, 1) end }
rex.action{ name = "previous_agent", title = "herdr: Previous Agent", category = "herdr", run = function(ctx) return step_agent(ctx, -1) end }

-- herdr/config.toml's command keys, behind the same ctrl+b prefix. Pane
-- movement stays on init.lua's Cmd chords and Ctrl+hjkl.
function M.bind()
  rex.bind("ctrl+b>f", "herdr_panes")
  rex.bind("cmd+k", "herdr_panes")
  rex.bind("ctrl+b>shift+f", "herdr_f1")
  rex.bind("ctrl+b>l", "herdr_lazygit_status")
  rex.bind("ctrl+b>shift+l", "herdr_lazygit_log")
  rex.bind("ctrl+b>y", "herdr_yazi")
  rex.bind("ctrl+b>shift+y", "herdr_yazi_pick")
  rex.bind("ctrl+b>r", "herdr_repos")
  rex.bind("ctrl+b>shift+h", "herdr_hotkeys")
  rex.bind("ctrl+b>shift+o", "herdr_aws")
  rex.bind("ctrl+b>t", "herdr_tsk")
  rex.bind("ctrl+b>ctrl+t", "herdr_tsk_capture")
  rex.bind("ctrl+b>ctrl+e", "herdr_tsk_notes")
  rex.bind("ctrl+b>shift+s", "herdr_subagents")
  rex.bind("ctrl+b>a", "next_agent")
  rex.bind("ctrl+b>shift+a", "previous_agent")
end

return M
