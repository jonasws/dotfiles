return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      -- "auto" picks latte or mocha from 'background', which follows tuios's light/dark
      -- reports; setting 'background' reloads the scheme by colors_name, so a
      -- pinned "catppuccin-mocha" would stay mocha.
      flavour = "auto",
      auto_integrations = true,
      transparent_background = true,
      term_colors = true,
      float = {
        transparent = true,
      },
    },
  },
  "HiPhish/rainbow-delimiters.nvim",
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
