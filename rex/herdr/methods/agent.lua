-- agent.*: terminals running a program that reports its status (OSC 7501),
-- or that a herdr client reported as an agent.
return function(H)
  local model, ids, keys, events = H.model, H.ids, H.keys, H.events
  local M = {}

  -- herdr's agent target: a pane or terminal id, or an agent's name (its
  -- block label), or its kind when only one agent has it.
  local function target(name)
    local p = H.pane(name)
    if p and model.agent_of(p.session_id, p.block_id) then return p end
    local by_label, by_kind = {}, {}
    model.each_pane(function(sid, bid, view)
      local agent = model.agent_of(sid, bid)
      if agent then
        local entry = { kind = "pane", session_id = sid, block_id = bid, window_id = view.blocks[bid].window_id }
        if view.blocks[bid].label == name then by_label[#by_label + 1] = entry end
        if agent.agent == name or agent.display_agent == name then by_kind[#by_kind + 1] = entry end
      end
    end)
    if #by_label == 1 then return by_label[1] end
    if #by_label == 0 and #by_kind == 1 then return by_kind[1] end
  end

  local function info(p) return model.agent_info(p.session_id, p.block_id) end
  local function missing(name) return H.fail("agent_not_found", "no agent " .. tostring(name)) end

  M["agent.list"] = function()
    local out = {}
    model.each_pane(function(sid, bid, view)
      local a = model.agent_info(sid, bid, view)
      if a then out[#out + 1] = a end
    end)
    return { type = "agent_list", agents = out }
  end

  M["agent.get"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    return { type = "agent_info", agent = info(p) }
  end

  M["agent.explain"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    local block = model.block(p.session_id, p.block_id)
    return { type = "agent_explain", explain = {
      source = "rex", program_status = block.records, reported = model.reported(p.block_id),
      process = block.foreground, title = block.title,
    } }
  end

  M["agent.read"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    return { type = "pane_read", read = H.read(p, params) }
  end

  M["agent.focus"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    local ok, err = H.focus_block(p.session_id, p.block_id)
    if not ok then return H.fail("rex_error", err) end
    return { type = "agent_info", agent = info(p) }
  end

  M["agent.send_keys"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    local ok, err = H.type(p, keys.encode_all(params.keys))
    if not ok then return H.fail("rex_error", err) end
    return { type = "ok" }
  end

  M["agent.prompt"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    local ok, err = H.type(p, (params.text or "") .. "\r")
    if not ok then return H.fail("rex_error", err) end
    return { type = "agent_prompted", agent = info(p) }
  end

  M["agent.rename"] = function(params)
    local p = target(params.target)
    if not p then return missing(params.target) end
    local _, err = model.session_call("set_block_label", p.session_id, { block_id = p.block_id, label = params.name or "" })
    if err then return H.fail("rex_error", err) end
    model.invalidate(p.session_id, p.block_id)
    return { type = "agent_info", agent = info(p) }
  end

  -- Starts an agent by typing its command into a pane, as a person would.
  M["agent.start"] = function(params)
    local p = H.pane(params.pane_id)
    if not p then return H.fail("pane_not_found", "no pane " .. tostring(params.pane_id)) end
    local argv = { params.kind }
    for _, a in ipairs(params.args or {}) do argv[#argv + 1] = a end
    local quoted = {}
    for i, a in ipairs(argv) do quoted[i] = a:find("[^%w%-_./=:@]") and ("'" .. a:gsub("'", "'\\''") .. "'") or a end
    if params.name then model.session_call("set_block_label", p.session_id, { block_id = p.block_id, label = params.name }) end
    local ok, err = H.type(p, table.concat(quoted, " ") .. "\r")
    if not ok then return H.fail("rex_error", err) end
    model.invalidate(p.session_id, p.block_id)
    local agent = info(p) or {
      terminal_id = ids.pane(p.session_id, p.block_id), name = params.name, agent = params.kind,
      agent_status = "unknown", workspace_id = ids.workspace(p.session_id),
      tab_id = H.pane_info(p).tab_id, pane_id = ids.pane(p.session_id, p.block_id), focused = false,
    }
    return { type = "agent_started", agent = agent, argv = argv }
  end

  M["agent.wait"] = function(params, req)
    local p = target(params.target)
    if not p then return missing(params.target) end
    local wanted = {}
    for _, s in ipairs(params["until"] or {}) do wanted[s] = true end
    local pane_id = ids.pane(p.session_id, p.block_id)
    local current = info(p)
    if current and wanted[current.agent_status] then return { type = "agent_info", agent = current } end
    local waiter = {}
    waiter.on_event = function(kind, data)
      if kind == "pane_agent_status_changed" and data.pane_id == pane_id and wanted[data.agent_status] then
        if waiter.timer then waiter.timer:cancel() end
        req.reply({ type = "agent_info", agent = info(p) })
        return true
      end
    end
    if params.timeout_ms then
      waiter.timer = rex.after(params.timeout_ms / 1000, function()
        events.unwait(waiter)
        req.fail("timeout", "timed out waiting for agent status")
      end)
    end
    events.wait(req.conn, waiter)
    return H.DEFER
  end

  return M
end
