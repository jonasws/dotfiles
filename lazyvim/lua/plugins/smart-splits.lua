return {
  {
    "mrjones2014/smart-splits.nvim",
    -- herdr-splits.nvim takes over inside a herdr session. Loading both would
    -- double-bind <C-hjkl>, and smart-splits would still target Rex's panes
    -- rather than herdr's.
    cond = vim.env.HERDR_ENV ~= "1",
    -- Backends are separate plugins since v3 and nothing auto-detects. This one
    -- is active only in a Rex terminal (REX_SESSION/REX_BLOCK set, `rex` on PATH).
    dependencies = {
      { "rawnly/smart-splits-backend-rex", main = "smart-splits-backend-rex" },
    },
    opts = {
      mux = {
        backend = "smart-splits-backend-rex",
        -- No Rex around means no backend; that is expected outside Rex.
        warn_if_unusable = false,
      },
    },
  },
}
