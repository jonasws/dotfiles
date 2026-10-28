-- herdr's socket API, answered by Rex. Run as
--
--   rex do ~/.config/rex/herdr/server.lua --all
--
-- (herdr/serve runs it under launchd: rex/launchd/com.jonasws.rex-herdr.plist).
-- This is tuios's approach (internal/session/herdr_api.go) for Rex: the API
-- is answered here, in Lua, against Rex's live state through the script's own
-- connection to the server, and Rex's events become herdr's. The only thing
-- outside Lua is bridge.mjs, which owns the Unix socket and passes lines:
--
--   bridge → here    R <conn> <request json>     a request
--                    G <conn>                    the client went away
--   here → bridge    S <conn> <json>             send a line, keep the connection
--                    E <conn> <json>             send a line and close
--
-- Mapping: a herdr workspace is a Rex session, a tab a window, a pane a
-- terminal block (ids.lua). Methods live in methods/*.lua. A method herdr has
-- that Rex can't do answers `unsupported`; one herdr doesn't have answers
-- `invalid_request`, as herdr and tuios do.

-- `rex do` gives a script no path of its own, so ctl passes its directory.
local here = rex.args.dir and (rex.args.dir:gsub("/*$", "/")) or debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = here .. "../?.lua;" .. package.path

local ids = require("herdr.ids")
local model = require("herdr.model")
local events = require("herdr.events")
local keys = require("herdr.keys")
local plugins = require("herdr.plugins")

local SOCKET = rex.args.socket or os.getenv("REX_HERDR_SOCKET")
  or ((os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/rex/herdr.sock")
plugins.socket = SOCKET

local SHELL_FLAVOR = "com.superlogical.terminal.shell"
local bridge

local function write(kind, conn, value)
  local text = rex.json.encode(value)
  if text and bridge then bridge:write(kind .. " " .. conn .. " " .. text .. "\n") end
end

-- ── Helpers the method tables share ────────────────────────────────────────

local H = { ids = ids, model = model, events = events, keys = keys, plugins = plugins }
H.DEFER = {}

function H.fail(code, message) return nil, code, message end

function H.pane(id)
  local found = model.resolve(id)
  if found and found.kind == "pane" then return found end
end

function H.pane_or_focused(id)
  if id then return H.pane(id) end
  local sid = model.focused_session()
  if not sid then return nil end
  local view = model.view(sid)
  local bid = view.focused or view.order[1]
  if bid then return { kind = "pane", session_id = sid, block_id = bid, window_id = view.blocks[bid].window_id } end
end

function H.pane_info(p) return model.pane_info(p.session_id, p.block_id) end

-- Tells the app to show a session and its active window. focus_block and
-- focus_window only move the server's idea of the focus; session.select is what
-- switches the app's tab (session.switch takes no session: it opens the picker).
-- A request handler has no client in scope for rex.client.queue, so the action
-- goes through `rex do`, which uses the app client when exactly one is connected.
local REX = os.getenv("REX_BIN") or "rex"

function H.show_session(session_id)
  model.note_focus(session_id)
  model.invalidate(session_id)
  local view = model.view(session_id)
  local argv = { REX, "do", "session.select", "session_id=" .. session_id }
  if view and view.active_window then argv[#argv + 1] = "window_id=" .. view.active_window end
  local h, err = rex.exec.start(argv, { detach = true })
  if not h then rex.log("warn", "herdr: cannot show session: " .. tostring(err)) end
end

function H.focus_block(session_id, block_id)
  local _, err = model.session_call("focus_block", session_id, { block_id = block_id })
  if err then return nil, err end
  H.show_session(session_id)
  return true
end

-- A terminal running the login shell, or `command`, with `env` set: herdr's
-- `env` map on pane.split, tab.create and workspace.create.
function H.terminal_layout(cwd, env, command)
  local options = { cwd = cwd }
  local argv
  if env and next(env) then
    argv = { "env" }
    for k, v in pairs(env) do argv[#argv + 1] = k .. "=" .. v end
    if command then for _, w in ipairs(command) do argv[#argv + 1] = w end
    else argv[#argv + 1] = os.getenv("SHELL") or "/bin/zsh"; argv[#argv + 1] = "-l" end
  elseif command then
    argv = command
  end
  if argv then options.command = argv; options.shell = "none" end
  return rex.layout.block{ flavor = SHELL_FLAVOR, options = options }
end

-- A split beside a block. herdr's `right` is Rex's horizontal split and
-- `down` its vertical one; the new block comes after the anchor.
function H.split(anchor, direction, layout, focus, ratio)
  local args = {
    direction = direction == "down" and "vertical" or "horizontal",
    side = "after", focus = focus ~= false, layout = layout,
  }
  if ratio then args.ratio = ratio end
  args.session_id = anchor.session_id
  args.anchor_id = anchor.block_id
  local result, err = rex.call("session.new_split", args)
  if not result then return nil, err end
  model.invalidate(anchor.session_id)
  local bid = result.block_ids and result.block_ids[1]
  if not bid then return nil, "new_split returned no block" end
  return { kind = "pane", session_id = anchor.session_id, block_id = bid }
end

-- Opens a command where a herdr plugin pane or popup would go: overlay,
-- popup and zoomed are a zoomed split, split is a split, tab a new window.
H.popups = {}
function H.open(argv, cwd, placement, target_pane_id)
  local anchor = H.pane_or_focused(target_pane_id)
  if not anchor then return nil, "pane_not_found" end
  local layout = rex.layout.block{ flavor = SHELL_FLAVOR, options = { command = argv, cwd = cwd, shell = "none" } }
  local opened
  if placement == "tab" then
    local w, err = model.session_call("new_window", anchor.session_id, { layout = layout })
    if not w then return nil, err end
    model.invalidate(anchor.session_id)
    opened = { session_id = anchor.session_id, block_id = w.block_ids and w.block_ids[1] }
  else
    local p, err = H.split(anchor, "right", layout, true)
    if not p then return nil, err end
    opened = p
    if placement ~= "split" then
      model.session_call("zoom_block", anchor.session_id, { block_id = p.block_id, zoom = true })
      table.insert(H.popups, p)
    end
  end
  if not opened.block_id then return nil, "the new terminal has no block id" end
  return model.pane_info(opened.session_id, opened.block_id)
end

-- Terminal text for pane.read and friends. `source` is herdr's ReadSource:
-- visible is the screen, recent and recent_unwrapped include scrollback.
function H.read(p, params)
  local source = params.source or "recent"
  local ansi = params.format == "ansi" and params.strip_ansi == false
  local unwrap = source == "recent_unwrapped"
  local result = model.terminal("format", p.session_id, p.block_id,
    { format = ansi and "vt" or "text", trim = true, unwrap = unwrap })
  local text = result and result.content or ""
  local lines = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  local keep = params.lines
  if source == "visible" then
    local size = model.terminal("size", p.session_id, p.block_id) or {}
    local rows = tonumber(size.rows or size.height or (size.cells and size.cells.rows))
    keep = math.min(keep or rows or #lines, rows or #lines)
  end
  local truncated = false
  if keep and #lines > keep then
    local tail = {}
    for i = #lines - keep + 1, #lines do tail[#tail + 1] = lines[i] end
    lines, truncated = tail, true
  end
  local pane = H.pane_info(p)
  return {
    pane_id = pane.pane_id, workspace_id = pane.workspace_id, tab_id = pane.tab_id,
    source = source, format = ansi and "ansi" or "text",
    text = table.concat(lines, "\n") .. (#lines > 0 and "\n" or ""),
    revision = pane.revision, truncated = truncated,
  }
end

-- Types bytes into a terminal, as if typed. Enter is not pressed for you.
function H.type(p, bytes)
  if bytes == "" then return true end
  local result, err = model.terminal("write", p.session_id, p.block_id, { data = bytes })
  if not result then return nil, err end
  return true
end

-- ── Methods ────────────────────────────────────────────────────────────────

local methods = {}
for _, name in ipairs({ "session", "workspace", "tab", "pane", "agent", "events", "plugin" }) do
  for method, fn in pairs(require("herdr.methods." .. name)(H)) do methods[method] = fn end
end

-- herdr methods Rex can't do. Anything else unknown is `invalid_request`.
local UNSUPPORTED = {
  "server.stop", "server.live_handoff", "server.reload_config", "server.ssh_agent.register",
  "server.agent_manifests", "server.reload_agent_manifests", "notification.show",
  "product_announcement.dismiss", "release_notes.dismiss", "command.invoke",
  "client.window_title.set", "client.window_title.clear", "client_shell.surface.set",
  "workspace.move", "workspace.move_block", "worktree.list", "worktree.create", "worktree.open",
  "worktree.remove", "agent.view.set", "agent.view.clear", "layout.export", "layout.apply",
  "layout.set_split_ratio", "pane.scroll", "pane.clear", "pane.edit_scrollback",
  "pane.selection.read", "pane.copy_motion", "pane.copy_search", "pane.input.set",
  "pane.link.activate", "pane.link.resolve", "integration.list", "integration.install",
  "integration.uninstall", "plugin.link", "plugin.unlink", "plugin.enable", "plugin.disable",
}
for _, name in ipairs(UNSUPPORTED) do
  if not methods[name] then
    methods[name] = function() return H.fail("unsupported", name .. " is not available on Rex") end
  end
end

-- ── Transport ──────────────────────────────────────────────────────────────

local function answer(conn, id, result, code, message)
  if result == H.DEFER then return end
  if result then
    write("E", conn, { id = id, result = result })
  else
    write("E", conn, { id = id, error = { code = code or "internal", message = message or code or "failed" } })
  end
end

local function request(conn, line)
  local req = rex.json.decode(line)
  if type(req) ~= "table" or type(req.method) ~= "string" then
    return answer(conn, type(req) == "table" and req.id or "", nil, "invalid_request", "expected a JSON request")
  end
  local fn = methods[req.method]
  if not fn then return answer(conn, req.id or "", nil, "invalid_request", "unknown method " .. req.method) end
  local ctx = {
    conn = conn, id = req.id or "",
    reply = function(result) write("E", conn, { id = req.id or "", result = result }) end,
    fail = function(code, message) write("E", conn, { id = req.id or "", error = { code = code, message = message or code } }) end,
    send = function(value) write("S", conn, value) end,
  }
  local ok, result, code, message = pcall(fn, req.params or {}, ctx)
  if not ok then return answer(conn, ctx.id, nil, "internal", tostring(result)) end
  answer(conn, ctx.id, result, code, message)
end

local buffer = ""
local function on_output(data)
  buffer = buffer .. data
  while true do
    local nl = buffer:find("\n", 1, true)
    if not nl then break end
    local line = buffer:sub(1, nl - 1)
    buffer = buffer:sub(nl + 1)
    local kind, conn, rest = line:match("^(%u) (%d+) ?(.*)$")
    if kind == "R" then
      request(conn, rest)
    elseif kind == "G" then
      events.drop(conn)
    end
  end
end

events.start(function(conn, value) write("S", conn, value) end)
events.observer = plugins.hook
events.listen()

local BRIDGE = here .. "bridge.mjs"
local node = os.getenv("REX_HERDR_NODE") or "node"
local err
bridge, err = rex.exec.start({ node, BRIDGE, SOCKET }, {
  stdin = true, detach = true, stdout = on_output,
  stderr = function(data) rex.log("warn", "herdr bridge: " .. data) end,
})
if not bridge then
  rex.log("error", "herdr: cannot start the bridge: " .. tostring(err))
  rex.stop(1)
end

events.prime()
plugins.startup()
rex.every(0.5, events.poll)
-- The bridge exits when its socket is taken or removed; the script follows it.
rex.every(2, function()
  if not bridge:running() then
    rex.log("info", "herdr: bridge stopped, exiting")
    rex.stop(0)
  end
end)
rex.log("info", "herdr: answering herdr protocol " .. model.PROTOCOL .. " on " .. SOCKET)
