-- herdr's event stream, from Rex's. Each Rex event is translated into the
-- herdr events it means and sent to every subscription that asked for them,
-- in herdr's shape (src/api/schema/events.rs, src/api/server.rs):
--
--   lifecycle events  {"event":"pane_created","data":{"type":"pane_created",…}}
--   per-pane events   {"event":"pane.agent_status_changed","data":{…}}, only to
--                     subscriptions that name the pane
--
--   Rex event                         herdr event
--   session_created                   workspace_created
--   session_destroyed                 workspace_closed
--   session_label_changed             workspace_renamed
--   window_created / window_closed    tab_created / tab_closed
--   window_label_changed              tab_renamed
--   active_window_changed             tab_focused, workspace_focused
--   block_created / block_closed      pane_created / pane_closed
--   terminal.child_exited             pane_exited
--   terminal.title_changed, pwd, …    pane_updated (when the pane's info changed)
--   terminal.program_status_changed   pane_agent_status_changed (+ the per-pane
--                                     event), pane_agent_detected on a first record
--   session_view_changed              pane_focused when the focused block moved,
--                                     layout_updated

local ids = require("herdr.ids")
local model = require("herdr.model")

local M = {}

local subscribers = {}   -- conn → { lifecycle = set of dotted names, panes = { pane_id → status filter|true } }
local waiters = {}       -- list of { match, reply, timer }
local last = { status = {}, focused = {}, panes = {} }

local send -- set by M.start: send(conn, table)

function M.start(sender) send = sender end

function M.subscribe(conn, subscriptions)
  local sub = { lifecycle = {}, panes = {}, output = {} }
  for _, s in ipairs(subscriptions or {}) do
    if s.type == "pane.agent_status_changed" and s.pane_id then
      sub.panes[s.pane_id] = s.agent_status or true
    elseif s.type == "pane.output_matched" and s.pane_id then
      sub.output[#sub.output + 1] = s
    elseif type(s.type) == "string" then
      sub.lifecycle[s.type] = true
    end
  end
  subscribers[conn] = sub
end

function M.drop(conn)
  subscribers[conn] = nil
  for i = #waiters, 1, -1 do
    if waiters[i].conn == conn then
      if waiters[i].timer then waiters[i].timer:cancel() end
      table.remove(waiters, i)
    end
  end
end

-- events.wait / agent.wait / pane.wait_for_output register here and are
-- answered from emit() or their poll.
function M.wait(conn, waiter)
  waiter.conn = conn
  waiters[#waiters + 1] = waiter
end

function M.unwait(waiter)
  for i = #waiters, 1, -1 do if waiters[i] == waiter then table.remove(waiters, i) end end
end

-- Sends one herdr event to everyone who asked for it.
local function emit(kind, data)
  data.type = kind
  local envelope = { event = kind, data = data }
  local dotted = kind:gsub("_", ".", 1)
  for conn, sub in pairs(subscribers) do
    if sub.lifecycle[dotted] then send(conn, envelope) end
  end
  for _, w in ipairs({ unpack(waiters) }) do
    if w.on_event and w.on_event(kind, data) then M.unwait(w) end
  end
  if M.observer then pcall(M.observer, kind, data) end
end
M.emit = emit

local function emit_status(pane, previous)
  local data = {
    pane_id = pane.pane_id, workspace_id = pane.workspace_id, agent_status = pane.agent_status,
    agent = pane.agent, title = pane.title, display_agent = pane.display_agent, state_labels = pane.state_labels,
  }
  emit("pane_agent_status_changed", {
    pane_id = data.pane_id, workspace_id = data.workspace_id, agent_status = data.agent_status,
    agent = data.agent, title = data.title, display_agent = data.display_agent, state_labels = data.state_labels,
  })
  for conn, sub in pairs(subscribers) do
    local filter = sub.panes[pane.pane_id]
    if filter and (filter == true or filter == pane.agent_status) then
      send(conn, { event = "pane.agent_status_changed", data = data })
    end
  end
  if not previous and pane.agent then
    emit("pane_agent_detected", { pane_id = pane.pane_id, workspace_id = pane.workspace_id, agent = pane.agent })
  elseif previous and previous ~= "unknown" and not pane.agent then
    emit("pane_agent_detected", { pane_id = pane.pane_id, workspace_id = pane.workspace_id, released = true, final_status = previous })
  end
end

-- Compares a block with what clients last saw and sends what changed.
local function refresh_pane(session_id, block_id)
  model.invalidate(session_id, block_id)
  local view = model.view(session_id)
  if not view.blocks[block_id] then return end
  local pane = model.pane_info(session_id, block_id, view)
  local before = last.panes[pane.pane_id]
  last.panes[pane.pane_id] = pane
  local status_before = last.status[pane.pane_id]
  if status_before ~= pane.agent_status then
    last.status[pane.pane_id] = pane.agent_status
    emit_status(pane, status_before)
  end
  if before and (before.terminal_title_stripped ~= pane.terminal_title_stripped or before.cwd ~= pane.cwd
    or before.label ~= pane.label or before.title ~= pane.title) then
    emit("pane_updated", { pane = pane })
  end
end
M.refresh_pane = refresh_pane

local function workspace_of(session_id)
  for i, s in ipairs(model.sessions()) do
    if s.session_id == session_id then return model.workspace_info(s, i) end
  end
end

local function tab_number(view, window_id)
  for i, wid in ipairs(view.window_order) do if wid == window_id then return i end end
  return 1
end

-- ── Rex handlers ───────────────────────────────────────────────────────────

local handlers = {}

handlers.session_created = function(ctx, ev)
  model.invalidate_sessions()
  local sid = (ev.session and ev.session.session_id) or ev.session_id or ctx.session_id
  local w = sid and workspace_of(sid)
  if w then emit("workspace_created", { workspace = w }) end
end

handlers.session_destroyed = function(ctx, ev)
  model.invalidate_sessions()
  local sid = ev.session_id or ctx.session_id
  if sid then emit("workspace_closed", { workspace_id = ids.workspace(sid) }) end
end

handlers.session_label_changed = function(ctx, ev)
  model.invalidate_sessions()
  emit("workspace_renamed", { workspace_id = ids.workspace(ctx.session_id), label = ev.label or "" })
end

handlers.window_created = function(ctx, ev)
  model.invalidate(ctx.session_id)
  local view = model.view(ctx.session_id)
  emit("tab_created", { tab = model.tab_info(ctx.session_id, ev.window_id, tab_number(view, ev.window_id), view) })
end

handlers.window_closed = function(ctx, ev)
  model.invalidate(ctx.session_id)
  emit("tab_closed", { tab_id = ids.tab(ctx.session_id, ev.window_id), workspace_id = ids.workspace(ctx.session_id) })
end

handlers.window_label_changed = function(ctx, ev)
  model.invalidate(ctx.session_id)
  emit("tab_renamed", { tab_id = ids.tab(ctx.session_id, ev.window_id), workspace_id = ids.workspace(ctx.session_id), label = ev.label or "" })
end

handlers.active_window_changed = function(ctx, ev)
  model.invalidate(ctx.session_id)
  local changed_workspace = model.focused_session() ~= ctx.session_id
  model.note_focus(ctx.session_id)
  if changed_workspace then emit("workspace_focused", { workspace_id = ids.workspace(ctx.session_id) }) end
  emit("tab_focused", { tab_id = ids.tab(ctx.session_id, ev.window_id), workspace_id = ids.workspace(ctx.session_id) })
end

handlers.block_created = function(ctx, ev)
  model.invalidate(ctx.session_id, ev.block_id)
  local view = model.view(ctx.session_id)
  if view.blocks[ev.block_id] then
    local pane = model.pane_info(ctx.session_id, ev.block_id, view)
    last.panes[pane.pane_id] = pane
    emit("pane_created", { pane = pane })
  end
end

handlers.block_closed = function(ctx, ev)
  local pane_id = ids.pane(ctx.session_id, ev.block_id)
  model.invalidate(ctx.session_id, ev.block_id)
  last.panes[pane_id], last.status[pane_id] = nil, nil
  emit("pane_closed", { pane_id = pane_id, workspace_id = ids.workspace(ctx.session_id) })
end

handlers.session_view_changed = function(ctx)
  model.invalidate(ctx.session_id)
  local view = model.view(ctx.session_id)
  if view.focused and view.focused ~= last.focused[ctx.session_id] then
    last.focused[ctx.session_id] = view.focused
    model.note_focus(ctx.session_id)
    emit("pane_focused", { pane_id = ids.pane(ctx.session_id, view.focused), workspace_id = ids.workspace(ctx.session_id) })
  end
  for _, wid in ipairs(view.window_order) do
    emit("layout_updated", { layout = model.layout(ctx.session_id, wid, view) })
  end
end

handlers["terminal.child_exited"] = function(ctx)
  emit("pane_exited", { pane_id = ids.pane(ctx.session_id, ctx.block_id), workspace_id = ids.workspace(ctx.session_id) })
end

local function remember(ctx, ev)
  local seen = model.records_seen
  seen[ctx.block_id] = seen[ctx.block_id] or {}
  if ev.name == "program_status_removed" then
    for _, id in ipairs(ev.ids or {}) do seen[ctx.block_id][id] = nil end
  elseif type(ev.record) == "table" then
    seen[ctx.block_id][ev.id or ""] = ev.record
  end
end

handlers["terminal.program_status_changed"] = function(ctx, ev) remember(ctx, ev); refresh_pane(ctx.session_id, ctx.block_id) end
handlers["terminal.program_status_removed"] = function(ctx, ev) remember(ctx, ev); refresh_pane(ctx.session_id, ctx.block_id) end

-- Titles change with every spinner frame, so these are coalesced per block.
local pending = {}
local function later(ctx)
  local key = ctx.block_id
  if not key or pending[key] then return end
  local sid, bid = ctx.session_id, ctx.block_id
  pending[key] = rex.after(0.5, function()
    pending[key] = nil
    refresh_pane(sid, bid)
  end)
end
handlers["terminal.title_changed"] = later
handlers["terminal.pwd_changed"] = later
handlers["terminal.process_changed"] = later

-- Registers every handler with rex.on. Called once, from the script's top
-- level, since rex.on may not be called later.
function M.listen()
  for name, fn in pairs(handlers) do
    rex.on(name, function(ctx, ev)
      local ok, err = pcall(fn, ctx, ev)
      if not ok then rex.log("warn", "herdr: " .. name .. ": " .. tostring(err)) end
    end)
  end
end

-- What clients have been told so far, so the first change after startup is
-- reported against real state rather than against nothing.
function M.prime()
  model.each_pane(function(sid, bid, view)
    local pane = model.pane_info(sid, bid, view)
    last.panes[pane.pane_id] = pane
    last.status[pane.pane_id] = pane.agent_status
    if view.focused then last.focused[sid] = view.focused end
  end)
end

-- Output subscriptions and output waits are polled: Rex has no output event.
function M.poll()
  for conn, sub in pairs(subscribers) do
    for _, s in ipairs(sub.output) do
      local ok, matched = pcall(s.check)
      if ok and matched then send(conn, { event = "pane.output_matched", data = matched }) end
    end
  end
  for _, w in ipairs({ unpack(waiters) }) do
    if w.poll then
      local ok, done = pcall(w.poll)
      if ok and done then M.unwait(w) end
    end
  end
end

return M
