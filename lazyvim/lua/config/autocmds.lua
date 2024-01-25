vim.api.nvim_create_autocmd("FileType", {
  pattern = "fish",
  callback = function()
    vim.bo.tabstop = 4
    vim.bo.shiftwidth = 4
    vim.bo.expandtab = true
  end,
})
