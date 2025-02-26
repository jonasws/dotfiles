-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
local splits = require("smart-splits")

vim.keymap.set("n", "<A-h>", splits.resize_left)
vim.keymap.set("n", "<A-j>", splits.resize_down)
vim.keymap.set("n", "<A-k>", splits.resize_up)
vim.keymap.set("n", "<A-l>", splits.resize_right)
-- moving between splits
vim.keymap.set("n", "<C-h>", splits.move_cursor_left)
vim.keymap.set("n", "<C-j>", splits.move_cursor_down)
vim.keymap.set("n", "<C-k>", splits.move_cursor_up)
vim.keymap.set("n", "<C-l>", splits.move_cursor_right)
vim.keymap.set("n", "<C-\\>", splits.move_cursor_previous)
