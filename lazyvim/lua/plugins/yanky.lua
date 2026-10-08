return {
  {
    "gbprod/yanky.nvim",
    dependencies = { "folke/snacks.nvim" },
    keys = {
      {
        "<leader>p",
        function()
          Snacks.picker.yanky()
        end,
        mode = { "n", "x" },
        desc = "Open Yank History",
      },
      { "ip", "<Plug>(YankyPutAfterCharwiseJoined)", mode = { "v" }, desc = "Put over selection" },
    },
  },
}
