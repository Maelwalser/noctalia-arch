-- Indentation guides
return {
  -- https://github.com/lukas-reineke/indent-blankline.nvim
  "lukas-reineke/indent-blankline.nvim",
  lazy = true,
  event = "BufReadPre",
  main = "ibl",
  opts = {
    enabled = true,
    exclude = {
      filetypes = { "help", "dashboard", "packer", "oil", "NvimTree", "Trouble", "TelescopePrompt", "Float" },
      buftypes = { "terminal", "nofile", "telescope" },
    },
    indent = {
      char = '|',
    },
    scope = {
      enabled = true,
      show_start = false,
    }
  },
}
