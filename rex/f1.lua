-- The 3D F1 dashboard, f1/f1.mjs, in a Rex tab, on ctrl+b then ctrl+f. Loaded
-- by init.lua. The dashboard reads Rex through the herdr socket
-- (herdr/server.lua), like herdr-f1 (herdr.lua).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or
  ((os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/rex/")
local LAUNCHER = here .. "f1/f1"
local SHELL = "com.superlogical.terminal.shell"

-- The first window labelled `label` in a session.view result, read
-- defensively: anything with a window_id and no block_id is a window.
local function find_window(node, label)
  if type(node) ~= "table" then return nil end
  if type(node.window_id) == "string" and node.block_id == nil and node.label == label then
    return node.window_id
  end
  for _, child in pairs(node) do
    local found = find_window(child, label)
    if found then return found end
  end
  return nil
end

-- Focuses the tab labelled `label`, or opens one running `command`.
local function open_tab(label, command)
  local view = rex.session.view{}
  local existing = view and find_window(view, label)
  if existing then
    rex.session.focus_window{ window_id = existing }
    return { window_id = existing, reused = true }
  end
  local w, err = rex.session.new_window{
    layout = rex.layout.block{ flavor = SHELL, options = { command = command } },
  }
  if err ~= nil then error(err, 0) end
  rex.session.set_window_label{ window_id = w.window_id, label = label }
  return { window_id = w.window_id }
end

rex.action{
  name = "f1",
  title = "Open F1 Dashboard",
  description = "A 3D Grand Prix of the agents in every Rex session. Reuses an open dashboard tab.",
  category = "F1",
  keywords = "race agents dashboard status 3d",
  args = { demo = "boolean?", camera = "string?" },
  run = function(ctx, args)
    local command = { LAUNCHER }
    if args.demo then command[#command + 1] = "--demo" end
    if args.camera then command[#command + 1] = "--camera=" .. args.camera end
    return open_tab("F1", command)
  end,
}

rex.bind("ctrl+b>ctrl+f", "f1")
