-- workspace.*: Rex sessions.
return function(H)
  local model, ids = H.model, H.ids
  local M = {}
  local tokens = {} -- workspace_id → reported tokens

  local function find(workspace_id)
    for i, s in ipairs(model.sessions()) do
      if ids.workspace(s.session_id) == workspace_id then return s, i end
    end
  end

  local function info(s, i)
    local w = model.workspace_info(s, i)
    if tokens[w.workspace_id] and next(tokens[w.workspace_id]) then w.tokens = tokens[w.workspace_id] end
    return w
  end

  M["workspace.list"] = function()
    local out = {}
    for i, s in ipairs(model.sessions()) do out[#out + 1] = info(s, i) end
    return { type = "workspace_list", workspaces = out }
  end

  M["workspace.get"] = function(p)
    local s, i = find(p.workspace_id)
    if not s then return H.fail("workspace_not_found", "no workspace " .. tostring(p.workspace_id)) end
    return { type = "workspace_info", workspace = info(s, i) }
  end

  M["workspace.focus"] = function(p)
    local s, i = find(p.workspace_id)
    if not s then return H.fail("workspace_not_found", "no workspace " .. tostring(p.workspace_id)) end
    H.show_session(s.session_id)
    H.events.emit("workspace_focused", { workspace_id = p.workspace_id })
    return { type = "workspace_info", workspace = info(s, i) }
  end

  M["workspace.rename"] = function(p)
    local s, i = find(p.workspace_id)
    if not s then return H.fail("workspace_not_found", "no workspace " .. tostring(p.workspace_id)) end
    local _, err = model.session_call("set_label", s.session_id, { label = p.label or "" })
    if err then return H.fail("rex_error", err) end
    model.invalidate_sessions()
    return { type = "workspace_info", workspace = info(find(p.workspace_id)) }
  end

  -- A new session, with one tab and terminal in `cwd`.
  M["workspace.create"] = function(p)
    local layout = H.terminal_layout(p.cwd, p.env)
    local created, err = rex.call("session.create", { label = p.label, initial_windows = { { layout = layout } } })
    if not created then return H.fail("rex_error", err) end
    model.invalidate_sessions()
    local sid = created.session_id or (created.session and created.session.session_id)
    if not sid then return H.fail("rex_error", "session.create returned no session id") end
    if p.focus then H.show_session(sid) end
    local s, i = find(ids.workspace(sid))
    local view = model.view(sid)
    local wid, bid = view.window_order[1], view.order[1]
    if not (s and wid and bid) then return H.fail("rex_error", "the new session has no terminal yet") end
    return { type = "workspace_created", workspace = info(s, i),
      tab = model.tab_info(sid, wid, 1, view), root_pane = model.pane_info(sid, bid, view) }
  end

  M["workspace.close"] = function(p)
    local s = find(p.workspace_id)
    if not s then return H.fail("workspace_not_found", "no workspace " .. tostring(p.workspace_id)) end
    local _, err = rex.call("session.destroy", { session_id = s.session_id })
    if err then return H.fail("rex_error", err) end
    model.invalidate_sessions()
    return { type = "ok" }
  end

  M["workspace.report_metadata"] = function(p)
    if not find(p.workspace_id) then return H.fail("workspace_not_found", "no workspace " .. tostring(p.workspace_id)) end
    local t = tokens[p.workspace_id] or {}
    for k, v in pairs(p.tokens or {}) do t[k] = v end
    tokens[p.workspace_id] = t
    local s, i = find(p.workspace_id)
    H.events.emit("workspace_metadata_updated", { workspace = info(s, i) })
    return { type = "ok" }
  end

  return M
end
