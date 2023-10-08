return {
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      table.insert(opts.ensure_installed, "prettier")
    end,
  },
  {
    "nvimtools/none-ls.nvim",
    opts = function(_, opts)
      local nls = require("null-ls")
      table.insert(opts.sources, nls.builtins.formatting.prettier)

      -- Remove shfmt from opts.sources
      for i, source in ipairs(opts.sources) do
        if source.name == "shfmt" then
          table.remove(opts.sources, i)
        end
      end
      table.insert(
        opts.sources,
        nls.builtins.formatting.shfmt.with({
          extra_args = { "--indent", "2", "--case-indent", "--space-redirects" },
        })
      )
    end,
  },
}
