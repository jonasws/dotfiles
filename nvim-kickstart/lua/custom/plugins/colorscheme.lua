return {
  {
    'maxmx03/dracula.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('dracula').setup {
        transparent = true,
        -- on_highlights = function(colors, color)
        --   ---@type dracula.highlights
        --   return {
        --     RainbowDelimiterRed = { fg = colors.pink },
        --     RainbowDelimiterYellow = { fg = colors.yellow },
        --     RainbowDelimiterBlue = { fg = colors.blue },
        --     RainbowDelimiterOrange = { fg = colors.orange },
        --     RainbowDelimiterGreen = { fg = colors.green },
        --     RainbowDelimiterViolet = { fg = colors.violet },
        --     RainbowDelimiterCyan = { fg = colors.cyan },
        --   }
        -- end,
      }
      -- vim.cmd.colorscheme 'dracula'
      vim.cmd.colorscheme 'dracula-soft'
      vim.cmd.hi 'Comment gui=none'
    end,
  },
  -- {
  --   'catppuccin/nvim',
  --   name = 'catppuccin',
  --   priority = 1000,
  --
  --   config = function()
  --     require('catppuccin').setup {
  --       transparent = true,
  --       -- on_highlights = function(colors, color)
  --       --   ---@type dracula.highlights
  --       --   return {
  --       --     RainbowDelimiterRed = { fg = colors.pink },
  --       --     RainbowDelimiterYellow = { fg = colors.yellow },
  --       --     RainbowDelimiterBlue = { fg = colors.blue },
  --       --     RainbowDelimiterOrange = { fg = colors.orange },
  --       --     RainbowDelimiterGreen = { fg = colors.green },
  --       --     RainbowDelimiterViolet = { fg = colors.violet },
  --       --     RainbowDelimiterCyan = { fg = colors.cyan },
  --       --   }
  --       -- end,
  --     }
  --     -- vim.cmd.colorscheme 'dracula'
  --     vim.cmd.colorscheme 'catppuccin-mocha'
  --     -- vim.cmd.hi 'Comment gui=none'
  --   end,
  -- },
}
