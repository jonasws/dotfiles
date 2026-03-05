local util = require("lspconfig.util")
local root_files = { "build.gradle", "build.gradle.kts", "pom.xml" }

return {
  -- {
  --   "neovim/nvim-lspconfig",
  --   opts = {
  --     servers = {
  --       kotlin_language_server = {
  --         cmd = { "kotlin-ls", "--stdio" },
  --         single_file_support = true,
  --         filetypes = { "kotlin" },
  --         root_dir = util.root_pattern(unpack(root_files)),
  --         init_options = {
  --           -- Enables caching and use project root to store cache data.
  --           storagePath = util.root_pattern(unpack(root_files))(vim.fn.expand("%:p:h")),
  --         },
  --       },
  --     },
  --   },
  -- },
}
