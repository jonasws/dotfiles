-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
-- vim.keymap.set('n', '<C-h>', '<C-w>h', { desc = 'Move focus to the left window' })
-- vim.keymap.set('n', '<C-l>', '<C-w>l', { desc = 'Move focus to the right window' })
-- vim.keymap.set('n', '<C-j>', '<C-w>j', { desc = 'Move focus to the lower window' })
-- vim.keymap.set('n', '<C-k>', '<C-w>k', { desc = 'Move focus to the upper window' })
--

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
vim.keymap.set('n', '[b', '<cmd>bprevious<cr>', {
  desc = 'Prev buffer',
})

vim.keymap.set('n', ']b', '<cmd>bnext<cr>', {
  desc = 'Next buffer',
})

local diagnostic_goto = function(next, severity)
  local go = next and vim.diagnostic.goto_next or vim.diagnostic.goto_prev
  severity = severity and vim.diagnostic.severity[severity] or nil
  return function()
    go { severity = severity }
  end
end

vim.keymap.set('n', ']d', diagnostic_goto(true), { desc = 'Next Diagnostic' })
vim.keymap.set('n', '[d', diagnostic_goto(false), { desc = 'Prev Diagnostic' })
vim.keymap.set('n', ']e', diagnostic_goto(true, 'ERROR'), { desc = 'Next Error' })
vim.keymap.set('n', '[e', diagnostic_goto(false, 'ERROR'), { desc = 'Prev Error' })
vim.keymap.set('n', ']w', diagnostic_goto(true, 'WARN'), { desc = 'Next Warning' })
vim.keymap.set('n', '[w', diagnostic_goto(false, 'WARN'), { desc = 'Prev Warning' })
--
vim.keymap.set('n', '<A-h>', require('smart-splits').resize_left)
vim.keymap.set('n', '<A-j>', require('smart-splits').resize_down)
vim.keymap.set('n', '<A-k>', require('smart-splits').resize_up)
vim.keymap.set('n', '<A-l>', require('smart-splits').resize_right)
-- moving between splits
vim.keymap.set('n', '<C-h>', require('smart-splits').move_cursor_left)
vim.keymap.set('n', '<C-j>', require('smart-splits').move_cursor_down)
vim.keymap.set('n', '<C-k>', require('smart-splits').move_cursor_up)
vim.keymap.set('n', '<C-l>', require('smart-splits').move_cursor_right)
vim.keymap.set('n', '<C-\\>', require('smart-splits').move_cursor_previous)
