return {
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
}
