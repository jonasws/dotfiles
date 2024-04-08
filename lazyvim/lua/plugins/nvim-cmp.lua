return {
  -- customize nvim-cmp configs
  -- Use <tab> for completion and snippets (supertab)
  -- first: disable default <tab> and <s-tab> behavior in LuaSnip
  {
    "L3MON4D3/LuaSnip",
    keys = function()
      return {}
    end,
  },
  -- then: setup supertab in cmp
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-emoji",
    },
    ---@param opts cmp.ConfigSchema
    opts = function(_, opts)
      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      local cmp = require("cmp")
      local types = require("cmp.types")

      -- This is reaaaally not easy to setup :D
      opts.mapping = vim.tbl_extend("force", opts.mapping, {
        ["<C-J>"] = {
          i = function()
            cmp.select_next_item({ behavior = types.cmp.SelectBehavior.Insert })
            if cmp.visible() then
            else
              cmp.complete()
            end
          end,
        },
        ["<C-K>"] = {
          i = function()
            if cmp.visible() then
              cmp.select_prev_item({ behavior = types.cmp.SelectBehavior.Insert })
            else
              cmp.complete()
            end
          end,
        },
        ["<C-L>"] = {
          i = function()
            cmp.confirm({ select = false })
          end,
        },
      })
    end,
  },
}
