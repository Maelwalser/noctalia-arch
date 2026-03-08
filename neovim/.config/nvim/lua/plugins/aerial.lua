return {
  'stevearc/aerial.nvim',
  opts = {},
  event = "VeryLazy",
  -- Optional dependencies
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "nvim-tree/nvim-web-devicons"
  },
  config = function()
    require("aerial").setup({
      backends = { "treesitter", "lsp", "markdown", "asciidoc", "man" },
      ignore = {
        filetypes = { "sql" },
      },
      default_direction = "prefer_left",

      on_attach = function(bufnr)
        -- Jump forwards/backwards with '{' and '}'
        vim.keymap.set("n", "{", "<cmd>AerialPrev<CR>", { buffer = bufnr })
        vim.keymap.set("n", "}", "<cmd>AerialNext<CR>", { buffer = bufnr })
      end,
    })
    -- Toggle Aerial
    vim.keymap.set("n", "<leader>a", "<cmd>AerialToggle!<CR>")
  end
}
