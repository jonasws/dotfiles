-- pane.*: Rex terminal blocks.
return function(H)
  local model, ids, keys, events = H.model, H.ids, H.keys, H.events
  local M = {}

  local function missing(id) return H.fail("pane_not_found", "no pane " .. tostring(id)) end

  local function layout_of(p)
    local view = model.view(p.session_id)
    local wid = p.window_id or (view.blocks[p.block_id] and view.blocks[p.block_id].window_id)
    return model.layout(p.session_id, wid, view)
  end

  local function focused_pane_id(p)
    local view = model.view(p.session_id)
    return view.focused and ids.pane(p.session_id, view.focused) or H.pane_info(p).pane_id
  end

  -- ── Reading ───────────────────────────────────────────────────────────

  M["pane.list"] = function(params)
    local out = {}
    model.each_pane(function(sid, bid, view)
      if not params.workspace_id or ids.workspace(sid) == params.workspace_id then
        out[#out + 1] = model.pane_info(sid, bid, view)
      end
    end)
    return { type = "pane_list", panes = out }
  end

  M["pane.get"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    return { type = "pane_info", pane = H.pane_info(p) }
  end

  M["pane.current"] = function(params)
    local p = H.pane_or_focused(params.caller_pane_id)
    if not p then return missing(params.caller_pane_id) end
    return { type = "pane_current", pane = H.pane_info(p) }
  end

  M["pane.read"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    return { type = "pane_read", read = H.read(p, params) }
  end

  M["pane.layout"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    return { type = "pane_layout", layout = layout_of(p) }
  end

  M["pane.neighbor"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    local layout, pane_id = layout_of(p), H.pane_info(p).pane_id
    return { type = "pane_neighbor", neighbor = {
      pane_id = pane_id, direction = params.direction,
      neighbor_pane_id = model.neighbor(layout, pane_id, params.direction), layout = layout,
    } }
  end

  M["pane.edges"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    local layout, pane_id = layout_of(p), H.pane_info(p).pane_id
    local edge = function(d) return model.neighbor(layout, pane_id, d) == nil end
    return { type = "pane_edges", edges = {
      pane_id = pane_id, left = edge("left"), right = edge("right"), up = edge("up"), down = edge("down"), layout = layout,
    } }
  end

  M["pane.process_info"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    local info = model.block(p.session_id, p.block_id)
    local proc = info.process or {}
    local fg = info.foreground or {}
    local processes = {}
    if fg.pid or fg.name then
      processes[1] = { pid = tonumber(fg.pid) or 0, name = fg.name or "", argv0 = fg.argv0, argv = fg.argv, cmdline = fg.cmdline, cwd = fg.cwd }
    end
    return { type = "pane_process_info", process_info = {
      pane_id = H.pane_info(p).pane_id,
      shell_pid = tonumber(proc.pid or proc.child_pid or (proc.child and proc.child.pid)),
      foreground_process_group_id = tonumber(fg.pgid or fg.pid),
      tty = proc.tty, foreground_processes = processes,
    } }
  end

  -- ── Typing ────────────────────────────────────────────────────────────

  M["pane.send_text"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local ok, err = H.type(p, params.text or "")
    if not ok then return H.fail("rex_error", err) end
    return { type = "ok" }
  end

  M["pane.send_keys"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local ok, err = H.type(p, keys.encode_all(params.keys))
    if not ok then return H.fail("rex_error", err) end
    return { type = "ok" }
  end

  M["pane.send_input"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local ok, err = H.type(p, (params.text or "") .. keys.encode_all(params.keys))
    if not ok then return H.fail("rex_error", err) end
    return { type = "ok" }
  end

  -- ── Layout ────────────────────────────────────────────────────────────

  M["pane.focus"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local ok, err = H.focus_block(p.session_id, p.block_id)
    if not ok then return H.fail("rex_error", err) end
    model.invalidate(p.session_id)
    return { type = "pane_info", pane = H.pane_info(p) }
  end

  M["pane.focus_direction"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    local layout, source = layout_of(p), H.pane_info(p).pane_id
    local target = model.neighbor(layout, source, params.direction)
    if target then
      local t = H.pane(target)
      if t then H.focus_block(t.session_id, t.block_id) end
      model.invalidate(p.session_id)
    end
    return { type = "pane_focus_direction", focus = {
      changed = target ~= nil, reason = target == nil and "no_neighbor" or nil,
      source_pane_id = source, focused_pane_id = target or source, layout = layout_of(p),
    } }
  end

  M["pane.split"] = function(params)
    local anchor
    if params.target_pane_id then
      anchor = H.pane(params.target_pane_id)
      if not anchor then return H.fail("target_pane_not_found", "no pane " .. params.target_pane_id) end
    else
      anchor = H.pane_or_focused(nil)
      if not anchor then return missing(nil) end
    end
    local cwd = params.cwd or model.block(anchor.session_id, anchor.block_id).cwd
    local p, err = H.split(anchor, params.direction or "right", H.terminal_layout(cwd, params.env), params.focus, params.ratio)
    if not p then return H.fail("rex_error", err) end
    return { type = "pane_info", pane = H.pane_info(p) }
  end

  M["pane.close"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local _, err = rex.call("block.close", { session_id = p.session_id, block_id = p.block_id })
    if err then return H.fail("rex_error", err) end
    H.plugins.forget_pane(params.pane_id)
    model.invalidate(p.session_id, p.block_id)
    return { type = "ok" }
  end

  M["pane.rename"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local _, err = model.session_call("set_block_label", p.session_id, { block_id = p.block_id, label = params.label or "" })
    if err then return H.fail("rex_error", err) end
    model.invalidate(p.session_id, p.block_id)
    return { type = "pane_info", pane = H.pane_info(p) }
  end

  M["pane.zoom"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    local view = model.view(p.session_id)
    local was = view.zoomed == p.block_id
    local want = params.mode == "on" or (params.mode ~= "off" and not was)
    if want ~= was then
      local _, err = model.session_call("zoom_block", p.session_id, { block_id = p.block_id, zoom = want })
      if err then return H.fail("rex_error", err) end
      model.invalidate(p.session_id)
    end
    local pane_id = H.pane_info(p).pane_id
    return { type = "pane_zoom", zoom = {
      changed = want ~= was, zoom_changed = want ~= was, focus_changed = false,
      pane_id = pane_id, focused_pane_id = focused_pane_id(p), zoomed = want, layout = layout_of(p),
    } }
  end

  M["pane.resize"] = function(params)
    local p = H.pane_or_focused(params.pane_id)
    if not p then return missing(params.pane_id) end
    local amount = params.amount and math.max(1, math.floor(params.amount)) or 3
    local border = model.border(p.session_id, p.block_id, params.direction)
    local err = border == nil and "no pane to resize against" or nil
    if border then
      local grow = (params.direction == "right" or params.direction == "down") and 1 or -1
      local _
      _, err = rex.call("session.resize_pane", {
        session_id = p.session_id, direction = border.direction,
        before_block_id = border.before, after_block_id = border.after,
        ratio = math.max(0.05, math.min(0.95, border.ratio + grow * amount / 1000)),
      })
    end
    model.invalidate(p.session_id)
    return { type = "pane_resize", resize = {
      changed = err == nil, reason = err and "rex_error" or nil,
      pane_id = H.pane_info(p).pane_id, focused_pane_id = focused_pane_id(p), layout = layout_of(p),
    } }
  end

  M["pane.swap"] = function(params)
    local source = H.pane_or_focused(params.source_pane_id or params.pane_id)
    if not source then return missing(params.source_pane_id or params.pane_id) end
    local source_id = H.pane_info(source).pane_id
    local target_id = params.target_pane_id or (params.direction and model.neighbor(layout_of(source), source_id, params.direction))
    local target = target_id and H.pane(target_id)
    if not target then
      return { type = "pane_swap", swap = { changed = false, reason = "no_target", source_pane_id = source_id,
        focused_pane_id = focused_pane_id(source), layout = layout_of(source) } }
    end
    local _, err = rex.call("session.swap_blocks",
      { session_id = source.session_id, block_id = source.block_id, other_block_id = target.block_id })
    if err then return H.fail("rex_error", err) end
    model.invalidate(source.session_id)
    return { type = "pane_swap", swap = { changed = true, source_pane_id = source_id, target_pane_id = target_id,
      focused_pane_id = focused_pane_id(source), layout = layout_of(source) } }
  end

  M["pane.move"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local dest = params.destination or {}
    local target = dest.target_pane_id and H.pane(dest.target_pane_id)
    if dest.type ~= "tab" or not target then
      return H.fail("unsupported", "Rex can move a pane beside another pane only")
    end
    local before = H.pane_info(p)
    local _, err = rex.call("session.move_block", {
      session_id = p.session_id, block_id = p.block_id, anchor_block_id = target.block_id,
      direction = dest.split == "down" and "vertical" or "horizontal", side = "after",
    })
    if err then return H.fail("rex_error", err) end
    model.invalidate(p.session_id)
    model.invalidate(target.session_id)
    local moved = H.pane(before.pane_id) or p
    return { type = "pane_move", move_result = {
      changed = true, previous_pane_id = before.pane_id, previous_workspace_id = before.workspace_id,
      previous_tab_id = before.tab_id, pane = H.pane_info(moved), target_layout = layout_of(moved),
      focused_pane_id = focused_pane_id(moved),
    } }
  end

  -- ── Waiting ───────────────────────────────────────────────────────────

  local function matcher(match)
    if type(match) ~= "table" then return function() return nil end end
    return function(text)
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if match.type == "regex" then
          -- Lua patterns stand in for regular expressions: the common
          -- subset (., *, +, ?, character classes) behaves the same.
          local ok, found = pcall(string.find, line, match.value)
          if ok and found then return line end
        elseif line:find(match.value or "", 1, true) then
          return line
        end
      end
    end
  end

  M["pane.wait_for_output"] = function(params, req)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    local find = matcher(params.match)
    local waiter = {}
    local function check()
      local read = H.read(p, params)
      local line = find(read.text)
      if line then
        req.reply({ type = "output_matched", pane_id = read.pane_id, revision = read.revision, matched_line = line, read = read })
        return true
      end
    end
    if check() then return H.DEFER end
    waiter.poll = check
    if params.timeout_ms then
      waiter.timer = rex.after(params.timeout_ms / 1000, function()
        events.unwait(waiter)
        req.fail("timeout", "timed out waiting for output match")
      end)
      local inner = waiter.poll
      waiter.poll = function()
        if inner() then waiter.timer:cancel(); return true end
      end
    end
    events.wait(req.conn, waiter)
    return H.DEFER
  end

  -- ── Reports from herdr clients ────────────────────────────────────────
  -- Agents and hooks that speak herdr's protocol (Crush, herdr integrations)
  -- report their state here. Reports from one source are ignored when their
  -- seq is not above the last one seen, as herdr does.

  local seqs = {}
  local function stale(p, params)
    if not params.seq then return false end
    local key = p.block_id .. "|" .. tostring(params.source)
    if seqs[key] and params.seq <= seqs[key] then return true end
    seqs[key] = params.seq
    return false
  end

  local function reported(p)
    events.refresh_pane(p.session_id, p.block_id)
    return { type = "ok" }
  end

  M["pane.report_agent"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    if stale(p, params) then return { type = "ok" } end
    local session
    if params.agent_session_id or params.agent_session_path then
      session = { source = params.source, agent = params.agent, kind = params.agent_session_id and "session_id" or "path",
        value = params.agent_session_id or params.agent_session_path }
    end
    model.report(p.block_id, { agent = params.agent, state = params.state, message = params.message or false,
      session = session or false, source = params.source })
    return reported(p)
  end

  M["pane.report_agent_session"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    if stale(p, params) then return { type = "ok" } end
    model.report(p.block_id, { session = { source = params.source, agent = params.agent,
      kind = params.agent_session_id and "session_id" or "path", value = params.agent_session_id or params.agent_session_path } })
    return reported(p)
  end

  M["pane.report_metadata"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    if stale(p, params) then return { type = "ok" } end
    local r = model.reported(p.block_id) or {}
    local tokens = r.tokens or {}
    for k, v in pairs(params.tokens or {}) do tokens[k] = v end
    model.report(p.block_id, {
      title = params.clear_title and false or params.title or r.title or false,
      display_agent = params.clear_display_agent and false or params.display_agent or r.display_agent or false,
      state_labels = params.clear_state_labels and false or (params.state_labels and next(params.state_labels) and params.state_labels) or r.state_labels or false,
      tokens = next(tokens) and tokens or false,
    })
    return reported(p)
  end

  M["pane.clear_agent_authority"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return missing(params.pane_id) end
    model.report(p.block_id, { agent = false, state = false, message = false, source = false })
    return reported(p)
  end

  M["pane.release_agent"] = M["pane.clear_agent_authority"]

  -- herdr plugin popups close themselves with popup.close; here a popup is a
  -- zoomed split, so the newest one still open is closed.
  M["popup.close"] = function()
    while #H.popups > 0 do
      local p = table.remove(H.popups)
      if model.view(p.session_id).blocks[p.block_id] then
        rex.call("block.close", { session_id = p.session_id, block_id = p.block_id })
        model.invalidate(p.session_id, p.block_id)
        return { type = "ok" }
      end
    end
    return H.fail("popup_not_found", "no popup is open")
  end

  return M
end
