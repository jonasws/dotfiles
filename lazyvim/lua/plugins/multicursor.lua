local mc = require("util.multicursor")

if not mc.available then
  return {}
end

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        function()
          local text = "󰗧 " .. mc.count()
          return vim.bo.follow and text .. " follow" or text
        end,
        cond = mc.active,
        color = function()
          return { fg = Snacks.util.color("MCursor", "bg") }
        end,
      })
    end,
  },
  {
    "folke/which-key.nvim",
    opts = {
      -- q= is left out: registering it would turn q into a which-key prefix
      -- and get in the way of macro recording.
      spec = {
        { "Q", desc = "Toggle multicursor" },
        { "Q", desc = "Cursor on each line", mode = "x" },
        { "zq", desc = "Multicursor at motion", mode = { "n", "x" } },
        { "gQ", desc = "Restore multicursors" },
        { "]C", desc = "Next multicursor" },
        { "[C", desc = "Prev multicursor" },
      },
    },
  },
}
