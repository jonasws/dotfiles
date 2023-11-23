return {
  "ThePrimeagen/harpoon",

  opts = function()
    require("telescope").load_extension("harpoon")
  end,
  keys = function()
    local ui = require("harpoon.ui")
    local mark = require("harpoon.mark")
    return {
      {
        "<leader>.",
        "<cmd>Telescope harpoon marks<cr>",
        desc = "Telescoope harpoon marks",
      },
      {
        "<leader>a",
        function(...)
          mark.add_file(...)
        end,
        desc = "Harpoon - add file",
      },
      {
        "<leader>1",
        function()
          ui.nav_file(1)
        end,
      },
      {
        "<leader>2",
        function()
          ui.nav_file(2)
        end,
      },
      {
        "<leader>3",
        function()
          ui.nav_file(3)
        end,
      },
      {
        "<leader>>",
        function()
          ui.nav_next()
        end,
      },
      {
        "<leader><",
        function()
          ui.nav_next()
        end,
      },
    }
  end,
}
