vim.api.nvim_create_autocmd({ "BufEnter", "BufNew", "BufWinEnter" }, {
  pattern = "*",
  group = vim.api.nvim_create_augroup("ts_fold_workaround", { clear = true }),
  command = "set foldexpr=nvim_treesitter#foldexpr()",
})

vim.api.nvim_create_autocmd({ "BufEnter" }, {
  pattern = { "*" },
  command = "normal! zx zR",
})
