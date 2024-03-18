-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
vim.keymap.set("i", "jk", "<ESC>", { noremap = true, silent = true, desc = "<ESC>" })
vim.keymap.set({ "n", "v" }, "<leader>k", "K", { noremap = true, desc = "Keyword" })
vim.keymap.set({ "n", "v" }, "<leader>j", "J", { noremap = true, desc = "Join lines" })
vim.keymap.set("c", "<C-j>", "<Down>", { noremap = true, desc = "Down" })
vim.keymap.set("c", "<C-k>", "<Up>", { noremap = true, desc = "Up" })
vim.keymap.set("c", "<C-h>", "<Left>", { noremap = true, desc = "Left" })
vim.keymap.set("c", "<C-l>", "<Right>", { noremap = true, desc = "Right" })
