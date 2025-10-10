return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      auto_integrations = true,
      transparent_background = true,
      float = {
        transparent = true,
      },
    },
  },
  "HiPhish/rainbow-delimiters.nvim",
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin-mocha",
    },
  },
}
