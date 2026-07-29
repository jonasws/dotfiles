return {
  {
    "mrjones2014/smart-splits.nvim",
    -- herdr-splits.nvim takes over inside a herdr session. Loading both would
    -- double-bind <C-hjkl>, and smart-splits would still target wezterm's panes
    -- rather than herdr's, since herdr keeps exporting TERM_PROGRAM=WezTerm.
    cond = vim.env.HERDR_ENV ~= "1",
  },
}
