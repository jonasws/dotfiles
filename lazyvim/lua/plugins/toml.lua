return {
  -- taplo reports TOML tables and values as Object/Boolean/String symbols, which
  -- the default kind_filter drops, leaving LSP symbol pickers empty.
  { "LazyVim/LazyVim", opts = { kind_filter = { toml = false } } },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        taplo = {
          settings = {
            evenBetterToml = {
              schema = {
                associations = {
                  ["^.*\\.?mise(\\.local)?\\.toml$"] = "https://mise.jdx.dev/schema/mise.json",
                },
              },
            },
          },
        },
      },
    },
  },
}
