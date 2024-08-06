-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Move focus to the upper window' })

--  Use space+<hjkl> to switch between windows (like in spacemacs)
vim.keymap.set('n', '<leader>wh', '<C-w>h', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<leader>wl', '<C-w>l', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<leader>wj', '<C-w>j', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<leader>wk', '<C-w>k', { desc = 'Move focus to the upper window' })
vim.keymap.set('n', '<leader>w-', '<C-w>s', { desc = 'Split window' })
vim.keymap.set('n', '<leader>w|', '<C-w>v', { desc = 'Split window vertically' })
vim.keymap.set('n', '<leader>ww', '<C-w>w', { desc = 'Move to other window' })
vim.keymap.set('n', '<leader>wd', '<C-w>q', { desc = 'Close window' })

vim.keymap.set('n', '<leader>j', ':Telescope jumplist<CR>', { desc = '[J]umplist Telescope' })

vim.keymap.set('n', '<leader>qq', ':qa<Enter>', { desc = 'Quit Neovim' })
vim.keymap.set('c', '<C-h>', '<Left>', { noremap = true, desc = 'Left' })
vim.keymap.set('c', '<C-l>', '<Right>', { noremap = true, desc = 'Right' })
vim.keymap.set('c', '<C-j>', '<Down>', { noremap = true, desc = 'Down' })
vim.keymap.set('c', '<C-k>', '<Up>', { noremap = true, desc = 'Up' })

vim.keymap.set('n', '<leader><tab>', '<Cmd>buffer#<CR>')
