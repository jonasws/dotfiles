-- Rex, as herdr sees it. Reads sessions, windows and terminal blocks through
-- the Rex API and shapes them into herdr's WorkspaceInfo, TabInfo, PaneInfo,
-- AgentInfo and PaneLayoutSnapshot (herdr src/api/schema). The server's
-- event handlers mark what changed, so a burst of requests reads Rex once.
--
-- The docs don't give the shapes of session.list, session.view or the
-- terminal methods' results, so they are read defensively: anything with a
-- block_id is a block, anything with a window_id and no block_id is a
-- window, and unknown fields are ignored.

local ids = require("herdr.ids")

local M = {}

M.TERMINAL = "com.superlogical.terminal"
M.VERSION = "0.9.5+rex"
M.PROTOCOL = 22

-- ── Calling Rex ────────────────────────────────────────────────────────────

function M.session_call(method, session_id, args)
  args = args or {}
  args.session_id = session_id
  return rex.call("session." .. method, args)
end

function M.terminal(method, session_id, block_id, args)
  return rex.call(M.TERMINAL .. "." .. method, { session_id = session_id, block_id = block_id, args = args or {} })
end

local function list_of(result, key)
  if type(result) ~= "table" then return {} end
  if result[1] ~= nil then return result end
  if type(result[key]) == "table" then return result[key] end
  for _, value in pairs(result) do
    if type(value) == "table" and type(value[1]) == "table" then return value end
  end
  return {}
end
M.list_of = list_of

-- ── Cache ──────────────────────────────────────────────────────────────────
-- Everything read from Rex is kept until an event says it changed, and for
-- at most a few seconds in case an event never comes.

local MAX_AGE = 3
local cache = { sessions = nil, views = {}, blocks = {}, at = {} }
local overlay = {}    -- pane reports from herdr clients, by Rex block id
local revisions = {}  -- herdr revision counters, by Rex block id
local focus = { session = nil }

local function now() return os.time() end

local function fresh(key)
  return cache.at[key] and now() - cache.at[key] <= MAX_AGE
end

function M.invalidate(session_id, block_id)
  if block_id then
    cache.blocks[block_id] = nil
    revisions[block_id] = (revisions[block_id] or 0) + 1
  end
  if session_id then cache.views[session_id] = nil end
  if not session_id and not block_id then
    cache.sessions, cache.views, cache.blocks = nil, {}, {}
  end
end

function M.invalidate_sessions() cache.sessions = nil end

function M.note_focus(session_id) focus.session = session_id end

-- ── Reading Rex ────────────────────────────────────────────────────────────

