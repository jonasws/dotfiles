return {
  {
    "Mofiqul/dracula.nvim",
    config = function()
      local dracula = require("dracula")
      local colors = require("dracula.palette")
      local util = require("tokyonight.util")
      local darken = util.darken

      dracula.setup({
        overrides = {
          DiffAdd = { bg = darken(colors.bright_green, 0.15) },
          DiffDelete = { fg = colors.bright_red },
          DiffChange = { bg = darken(colors.comment, 0.15) },
          DiffText = { bg = darken(colors.comment, 0.50) },
          illuminatedWord = { bg = darken(colors.comment, 0.65) },
          illuminatedCurWord = { bg = darken(colors.comment, 0.65) },
          IlluminatedWordText = { bg = darken(colors.comment, 0.65) },
          IlluminatedWordRead = { bg = darken(colors.comment, 0.65) },
          IlluminatedWordWrite = { bg = darken(colors.comment, 0.65) },
        },
      })
    end,
    dependencies = {
      "folke/tokyonight.nvim",
    },
  },
  {

    "LazyVim/LazyVim",
    opts = {
      colorscheme = "dracula",
    },
  },
}
