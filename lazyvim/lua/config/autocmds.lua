-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
--
--
--
-- Autoformat setting
local set_autoformat = function(pattern, bool_val)
  vim.api.nvim_create_autocmd({ "FileType" }, {
    pattern = pattern,
    callback = function()
      vim.b.autoformat = bool_val
    end,
  })
end

set_autoformat({ "xml" }, false)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "jq" },
  callback = function()
    vim.keymap.set(
      { "n", "v" },
      "<Leader>S",
      "<Plug>(DBUI_ExecuteQuery)",
      { buffer = true, silent = true, desc = "Execute current buffer sql query" }
    )
    if LazyVim.has_extra("coding.nvim-cmp") then
      local cmp = require("cmp")

      -- global sources
      ---@param source cmp.SourceConfig
      local sources = vim.tbl_map(function(source)
        return { name = source.name }
      end, cmp.get_config().sources)

      -- add vim-dadbod-completion source
      table.insert(sources, { name = "vim-dadbod-completion" })

      -- update sources for the current buffer
      cmp.setup.buffer({ sources = sources })
    end
  end,
})
