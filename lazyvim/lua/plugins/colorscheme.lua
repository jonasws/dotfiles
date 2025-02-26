return {
  -- {
  --   lazy = true,
  --   "catppuccin/nvim",
  --   name = "catppuccin",
  --   opts = {
  --     transparent_background = true,
  --     flavour = "mocha",
  --     integrations = {
  --       aerial = true,
  --       alpha = true,
  --       cmp = true,
  --       dashboard = true,
  --       flash = true,
  --       fzf = true,
  --       grug_far = true,
  --       gitsigns = true,
  --       headlines = true,
  --       indent_blankline = { enabled = true },
  --       illuminate = true,
  --       leap = true,
  --       lsp_trouble = true,
  --       mason = true,
  --       markdown = true,
  --       mini = true,
  --       native_lsp = {
  --         enabled = true,
  --         underlines = {
  --           errors = { "undercurl" },
  --           hints = { "undercurl" },
  --           warnings = { "undercurl" },
  --           information = { "undercurl" },
  --         },
  --       },
  --       navic = { enabled = true, custom_bg = "lualine" },
  --       neotest = true,
  --       neotree = true,
  --       noice = true,
  --       notify = true,
  --       semantic_tokens = true,
  --       snacks = true,
  --       telescope = true,
  --       treesitter = true,
  --       treesitter_context = true,
  --       which_key = true,
  --     },
  --   },
  --   specs = {
  --     {
  --       "akinsho/bufferline.nvim",
  --       optional = true,
  --       opts = function(_, opts)
  --         if (vim.g.colors_name or ""):find("catppuccin") then
  --           opts.highlights = require("catppuccin.groups.integrations.bufferline").get()
  --         end
  --       end,
  --     },
  --   },
  -- },
  {
    "maxmx03/dracula.nvim",
    lazy = true,
    opts = {
      transparent = true,
      on_highlights = function(colors, color)
        ---@type dracula.highlights
        return {
          RainbowDelimiterRed = { fg = colors.pink },
          RainbowDelimiterYellow = { fg = colors.yellow },
          RainbowDelimiterBlue = { fg = colors.blue },
          RainbowDelimiterOrange = { fg = colors.orange },
          RainbowDelimiterGreen = { fg = colors.green },
          RainbowDelimiterViolet = { fg = colors.violet },
          RainbowDelimiterCyan = { fg = colors.cyan },
        }
      end,
    },
  },
  {
    "HiPhish/rainbow-delimiters.nvim",
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "dracula",
    },
  },
}
