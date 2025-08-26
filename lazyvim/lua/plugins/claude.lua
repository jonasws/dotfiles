return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    opts = {
      terminal = {
        split_side = "right", -- Dock at the right side
        split_width_percentage = 0.4, -- Make window 30% of screen width
        provider = "snacks", -- Use snacks provider for better integration
      },
    },
    keys = {
      { "<leader>a", nil, desc = "AI/Claude Code" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
      -- { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
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
      -- File picker integration using Snacks (works with your LazyVim setup)
      -- Diff management
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
    },
  },
}
