return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal = {
        split_side = "right",
        split_width_percentage = 0.4,
        provider = "snacks",
      },
    },
    keys = {
      {
        "<leader>ap",
        function()
          Snacks.picker.files({
            title = "Add File to Claude",
            confirm = function(picker, item)
              picker:close()
              if item then
                vim.schedule(function()
                  local file_path = vim.fn.fnamemodify(item.file, ":p")
                  vim.cmd("ClaudeCodeAdd " .. vim.fn.fnameescape(file_path))
                end)
              end
            end,
          })
        end,
        desc = "Add file to Claude",
      },
    },
  },
}
