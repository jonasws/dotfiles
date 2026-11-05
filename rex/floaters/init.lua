-- rex-floaters (https://github.com/enkelm/rex-floaters): named floating
-- terminals, one per Rex tab, that the same key shows and hides without
-- restarting the program. Loaded by init.lua after herdr.lua, so its keys
-- replace the herdr popups (zoomed splits) on the same chords.
--
-- The checkout isn't in this repo: `mise -C ~/dotfiles run sync:rex-plugins`
-- clones it at the commit in rex/plugins.lock.json, under
-- ~/.local/share/rex/plugins. Without it, this does nothing and the herdr
-- popups keep their keys.

local M = {}

local here = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")
local PLUGINS = (os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/rex/plugins"

-- Centred 80% × 80%, the size herdr/config.toml gives its popups.
local BOUNDS = { 0.1, 0.1, 0.8, 0.8 }

-- Entries are rex-floaters definitions. Ours all run floaters/run.lua, which
-- looks the command up in commands.lua by name.
local function entries()
  local out = {}
  for _, spec in ipairs(dofile(here .. "commands.lua")) do
    out[#out + 1] = {
      name = spec.name,
      title = spec.title,
      binding = spec.binding,
      category = "Floaters",
      keywords = spec.keywords,
      collect = spec.collect,
      picker = spec.picker,
      execute = here .. "run.lua",
    }
  end

  -- Bundled with rex-floaters. Pluck copies a hinted URL, path, SHA or other
  -- token from the tab's visible panes: Rex has no copy mode, and Ctrl+B e
  -- (edit_scrollback) is for longer selections.
  out[#out + 1] = {
    name = "pluck",
    title = "Pluck",
    binding = "cmd+shift+y",
    category = "Floaters",
    description = "Copy a hinted URL, path, or other token from the visible panes in this tab.",
    keywords = "pluck copy hint url path sha uuid clipboard",
    zoom = true,
    execute = "pluck/execute.lua",
  }

  -- Rex tabs across sessions with a preview of their splits, in tv. Unbound:
  -- Ctrl+B f (tv herdr-sessions) is the pane picker; this is in the palette.
  out[#out + 1] = {
    name = "rex_tabs",
    title = "Rex Tab Picker",
    category = "Floaters",
    description = "Choose a Rex tab, preview all of its splits, and focus its remembered pane.",
    keywords = "rex tab pane split session television picker",
    collect = "rex/collect.lua",
    picker = { title = "Rex tabs", backend = "tv", preview = "rex/preview.lua", skip_single = false },
    execute = "rex/execute.lua",
  }
  return out
end

function M.setup()
  package.path = PLUGINS .. "/?/init.lua;" .. package.path
  local ok, floaters = pcall(require, "rex-floaters")
  if not ok then
    rex.log("warn", "rex-floaters isn't installed; run `mise -C ~/dotfiles run sync:rex-plugins`")
    return false
  end
  floaters.setup{ bounds = BOUNDS, entries = entries() }

  -- tmux's copy-mode key, for Pluck behind the prefix too.
  rex.bind("ctrl+b>[", "floaters_pluck_toggle")
  return true
end

return M
