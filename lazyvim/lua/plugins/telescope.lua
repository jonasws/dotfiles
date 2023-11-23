local Util = require("lazyvim.util")

return {
  {
    "nvim-telescope/telescope.nvim",
    -- install fzf native
    dependencies = {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
      config = function()
        require("telescope").load_extension("fzf")
      end,
    },
    opts = {
      defaults = {
        mappings = {
          i = {
            ["<C-J>"] = function(...)
              require("telescope.actions").move_selection_next(...)
            end,
            ["<C-K>"] = function(...)
              require("telescope.actions").move_selection_previous(...)
            end,
          },
        },
      },
    },
  },
}
