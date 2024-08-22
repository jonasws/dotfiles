return {
  {
    'maxmx03/dracula.nvim',
    lazy = false,
    priority = 1000,
    config = function()
      require('dracula').setup {
        transparent = true,
      }
      vim.cmd.colorscheme 'dracula'
      vim.cmd.colorscheme 'dracula-soft'
      vim.cmd.hi 'Comment gui=none'
    end,
  },
}
