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

}
