return {
  {
    "mason.nvim",
    opts = {
      ensure_installed = { "xmlformatter" },
    },
  },
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        sqlfluff = {
          args = { "fix", "--dialect=postgres", "-" },
          require_cwd = false,
        },
      },
      formatters_by_ft = {
        xml = { "xmlformatter" },
        -- sql = { "pg_format" },
      },
    },
  },
}
