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

-- Rex binds Ctrl+hjkl itself (rex/init.lua) and has to know when Neovim owns
-- the keys. Rex can't tell: its foreground-process lookup stops at the login
-- process, since the shell runs behind atuin's PTY proxy. So Neovim leaves a
-- marker file named after its Rex block, holding its pid, while it is running.
local rex_block = vim.env.REX_BLOCK
if rex_block and rex_block ~= "" then
  local marker = vim.fn.stdpath("state") .. "/rex-nvim/" .. rex_block:gsub("[^%w%-]", "_")
  local function mark()
    vim.fn.mkdir(vim.fn.fnamemodify(marker, ":h"), "p")
    vim.fn.writefile({ tostring(vim.fn.getpid()) }, marker)
  end
  local function unmark()
    vim.fn.delete(marker)
  end
  local group = vim.api.nvim_create_augroup("rex_nvim_marker", { clear = true })
  vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, { group = group, callback = unmark })
  vim.api.nvim_create_autocmd("VimResume", { group = group, callback = mark })
  mark()
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sql", "mysql", "plsql", "markdown" },
  callback = function()
    vim.diagnostic.enable(false, { bufnr = 0 })
  end,
})
