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
    message = {
      history = {
        max_length = 100,
      },
    },
  },
  config = function(_, opts)
    require("noice").setup(opts)

    local p = require("config.palette")
    local set = function(name, val) vim.api.nvim_set_hl(0, name, val) end

    -- Cmdline popup (borders colored by mode)
    set("NoiceCmdline",                    { fg = p.fg, bg = p.bg_float })
    set("NoiceCmdlinePopup",               { fg = p.fg, bg = p.bg_float })
    set("NoiceCmdlinePopupTitle",          { fg = p.cyan, bold = true })
    set("NoiceCmdlinePopupBorder",         { fg = p.cyan, bg = p.bg_float })
    set("NoiceCmdlinePopupBorderCmdline",  { fg = p.cyan, bg = p.bg_float })
    set("NoiceCmdlinePopupBorderSearch",   { fg = p.magenta, bg = p.bg_float })
    set("NoiceCmdlinePopupBorderLua",      { fg = p.green, bg = p.bg_float })
    set("NoiceCmdlinePopupBorderHelp",     { fg = p.yellow, bg = p.bg_float })
    set("NoiceCmdlinePopupBorderFilter",   { fg = p.orange, bg = p.bg_float })
    set("NoiceCmdlineIcon",                { fg = p.cyan })
    set("NoiceCmdlineIconSearch",          { fg = p.magenta })
    set("NoiceCmdlineIconLua",             { fg = p.green })
    set("NoiceCmdlineIconHelp",            { fg = p.yellow })
    set("NoiceCmdlineIconFilter",          { fg = p.orange })

    -- Confirm / mini / popup
    set("NoiceConfirm",       { fg = p.fg, bg = p.bg_float })
    set("NoiceConfirmBorder", { fg = p.border, bg = p.bg_float })
    set("NoiceMini",          { fg = p.fg, bg = p.bg_alt })
    set("NoicePopup",         { fg = p.fg, bg = p.bg_float })
    set("NoicePopupBorder",   { fg = p.border, bg = p.bg_float })
    set("NoicePopupmenu",     { fg = p.fg, bg = p.bg_alt })
    set("NoicePopupmenuBorder", { fg = p.border, bg = p.bg_alt })
    set("NoicePopupmenuSelected", { fg = p.cyan, bg = p.selection, bold = true })
    set("NoicePopupmenuMatch",    { fg = p.magenta, bold = true })
    set("NoiceVirtualText",   { fg = p.fg_dim, italic = true })
  end,
}
