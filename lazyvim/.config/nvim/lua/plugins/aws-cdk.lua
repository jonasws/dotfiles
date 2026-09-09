return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        cdk_lsp = {
          mason = false, -- not in the mason registry; ships inside the aws-cdk CLI
          cmd = { "npx", "cdk", "lsp" },
          filetypes = { "typescript", "javascript", "python" },
          root_markers = { "cdk.json" },
          before_init = function(params, config)
            -- server falls back to its own cwd if applicationDir is unset
            params.initializationOptions = params.initializationOptions or {}
            params.initializationOptions.applicationDir = config.root_dir
          end,
        },
      },
    },
  },
}
