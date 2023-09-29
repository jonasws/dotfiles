local wezterm = require("wezterm")
local act = wezterm.action

local config = {}

config.color_scheme = "Dracula (Official)"
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.window_decorations = "RESIZE"
config.font_size = 14.0

config.keys = {
	{
		key = "d",
		mods = "SUPER",
		action = act.SplitVertical({ domain = "CurrentPaneDomain" }),
	},
	{
		key = "r",
		mods = "SUPER",
		action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }),
	},
	{
		key = "]",
		mods = "SUPER",
		action = act.ActivatePaneDirection("Next"),
	},
	{
		key = "[",
		mods = "SUPER",
		action = act.ActivatePaneDirection("Prev"),
	},
	{
		key = ".",
		mods = "SUPER",
		action = act.PaneSelect,
	},
}

return config
