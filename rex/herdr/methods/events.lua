-- events.subscribe and events.wait.
return function(H)
  local events = H.events
  local M = {}

  -- Keeps the connection open and streams events (herdr/events.lua). Output
  -- subscriptions are checked on every poll.
  M["events.subscribe"] = function(params, req)
    local subscriptions = params.subscriptions or {}
    for _, s in ipairs(subscriptions) do
      if s.type == "pane.output_matched" then
        local seen
        s.check = function()
          local p = H.pane(s.pane_id)
          if not p then return nil end
          local read = H.read(p, s)
          for line in (read.text .. "\n"):gmatch("([^\n]*)\n") do
            local hit = s.match and (s.match.type == "regex" and line:find(s.match.value) or line:find(s.match.value or "", 1, true))
            if hit and line ~= seen then
              seen = line
              return { pane_id = read.pane_id, matched_line = line, read = read }
            end
          end
        end
      end
    end
    events.subscribe(req.conn, subscriptions)
    req.send({ id = req.id, result = { type = "subscription_started" } })
    return H.DEFER
  end

  -- Answers with the first event that matches, in herdr's EventMatch shape:
  -- { event = "pane_agent_status_changed", pane_id = …, agent_status = … }.
  M["events.wait"] = function(params, req)
    local match = params.match_event or {}
    local waiter = {}
    waiter.on_event = function(kind, data)
      if kind ~= match.event then return false end
      for k, v in pairs(match) do
        if k ~= "event" then
          local have = data[k]
          if have == nil and type(data.pane) == "table" then have = data.pane[k] end
          if have == nil and type(data.workspace) == "table" then have = data.workspace[k] end
          if have == nil and type(data.tab) == "table" then have = data.tab[k] end
          if have ~= v then return false end
        end
      end
      if waiter.timer then waiter.timer:cancel() end
      req.reply({ type = "wait_matched", event = { event = kind, data = data } })
      return true
    end
    if params.timeout_ms then
      waiter.timer = rex.after(params.timeout_ms / 1000, function()
        events.unwait(waiter)
        req.fail("timeout", "timed out waiting for " .. tostring(match.event))
      end)
    end
    events.wait(req.conn, waiter)
    return H.DEFER
  end

  return M
end
