return {
  {
    "gbprod/substitute.nvim",
    -- opts = {
    --   on_substitute = require("yanky.integration").substitute(),
    -- },
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
}
