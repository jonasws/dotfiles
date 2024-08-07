return {
  'NeogitOrg/neogit',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'sindrets/diffview.nvim',

    'nvim-telescope/telescope.nvim',
  },
  branch = 'master',
  config = true,
  keys = {
    {
      '<leader>gg',
      function()
        require('neogit').open { kind = 'auto' }
      end,
    },
  },
}
