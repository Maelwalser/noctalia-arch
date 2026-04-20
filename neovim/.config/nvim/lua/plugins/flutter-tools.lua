return {
  'akinsho/flutter-tools.nvim',
  lazy = false,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'stevearc/dressing.nvim',
    'saghen/blink.cmp',
  },
  config = function()
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    local blink_ok, blink = pcall(require, "blink.cmp")
    if blink_ok and blink.get_lsp_capabilities then
      capabilities = blink.get_lsp_capabilities(capabilities)
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
        on_attach = function(_, bufnr)
          -- Shared LSP keymaps (gD/gd/K/<leader>g*/<leader>rn/...) come from
          -- the global LspAttach autocmd. Dart-specific overrides only below.

          -- Error-only diagnostic navigation (generic <leader>gn/gp jumps any severity)
          vim.keymap.set("n", "<leader>gn", function()
            vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
          end, { buffer = bufnr, desc = "Next Dart error" })
          vim.keymap.set("n", "<leader>gp", function()
            vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR, float = true })
          end, { buffer = bufnr, desc = "Previous Dart error" })

          -- Organize imports on save (Dart-specific LSP action)
          vim.api.nvim_create_autocmd("BufWritePre", {
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.code_action({
                apply = true,
                context = { only = { "source.organizeImports" }, diagnostics = {} },
              })
            end,
          })
        end,
      }
    })
  end,
}
