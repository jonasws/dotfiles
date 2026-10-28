-- Runs rex/herdr/server.lua against a scripted Rex. stdin carries the bridge's
-- lines (R/G), clock ticks (T), Rex events to fire (X name json) and state
-- edits (M json); stdout carries the server's lines to the bridge.
local SERVER, SOCKET = arg[1], arg[2]
package.path = arg[0]:match("^(.*/)") .. "?.lua;" .. package.path
local json = require("json")
local function log(...) io.stderr:write(table.concat({ ... }, " "), "\n") end

local S1, S2 = "session:00000000-0000-7000-8000-0000aaaa1111", "session:00000000-0000-7000-8000-0000bbbb2222"
local W1, W2, W3 = "window:00000000-0000-7000-8000-00000000c001", "window:00000000-0000-7000-8000-00000000c002", "window:00000000-0000-7000-8000-00000000c003"
local B = function(n) return string.format("block:00000000-0000-7000-8000-%012x", n) end

local state = {
  order = { S1, S2 },
  sessions = {
    [S1] = { label = "dotfiles", focused = B(1), active = W1, windows = { W1, W2 } },
    [S2] = { label = "api", focused = B(4), active = W3, windows = { W3 } },
  },
  windows = {
    [W1] = { label = "agents", layout = { kind = "split", direction = "horizontal", ratio = 0.5, children = { { block_id = B(1) }, { block_id = B(2) } } } },
    [W2] = { label = "shell", layout = { block_id = B(3) } },
    [W3] = { label = "tests", layout = { block_id = B(4) } },
  },
  blocks = {
    [B(1)] = { title = "✳ Claude Code", pwd = "file://mac/Users/me/dotfiles", fg = { name = "claude", cwd = "/Users/me/dotfiles", pid = 101 }, records = { { id = "", state = "working", app = "claude-code", msg = "Refactoring the parser" } }, screen = "hello from claude\n> doing work\n" },
    [B(2)] = { title = "fish", pwd = "file://mac/Users/me/dotfiles", fg = { name = "fish", cwd = "/Users/me/dotfiles", pid = 102 }, records = {}, screen = "$ ls\nREADME.md\n" },
    [B(3)] = { title = "nvim", pwd = "file://mac/Users/me/dotfiles/rex", fg = { name = "nvim", cwd = "/Users/me/dotfiles/rex", pid = 103 }, records = {}, screen = "nvim screen\n" },
    [B(4)] = { title = "codex", pwd = "file://mac/Users/me/api", fg = { name = "node", cwd = "/Users/me/api", pid = 104 }, records = { { id = "", state = "blocked", kind = "permission", app = "codex", msg = "Allow Bash(rm -rf build)?" } }, screen = "codex asks\n" },
  },
  next_block = 100, next_window = 100, next_session = 100,
}

local handlers, timers, now = {}, {}, 0
local bridge_cb
local calls = {}

local function fire(name, ctx, ev)
  ev = ev or {}
  for _, fn in ipairs(handlers[name] or {}) do fn(ctx, ev) end
end

local function find_leaf(node, bid, parent, key)
  if type(node) ~= "table" then return nil end
  if node.block_id == bid then return node, parent, key end
  for i, child in ipairs(node.children or {}) do
    local a, b, c = find_leaf(child, bid, node, i)
    if a then return a, b, c end
  end
end

local function window_of(bid)
  for wid, w in pairs(state.windows) do if find_leaf(w.layout, bid) then return wid end end
end

local function session_of_window(wid)
  for sid, s in pairs(state.sessions) do for _, w in ipairs(s.windows) do if w == wid then return sid end end end
end

local function labelled(node)
  if type(node) ~= "table" then return node end
  if node.block_id then return { block_id = node.block_id, label = state.blocks[node.block_id] and state.blocks[node.block_id].label } end
  local out = {}
  for k, v in pairs(node) do out[k] = k == "children" and {} or v end
  for i, c in ipairs(node.children or {}) do out.children[i] = labelled(c) end
  return out
end

