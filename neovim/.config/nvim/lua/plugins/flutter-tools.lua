return {
  'akinsho/flutter-tools.nvim',
  lazy = false,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'stevearc/dressing.nvim',
    'hrsh7th/cmp-nvim-lsp',
  },
  config = function()
    -- Create the capabilities for auto-import (completions)
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    local cmp_ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
    if cmp_ok then
      capabilities = cmp_lsp.default_capabilities(capabilities)
    end

    require("flutter-tools").setup({
      ui = {
        border = "rounded",
      },
      decorations = {
        statusline = {
          app_version = true,
          device = true,
        },
      },
      closing_tags = {
        highlight = "Comment",
        prefix = "// ",
        enabled = true,
      },
      lsp = {
        capabilities = capabilities,
        -- settings specifically for the Dart LSP
        settings = {
          dart = {
            analysisExcludedFolders = {
              vim.fn.expand("$HOME/.pub-cache"),
              vim.fn.expand("/opt/flutter/"),
            },
            updateImportsOnRename = true,
            completeFunctionCalls = true,
            showTodos = true,
            -- Core setting for auto-import in cmp
            suggestFromUnimportedLibraries = true, 
          }
        },
        on_attach = function(client, bufnr)
          local opts = { buffer = bufnr, noremap = true, silent = true }

          -- 1. Code Actions (Your request: <leader>ga)
          vim.keymap.set({ "n", "v" }, "<leader>ga", vim.lsp.buf.code_action,
            vim.tbl_extend("force", opts, { desc = "Flutter Code Action" }))

          -- Standard Navigation
          vim.keymap.set('n', 'gd', vim.lsp.buf.definition, opts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, opts)
          vim.keymap.set('n', '<leader>rr', vim.lsp.buf.rename, opts)

          -- Navigation through errors
          vim.keymap.set("n", "<leader>gn", function()
            vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
          end, vim.tbl_extend("force", opts, { desc = "Next Error" }))

          vim.keymap.set("n", "<leader>gp", function()
            vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
          end, vim.tbl_extend("force", opts, { desc = "Previous Error" }))

          -- AUTOMATION: Organize Imports on Save
          -- This triggers the LSP "source.organizeImports" action before saving
          vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.code_action({
                apply = true,
                context = {
                  only = { "source.organizeImports" },
                  diagnostics = {},
                },
              })
            end,
          })
        end,
      }
    })
  end,
}
