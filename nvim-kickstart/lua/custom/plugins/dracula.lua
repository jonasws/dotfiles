local M = {}

M.bg = '#000000'
M.fg = '#ffffff'
M.day_brightness = 0.3

---@param c  string
local function hexToRgb(c)
  c = string.lower(c)
  return { tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16) }
end

---@param foreground string foreground color
---@param background string background color
---@param alpha number|string number between 0 and 1. 0 results in bg, 1 results in fg
function M.blend(foreground, background, alpha)
  alpha = type(alpha) == 'string' and (tonumber(alpha, 16) / 0xff) or alpha
  local bg = hexToRgb(background)
  local fg = hexToRgb(foreground)

  local blendChannel = function(i)
    local ret = (alpha * fg[i] + ((1 - alpha) * bg[i]))
    return math.floor(math.min(math.max(0, ret), 255) + 0.5)
  end

  return string.format('#%02x%02x%02x', blendChannel(1), blendChannel(2), blendChannel(3))
end

function M.darken(hex, amount, bg)
  return M.blend(hex, bg or M.bg, amount)
end

return {
  -- You can easily change to a different colorscheme.
  -- Change the name of the colorscheme plugin below, and then
  -- change the command in the config to whatever the name of that colorscheme is
  --
  -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`
  'Mofiqul/dracula.nvim',
  lazy = false, -- make sure we load this during startup if it is your main colorscheme
  priority = 1000, -- make sure to load this before all the other start plugins
  config = function()
    local dracula = require 'dracula'
    dracula.setup {
      -- customize dracula color palette
      colors = {
        bg = '#282A36',
        fg = '#F8F8F2',
        selection = '#44475A',
        comment = '#6272A4',
        red = '#FF5555',
        orange = '#FFB86C',
        yellow = '#F1FA8C',
        green = '#50fa7b',
        purple = '#BD93F9',
        cyan = '#8BE9FD',
        pink = '#FF79C6',
        bright_red = '#FF6E6E',
        bright_green = '#69FF94',
        bright_yellow = '#FFFFA5',
        bright_blue = '#D6ACFF',
        bright_magenta = '#FF92DF',
        bright_cyan = '#A4FFFF',
        bright_white = '#FFFFFF',
        menu = '#21222C',
        visual = '#3E4452',
        gutter_fg = '#4B5263',
        nontext = '#3B4048',
        white = '#ABB2BF',
        black = '#191A21',
      },
      -- show the '~' characters after the end of buffers
      show_end_of_buffer = true, -- default false
      -- use transparent background
      transparent_bg = true, -- default false
      -- set custom lualine background color
      lualine_bg_color = '#44475a', -- default nil
      -- set italic comment
      italic_comment = true, -- default false
      -- overrides the default highlights with table see `:h synIDattr`
      -- overrides = {},
      -- You can use overrides as table like this
      -- overrides = {
      --   NonText = { fg = "white" }, -- set NonText fg to white
      --   NvimTreeIndentMarker = { link = "NonText" }, -- link to NonText highlight
      --   Nothing = {} -- clear highlight of Nothing
      -- },
      -- Or you can also use it like a function to get color from theme
      overrides = function(colors)
        return {
          DiffAdd = { bg = M.darken(colors.bright_green, 0.15) },
          DiffDelete = { fg = colors.bright_red },
          DiffChange = { bg = M.darken(colors.comment, 0.15) },
          DiffText = { bg = M.darken(colors.comment, 0.50) },
          illuminatedWord = { bg = M.darken(colors.comment, 0.65) },
          illuminatedCurWord = { bg = M.darken(colors.comment, 0.65) },
          IlluminatedWordText = { bg = M.darken(colors.comment, 0.65) },
          IlluminatedWordRead = { bg = M.darken(colors.comment, 0.65) },
          IlluminatedWordWrite = { bg = M.darken(colors.comment, 0.65) },
        }
      end,
    }
    -- Load the colorscheme here
    vim.cmd.colorscheme 'dracula'

    -- You can configure highlights by doing something like
    vim.cmd.hi 'Comment gui=none'
  end,
}
