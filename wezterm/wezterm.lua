local wezterm = require("wezterm")
local act = wezterm.action

local config = {}

config.color_scheme = "Dracula"
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
