local os = require 'os'
local wezterm = require 'wezterm'
-- local mux = wezterm.mux
local act = wezterm.action

local config = wezterm.config_builder()

config.font = wezterm.font 'JetBrainsMono Nerd Font'
-- config.default_prog = { '/Users/jonasws/.local-fish/bin/fish', '-l' }

config.color_scheme = 'Dracula (Official)'
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false

config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = 'RESIZE'
config.font_size = 16.0
config.native_macos_fullscreen_mode = true

config.window_background_opacity = 0.80
config.macos_window_background_blur = 10

config.command_palette_bg_color = '#282a36'
config.command_palette_fg_color = '#f8f8f2'
config.command_palette_font_size = 16.0
config.command_palette_rows = 14

config.use_dead_keys = false
config.scrollback_lines = 5000

config.leader = { key = 'b', mods = 'CMD', timeout_milliseconds = 2000 }

config.keys = {
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
    key = ']',
    mods = 'SUPER',
    action = act.ActivatePaneDirection 'Next',
  },
  {
    key = '[',
    mods = 'SUPER',
    action = act.ActivatePaneDirection 'Prev',
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