function M.sessions()
  if cache.sessions and fresh("sessions") then return cache.sessions end
  local out = {}
  for _, s in ipairs(list_of(rex.call("session.list"), "sessions")) do
    if type(s.session_id) == "string" then out[#out + 1] = s end
  end
  cache.sessions, cache.at.sessions = out, now()
  return out
end

-- Children in a stable order: list entries first, then named fields sorted.
local function children(node)
  local out, names = {}, {}
  for _, child in ipairs(node) do
    if type(child) == "table" then out[#out + 1] = child end
  end
  for k, child in pairs(node) do
    if type(k) ~= "number" and type(child) == "table" then names[#names + 1] = k end
  end
  table.sort(names)
  for _, k in ipairs(names) do out[#out + 1] = node[k] end
  return out
end

local function focus_hint(node)
  for k, v in pairs(node) do
    if type(k) == "string" and k ~= "block_id" and type(v) == "string" and v:find("^block:")
      and (k:find("focus") or k:find("active")) then
      return v
    end
  end
  if type(node.block_id) == "string" and (node.focused == true or node.active == true) then
    return node.block_id
  end
end

local function active_window(node)
  for k, v in pairs(node) do
    if type(k) == "string" and type(v) == "string" and v:find("^window:")
      and (k:find("focus") or k:find("active")) then
      return v
    end
  end
end

local function walk(node, view, window, depth)
  local hint = focus_hint(node)
  if hint and (view.focus_depth == nil or depth < view.focus_depth) then
    view.focused, view.focus_depth = hint, depth
  end
  if type(node.block_id) == "string" then
    local block = view.blocks[node.block_id]
    if not block then
      block = { block_id = node.block_id }
      view.blocks[node.block_id] = block
      view.order[#view.order + 1] = node.block_id
    end
    if block.label == nil and type(node.label) == "string" then block.label = node.label end
    block.window_id = block.window_id or (type(node.window_id) == "string" and node.window_id) or window
    if node.zoomed == true then view.zoomed = node.block_id end
  elseif type(node.window_id) == "string" then
    window = node.window_id
    if view.windows[window] == nil then
      view.windows[window] = { window_id = window, label = node.label, node = node, blocks = {} }
      view.window_order[#view.window_order + 1] = window
    end
  end
  for _, child in ipairs(children(node)) do walk(child, view, window, depth + 1) end
end

-- One session: windows and blocks in layout order, the focused block and
-- window when the view names them, and each window's layout tree.
function M.view(session_id)
  local key = "view:" .. session_id
  if cache.views[session_id] and fresh(key) then return cache.views[session_id] end
  local raw = M.session_call("view", session_id) or {}
  local view = { session_id = session_id, label = raw.label, blocks = {}, order = {}, windows = {}, window_order = {} }
  walk(raw, view, nil, 0)
  view.active_window = active_window(raw)
  for _, bid in ipairs(view.order) do
    local w = view.blocks[bid].window_id
    if w and view.windows[w] then table.insert(view.windows[w].blocks, bid) end
  end
  if not view.active_window and view.focused and view.blocks[view.focused] then
    view.active_window = view.blocks[view.focused].window_id
  end
  view.active_window = view.active_window or view.window_order[1]
  cache.views[session_id], cache.at[key] = view, now()
  return view
end

local function normalize(entry, id)
  if type(entry) ~= "table" then return nil end
  local record = type(entry.record) == "table" and entry.record or entry
  if type(record.state) ~= "string" then return nil end
  return {
    id = entry.id or record.id or id or "",
    state = record.state, kind = record.kind, app = record.app,
    title = record.title, msg = record.msg or record.message, progress = record.progress,
  }
end
M.normalize = normalize

-- Program status records (OSC 7501) as events reported them, by block. The
-- program_status method is the source of truth; these cover a failed call.
M.records_seen = {}

local function records(session_id, block_id)
  local result = M.terminal("program_status", session_id, block_id)
  local out = {}
  if type(result) == "table" then
    local list = list_of(result, "records")
    if #list == 0 and type(result.records) == "table" then
      for id, entry in pairs(result.records) do out[#out + 1] = normalize(entry, id) end
    else
      for _, entry in ipairs(list) do out[#out + 1] = normalize(entry) end
    end
    return out
  end
  for id, record in pairs(M.records_seen[block_id] or {}) do out[#out + 1] = normalize(record, id) end
  return out
end

local function file_path(url)
  if type(url) ~= "string" then return nil end
  local path = url:match("^file://[^/]*(/.*)$") or url
  return (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- A terminal's title, working directory, foreground process and records.
function M.block(session_id, block_id)
  local key = "block:" .. block_id
  if cache.blocks[block_id] and fresh(key) then return cache.blocks[block_id] end
  local title = M.terminal("title", session_id, block_id) or {}
  local pwd = M.terminal("pwd", session_id, block_id) or {}
  local process = M.terminal("process", session_id, block_id) or {}
  local foreground = type(process.foreground) == "table" and process.foreground or {}
  local info = {
    title = title.title,
    cwd = file_path(pwd.pwd or pwd.url or pwd.path or pwd.cwd),
    process = process,
    foreground = foreground,
    records = records(session_id, block_id),
  }
  cache.blocks[block_id], cache.at[key] = info, now()
  return info
end

-- ── herdr's view ───────────────────────────────────────────────────────────

-- Rex's program states → herdr's AgentStatus. herdr has no error state; a
-- failed program needs looking at, like a blocked one.
local STATUS = { working = "working", idle = "idle", done = "done", blocked = "blocked", error = "blocked" }
local RANK = { blocked = 5, error = 4, working = 3, done = 2, idle = 1 }
-- Agent ids herdr uses, for apps Rex reports under another name.
local AGENT = { ["claude-code"] = "claude", ["codex-cli"] = "codex" }
local SHELLS = { sh = true, bash = true, zsh = true, fish = true, nu = true, login = true, dash = true, ksh = true, tcsh = true }

local function dominant(list)
  local best
  for _, r in ipairs(list) do
    if RANK[r.state] and (not best or RANK[r.state] > RANK[best.state] or (RANK[r.state] == RANK[best.state] and r.id == "")) then
      best = r
    end
  end
  return best
end

local function tilde(dir)
  local home = os.getenv("HOME")
  if dir and home and dir:sub(1, #home) == home then return "~" .. dir:sub(#home + 1) end
  return dir or ""
end

-- The agent in a block, from its status records and any herdr report.
function M.agent_of(session_id, block_id)
  local info = M.block(session_id, block_id)
  local record = dominant(info.records)
  local report = overlay[block_id]
  if report and report.state and report.agent then
    return {
      agent = report.agent, display_agent = report.display_agent or report.agent,
      status = report.state, message = report.message, title = report.title,
      state_labels = report.state_labels or (report.message and { [report.state] = report.message }) or nil,
      session = report.session, record = record,
    }
  end
  if not record then return nil end
  local app = record.app or info.foreground.name or "agent"
  local status = STATUS[record.state] or "unknown"
  local labels = (report and report.state_labels) or (record.msg and { [status] = record.msg }) or nil
  return {
    agent = AGENT[app] or app, display_agent = (report and report.display_agent) or app,
    status = status, message = record.msg, title = (report and report.title) or record.title,
    state_labels = labels, session = report and report.session, record = record,
  }
end

local function empty_to_nil(t)
  return (t and next(t)) and t or nil
end

function M.pane_info(session_id, block_id, view)
  view = view or M.view(session_id)
  local block = view.blocks[block_id] or {}
  local info = M.block(session_id, block_id)
  local agent = M.agent_of(session_id, block_id)
  local process = (info.foreground.name or ""):gsub("^%-", "")
  local stripped
  if agent then stripped = info.title
  elseif SHELLS[process] then stripped = tilde(info.cwd)
  elseif process ~= "" then stripped = (process .. " " .. tilde(info.cwd)):gsub("%s+$", "")
  else stripped = info.title end
  local report = overlay[block_id] or {}
  return {
    pane_id = ids.pane(session_id, block_id),
    terminal_id = ids.pane(session_id, block_id),
    workspace_id = ids.workspace(session_id),
    tab_id = block.window_id and ids.tab(session_id, block.window_id) or (ids.workspace(session_id) .. ":t0"),
    focused = view.focused == block_id,
    cwd = info.cwd,
    foreground_cwd = info.foreground.cwd,
    label = block.label,
    agent = agent and agent.agent or nil,
    title = report.title or (agent and agent.title) or block.label,
    terminal_title = info.title,
    terminal_title_stripped = stripped,
    display_agent = agent and agent.display_agent or nil,
    agent_status = agent and agent.status or "unknown",
    state_labels = empty_to_nil(agent and agent.state_labels),
    tokens = empty_to_nil(report.tokens),
    agent_session = agent and agent.session or nil,
    revision = revisions[block_id] or 0,
  }
end

function M.agent_info(session_id, block_id, view)
  local pane = M.pane_info(session_id, block_id, view)
  if not pane.agent then return nil end
  return {
    terminal_id = pane.terminal_id, name = pane.label, agent = pane.agent,
    title = pane.title, terminal_title = pane.terminal_title,
    terminal_title_stripped = pane.terminal_title_stripped, display_agent = pane.display_agent,
    agent_status = pane.agent_status, state_labels = pane.state_labels, tokens = pane.tokens,
    agent_session = pane.agent_session or { source = "rex", agent = pane.agent, kind = "terminal", value = pane.pane_id },
    workspace_id = pane.workspace_id, tab_id = pane.tab_id, pane_id = pane.pane_id,
    focused = pane.focused, interactive_ready = true, state_change_seq = pane.revision,
    cwd = pane.cwd, foreground_cwd = pane.foreground_cwd,
  }
end

local ROLLUP = { blocked = 5, working = 4, done = 3, idle = 2, unknown = 1 }
local function rollup(statuses)
  local best = "unknown"
  for _, s in ipairs(statuses) do
    if (ROLLUP[s] or 0) > ROLLUP[best] then best = s end
  end
  return best
end

function M.tab_info(session_id, window_id, number, view)
  view = view or M.view(session_id)
  local window = view.windows[window_id] or { blocks = {} }
  local statuses = {}
  for _, bid in ipairs(window.blocks) do
    local agent = M.agent_of(session_id, bid)
    if agent then statuses[#statuses + 1] = agent.status end
  end
  return {
    tab_id = ids.tab(session_id, window_id), workspace_id = ids.workspace(session_id),
    number = number or 1, label = window.label or "",
    focused = view.active_window == window_id and M.focused_session() == session_id,
    pane_count = #window.blocks, agent_status = rollup(statuses),
  }
end

function M.workspace_info(session, number)
  local sid = session.session_id
  local view = M.view(sid)
  local statuses = {}
  for _, bid in ipairs(view.order) do
    local agent = M.agent_of(sid, bid)
    if agent then statuses[#statuses + 1] = agent.status end
  end
  return {
    workspace_id = ids.workspace(sid), number = number, label = session.label or view.label or ids.workspace(sid),
    focused = M.focused_session() == sid, pane_count = #view.order, tab_count = #view.window_order,
    active_tab_id = view.active_window and ids.tab(sid, view.active_window) or (ids.workspace(sid) .. ":t0"),
    agent_status = rollup(statuses),
  }
end

-- The session the person is most likely looking at: the last one with a
-- focus change, else the first. Rex reports no client's current session.
function M.focused_session()
  local list = M.sessions()
  if focus.session then
    for _, s in ipairs(list) do if s.session_id == focus.session then return focus.session end end
  end
  return list[1] and list[1].session_id
end

-- ── Layout ─────────────────────────────────────────────────────────────────
-- herdr reports pane rectangles in cells. Rex's view carries a split tree but
-- not, as far as the docs say, cell sizes, so rectangles are laid out on a
-- 1000×1000 grid from the tree's ratios. Neighbours and edges only need the
-- relative positions.

local GRID = 1000

-- A split node's two sides, wherever the view keeps them: a children list,
-- a/b or first/second fields, or the node's own list entries.
local function sides(node)
  for _, key in ipairs({ "children", "panes", "items", "nodes" }) do
    if type(node[key]) == "table" and #node[key] >= 2 then return node[key] end
  end
  for _, pair in ipairs({ { "a", "b" }, { "first", "second" }, { "left", "right" }, { "top", "bottom" } }) do
    if type(node[pair[1]]) == "table" and type(node[pair[2]]) == "table" then return { node[pair[1]], node[pair[2]] } end
  end
  if #node >= 2 then return node end
end

local function split_of(node)
  if type(node) ~= "table" or node.block_id then return nil end
  local kids = sides(node)
  if not kids then return nil end
  local word = tostring(node.direction or node.axis or node.orientation or node.kind or node.type or ""):lower()
  local across = word:find("horiz") or word:find("row") or word:find("right") or word:find("left")
  local ratio = tonumber(node.ratio or node.split or node.fraction or node.size) or 0.5
  return { a = kids[1], b = kids[2], across = across ~= nil, ratio = (ratio > 0 and ratio < 1) and ratio or 0.5 }
end

local function place(node, rect, out, session_id, focused)
  if type(node) ~= "table" then return end
  if node.block_id then
    out.panes[#out.panes + 1] = { pane_id = ids.pane(session_id, node.block_id), focused = node.block_id == focused, rect = rect, block_id = node.block_id }
    return
  end
  local split = split_of(node)
  if not split then
    for _, child in ipairs(children(node)) do place(child, rect, out, session_id, focused) end
    return
  end
  if #(sides(node)) > 2 then
    -- More than two sides: equal shares along the split.
    local kids = sides(node)
    for i, child in ipairs(kids) do
      local r
      if split.across then
        local w = math.floor(rect.width / #kids)
        r = { x = rect.x + (i - 1) * w, y = rect.y, width = i == #kids and rect.width - (i - 1) * w or w, height = rect.height }
      else
        local h = math.floor(rect.height / #kids)
        r = { x = rect.x, y = rect.y + (i - 1) * h, width = rect.width, height = i == #kids and rect.height - (i - 1) * h or h }
      end
      place(child, r, out, session_id, focused)
    end
    return
  end
  local first, second
  if split.across then
    local w = math.floor(rect.width * split.ratio)
    first = { x = rect.x, y = rect.y, width = w, height = rect.height }
    second = { x = rect.x + w, y = rect.y, width = rect.width - w, height = rect.height }
  else
    local h = math.floor(rect.height * split.ratio)
    first = { x = rect.x, y = rect.y, width = rect.width, height = h }
    second = { x = rect.x, y = rect.y + h, width = rect.width, height = rect.height - h }
  end
  out.splits[#out.splits + 1] = { id = tostring(#out.splits + 1), direction = split.across and "right" or "down", ratio = split.ratio, rect = rect }
  place(split.a, first, out, session_id, focused)
  place(split.b, second, out, session_id, focused)
end

-- herdr's PaneLayoutSnapshot for one window. Blocks the tree didn't place
-- (a view without a usable tree) are stacked top to bottom.
function M.layout(session_id, window_id, view)
  view = view or M.view(session_id)
  local window = view.windows[window_id] or { blocks = {}, node = {} }
  local out = { panes = {}, splits = {} }
  place(window.node or {}, { x = 0, y = 0, width = GRID, height = GRID }, out, session_id, view.focused)
  local placed = {}
  for _, p in ipairs(out.panes) do placed[p.block_id] = true end
  local missing = {}
  for _, bid in ipairs(window.blocks) do if not placed[bid] then missing[#missing + 1] = bid end end
  if #out.panes == 0 and #missing > 0 then
    local h = math.floor(GRID / #missing)
    for i, bid in ipairs(missing) do
      out.panes[#out.panes + 1] = { pane_id = ids.pane(session_id, bid), focused = bid == view.focused, rect = { x = 0, y = (i - 1) * h, width = GRID, height = h }, block_id = bid }
    end
  end
  local focused = view.focused and view.blocks[view.focused] and view.blocks[view.focused].window_id == window_id
    and ids.pane(session_id, view.focused) or (out.panes[1] and out.panes[1].pane_id) or ""
  for _, p in ipairs(out.panes) do p.block_id = nil end
  return {
    workspace_id = ids.workspace(session_id), tab_id = ids.tab(session_id, window_id),
    zoomed = view.zoomed ~= nil and view.blocks[view.zoomed] and view.blocks[view.zoomed].window_id == window_id or false,
    area = { x = 0, y = 0, width = GRID, height = GRID },
    focused_pane_id = focused, panes = out.panes, splits = out.splits,
  }
end

-- The pane next to `pane_id` in a direction, from the layout's rectangles.
function M.neighbor(layout, pane_id, direction)
  local from
  for _, p in ipairs(layout.panes) do if p.pane_id == pane_id then from = p.rect end end
  if not from then return nil end
  local best, best_distance
  for _, p in ipairs(layout.panes) do
    local r = p.rect
    if p.pane_id ~= pane_id then
      local overlap_y = r.y < from.y + from.height and from.y < r.y + r.height
      local overlap_x = r.x < from.x + from.width and from.x < r.x + r.width
      local ok, distance
      if direction == "left" then ok, distance = overlap_y and r.x + r.width <= from.x, from.x - (r.x + r.width)
      elseif direction == "right" then ok, distance = overlap_y and r.x >= from.x + from.width, r.x - (from.x + from.width)
      elseif direction == "up" then ok, distance = overlap_x and r.y + r.height <= from.y, from.y - (r.y + r.height)
      elseif direction == "down" then ok, distance = overlap_x and r.y >= from.y + from.height, r.y - (from.y + from.height) end
      if ok and (not best or distance < best_distance) then best, best_distance = p.pane_id, distance end
    end
  end
  return best
end

local function first_leaf(node)
  if type(node) ~= "table" then return nil end
  if node.block_id then return node.block_id end
  for _, child in ipairs(children(node)) do
    local leaf = first_leaf(child)
    if leaf then return leaf end
  end
end

local function holds(node, block_id)
  if type(node) ~= "table" then return false end
  if node.block_id then return node.block_id == block_id end
  for _, child in ipairs(children(node)) do
    if holds(child, block_id) then return true end
  end
  return false
end

-- The border session.resize_pane needs to grow `block_id` toward `direction`:
-- the nearest split on that axis with the block on the opposite side. Returns
-- Rex's direction, a block on each side, and the split's current ratio.
function M.border(session_id, block_id, direction)
  local view = M.view(session_id)
  local block = view.blocks[block_id]
  local window = block and view.windows[block.window_id]
  if not window then return nil end
  local across = direction == "left" or direction == "right"
  local pane_first = direction == "right" or direction == "down"
  local found
  local function descend(node)
    local split = split_of(node)
    if split and #sides(node) == 2 then
      local in_a, in_b = holds(split.a, block_id), holds(split.b, block_id)
      if (in_a or in_b) and split.across == across and in_a == pane_first then
        found = { direction = across and "horizontal" or "vertical", before = first_leaf(split.a), after = first_leaf(split.b), ratio = split.ratio }
      end
    end
    for _, child in ipairs(children(node)) do
      if holds(child, block_id) then descend(child) end
    end
  end
  descend(window.node)
  return found
end

-- ── Finding things by herdr id ─────────────────────────────────────────────

-- herdr id → { session_id, window_id?, block_id? }, or nil.
function M.resolve(id)
  local kind, w, rest = ids.parse(id)
  if not kind then return nil end
  for _, s in ipairs(M.sessions()) do
    if ids.tail(s.session_id) == w then
      if kind == "workspace" then return { kind = kind, session_id = s.session_id } end
      local view = M.view(s.session_id)
      if kind == "tab" then
        for _, wid in ipairs(view.window_order) do
          if ids.tail(wid) == rest then return { kind = kind, session_id = s.session_id, window_id = wid } end
        end
      else
        for _, bid in ipairs(view.order) do
          if ids.tail(bid) == rest then
            return { kind = kind, session_id = s.session_id, block_id = bid, window_id = view.blocks[bid].window_id }
          end
        end
      end
    end
  end
  -- A pane is found by its own part alone, so a block that moved to another
  -- session is still found by the id a client read before the move.
  if kind == "pane" then
    for _, s in ipairs(M.sessions()) do
      local view = M.view(s.session_id)
      for _, bid in ipairs(view.order) do
        if ids.tail(bid) == rest then
          return { kind = kind, session_id = s.session_id, block_id = bid, window_id = view.blocks[bid].window_id }
        end
      end
    end
  end
  return nil
end

-- Every pane, workspace by workspace, in layout order.
function M.each_pane(fn)
  for _, s in ipairs(M.sessions()) do
    local view = M.view(s.session_id)
    for _, bid in ipairs(view.order) do fn(s.session_id, bid, view) end
  end
end

-- ── herdr clients' own reports ─────────────────────────────────────────────
-- pane.report_agent and pane.report_metadata are kept here and merged into
-- what herdr clients see. Rex has no API to set a program status record, so
-- they don't reach Rex's own indicators.

function M.report(block_id, fields)
  local r = overlay[block_id] or {}
  for k, v in pairs(fields) do
    if v == false then r[k] = nil else r[k] = v end
  end
  overlay[block_id] = next(r) and r or nil
  revisions[block_id] = (revisions[block_id] or 0) + 1
end

function M.reported(block_id) return overlay[block_id] end

return M
