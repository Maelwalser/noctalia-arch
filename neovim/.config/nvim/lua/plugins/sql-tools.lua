return {
  "nanotee/sqls.nvim",
  ft = { "sql", "pgsql" }, -- Load only for SQL files
  dependencies = {
    "neovim/nvim-lspconfig",
  },
  config = function()
    require('lspconfig').sqls.setup({
      settings = {
        sqls = {
          connections = {
            {
              driver = 'postgresql',
              dataSourceName = 'host=localhost port=5432 user=postgres password=postgres dbname=postgres',
            },
          },
        },
      },
    })
  end,
}
