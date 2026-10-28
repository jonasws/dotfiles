-- tab.*: Rex windows.
return function(H)
  local model, ids = H.model, H.ids
  local M = {}

  local function find(tab_id)
    local found = model.resolve(tab_id)
    if found and found.kind == "tab" then return found end
  end

  local function number(view, wid)
    for i, w in ipairs(view.window_order) do if w == wid then return i end end
    return 1
  end

  local function info(t)
    local view = model.view(t.session_id)
    return model.tab_info(t.session_id, t.window_id, number(view, t.window_id), view)
  end

  local function missing(id) return H.fail("tab_not_found", "no tab " .. tostring(id)) end

  M["tab.list"] = function(p)
    local out = {}
    for _, s in ipairs(model.sessions()) do
      if not p.workspace_id or ids.workspace(s.session_id) == p.workspace_id then
        local view = model.view(s.session_id)
        for n, wid in ipairs(view.window_order) do out[#out + 1] = model.tab_info(s.session_id, wid, n, view) end
      end
    end
    return { type = "tab_list", tabs = out }
  end

  M["tab.get"] = function(p)
    local t = find(p.tab_id)
    if not t then return missing(p.tab_id) end
    return { type = "tab_info", tab = info(t) }
  end

  M["tab.focus"] = function(p)
    local t = find(p.tab_id)
    if not t then return missing(p.tab_id) end
    local _, err = model.session_call("focus_window", t.session_id, { window_id = t.window_id })
    if err then return H.fail("rex_error", err) end
    H.show_session(t.session_id)
    model.invalidate(t.session_id)
    return { type = "tab_info", tab = info(t) }
  end

  M["tab.rename"] = function(p)
    local t = find(p.tab_id)
    if not t then return missing(p.tab_id) end
    local _, err = model.session_call("set_window_label", t.session_id, { window_id = t.window_id, label = p.label or "" })
    if err then return H.fail("rex_error", err) end
    model.invalidate(t.session_id)
    return { type = "tab_info", tab = info(t) }
  end

  M["tab.close"] = function(p)
    local t = find(p.tab_id)
    if not t then return missing(p.tab_id) end
    local _, err = model.session_call("close_window", t.session_id, { window_id = t.window_id })
    if err then return H.fail("rex_error", err) end
    model.invalidate(t.session_id)
    return { type = "ok" }
  end

  M["tab.move"] = function(p)
    local t = find(p.tab_id)
    if not t then return missing(p.tab_id) end
    local others = {}
    for _, wid in ipairs(model.view(t.session_id).window_order) do
      if wid ~= t.window_id then others[#others + 1] = wid end
    end
    local _, err = rex.call("session.move_window", {
      session_id = t.session_id, window_id = t.window_id,
      before_window_id = others[(tonumber(p.insert_index) or #others) + 1],
    })
    if err then return H.fail("rex_error", err) end
    model.invalidate(t.session_id)
    return { type = "tab_info", tab = info(t) }
  end

  M["tab.create"] = function(p)
    local sid
    if p.workspace_id then
      for _, s in ipairs(model.sessions()) do
        if ids.workspace(s.session_id) == p.workspace_id then sid = s.session_id end
      end
      if not sid then return H.fail("workspace_not_found", "no workspace " .. p.workspace_id) end
    else
      sid = model.focused_session()
    end
    if not sid then return H.fail("workspace_not_found", "no workspace to open a tab in") end
    local w, err = model.session_call("new_window", sid, { layout = H.terminal_layout(p.cwd, p.env) })
    if not w then return H.fail("rex_error", err) end
    if p.label and w.window_id then
      model.session_call("set_window_label", sid, { window_id = w.window_id, label = p.label })
    end
    model.invalidate(sid)
    local view = model.view(sid)
    local wid = w.window_id or view.window_order[#view.window_order]
    local bid = (w.block_ids and w.block_ids[1]) or (view.windows[wid] and view.windows[wid].blocks[1])
    if p.focus then H.show_session(sid) end
    if not (wid and bid) then return H.fail("rex_error", "the new tab has no terminal yet") end
    return { type = "tab_created", tab = model.tab_info(sid, wid, number(view, wid), view), root_pane = model.pane_info(sid, bid, view) }
  end

  return M
end
