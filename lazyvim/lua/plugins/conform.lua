return {
  { "mason.nvim", opts = {
    ensure_installed = { "xmlformatter" },
  } },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        xml = { "xmlformatter" },
      },
    },
  },
}
