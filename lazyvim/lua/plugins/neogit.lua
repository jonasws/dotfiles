return {
  {
    "NeogitOrg/neogit",
    opts = {
      integrations = {
        telescope = true,
        diffview = true,
      },
    },
    keys = {
      { "<leader>gg", "<cmd>Neogit kind=auto<cr>", "Neogit" },
      { "<leader>gs", "<cmd>Neogit kind=auto<cr>", "Neogit" },
    },
  },
}
