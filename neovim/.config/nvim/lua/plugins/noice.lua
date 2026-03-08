-- in your plugins/noice.lua (or equivalent)
return {
  "folke/noice.nvim",
  event = "UIEnter",
  dependencies = {
    { "MunifTanjim/nui.nvim" },
  },
  opts = {
    lsp = {
      override = {
        ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
        ["vim.lsp.util.stylize_markdown"] = true,
      },
    },
    routes = {
      {
        filter = { event = "msg_show", min_height = 10 },
        view = "split",
      },
    },
    presets = {
      bottom_search = false,
      command_palette = false,
      long_message_to_split = true,
    },
    -- Reduce the message history size
    message = {
      history = {
        max_length = 100, -- Reduce from default
      },
    },
  },

  config = function(_, opts)
    require("noice").setup(opts)

    -- Defer cmp integration to when cmp is actually loaded
    vim.api.nvim_create_autocmd("User", {
      pattern = "CmpReady",
      callback = function()
        local cmp = require("cmp")
        cmp.setup({
          window = {
            documentation = cmp.config.window.bordered(),
          },
        })

        -- Configure cmp.entry.get_documentation
        local cmp_orig = require("cmp.entry").get_documentation
        require("cmp.entry").get_documentation = function(entry)
          local result = cmp_orig(entry)
          if result and vim.g.noice_cmp_enabled then
            return result
          end
          return result
        end
        vim.g.noice_cmp_enabled = true
      end,
      once = true,
    })

    -- Trigger the event when cmp is loaded
    if package.loaded["cmp"] then
      vim.api.nvim_exec_autocmds("User", { pattern = "CmpReady" })
    end
  end,
}
