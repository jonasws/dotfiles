local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- Catppuccin Mocha (modified). The scheme's ANSI blue (index 4) is Mocha
-- "Blue" #89b4fa — a pastel at ~76% lightness. Fine as foreground text,
-- but unreadable as a *background*: apps like mitmproxy paint light fg on
-- ANSI-blue bg, giving light-on-light. Extend the built-in scheme and
-- swap ANSI 4 for a darker navy. Bright blue (index 12) stays at spec, so
-- blue *text* keeps its pastel look.
-- local mocha = wezterm.color.get_builtin_schemes()['Catppuccin Mocha']
-- mocha.ansi[5] = '#3b5a8a' -- ANSI 4 (Lua 1-based index): darker navy for bg use
-- -- Mocha sets ANSI 0 ("black") = #45475a (Surface1), a grey-purple so that
-- -- black *text* stays visible. But TUIs built on tview/tcell (e.g. otel-tui)
-- -- fill their panel *background* with tcell.ColorBlack = ANSI 0, so that
-- -- grey-purple bleeds across the whole UI. Pin ANSI 0 to Mocha Base #1e1e2e
-- -- (the terminal background) so those panel fills blend into the window and the
-- -- background blur shows through, instead of harsh true black or grey-purple.
-- -- Bright black (index 8) keeps Mocha's Surface for dimmed text.
-- mocha.ansi[1] = '#1e1e2e' -- ANSI 0 (Lua 1-based index): match bg so TUI fills blend
-- config.color_schemes = {
--   ['Catppuccin Mocha (dark ANSI blue)'] = mocha,
--   ['Catppuccin Mocha (ANSI 0 = base)'] = mocha,
-- }
-- config.color_scheme = 'Catppuccin Mocha (dark ANSI blue)'
config.color_scheme = 'Catppuccin Mocha'

config.set_environment_variables = {
  TERMINFO_DIRS = os.getenv 'HOME' .. '/.terminfo',
}

config.term = 'wezterm'

config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false

config.enable_kitty_keyboard = false
config.audible_bell = 'Disabled'
config.front_end = 'WebGpu'

