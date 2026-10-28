-- herdr plugins, run by Rex. herdr records every installed or linked plugin
-- in ~/.config/herdr/plugins.json as its full manifest (InstalledPluginInfo,
-- src/persist/plugin_registry.rs), so the plugins `herdr plugin install`
-- set up run here too, with the environment herdr gives them (docs/plugins,
-- "Commands and environment"). Installing, linking and enabling stay with
-- herdr: those calls answer `unsupported`.
--
-- Actions run detached in the plugin's directory and are logged. Panes open
-- as splits, tabs, or zoomed splits for overlay and popup placements: Rex's
-- floating layers don't draw full-screen programs yet.

local ids = require("herdr.ids")
local model = require("herdr.model")

local M = {}

local HOME = os.getenv("HOME") or ""
local CONFIG = (os.getenv("XDG_CONFIG_HOME") or (HOME .. "/.config")) .. "/herdr"
local STATE = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/herdr"

local logs = {}       -- newest last, capped
local plugin_panes = {} -- herdr pane id → { plugin_id, entrypoint }
local next_log = 1

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

-- herdr's path component for a plugin id (plugin_config_path_component).
local function component(id)
  local out = id:gsub("[^a-z0-9._%-]", function(c) return string.format("%%%02X", c:byte()) end)
  if out:sub(-1) == "." then out = out:sub(1, -2) .. "%2E" end
  return out
end

function M.dirs(plugin_id)
  return CONFIG .. "/plugins/config/" .. component(plugin_id), STATE .. "/plugins/" .. component(plugin_id)
end

local function platform_ok(item, plugin)
  local platforms = item.platforms or plugin.platforms
  if type(platforms) ~= "table" or #platforms == 0 then return true end
  local here = (os.getenv("OSTYPE") or ""):find("linux") and "linux" or "macos"
  for _, p in ipairs(platforms) do if p == here then return true end end
  return false
end

function M.list()
  local text = read(CONFIG .. "/plugins.json")
  local list = text and rex.json.decode(text)
  if type(list) ~= "table" then return {} end
  if list.plugins then list = list.plugins end
  return list
end

function M.find(plugin_id)
  for _, p in ipairs(M.list()) do if p.plugin_id == plugin_id then return p end end
end

