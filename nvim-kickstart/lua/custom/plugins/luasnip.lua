return {
  {
    'benfowler/telescope-luasnip.nvim',
    after = 'nvim-telescope/telescope.nvim',
    config = function()
      require('telescope').load_extension 'luasnip'
    end,
  },
}