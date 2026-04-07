return {
  "nanotee/sqls.nvim",
  ft = { "sql", "pgsql" }, -- Load only for SQL files
  dependencies = {
    "neovim/nvim-lspconfig",
  },
  config = function()
    local pg_user = vim.env.PGUSER or "postgres"
    local pg_pass = vim.env.PGPASSWORD or "postgres"
    local pg_host = vim.env.PGHOST or "localhost"
    local pg_port = vim.env.PGPORT or "5432"
    local pg_db = vim.env.PGDATABASE or "postgres"

    require('lspconfig').sqls.setup({
      settings = {
        sqls = {
          connections = {
            {
              driver = 'postgresql',
              dataSourceName = string.format(
                'host=%s port=%s user=%s password=%s dbname=%s',
                pg_host, pg_port, pg_user, pg_pass, pg_db
              ),
            },
          },
        },
      },
    })
  end,
}
