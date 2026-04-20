-- Indentation guides (cyberpunk)
return {
  "lukas-reineke/indent-blankline.nvim",
  lazy = true,
  event = "BufReadPre",
  main = "ibl",
  config = function()
    require("ibl").setup({
      enabled = true,
      exclude = {
        filetypes = { "help", "dashboard", "packer", "oil", "NvimTree", "Trouble", "TelescopePrompt", "Float" },
        buftypes = { "terminal", "nofile", "telescope" },
      },
      indent = {
        char = "▏",
        highlight = "IblIndent",
      },
      whitespace = {
        highlight = "IblWhitespace",
        remove_blankline_trail = true,
      },
      scope = {
        enabled = true,
        show_start = false,
        show_end = false,
        highlight = "IblScope",
      },
    })

    local p = require("config.palette")
    vim.api.nvim_set_hl(0, "IblIndent", { fg = p.indent, nocombine = true })
    vim.api.nvim_set_hl(0, "IblWhitespace", { fg = p.indent, nocombine = true })
    vim.api.nvim_set_hl(0, "IblScope", { fg = p.cyan, nocombine = true, bold = true })

    -- Re-apply on colorscheme changes so theme swaps don't wipe scope glow
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("IblCyberpunk", { clear = true }),
      callback = function()
        vim.api.nvim_set_hl(0, "IblIndent", { fg = p.indent, nocombine = true })
        vim.api.nvim_set_hl(0, "IblWhitespace", { fg = p.indent, nocombine = true })
        vim.api.nvim_set_hl(0, "IblScope", { fg = p.cyan, nocombine = true, bold = true })
      end,
    })
  end,
}
