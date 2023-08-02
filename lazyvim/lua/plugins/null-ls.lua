local nls = require("null-ls")
return {
  "jose-elias-alvarez/null-ls.nvim",
  opts = function(_, opts)
    table.insert(opts.sources, nls.builtins.formatting.prettierd)
    table.insert(opts.sources, require("typescript.extensions.null-ls.code-actions"))

    opts.sources = opts.sources or {}
    vim.list_extend(opts.sources, {
      nls.builtins.diagnostics.hadolint,
    })
  end,
}
