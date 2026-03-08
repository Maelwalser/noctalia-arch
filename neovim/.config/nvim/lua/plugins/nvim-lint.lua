return {
  'mfussenegger/nvim-lint',

  config = function()
    require('lint').linters_by_ft = {
      java = { 'checkstyle' },
      javascript = { 'eslint_d' },
      typescript = { 'eslint_d' },
      html = { 'htmlhint' },
      css = { 'stylelint' },
      dotenv = { 'dotenv-linter' },
      javascriptreact = { "eslint_d" },
      typescriptreact = { "eslint_d" },
      json = { 'jsonlint' },
      http = { 'kulala-fmt' },
      python = { "ruff" },
      go = { "golangcilint" },
      yaml = { "yamllint" },
      dockerfile = { "hadolint" },
    }

    vim.api.nvim_create_autocmd({ "BufWritePost" }, {
      callback = function()
        require("lint").try_lint()
      end,
    })
  end
}
