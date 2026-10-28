-- ping and session.snapshot.
return function(H)
  local model = H.model
  local M = {}

  -- The version carries "+rex", as tuios's carries "+tuios", so a client can
  -- tell. The protocol is herdr's, which the herdr CLI checks before every
  -- call.
  M["ping"] = function()
    return { type = "pong", version = model.VERSION, protocol = model.PROTOCOL }
  end

  M["session.snapshot"] = function()
    local workspaces, tabs, panes, layouts, agents = {}, {}, {}, {}, {}
    local focused_pane, focused_tab
    local focused_session = model.focused_session()
    for i, s in ipairs(model.sessions()) do
      local sid = s.session_id
      local view = model.view(sid)
      workspaces[#workspaces + 1] = model.workspace_info(s, i)
      for n, wid in ipairs(view.window_order) do
        tabs[#tabs + 1] = model.tab_info(sid, wid, n, view)
        layouts[#layouts + 1] = model.layout(sid, wid, view)
      end
      for _, bid in ipairs(view.order) do
        local pane = model.pane_info(sid, bid, view)
        panes[#panes + 1] = pane
        local agent = model.agent_info(sid, bid, view)
        if agent then agents[#agents + 1] = agent end
      end
      if sid == focused_session then
        focused_pane = view.focused and H.ids.pane(sid, view.focused)
        focused_tab = view.active_window and H.ids.tab(sid, view.active_window)
      end
    end
    return { type = "session_snapshot", snapshot = {
      version = model.VERSION, protocol = model.PROTOCOL,
      focused_workspace_id = focused_session and H.ids.workspace(focused_session) or nil,
      focused_tab_id = focused_tab, focused_pane_id = focused_pane,
      workspaces = workspaces, tabs = tabs, panes = panes, layouts = layouts, agents = agents,
    } }
  end

  return M
end
