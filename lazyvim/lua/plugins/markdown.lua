return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      code = {
        sign = false,
        width = "block",
        right_pad = 1,
      },
      heading = {
        sign = false,
        icons = {},
      },
      checkbox = {
        enabled = false,
      },
      completions = {
        lsp = {
          enabled = true,
        },
      },
    },
    ft = { "markdown", "norg", "rmd", "org", "codecompanion" },
  },
}
