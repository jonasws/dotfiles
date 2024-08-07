return {
  {
    'stevearc/oil.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function()
      require('oil').setup {
        columns = { 'icon' },
        keymaps = {
          ['<C-h>'] = false,
          ['<M-h>'] = 'actions.select_split',
          ['q'] = 'actions.close',
        },
        view_options = {
          show_hidden = true,
        },
        experimental_watch_for_changes = true,
        delete_to_trash = false,
      }

      -- Open parent directory in floating window
      vim.keymap.set('n', '<space>-', require('oil').toggle_float, { desc = 'Open parent directory (floating)' })
    end,
  },
}