-- Every enabled action: { plugin = p, action = a }.
function M.actions(plugin_id)
  local out = {}
  for _, p in ipairs(M.list()) do
    if p.enabled ~= false and (not plugin_id or p.plugin_id == plugin_id) then
      for _, a in ipairs(p.actions or {}) do
        if platform_ok(a, p) then out[#out + 1] = { plugin = p, action = a } end
      end
    end
  end
  return out
end

-- An action by local or qualified id ("open" or "dev.minung.herdr-f1.open").
function M.find_action(action_id, plugin_id)
  local matches = {}
  for _, entry in ipairs(M.actions(plugin_id)) do
    local qualified = entry.plugin.plugin_id .. "." .. entry.action.id
    if entry.action.id == action_id or qualified == action_id then matches[#matches + 1] = entry end
  end
  if #matches == 1 then return matches[1] end
  if #matches > 1 then return nil, "ambiguous_plugin_action" end
  return nil, "plugin_action_not_found"
end

function M.action_info(entry)
  local a = entry.action
  return {
    plugin_id = entry.plugin.plugin_id, action_id = a.id, title = a.title or a.id,
    description = a.description, contexts = a.contexts or {}, command = a.command or {}, platforms = a.platforms,
  }
end

-- The context herdr hands a plugin: the focused workspace, tab and pane.
function M.context(given)
  local ctx = given or {}
  local sid = model.focused_session()
  if sid and not ctx.workspace_id then
    local view = model.view(sid)
    ctx.workspace_id = ids.workspace(sid)
    ctx.workspace_label = view.label
    if view.active_window then
      ctx.tab_id = ids.tab(sid, view.active_window)
      ctx.tab_label = view.windows[view.active_window] and view.windows[view.active_window].label
    end
    if view.focused then
      local pane = model.pane_info(sid, view.focused, view)
      ctx.focused_pane_id = pane.pane_id
      ctx.focused_pane_cwd = pane.cwd
      ctx.focused_pane_agent = pane.agent
      ctx.focused_pane_status = pane.agent_status
    end
  end
  ctx.invocation_source = ctx.invocation_source or "api"
  return ctx
end

local function env_for(plugin, context, extra)
  local config_dir, state_dir = M.dirs(plugin.plugin_id)
  local env = {
    HERDR_ENV = "1",
    HERDR_SOCKET_PATH = M.socket,
    HERDR_PLUGIN_ID = plugin.plugin_id,
    HERDR_PLUGIN_ROOT = plugin.plugin_root,
    HERDR_PLUGIN_CONFIG_DIR = config_dir,
    HERDR_PLUGIN_STATE_DIR = state_dir,
    HERDR_PLUGIN_CONTEXT_JSON = rex.json.encode(context),
    HERDR_WORKSPACE_ID = context.workspace_id or false,
    HERDR_TAB_ID = context.tab_id or false,
    HERDR_PANE_ID = context.focused_pane_id or false,
  }
  local herdr = rex.exec({ "/bin/sh", "-c", "command -v herdr" })
  local bin = herdr and herdr.ok and herdr.stdout:gsub("%s+$", "") or ""
  if bin ~= "" then env.HERDR_BIN_PATH = bin end
  for k, v in pairs(extra or {}) do env[k] = v end
  return env, config_dir, state_dir
end

local function log_entry(fields)
  fields.log_id = tostring(next_log)
  next_log = next_log + 1
  logs[#logs + 1] = fields
  if #logs > 200 then table.remove(logs, 1) end
  return fields
end

function M.logs(plugin_id, limit)
  local out = {}
  for i = #logs, 1, -1 do
    if not plugin_id or logs[i].plugin_id == plugin_id then out[#out + 1] = logs[i] end
    if limit and #out >= limit then break end
  end
  return out
end

-- Runs an action. It is logged as running and updated when it exits.
function M.invoke(entry, context)
  local plugin, action = entry.plugin, entry.action
  context = M.context(context)
  local env, config_dir, state_dir = env_for(plugin, context, { HERDR_PLUGIN_ACTION_ID = action.id })
  rex.exec({ "mkdir", "-p", config_dir, state_dir })
  local log = log_entry({
    plugin_id = plugin.plugin_id, action_id = action.id, command = action.command,
    status = "running", started_unix_ms = os.time() * 1000,
  })
  local out, err = {}, {}
  local h, e = rex.exec.start(action.command, {
    cwd = plugin.plugin_root, env = env, detach = true,
    stdout = function(data) out[#out + 1] = data end,
    stderr = function(data) err[#err + 1] = data end,
  })
  if not h then
    log.status, log.error = "failed", tostring(e)
    return M.action_info(entry), context, log
  end
  local timer
  timer = rex.every(0.5, function()
    if h:running() then return end
    timer:cancel()
    local result = h:wait(0)
    log.status = result and result.ok and "succeeded" or "failed"
    log.exit_code = result and result.code
    log.finished_unix_ms = os.time() * 1000
    log.stdout, log.stderr = table.concat(out), table.concat(err)
  end)
  return M.action_info(entry), context, log
end

-- Opens a plugin pane where herdr would: a split, a tab, or a zoomed split
-- standing in for herdr's overlay and popup.
function M.open_pane(plugin, entrypoint, params, open)
  local pane
  for _, p in ipairs(plugin.panes or {}) do if p.id == entrypoint then pane = p end end
  if not pane then return nil, "plugin_pane_not_found" end
  local context = M.context(params.context)
  local env = env_for(plugin, context, { HERDR_PLUGIN_ENTRYPOINT_ID = entrypoint })
  local argv = { "env" }
  for k, v in pairs(env) do
    if v == false then table.insert(argv, 2, "-u"); table.insert(argv, 3, k) else argv[#argv + 1] = k .. "=" .. v end
  end
  for _, word in ipairs(pane.command or {}) do argv[#argv + 1] = word end
  local placement = params.placement or pane.placement or "overlay"
  local pane_info, err = open(argv, plugin.plugin_root, placement, params.target_pane_id)
  if not pane_info then return nil, err end
  plugin_panes[pane_info.pane_id] = { plugin_id = plugin.plugin_id, entrypoint = entrypoint }
  return { plugin_id = plugin.plugin_id, entrypoint = entrypoint, pane = pane_info }
end

function M.pane_owner(pane_id) return plugin_panes[pane_id] end
function M.forget_pane(pane_id) plugin_panes[pane_id] = nil end

-- Startup hooks run once, when the server starts.
function M.startup()
  for _, p in ipairs(M.list()) do
    if p.enabled ~= false then
      for _, hook in ipairs(p.startup or {}) do
        if platform_ok(hook, p) then
          local env, config_dir, state_dir = env_for(p, M.context(), { HERDR_PLUGIN_EVENT = "startup" })
          rex.exec({ "mkdir", "-p", config_dir, state_dir })
          rex.exec.start(hook.command, { cwd = p.plugin_root, env = env, detach = true })
        end
      end
    end
  end
end

-- Event hooks: `[[events]] on = "workspace.created"` runs its command with
-- the event as HERDR_PLUGIN_EVENT_JSON.
function M.hook(kind, data)
  local dotted = kind:gsub("_", ".", 1)
  for _, p in ipairs(M.list()) do
    if p.enabled ~= false then
      for _, hook in ipairs(p.events or {}) do
        if hook.on == dotted and platform_ok(hook, p) then
          local env = env_for(p, M.context(), { HERDR_PLUGIN_EVENT = dotted, HERDR_PLUGIN_EVENT_JSON = rex.json.encode({ event = kind, data = data }) })
          rex.exec.start(hook.command, { cwd = p.plugin_root, env = env, detach = true })
        end
      end
    end
  end
end

return M
