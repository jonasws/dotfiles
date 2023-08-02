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
        "gx",
        function(...)
          require("substitute.exchange").operator(...)
        end,
        desc = "Exchange operator",
        mode = { "n" },
      },
      {
        "gX",
        function(...)
          require("substitute.exchange").visual(...)
        end,
        desc = "Exchange visual",
        mode = { "x" },
      },
    },
  },
}
