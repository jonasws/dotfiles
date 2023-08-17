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
    keys = {
      {
        "<leader>fp",
        function()
          local git_dir = vim.fn.systemlist("git rev-parse --show-toplevel")

          -- Use nil if the previous command failed
          if vim.v.shell_error ~= 0 then
            Util.telescope("find_files", {})()
          else
            Util.telescope("find_files", { cwd = git_dir[1] })()
          end
        end,
        desc = "Find project files",
      },
    },
  },
}
