return {
  {
    "gbprod/substitute.nvim",
    opts = {
      on_substitute = require("yanky.integration").substitute(),
    },
    vscode = true,
    keys = {
      {
        "gs",
        function(...)
          require("substitute").operator(...)
        end,
        desc = "Substitute operator",
        mode = { "n" },
      },
      {
        "gss",
        function(...)
          require("substitute").line(...)
        end,
        desc = "Substitute line",
        mode = { "n" },
      },
      {
        "gS",
        function(...)
          require("substitute").eol(...)
        end,
        desc = "Substitute eol",
        mode = { "n" },
      },
      {
        "gs",
        function(...)
          require("substitute").visual(...)
        end,
        desc = "Substitute visual",
        mode = { "x" },
      },
      {
        "gsx",
        function(...)
          require("substitute.exchange").operator(...)
        end,
        desc = "Exchange operator",
        mode = { "n" },
      },
      {
        "gsxx",
        function(...)
          require("substitute.exchange").line(...)
        end,
        desc = "Exchange line",
        mode = { "n" },
      },
      {
        "gsX",
        function(...)
          require("substitute.exchange").eol(...)
        end,
        desc = "Exchange eol",
        mode = { "n" },
      },
      {
        "gsx",
        function(...)
          require("substitute.exchange").visual(...)
        end,
        desc = "Exchange visual",
        mode = { "x" },
      },
    },
  },
  -- rename surround mappings from gs to gz to prevent conflict with substitute
  -- inspired by https://github.com/LazyVim/LazyVim/blob/a50f92f7550fb6e9f21c0852e6cb190e6fcd50f5/lua/lazyvim/plugins/extras/editor/leap.lua#L38C1-L52C5
  -- which is meant to fix conflicting binds for leap
  {
    "echasnovski/mini.surround",
    opts = {
      mappings = {
        add = "gza", -- Add surrounding in Normal and Visual modes
        delete = "gzd", -- Delete surrounding
        find = "gzf", -- Find surrounding (to the right)
        find_left = "gzF", -- Find surrounding (to the left)
        highlight = "gzh", -- Highlight surrounding
        replace = "gzr", -- Replace surrounding
        update_n_lines = "gzn", -- Update `n_lines`
      },
    },
  },
}
