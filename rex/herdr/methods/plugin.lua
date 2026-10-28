-- plugin.*: herdr plugins installed with `herdr plugin install`, run by Rex
-- (herdr/plugins.lua). Installing, linking and enabling stay with herdr.
return function(H)
  local plugins, model = H.plugins, H.model
  local M = {}

  local function info(p)
    return {
      plugin_id = p.plugin_id, name = p.name or p.plugin_id, version = p.version or "",
      min_herdr_version = p.min_herdr_version or "", description = p.description,
      manifest_path = p.manifest_path or "", plugin_root = p.plugin_root or "", enabled = p.enabled ~= false,
      platforms = p.platforms, build = p.build or {}, startup = p.startup or {}, actions = p.actions or {},
      events = p.events or {}, panes = p.panes or {}, link_handlers = p.link_handlers or {},
      source = p.source or { kind = "local" }, warnings = p.warnings or {},
    }
  end

  M["plugin.list"] = function(params)
    local out = {}
    for _, p in ipairs(plugins.list()) do
      if not params.plugin_id or p.plugin_id == params.plugin_id then out[#out + 1] = info(p) end
    end
    return { type = "plugin_list", plugins = out }
  end

  M["plugin.action.list"] = function(params)
    local out = {}
    for _, entry in ipairs(plugins.actions(params.plugin_id)) do out[#out + 1] = plugins.action_info(entry) end
    return { type = "plugin_action_list", actions = out }
  end

  M["plugin.action.invoke"] = function(params)
    local entry, code = plugins.find_action(params.action_id, params.plugin_id)
    if not entry then return H.fail(code, "no plugin action " .. tostring(params.action_id)) end
    local action, context, log = plugins.invoke(entry, params.context)
    return { type = "plugin_action_invoked", action = action, context = context, log = log }
  end

  M["plugin.log.list"] = function(params)
    return { type = "plugin_log_list", logs = plugins.logs(params.plugin_id, params.limit) }
  end

  M["plugin.pane.open"] = function(params)
    local p = plugins.find(params.plugin_id)
    if not p or p.enabled == false then return H.fail("plugin_not_found", "no plugin " .. tostring(params.plugin_id)) end
    local opened, err = plugins.open_pane(p, params.entrypoint, params, H.open)
    if not opened then return H.fail(err == "plugin_pane_not_found" and err or "rex_error", tostring(err)) end
    return { type = "plugin_pane_opened", plugin_pane = opened }
  end

  M["plugin.pane.focus"] = function(params)
    local owner = plugins.pane_owner(params.pane_id)
    local p = H.pane(params.pane_id)
    if not owner or not p then return H.fail("plugin_pane_not_found", "no plugin pane " .. tostring(params.pane_id)) end
    H.focus_block(p.session_id, p.block_id)
    return { type = "plugin_pane_focused", plugin_pane = { plugin_id = owner.plugin_id, entrypoint = owner.entrypoint, pane = H.pane_info(p) } }
  end

  M["plugin.pane.close"] = function(params)
    local owner = plugins.pane_owner(params.pane_id)
    local p = H.pane(params.pane_id)
    if not owner or not p then return H.fail("plugin_pane_not_found", "no plugin pane " .. tostring(params.pane_id)) end
    rex.call("block.close", { session_id = p.session_id, block_id = p.block_id })
    plugins.forget_pane(params.pane_id)
    model.invalidate(p.session_id, p.block_id)
    return { type = "plugin_pane_closed", pane_id = params.pane_id }
  end

  return M
end
