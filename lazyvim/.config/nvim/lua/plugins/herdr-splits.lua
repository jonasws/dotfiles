return {
  {
    "lmilojevicc/herdr-splits.nvim",
    -- Local fork: adds `forward` as an at_edge / nav_at_edge behaviour, which
    -- hands a motion to WezTerm at a herdr layout edge. Upstream only offers
    -- wrap and stop, so without it a chord can never leave the herdr layout
    -- and sibling WezTerm panes are unreachable from inside a session.
    -- The herdr *side* of the plugin is separate — `herdr plugin link` it from
    -- the same checkout, or the scripts keep coming from the GitHub install.
    dir = vim.fn.expand("~/herdr-splits.nvim"),
    -- Only meaningful inside a herdr session; outside one smart-splits.nvim
    -- keeps driving the same chords against wezterm.
    cond = vim.env.HERDR_ENV == "1",
    -- setup() writes herdr-splits.conf, which the herdr-side plugin scripts read
    -- to learn which chords to forward. That has to happen before the first
    -- keypress, so this can't lazy-load on `keys`.
    event = "VeryLazy",
    opts = {
      -- Chords go in Neovim notation here; the plugin translates them to herdr
      -- notation when it writes the conf. Resize sits on CTRL+SHIFT rather than
      -- the plugin's default <M-...> because Option is the us-altgr-intl compose
      -- layer (Option+l is ø) and has to stay free for text input.
      nav_keys = { left = "<C-h>", down = "<C-j>", up = "<C-k>", right = "<C-l>" },
      resize_keys = { left = "<C-S-h>", down = "<C-S-j>", up = "<C-S-k>", right = "<C-S-l>" },
      -- Escape the nested multiplexer rather than wrapping back into herdr.
      -- Two settings because two code paths own the edge: at_edge is Neovim's
      -- (fires when a window is at both the Neovim and the herdr edge), while
      -- nav_at_edge is the herdr-side script's, covering shell and agent panes
      -- that have no Neovim in them. Both fall back to wrapping when WezTerm
      -- has no pane in that direction either.
      at_edge = "forward",
      nav_at_edge = "forward",
    },
  },
}
