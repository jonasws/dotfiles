local wezterm = require 'wezterm'
-- local mux = wezterm.mux
local act = wezterm.action

local catppuccin = wezterm.plugin.require 'https://github.com/catppuccin/wezterm'
local config = wezterm.config_builder()
catppuccin.apply_to_config(config, {
  flavor = 'mocha',
})

config.term = 'wezterm'

config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.line_height = 1.1

config.enable_kitty_keyboard = true
config.audible_bell = 'Disabled'
config.front_end = 'WebGpu'

config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = 'RESIZE'
config.font_size = 16.0
config.native_macos_fullscreen_mode = true

config.window_background_opacity = 0.90
config.macos_window_background_blur = 10

config.command_palette_font_size = 14.0
config.command_palette_rows = 14

config.use_dead_keys = false
config.scrollback_lines = 5000

-- config.window_padding = {
--   left = 2,
--   right = 2,
--   top = 0,
--   bottom = 0,
-- }
--

local scroll_interval = 5
config.key_tables = {
  scrolling = {
    { key = 'j', mods = 'NONE', action = act.ScrollByLine(scroll_interval) },
    { key = 'k', mods = 'NONE', action = act.ScrollByLine(-scroll_interval) },

    { key = 'u', mods = 'CTRL', action = act.ScrollByPage(-0.5) },
    { key = 'd', mods = 'CTRL', action = act.ScrollByPage(0.5) },

    { key = 'b', mods = 'CTRL', action = act.ScrollByPage(-1) },
    { key = 'f', mods = 'CTRL', action = act.ScrollByPage(1) },

    { key = 'g', mods = 'SHIFT', action = act.ScrollToBottom },
    { key = 'g', mods = 'NONE', action = act.ScrollToTop },

    { key = '/', mods = 'NONE', action = act.Search { CaseSensitiveString = '' } },
    { key = 'Escape', mods = 'NONE', action = act.PopKeyTable },
    { key = 'q', mods = 'NONE', action = act.PopKeyTable },
  },
}

config.leader = { key = 'l', mods = 'CMD', timeout_milliseconds = 2000 }

config.keys = {
  {
    key = 'Enter',
    mods = 'ALT',
    action = wezterm.action.DisableDefaultAssignment,
  },
  {
    key = 'd',
    mods = 'SUPER',
    action = act.SplitVertical { domain = 'CurrentPaneDomain' },
  },
  {
    key = 'r',
    mods = 'SUPER',
    action = act.SplitHorizontal { domain = 'CurrentPaneDomain' },
  },
  {
    key = '.',
    mods = 'SUPER',
    action = act.PaneSelect,
  },
  {
    key = 'p',
    mods = 'SUPER',
    action = act.ActivateCommandPalette,
  },
  { key = 'Enter', mods = 'LEADER', action = act.ActivateCopyMode },
  {
    key = '9',
    mods = 'ALT',
    action = act.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' },
  },
  {
    key = 'Tab',
    mods = 'ALT',
    action = act.SwitchWorkspaceRelative(1),
  },
  {
    key = 'o',
    mods = 'SUPER',
    action = act.QuickSelectArgs {
      label = 'open url',
      patterns = {
        [[https?:\/\/[^\s"'<>,]+]], -- URL with http or https, excluding trailing commas
      },
      action = wezterm.action_callback(function(window, pane)
        local url = window:get_selection_text_for_pane(pane)
        wezterm.open_with(url)
      end),
    },
  },
  {
    key = 's',
    mods = 'SUPER',
    action = act.ActivateKeyTable {
      name = 'scrolling',
      one_shot = false, -- Stays in the mode until Escape is pressed
    },
    -- action = function(window, pane)
    --   -- Store the current scroll position
    --   original_scroll_position = pane:get_scrollback_lines(0) -- Get the current scroll position
    --   -- Activate the scrolling key table
    --   window:perform_action(
    --     wezterm.action.ActivateKeyTable {
    --       name = 'scrolling',
    --       one_shot = false, -- Stay in scrolling mode until Escape is pressed
    --     },
    --     pane
    --   )
    --
    -- end,
  },
  {
    key = 'T',
    mods = 'SUPER|SHIFT',
    action = act.Search { Regex = '[0-9a-f]{32}' },
  },
}

config.ssh_domains = {
  {
    -- This name identifies the domain
    name = 'pi',
    -- The hostname or address to connect to. Will be used to match settings
    -- from your ssh config file
    remote_address = 'raspberrypi.lan',
    -- The username to use on the remote host
    username = 'pi',
  },
}

local DOMAIN_TO_SCHEME = {
  -- the keys correspond to your ssh and/or tls domain names
  ['pi'] = 'cyberpunk',
}

wezterm.on('update-status', function(window, pane)
  local domain = pane:get_domain_name()

  -- show the domain name in the right status area to aid in debugging/understanding
  window:set_right_status(domain)

  local overrides = window:get_config_overrides() or {}
  -- resolve the scheme for the domain. If there is no mapping, then the overridden
  -- scheme is cleared and your default colors will be used
  overrides.color_scheme = DOMAIN_TO_SCHEME[domain]
  window:set_config_overrides(overrides)
end)

local smart_splits = wezterm.plugin.require 'https://github.com/mrjones2014/smart-splits.nvim'
smart_splits.apply_to_config(config)

return config