config.adjust_window_size_when_changing_font_size = false
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = 'RESIZE'
-- Use the "Mono" Nerd Font variant for both text and powerline/icon glyphs.
-- The plain "JetBrainsMono Nerd Font" build patches in icon glyphs with
-- inflated vertical metrics (and double-width cells) that overshoot the cell
-- box, clipping glyph tops/bottoms as the screen scrolls. The "...Nerd Font
-- Mono" build clamps every glyph to a single constrained cell, so ascenders
-- and descenders stay inside the row and nothing is cropped on scroll.
-- Text from plain "JetBrains Mono" (clean, spec-compliant vertical metrics);
-- icon/powerline glyphs fall back to the "Nerd Font Mono" build, which clamps
-- every glyph to a single constrained cell. The non-Mono Nerd Font builds patch
-- in icons with inflated vertical metrics that overshoot the cell box and clip
-- glyph tops/bottoms on scroll (wezterm #6785) — so they are deliberately NOT in
-- the fallback chain.
config.font = wezterm.font_with_fallback {
  'JetBrains Mono',
  'JetBrainsMono Nerd Font Mono',
}
config.font_size = 18.0
-- Keep line_height integer (1.0). JetBrainsMono has tight vertical metrics, so
-- any fractional line_height lands the cell off the pixel grid and clips glyph
-- tops/bottoms on scroll (wezterm #6785). Pills are flatter as a result — that's
-- the tradeoff for a clip-free render; a taller cell would need a bigger font.
config.line_height = 1.0

config.native_macos_fullscreen_mode = true

config.window_background_opacity = 0.90
config.macos_window_background_blur = 10

config.command_palette_font_size = 14.0
config.command_palette_rows = 14
config.command_palette_bg_color = '#181825' -- Mocha Mantle
config.command_palette_fg_color = '#cdd6f4' -- Mocha Text

-- Norwegian chars (æ ø å) compose via Option/Alt elsewhere in macOS (Safari,
-- Slack, Notes, ...) through the OS input source, unaffected by this file.
-- Inside WezTerm specifically, both Option keys send Meta/ESC instead of
-- OS-composed characters, so <M-h>-style terminal keybindings (Neovim,
-- snacks picker, etc.) register. use_dead_keys stays true so dead-key
-- composition still works for the rare case send_composed_key is on.
config.use_dead_keys = true
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false
config.scrollback_lines = 100000
config.notification_handling = 'SuppressFromFocusedTab'

-- Add hyperlink rules for Firefox container URLs
config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, {
  -- Pattern matches ext+container: followed by parameters
  regex = [[ext\+container:(?:name=[^&\s]+)(?:&[a-zA-Z]+=(?:[^&\s]+))*]],
  format = '$0',
})

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
  -- Escape hatch out of a nested multiplexer. herdr's nav_at_edge is only
  -- 'wrap' or 'stop' — neither hands the chord back to the outer terminal — so
  -- CTRL+hjkl can never cross from a herdr pane to a sibling WezTerm pane.
  -- LEADER+hjkl always moves WezTerm panes, whatever runs inside them.
  { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
  { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
  { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
  { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
  -- Claude Code integration: Enable Shift+Enter for multiline input.
  -- Sends ESC+CR (alt+Enter), not a bare LF. A bare LF is byte 0x0A, which is
  -- indistinguishable from ctrl+j without the kitty keyboard protocol (disabled
  -- above), so herdr's direct ctrl+j binding (herdr-splits.nav-down) swallowed it
  -- and the newline never reached the pane. Nothing binds alt+Enter in herdr, and
  -- ALT+Enter's WezTerm default is disabled above, so ESC+CR passes through clean.
  {
    key = 'Enter',
    mods = 'SHIFT',
    action = act.SendString '\x1b\r',
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
        [[ext\+container:(?:name=[^&\s]+)(?:&[a-zA-Z]+=(?:[^&\s]+))*]], -- Firefox container URLs
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

-- config.ssh_domains = {
--   {
--     -- This name identifies the domain
--     name = 'pi',
--     -- The hostname or address to connect to. Will be used to match settings
--     -- from your ssh config file
--     remote_address = 'raspberrypi.local',
--     -- The username to use on the remote host
--     username = 'pi',
--   },
-- }
--
-- local DOMAIN_TO_SCHEME = {
--   -- the keys correspond to your ssh and/or tls domain names
--   ['pi'] = 'cyberpunk',
-- }
--
-- wezterm.on('update-status', function(window, pane)
--   local domain = pane:get_domain_name()
--
--   -- show the domain name in the right status area to aid in debugging/understanding
--   window:set_right_status(domain)
--
--   local overrides = window:get_config_overrides() or {}
--   -- resolve the scheme for the domain. If there is no mapping, then the overridden
--   -- scheme is cleared and your default colors will be used
--   overrides.color_scheme = DOMAIN_TO_SCHEME[domain]
--   window:set_config_overrides(overrides)
-- end)

-- Smart split navigation, hand-rolled rather than via
-- smart-splits.nvim's apply_to_config. That helper's is_vim predicate only
-- checks the IS_NVIM user var, which herdr neither sets nor proxies out from
-- the Neovim running inside its panes — so under herdr WezTerm would decide
-- "not vim", claim CTRL+hjkl for itself, and herdr-splits would never see a
-- keypress. apply_to_config exposes no way to override that predicate
-- (only default_amount / direction_keys / modifiers / log_level), so the
-- bindings are built here instead.
--
-- Move is CTRL, resize is CTRL+SHIFT. Resize deliberately avoids the plugin's
-- META default: Option is the us-altgr-intl compose layer (Option+l is ø) and
-- must stay free for text input. Keep in sync with herdr's config.toml and
-- lazyvim/.../config/keymaps.lua, which bind the same two chord families.

---Panes that own these chords themselves, so WezTerm must forward rather than act:
---  * Neovim directly in a WezTerm pane — smart-splits.nvim sets IS_NVIM, and
---    handles crossing back out to WezTerm itself via `wezterm cli`.
---  * herdr — its own ctrl+hjkl / ctrl+shift+hjkl bindings drive herdr-splits,
---    which in turn reaches any Neovim nested inside a herdr pane.
local function pane_owns_splits(pane)
  if pane:get_user_vars().IS_NVIM == 'true' then
    return true
  end
  -- nil for panes WezTerm can't introspect (ssh/mux domains); those fall
  -- through to WezTerm-side movement, which is the right default there.
  local proc = pane:get_foreground_process_name()
  return proc ~= nil and proc:match '[/\\]herdr$' ~= nil
end

local function split_nav(kind, key, direction)
  local mods = kind == 'resize' and 'CTRL|SHIFT' or 'CTRL'
  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(win, pane)
      if pane_owns_splits(pane) then
        win:perform_action(act.SendKey { key = key, mods = mods }, pane)
      elseif kind == 'resize' then
        win:perform_action(act.AdjustPaneSize { direction, 3 }, pane)
      else
        win:perform_action(act.ActivatePaneDirection(direction), pane)
      end
    end),
  }
end

for _, nav in ipairs {
  { 'h', 'Left' },
  { 'j', 'Down' },
  { 'k', 'Up' },
  { 'l', 'Right' },
} do
  local key, direction = nav[1], nav[2]
  table.insert(config.keys, split_nav('move', key, direction))
  table.insert(config.keys, split_nav('resize', key, direction))
end

return config