local function view(sid)
  local s = state.sessions[sid]
  local windows = {}
  for _, wid in ipairs(s.windows) do
    windows[#windows + 1] = { window_id = wid, label = state.windows[wid].label, layout = labelled(state.windows[wid].layout) }
  end
  return { session_id = sid, label = s.label, active_window_id = s.active, focused_block_id = s.focused, windows = windows }
end

local function new_block(bid, title)
  state.blocks[bid] = { title = title or "fish", pwd = "file://mac/Users/me", fg = { name = "fish", cwd = "/Users/me", pid = 200 }, records = {}, screen = "$ \n" }
end

local TERMINAL = "com.superlogical.terminal."
local api = {}
api["session.list"] = function()
  local out = {}
  for _, sid in ipairs(state.order) do out[#out + 1] = { session_id = sid, label = state.sessions[sid].label } end
  return { sessions = out }
end
api["session.view"] = function(a) return state.sessions[a.session_id] and view(a.session_id) or nil, "session_not_found" end
api[TERMINAL .. "title"] = function(a) return { title = state.blocks[a.block_id].title } end
api[TERMINAL .. "pwd"] = function(a) return { pwd = state.blocks[a.block_id].pwd } end
api[TERMINAL .. "process"] = function(a) return { pid = 50, foreground = state.blocks[a.block_id].fg } end
api[TERMINAL .. "program_status"] = function(a) return { records = state.blocks[a.block_id].records } end
api[TERMINAL .. "format"] = function(a) return { content = state.blocks[a.block_id].screen } end
api[TERMINAL .. "size"] = function() return { rows = 2, cols = 80 } end
api[TERMINAL .. "write"] = function(a)
  if a.args.data == nil then return nil, "bad_request: data is required" end
  local b = state.blocks[a.block_id]
  b.screen = b.screen .. a.args.data
  return { written = #a.args.data }
end
api["session.focus_block"] = function(a)
  state.sessions[a.session_id].focused = a.block_id
  state.sessions[a.session_id].active = window_of(a.block_id)
  fire("session_view_changed", { session_id = a.session_id }, { revision = 1 })
  return { revision = 1 }
end
api["session.focus_window"] = function(a) state.sessions[a.session_id].active = a.window_id; fire("active_window_changed", { session_id = a.session_id }, { window_id = a.window_id }); return {} end
api["session.set_window_label"] = function(a) state.windows[a.window_id].label = a.label; fire("window_label_changed", { session_id = a.session_id }, { window_id = a.window_id, label = a.label }); return {} end
api["session.set_block_label"] = function(a) state.blocks[a.block_id].label = a.label; return {} end
api["session.set_label"] = function(a) state.sessions[a.session_id].label = a.label; fire("session_label_changed", { session_id = a.session_id }, { label = a.label }); return {} end
api["session.zoom_block"] = function(a) state.sessions[a.session_id].zoomed = a.zoom and a.block_id or nil; return {} end
api["session.new_split"] = function(a)
  local sid = a.session_id
  local anchor = a.block_id or state.sessions[sid].focused
  local wid = window_of(anchor)
  state.next_block = state.next_block + 1
  local bid = B(state.next_block)
  local leaf, parent, key = find_leaf(state.windows[wid].layout, anchor)
  local split = { kind = "split", direction = a.direction, ratio = 0.5, children = { { block_id = anchor }, { block_id = bid } } }
  if parent then parent.children[key] = split else state.windows[wid].layout = split end
  new_block(bid)
  if a.focus then state.sessions[sid].focused = bid end
  fire("block_created", { session_id = sid }, { block_id = bid })
  fire("session_view_changed", { session_id = sid }, { revision = 2 })
  return { block_ids = { bid }, anchor_block_id = anchor }
end
api["session.new_window"] = function(a)
  state.next_window = state.next_window + 1
  state.next_block = state.next_block + 1
  local wid = string.format("window:00000000-0000-7000-8000-%012x", state.next_window)
  local bid = B(state.next_block)
  state.windows[wid] = { label = "", layout = { block_id = bid } }
  table.insert(state.sessions[a.session_id].windows, wid)
  new_block(bid)
  fire("window_created", { session_id = a.session_id }, { window_id = wid })
  fire("block_created", { session_id = a.session_id }, { block_id = bid })
  return { window_id = wid, block_ids = { bid } }
end
api["session.create"] = function(a)
  state.next_session = state.next_session + 1
  state.next_window = state.next_window + 1
  state.next_block = state.next_block + 1
  local sid = string.format("session:00000000-0000-7000-8000-%012x", state.next_session)
  local wid = string.format("window:00000000-0000-7000-8000-%012x", state.next_window)
  local bid = B(state.next_block)
  state.windows[wid] = { label = "", layout = { block_id = bid } }
  state.sessions[sid] = { label = a.label or "new", focused = bid, active = wid, windows = { wid } }
  table.insert(state.order, sid)
  new_block(bid)
  fire("session_created", {}, { session = { session_id = sid, label = a.label } })
  return { session_id = sid }
end
api["block.close"] = function(a)
  local wid = window_of(a.block_id)
  local leaf, parent, key = find_leaf(state.windows[wid].layout, a.block_id)
  if parent then table.remove(parent.children, key); if #parent.children == 1 then for k, v in pairs(parent.children[1]) do parent[k] = v end; parent.children = parent.children[1].children; parent.kind = parent.children and "split" or nil end end
  state.blocks[a.block_id] = nil
  fire("block_closed", { session_id = a.session_id }, { block_id = a.block_id })
  return {}
end

rex = {
  args = { socket = SOCKET },
  json = json,
  log = function(level, msg) log("[" .. tostring(level) .. "]", tostring(msg)) end,
  stop = function(code) log("rex.stop", tostring(code)); os.exit(code or 0) end,
  on = function(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end,
  call = function(method, args)
    calls[#calls + 1] = method
    local fn = api[method]
    if not fn then return nil, "method_not_found: " .. method end
    local ok, r, e = pcall(fn, args or {})
    if not ok then return nil, tostring(r) end
    return r, e
  end,
  layout = { block = function(t) return t end },
  client = { queue = function(name, args) log("client.queue", name, json.encode(args)) end },
}
local function timer(at, every, fn)
  local t = { at = at, every = every, fn = fn, live = true }
  function t:cancel() self.live = false end
  function t:active() return self.live end
  timers[#timers + 1] = t
  return t
end
rex.after = function(s, fn) return timer(now + s, nil, fn) end
rex.every = function(s, fn) return timer(now + s, s, fn) end
rex.exec = setmetatable({
  start = function(argv, opts)
    if tostring(argv[2]):find("bridge%.mjs$") then
      bridge_cb = opts.stdout
      return { pid = 1, write = function(_, data) io.stdout:write(data); io.stdout:flush(); return true end, running = function() return true end }
    end
    log("exec.start", table.concat(argv, " "), "cwd=" .. tostring(opts and opts.cwd))
    local env = {}
    for k, v in pairs(opts and opts.env or {}) do if v ~= false then env[#env + 1] = k .. "='" .. tostring(v):gsub("'", "'\\''") .. "'" end end
    local q = {}
    for i, a in ipairs(argv) do q[i] = "'" .. a:gsub("'", "'\\''") .. "'" end
    os.execute("cd '" .. tostring(opts and opts.cwd or ".") .. "' && env " .. table.concat(env, " ") .. " " .. table.concat(q, " ") .. " >/dev/null 2>&1 &")
    return { pid = 2, running = function() return false end, wait = function() return { ok = true, code = 0 } end }
  end,
}, { __call = function(_, argv)
  local q = {}
  for i, a in ipairs(argv) do q[i] = "'" .. a:gsub("'", "'\\''") .. "'" end
  local p = io.popen(table.concat(q, " ") .. " 2>/dev/null")
  local out = p:read("*a")
  local ok = p:close()
  return { ok = ok == true or ok == 0, code = 0, stdout = out, stderr = "" }
end })

dofile(SERVER)
log("harness: server loaded")

local function run_timers()
  for _, t in ipairs({ unpack(timers) }) do
    if t.live and t.at <= now then
      if t.every then t.at = now + t.every else t.live = false end
      local ok, err = pcall(t.fn, {})
      if not ok then log("timer error", tostring(err)) end
    end
  end
end

for line in io.lines() do
  local kind = line:sub(1, 1)
  if kind == "T" then
    now = now + 0.1
    run_timers()
  elseif kind == "X" then
    local name, rest = line:match("^X (%S+) (.*)$")
    local ev = json.decode(rest)
    fire(name, ev.ctx or {}, ev.ev or {})
  elseif kind == "M" then
    local edit = json.decode(line:sub(3))
    local b = state.blocks[edit.block_id]
    for k, v in pairs(edit.set or {}) do b[k] = v end
    if edit.records_empty then b.records = {} end
  elseif bridge_cb and (kind == "R" or kind == "G") then
    local ok, err = pcall(bridge_cb, line .. "\n")
    if not ok then log("request error", tostring(err)) end
  end
end
