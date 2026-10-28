return {
  {
    "mrjones2014/smart-splits.nvim",
    -- herdr-splits.nvim takes over inside a herdr session. Loading both would
    -- double-bind <C-hjkl>, and smart-splits would still target Rex's panes
    -- rather than herdr's. Rex panes also carry HERDR_ENV=1, for the herdr
    -- socket Rex answers (fish/conf.d/45-rex-herdr.fish), but Rex binds
    -- Ctrl+hjkl itself, so REX_SESSION keeps this backend there.
    cond = vim.env.HERDR_ENV ~= "1" or (vim.env.REX_SESSION or "") ~= "",
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
